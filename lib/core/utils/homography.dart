import 'dart:math' as math;
import 'dart:ui' show Offset;

/// 平面单应（Homography）：3×3 矩阵，把「图像像素坐标」映射到
/// 「被测平面（墙面/地面）的毫米坐标」。
///
/// 为什么需要它：手机上斜着拍墙面时，透视会把远处压缩，用「两点比例法」
/// （像素距 × mm/px）量出来的尺寸必然失真——倾角越大、距离越远误差越大。
/// 用画面里已知模数（瓷砖缝 600、吊顶扣板、A4、86 面板等）的 4 个及以上的点
/// 求解单应，相当于把斜拍画面「矫正为正视图」，在这个平面上量取的距离
/// 才是真实尺寸，且尺度已由已知模数带入，无需用户再填参考物尺寸。
///
/// 求解用标准 DLT（归一化坐标 + 9 元齐次最小二乘，取 AᵀA 最小特征向量）。
/// 注意：**不能**用「固定 h₈=1」的 8 元解法——当真实单应的 h₈=0（例如
/// 镜像/某些矩形对应，属合法情况）时该方程组奇异，会解不出来。
///
/// 纯函数实现，不依赖 Flutter 组件，便于单测。
class Homography {
  /// 行主序 3×3（长度 9）。
  final List<double> h;

  const Homography(this.h);

  factory Homography.fromMatrix(List<double> m) {
    if (m.length != 9) {
      throw ArgumentError('Homography 需要 9 个元素，实际 ${m.length}');
    }
    return Homography(List<double>.from(m));
  }

  /// 由 4 组及以上的对应点求单应（归一化 DLT + 最小二乘）。
  ///
  /// [src] 图像像素点，[dst] 对应的平面毫米坐标；长度须一致且 ≥4。
  /// 点共线/奇异/退化时返回 null（调用方回退两点比例法）。
  static Homography? solve(List<Offset> src, List<Offset> dst) {
    if (src.length != dst.length || src.length < 4) return null;

    final ns = _normalize(src);
    final nd = _normalize(dst);
    if (ns == null || nd == null) return null;
    final s = ns.points, d = nd.points;

    // 归一化坐标系下的 DLT：每点给出两行，构成 2n×9 齐次方程组。
    final ata = List.generate(9, (_) => List<double>.filled(9, 0.0));
    for (var i = 0; i < s.length; i++) {
      final x = s[i].dx, y = s[i].dy;
      final X = d[i].dx, Y = d[i].dy;
      final r1 = <double>[x, y, 1, 0, 0, 0, -X * x, -X * y, -X];
      final r2 = <double>[0, 0, 0, x, y, 1, -Y * x, -Y * y, -Y];
      for (var a = 0; a < 9; a++) {
        for (var b = a; b < 9; b++) {
          final v = r1[a] * r1[b] + r2[a] * r2[b];
          ata[a][b] += v;
          if (a != b) ata[b][a] += v;
        }
      }
    }

    final hn = _smallestEigenvector(ata);
    if (hn == null) return null;

    // H = Td⁻¹ · Hn · Ts（去归一化）
    final ti = _inverse3(nd.matrix);
    if (ti == null) return null;
    final m = _mul3(ti, _mul3(hn, ns.matrix));

    // 归一化尺度：按最大幅值元素归一，避免 h₈=0 时无法除（单应本身与尺度无关）。
    var maxAbs = 0.0;
    for (final v in m) {
      final a = v.abs();
      if (a > maxAbs) maxAbs = a;
    }
    if (maxAbs < 1e-15) return null;
    final out = m.map((v) => v / maxAbs).toList();

    final hom = Homography(out);
    return hom.isValid ? hom : null;
  }

  /// 4 点矩形标定的便捷入口：图像上依次传入「左上→右上→右下→左下」，
  /// 给出该矩形的真实宽 [wMm]、高 [hMm]（如瓷砖 2×2 即 1200×1200）。
  static Homography? fromRect(List<Offset> corners, double wMm, double hMm) {
    if (corners.length != 4 || wMm <= 0 || hMm <= 0) return null;
    return solve(corners, <Offset>[
      Offset.zero,
      Offset(wMm, 0),
      Offset(wMm, hMm),
      Offset(0, hMm),
    ]);
  }

  /// 图像像素点 → 平面毫米坐标。
  Offset apply(Offset p) {
    final d = h[6] * p.dx + h[7] * p.dy + h[8];
    if (d.abs() < 1e-12) return Offset.zero;
    return Offset(
      (h[0] * p.dx + h[1] * p.dy + h[2]) / d,
      (h[3] * p.dx + h[4] * p.dy + h[5]) / d,
    );
  }

  /// 平面上两点间的真实距离（mm）。
  double distanceMm(Offset a, Offset b) {
    final pa = apply(a), pb = apply(b);
    return (pa - pb).distance;
  }

  /// 标定质量：控制点经单应映射后与期望毫米坐标的**最大**偏差（mm）。
  /// 注意 4 个点时为精确解，残差恒 ≈0，只有 ≥5 点才有判别意义。
  static double residualMm(Homography hom, List<Offset> src, List<Offset> dst) {
    var worst = 0.0;
    for (var i = 0; i < src.length && i < dst.length; i++) {
      final d = (hom.apply(src[i]) - dst[i]).distance;
      if (d > worst) worst = d;
    }
    return worst;
  }

  /// 全部元素有限且矩阵非奇异。
  bool get isValid =>
      h.length == 9 && h.every((v) => v.isFinite) && _inverse3(h) != null;

  List<double> toList() => List<double>.from(h);

  /// 逆变换（平面 mm → 图像 px），用于把平面坐标画回照片上。
  Homography? get inverse {
    final inv = _inverse3(h);
    if (inv == null) return null;
    return Homography(inv);
  }

  // ————————————————————— 内部：矩阵与特征分解 —————————————————————

  static List<double> _mul3(List<double> a, List<double> b) {
    final out = List<double>.filled(9, 0.0);
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        var s = 0.0;
        for (var k = 0; k < 3; k++) {
          s += a[i * 3 + k] * b[k * 3 + j];
        }
        out[i * 3 + j] = s;
      }
    }
    return out;
  }

  static List<double>? _inverse3(List<double> m) {
    final a = m[0], b = m[1], c = m[2];
    final d = m[3], e = m[4], f = m[5];
    final g = m[6], h = m[7], i = m[8];
    final det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
    if (det.abs() < 1e-14) return null;
    final invDet = 1 / det;
    return <double>[
      (e * i - f * h) * invDet,
      (c * h - b * i) * invDet,
      (b * f - c * e) * invDet,
      (f * g - d * i) * invDet,
      (a * i - c * g) * invDet,
      (c * d - a * f) * invDet,
      (d * h - e * g) * invDet,
      (b * g - a * h) * invDet,
      (a * e - b * d) * invDet,
    ];
  }

  /// 归一化：平移到质心、按平均距离缩放到 √2（Hartley 归一化），
  /// 显著改善 DLT 的数值条件。
  static ({List<Offset> points, List<double> matrix})? _normalize(
    List<Offset> pts,
  ) {
    var cx = 0.0, cy = 0.0;
    for (final p in pts) {
      cx += p.dx;
      cy += p.dy;
    }
    cx /= pts.length;
    cy /= pts.length;
    var md = 0.0;
    for (final p in pts) {
      md += math.sqrt(math.pow(p.dx - cx, 2) + math.pow(p.dy - cy, 2));
    }
    md /= pts.length;
    if (md < 1e-9) return null;
    final s = math.sqrt2 / md;
    return (
      points: pts
          .map((p) => Offset((p.dx - cx) * s, (p.dy - cy) * s))
          .toList(growable: false),
      matrix: <double>[s, 0, -s * cx, 0, s, -s * cy, 0, 0, 1],
    );
  }

  /// 对称矩阵的最小特征值对应特征向量（循环 Jacobi 旋转）。
  ///
  /// 用于齐次 DLT：A h = 0 的最小二乘解即 AᵀA 最小特征向量。
  /// 相比「固定 h₈=1」的 8 元解法，这里不假设 h₈≠0，因而不受镜像/特殊
  /// 矩形对应等合法退化情形的限制（那正是 4 点矩形标定会踩到的坑）。
  static List<double>? _smallestEigenvector(List<List<double>> ata) {
    const n = 9;
    final a = [for (var i = 0; i < n; i++) List<double>.from(ata[i])];
    final v = [
      for (var i = 0; i < n; i++)
        [for (var j = 0; j < n; j++) i == j ? 1.0 : 0.0]
    ];

    for (var sweep = 0; sweep < 60; sweep++) {
      var off = 0.0;
      for (var p = 0; p < n; p++) {
        for (var q = p + 1; q < n; q++) {
          off += a[p][q] * a[p][q];
        }
      }
      if (off < 1e-20) break;

      for (var p = 0; p < n; p++) {
        for (var q = p + 1; q < n; q++) {
          if (a[p][q].abs() < 1e-18) continue;
          final theta = (a[q][q] - a[p][p]) / (2 * a[p][q]);
          final t = (theta >= 0 ? 1.0 : -1.0) /
              (theta.abs() + math.sqrt(theta * theta + 1));
          final c = 1 / math.sqrt(t * t + 1);
          final s = t * c;

          for (var k = 0; k < n; k++) {
            final akp = a[k][p], akq = a[k][q];
            a[k][p] = c * akp - s * akq;
            a[k][q] = s * akp + c * akq;
          }
          for (var k = 0; k < n; k++) {
            final apk = a[p][k], aqk = a[q][k];
            a[p][k] = c * apk - s * aqk;
            a[q][k] = s * apk + c * aqk;
          }
          for (var k = 0; k < n; k++) {
            final vkp = v[k][p], vkq = v[k][q];
            v[k][p] = c * vkp - s * vkq;
            v[k][q] = s * vkp + c * vkq;
          }
        }
      }
    }

    var mi = 0;
    for (var i = 1; i < n; i++) {
      if (a[i][i] < a[mi][mi]) mi = i;
    }
    if (!a[mi][mi].isFinite) return null;
    return [for (var k = 0; k < n; k++) v[k][mi]];
  }
}
