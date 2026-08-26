import 'dart:math' as math;
import 'dart:ui' as ui;

import 'axis_calibration.dart';

/// 轴网交点自动匹配校准（建筑工程"轴网套图"标准做法）。
///
/// 原理：工程图纸上最可靠的定位基准是「轴网交点」——底图（PDF 渲染）上的
/// 轴线交点集合与 CAD（DXF）中的轴网交点集合是**同一几何网格**，只是分处
/// 像素坐标系与毫米坐标系。通过 RANSAC 自动找出两组交点间的对应关系并拟合
/// 仿射变换，即可**完全自动**完成图纸校准，无需人工点选坐标。
///
/// 管线：
///   1. 底图侧：用 [detectAxisLines] 识别横/竖轴线 → [axisIntersections] 求交点（像素）
///   2. CAD 侧：服务端从 DXF 轴网层提取轴网交点（毫米），随 App 打包
///   3. [matchAxisIntersections]：两组交点 RANSAC 自动配对 + 最小二乘仿射拟合
///   4. 得到 [CadCoordMapper]，写入校准存储 → 打开图纸即精确对齐
///
/// 优势：完全离线、全自动、不依赖浏览器端手动校准；精度受底图渲染与轴网
/// 识别影响，通常可达图纸比例下的毫米级（<5mm），工程可用。

/// 从检测到的横/竖轴线计算轴网交点（像素坐标，原图坐标系）。
///
/// 水平线与垂直线两两求交：交点 (x_v, y_h)，其中 x 取竖线横坐标、y 取横线纵坐标。
/// 返回交点列表（按 x 升序、x 相同时 y 升序，便于调试/稳定输出）。
List<ui.Offset> axisIntersections(AxisGrid grid) {
  final xs = <double>{};
  for (final v in grid.verticals) {
    xs.add(v.a.dx);
  }
  final ys = <double>{};
  for (final h in grid.horizontals) {
    ys.add(h.a.dy);
  }
  final sx = xs.toList()..sort();
  final sy = ys.toList()..sort();
  final pts = <ui.Offset>[];
  for (final x in sx) {
    for (final y in sy) {
      pts.add(ui.Offset(x, y));
    }
  }
  return pts;
}

/// 轴网自动匹配结果。
class AxisMatchResult {
  /// 拟合出的坐标映射（像素 → 毫米）；null 表示匹配失败（内点不足）。
  final AffineFitResult? fit;

  /// 匹配上的内点（一致的交点对，像素 ↔ 毫米）。
  final List<CalibPointPair> inliers;

  /// 估计的缩放（mm/px，X/Y 取平均）。
  final double scale;

  /// 估计的旋转角（弧度）。
  final double angle;

  /// 匹配总尝试次数。
  final int trials;

  const AxisMatchResult({
    required this.fit,
    required this.inliers,
    required this.scale,
    required this.angle,
    required this.trials,
  });

  bool get success => fit != null;
}

/// 对两组轴网交点做 RANSAC 自动配对并拟合仿射校准。
///
/// [imgPts]：底图检测到的轴网交点（像素坐标）
/// [cadPts]：DXF 提取的轴网交点（毫米坐标）
/// [imgW]/[imgH]：底图像素尺寸，用于构造 mapper
///
/// 算法（RANSAC + 相似变换假设）：
///   1. 随机取底图 2 点与 CAD 2 点，假设对应 → 解出相似变换 (scale, angle, tx, ty)
///   2. 用该变换映射全部底图交点，在 CAD 交点中找最近邻，距离 < [matchRadiusMm] 计为内点
///   3. 迭代 [trials] 次，保留内点最多的假设
///   4. 用全部内点做最小二乘仿射精拟合 + 残差剔除（[fitAffineRobust]）
///
/// 内点数 < [minInliers] 时判定失败（fit=null），此时应回退手动校准。
AxisMatchResult matchAxisIntersections(
  List<ui.Offset> imgPts,
  List<ui.Offset> cadPts,
  double imgW,
  double imgH, {
  int trials = 2000,
  double matchRadiusMm = 2000,
  int minInliers = 3,
  double minScale = 0.001,
  double maxScale = 2000,
  bool verbose = false,
}) {
  if (imgPts.length < 2 || cadPts.length < 2) {
    return const AxisMatchResult(
        fit: null, inliers: [], scale: 1, angle: 0, trials: 0);
  }

  // 优先使用确定性网格匹配（利用行列结构，避免 RANSAC 在规则网格上的
  // 对称局部最优）；失败再回退 RANSAC。
  final det = matchAxisGridDeterministic(
    imgPts,
    cadPts,
    imgW,
    imgH,
    minScale: minScale,
    maxScale: maxScale,
  );
  if (det != null && det.fit != null) {
    return det;
  }

  final rng = math.Random(0x5EED);

  // RANSAC 阶段匹配半径：应能容忍「平移偏移一格」的采样假设，
  // 否则 δ=0 的正确假设（命中概率极低）几乎采不到。
  final gridSpacing = _minGridSpacingOf(cadPts);
  final ransacRadius = (gridSpacing > 0)
      ? math.max(matchRadiusMm, gridSpacing * 1.2)
      : matchRadiusMm;

  /// 用相似变换（scale, angle, t）把底图点映射到 CAD 坐标系。
  /// 变换约定：CAD = R(angle)*scale*flipY(pixel) + t，flipY 使像素 Y 向下 → CAD Y 向上。
  /// X' = (cosA*px + sinA*py)*scale + tx；Y' = (sinA*px - cosA*py)*scale + ty。
  ui.Offset _map(ui.Offset p, double scale, double angle, ui.Offset t) {
    final c = math.cos(angle), s = math.sin(angle);
    final px = p.dx, py = p.dy;
    return ui.Offset(
      (c * px + s * py) * scale + t.dx,
      (s * px - c * py) * scale + t.dy,
    );
  }

  /// 一对一贪心匹配：对每个底图点找最近 CAD 点，但每个 CAD 点最多匹配一次。
  /// 返回 (点对, 是否全部落在半径内)。
  List<CalibPointPair> _matchOneToOne(
      double scale, double angle, ui.Offset t, double radius) {
    // 收集所有候选 (imgIdx, cadIdx, dist)，按 dist 升序贪心配对
    final cands = <(int, int, double)>[];
    for (var i = 0; i < imgPts.length; i++) {
      final w = _map(imgPts[i], scale, angle, t);
      var bestD = double.infinity;
      var bestJ = -1;
      for (var j = 0; j < cadPts.length; j++) {
        final d = (w - cadPts[j]).distance;
        if (d < bestD) {
          bestD = d;
          bestJ = j;
        }
      }
      if (bestJ >= 0 && bestD <= radius) {
        cands.add((i, bestJ, bestD));
      }
    }
    cands.sort((a, b) => a.$3.compareTo(b.$3));
    final usedImg = Set<int>();
    final usedCad = Set<int>();
    final pairs = <CalibPointPair>[];
    for (final (i, j, _) in cands) {
      if (usedImg.contains(i) || usedCad.contains(j)) continue;
      usedImg.add(i);
      usedCad.add(j);
      pairs.add(CalibPointPair(pixel: imgPts[i], world: cadPts[j]));
    }
    return pairs;
  }

  // RANSAC：收集内点数达到阈值的候选假设（按内点数排序保留前 [topCandidates]）。
  final candidates =
      <({double scale, double angle, ui.Offset t, int inliers})>[];
  var guardAll = 0;
  for (var t = 0; t < trials; t++) {
    // 随机采样底图 2 点（必须不重合）
    final i1 = rng.nextInt(imgPts.length);
    var i2 = rng.nextInt(imgPts.length);
    guardAll = 0;
    while ((imgPts[i1] - imgPts[i2]).distance < 1.0 && guardAll++ < 20) {
      i2 = rng.nextInt(imgPts.length);
    }
    if (guardAll >= 20) continue;
    final p1 = imgPts[i1], p2 = imgPts[i2];

    // 随机采样 CAD 2 点
    final j1 = rng.nextInt(cadPts.length);
    var j2 = rng.nextInt(cadPts.length);
    guardAll = 0;
    while ((cadPts[j1] - cadPts[j2]).distance < 1e-3 && guardAll++ < 20) {
      j2 = rng.nextInt(cadPts.length);
    }
    if (guardAll >= 20) continue;
    final q1 = cadPts[j1], q2 = cadPts[j2];

    // 估计缩放：|dq|/|dp|，须在合理范围
    final dp = p2 - p1;
    final dq = q2 - q1;
    final dLenP = dp.distance;
    final dLenQ = dq.distance;
    if (dLenP < 1e-6) continue;
    final scale = dLenQ / dLenP;
    if (scale < minScale || scale > maxScale) continue;

    // 估计旋转角（CAD Y 向上 = 像素 Y 向下：像素向量翻转 Y 后与 CAD 向量求夹角）
    final dpF = ui.Offset(dp.dx, -dp.dy);
    final cross = dpF.dx * dq.dy - dpF.dy * dq.dx;
    final dot = dpF.dx * dq.dx + dpF.dy * dq.dy;
    final angle = math.atan2(cross, dot);

    // 平移：要求 _map(p1) == q1
    final c = math.cos(angle), s = math.sin(angle);
    final tx = q1.dx - (c * p1.dx + s * p1.dy) * scale;
    final ty = q1.dy - (s * p1.dx - c * p1.dy) * scale;
    final t = ui.Offset(tx, ty);

    final inl = _matchOneToOne(scale, angle, t, ransacRadius);
    if (inl.length < minInliers) continue;
    candidates.add((scale: scale, angle: angle, t: t, inliers: inl.length));
  }
  if (verbose) {
    // ignore: avoid_print
    print('  [verb] candidates: ${candidates.length}');
  }
  candidates.sort((a, b) => b.inliers.compareTo(a.inliers));
  final top = candidates.length > 30
      ? candidates.sublist(0, 30)
      : candidates;

  // 对每个候选做「相似变换最小二乘精修 + 重匹配 + 仿射拟合」。
  // 选择策略：优先内点数多（正确解能匹配到全部交点），
  // 内点数相同时选残差小（排除网格错位的局部最优）。
  int bestInlierCount = -1;
  double bestResidual = double.infinity;
  var bestInliers = <CalibPointPair>[];
  var bestScale = 1.0, bestAngle = 0.0;
  for (final cand in top) {
    var cScale = cand.scale, cAngle = cand.angle, cT = cand.t;
    var cInl = _matchOneToOne(cScale, cAngle, cT, matchRadiusMm);
    if (cInl.length < minInliers) continue;
    final rawCount = cInl.length;
    // 相似最小二乘精修
    final sim = _fitSimilarity(cInl);
    if (sim != null) {
      cScale = sim.scale;
      cAngle = sim.angle;
      cT = sim.t;
      final rem = _matchOneToOne(cScale, cAngle, cT, matchRadiusMm);
      if (rem.length >= minInliers) cInl = rem;
    }
    final fit = fitAffineRobust(
      cInl,
      imgW,
      imgH,
      maxResidualMm: matchRadiusMm,
      maxIters: 3,
    );
    if (fit == null) continue;
    if (verbose && (cInl.length > 30 || cand.inliers > 30)) {
      // ignore: avoid_print
      print('  [verb] cand raw=${cand.inliers} (match=${rawCount}) '
          '-> after=${cInl.length} resid=${fit.meanResidualMm.toStringAsFixed(2)} '
          'scale=${cScale.toStringAsFixed(3)} angle=${cAngle.toStringAsFixed(3)}');
    }
    if (cInl.length > bestInlierCount ||
        (cInl.length == bestInlierCount && fit.meanResidualMm < bestResidual)) {
      bestInlierCount = cInl.length;
      bestResidual = fit.meanResidualMm;
      bestInliers = cInl;
      bestScale = cScale;
      bestAngle = cAngle;
    }
  }

  if (verbose) {
    // ignore: avoid_print
    print('  [verb] selected: scale=$bestScale angle=$bestAngle '
        'inliers=${bestInliers.length} residual=$bestResidual');
  }

  if (bestInliers.length < minInliers) {
    return AxisMatchResult(
      fit: null,
      inliers: bestInliers,
      scale: bestScale,
      angle: bestAngle,
      trials: trials,
    );
  }

  // 用内点做最小二乘仿射精拟合 + 残差剔除
  var robust = fitAffineRobust(
    bestInliers,
    imgW,
    imgH,
    maxResidualMm: matchRadiusMm,
    maxIters: 3,
  );

  // 精化迭代（ICP 式）：用当前 mapper 重新映射全部底图点做一对一匹配，
  // 再用新内点重新拟合，通常 1~2 次即可收敛到 <1mm。
  // 精化半径按轴网最小格距自适应收紧，避免匹配到相邻交点。
  var cur = robust;
  final adaptiveRadius = _minGridSpacing(cadPts, bestInliers);
  final refineRadius =
      (adaptiveRadius > 0) ? math.min(matchRadiusMm, adaptiveRadius * 0.4) : matchRadiusMm;

  for (var iter = 0; iter < 2 && cur != null; iter++) {
    final mapper = cur.mapper;
    final cands = <(int, int, double)>[];
    for (var i = 0; i < imgPts.length; i++) {
      final w = mapper.screenToWorld(imgPts[i].dx, imgPts[i].dy);
      var bestD = double.infinity;
      var bestJ = -1;
      for (var j = 0; j < cadPts.length; j++) {
        final d = (w - cadPts[j]).distance;
        if (d < bestD) {
          bestD = d;
          bestJ = j;
        }
      }
      if (bestJ >= 0 && bestD <= refineRadius) {
        cands.add((i, bestJ, bestD));
      }
    }
    cands.sort((a, b) => a.$3.compareTo(b.$3));
    final usedImg = Set<int>();
    final usedCad = Set<int>();
    final refined = <CalibPointPair>[];
    for (final (i, j, _) in cands) {
      if (usedImg.contains(i) || usedCad.contains(j)) continue;
      usedImg.add(i);
      usedCad.add(j);
      refined.add(CalibPointPair(pixel: imgPts[i], world: cadPts[j]));
    }
    if (refined.length < minInliers) break;
    final next = fitAffineRobust(
      refined,
      imgW,
      imgH,
      maxResidualMm: refineRadius,
      maxIters: 3,
    );
    if (next == null) break;
    // 若残差未改善则结束
    if (next.meanResidualMm >= cur.meanResidualMm) break;
    cur = next;
    bestInliers = refined;
  }
  robust = cur;

  return AxisMatchResult(
    fit: robust,
    inliers: bestInliers,
    scale: bestScale,
    angle: bestAngle,
    trials: trials,
  );
}

/// 相似变换最小二乘：从点对估计 (scale, angle, t)，使 qi ≈ _map(pi)。
/// 返回 null 表示退化。用于 RANSAC 采样后的精修，比单次 2 点采样更稳。
({double scale, double angle, ui.Offset t})? _fitSimilarity(
    List<CalibPointPair> pairs) {
  if (pairs.length < 2) return null;
  // xi = flipY(p) = (px, -py)；q = scale*R(angle)*xi + t
  // 线性化：q.x = a_*xi.x - b_*xi.y + tx；q.y = b_*xi.x + a_*xi.y + ty
  // 其中 a_ = scale*cos(angle)，b_ = scale*sin(angle)。
  double sxx = 0, syy = 0, sx = 0, sy = 0;
  double s_qxx = 0, s_qxy = 0, s_qyx = 0, s_qyy = 0, sqx = 0, sqy = 0;
  for (final p in pairs) {
    final xi = p.pixel.dx, yi = -p.pixel.dy; // flipY
    final qx = p.world.dx, qy = p.world.dy;
    sxx += xi * xi;
    syy += yi * yi;
    sx += xi;
    sy += yi;
    s_qxx += qx * xi;
    s_qxy -= qx * yi;
    s_qyx += qy * xi;
    s_qyy += qy * yi;
    sqx += qx;
    sqy += qy;
  }
  final n = pairs.length.toDouble();
  // 4x4 正规方程 M v = b, v = [a_, b_, tx, ty]
  // M:
  final m11 = sxx + syy, m12 = 0.0, m13 = sx, m14 = sy;
  final m22 = sxx + syy, m23 = -sy, m24 = sx;
  final m33 = n, m34 = 0.0;
  final m44 = n;
  // A^T b：b1 = Σ(qx·xi + qy·yi)，b2 = Σ(-qx·yi + qy·xi)
  final b1 = s_qxx + s_qyy, b2 = s_qxy + s_qyx, b3 = sqx, b4 = sqy;
  // 4x4 对称矩阵：m12=0, m34=0, m13=m31=sx, m14=m41=sy, m23=m32=-sy, m24=m42=sx
  final sol = _solveLinear4(
    m11, m12, m13, m14, b1,
    m12, m22, m23, m24, b2,
    m13, m23, m33, m34, b3,
    m14, m24, m34, m44, b4,
  );
  if (sol == null) return null;
  final a_ = sol[0], b_ = sol[1];
  final scale = math.sqrt(a_ * a_ + b_ * b_);
  if (scale < 1e-9) return null;
  final angle = math.atan2(b_, a_);
  return (scale: scale, angle: angle, t: ui.Offset(sol[2], sol[3]));
}

/// 从 CAD 交点集全集估算轴网最小格距（X/Y 方向各取最小相邻差）。
double _minGridSpacingOf(List<ui.Offset> cadPts) {
  final xs = cadPts.map((p) => p.dx).toList()..sort();
  final ys = cadPts.map((p) => p.dy).toList()..sort();
  double minDx = double.infinity, minDy = double.infinity;
  for (var i = 1; i < xs.length; i++) {
    final d = xs[i] - xs[i - 1];
    if (d > 1e-3 && d < minDx) minDx = d;
  }
  for (var i = 1; i < ys.length; i++) {
    final d = ys[i] - ys[i - 1];
    if (d > 1e-3 && d < minDy) minDy = d;
  }
  final m = math.min(minDx, minDy);
  return m.isFinite ? m : 0;
}

/// 从 CAD 交点集估算轴网最小格距（用于精化半径收紧）。
double _minGridSpacing(List<ui.Offset> cadPts, List<CalibPointPair> inliers) {
  // 用内点的 CAD 坐标求最小间距（X/Y 方向）
  final xs = inliers.map((p) => p.world.dx).toList()..sort();
  final ys = inliers.map((p) => p.world.dy).toList()..sort();
  double minDx = double.infinity, minDy = double.infinity;
  for (var i = 1; i < xs.length; i++) {
    final d = xs[i] - xs[i - 1];
    if (d > 1e-3 && d < minDx) minDx = d;
  }
  for (var i = 1; i < ys.length; i++) {
    final d = ys[i] - ys[i - 1];
    if (d > 1e-3 && d < minDy) minDy = d;
  }
  final m = math.min(minDx, minDy);
  return m.isFinite ? m : 0;
}

/// 解 4x4 线性系统（对称矩阵，仅存上三角）。返回 null 表示奇异。
List<double>? _solveLinear4(
    double m11, double m12, double m13, double m14, double b1,
    double m21, double m22, double m23, double m24, double b2,
    double m31, double m32, double m33, double m34, double b3,
    double m41, double m42, double m43, double m44, double b4) {
  // 高斯消元（部分主元）
  var a = [
    [m11, m12, m13, m14, b1],
    [m21, m22, m23, m24, b2],
    [m31, m32, m33, m34, b3],
    [m41, m42, m43, m44, b4],
  ];
  for (var col = 0; col < 4; col++) {
    // 找主元
    var piv = col;
    for (var r = col + 1; r < 4; r++) {
      if (a[r][col].abs() > a[piv][col].abs()) piv = r;
    }
    if (a[piv][col].abs() < 1e-12) return null;
    if (piv != col) {
      final tmp = a[col];
      a[col] = a[piv];
      a[piv] = tmp;
    }
    for (var r = col + 1; r < 4; r++) {
      final f = a[r][col] / a[col][col];
      for (var c = col; c < 5; c++) {
        a[r][c] -= f * a[col][c];
      }
    }
  }
  // 回代
  final x = List<double>.filled(4, 0);
  for (var r = 3; r >= 0; r--) {
    var s = a[r][4];
    for (var c = r + 1; c < 4; c++) {
      s -= a[r][c] * x[c];
    }
    x[r] = s / a[r][r];
  }
  return x;
}

/// 确定性网格匹配：利用轴网「行列结构」直接对齐底图交点与 CAD 交点。
///
/// 原理：轴网是正交规则网格，X/Y 方向可各自独立做一维匹配（投票求
/// 缩放与平移），再组合行列对应得到交点对。比 RANSAC 更可靠——
/// 规则网格的高度对称性会让 RANSAC 陷入"错位一格"的局部最优。
///
/// 步骤：
///   1. 提取底图/ CAD 交点集的 X、Y 坐标集合
///   2. X 方向：在跨度比 ±30% 内扫描 scale，对每个 scale 投票最佳平移 tx
///   3. Y 方向：像素 Y 向下 → CAD Y 向上，对翻转后的 Y 坐标同样投票
///   4. 行列对应 → 交点对 → 最小二乘仿射拟合（含残差剔除）
///
/// 返回 null 表示行列匹配失败（交点过少/非规则网格）。
AxisMatchResult? matchAxisGridDeterministic(
  List<ui.Offset> imgPts,
  List<ui.Offset> cadPts,
  double imgW,
  double imgH, {
  double minScale = 0.001,
  double maxScale = 2000,
}) {
  if (imgPts.length < 4 || cadPts.length < 4) return null;
  final imgXs = imgPts.map((p) => p.dx).toSet().toList()..sort();
  final imgYs = imgPts.map((p) => p.dy).toSet().toList()..sort();
  final cadXs = cadPts.map((p) => p.dx).toSet().toList()..sort();
  final cadYs = cadPts.map((p) => p.dy).toSet().toList()..sort();
  if (imgXs.length < 2 || imgYs.length < 2 || cadXs.length < 2 || cadYs.length < 2) {
    return null;
  }

  // X 方向一维匹配
  final mx = _matchAxis1D(imgXs, cadXs, minScale, maxScale);
  // Y 方向：像素 Y 向下 → CAD Y 向上，翻转像素 Y 后匹配
  final imgYf = imgYs.map((y) => -y).toList()..sort();
  final my = _matchAxis1D(imgYf, cadYs, minScale, maxScale);
  if (mx == null || my == null) return null;

  // 行列对应：每个底图坐标 → 最近的 CAD 坐标（依据 scale/tx）。
  // 容差自适应：detectAxisLines 用 min-pooling 降采样，轴线质心会有几个像素
  // 误差（sampleW≈700 时约 ±4px），故容差取 scale*4px 与 5mm 的较大者。
  final alignTolMm = math.max(5.0, mx.scale * 4.0);
  List<(double, double)> alignX(List<double> img, List<double> cad,
      double scale, double tx) {
    final out = <(double, double)>[];
    for (final ic in img) {
      final proj = ic * scale + tx;
      var bestD = double.infinity;
      double bestC = 0;
      for (final cc in cad) {
        final d = (cc - proj).abs();
        if (d < bestD) {
          bestD = d;
          bestC = cc;
        }
      }
      if (bestD <= alignTolMm) {
        out.add((ic, bestC));
      }
    }
    return out;
  }

  final xMap = alignX(imgXs, cadXs, mx.scale, mx.tx);
  final yMap = alignY(imgYs, cadYs, my.scale, my.tx);
  if (xMap.length < 2 || yMap.length < 2) return null;

  // 组合交点对：对每个底图交点，行列都匹配才保留
  final xByImg = <double, double>{}; // imgX -> cadX
  for (final (ic, cc) in xMap) {
    xByImg[ic] = cc;
  }
  final yByImg = <double, double>{}; // imgY -> cadY
  for (final (ic, cc) in yMap) {
    yByImg[ic] = cc;
  }
  final pairs = <CalibPointPair>[];
  for (final p in imgPts) {
    final cx = xByImg[p.dx];
    final cy = yByImg[p.dy];
    if (cx != null && cy != null) {
      pairs.add(CalibPointPair(pixel: p, world: ui.Offset(cx, cy)));
    }
  }
  // 覆盖率校验：真实场景底图检测会混入墙线/文字等非轴网线，交点里可能
  // 只有一部分落在 CAD 轴网上。放宽到 25% 且至少 6 个配对，由后续
  // 仿射拟合残差把关（均值残差 >10mm 仍判失败），避免错误套图。
  final minPairs = math.max(6, (imgPts.length * 0.25).ceil());
  if (pairs.length < minPairs) return null;

  final fit = fitAffineRobust(
    pairs,
    imgW,
    imgH,
    maxResidualMm: 50,
    maxIters: 3,
  );
  // 残差校验：行列错配会得到大残差
  if (fit == null || fit.meanResidualMm > 10.0) return null;
  return AxisMatchResult(
    fit: fit,
    inliers: pairs,
    scale: (mx.scale + (-my.scale)) / 2,
    angle: 0,
    trials: 0,
  );
}

/// 一维坐标匹配：投票求 scale 与平移 tx，使 imgCoords*scale + tx ≈ cadCoords。
/// 返回 null 表示匹配失败。
///
/// scale 估计用「间距比值投票」：真实轴网相邻间距比值集中（如 60/120=0.5），
/// 而干扰/离群点间距比值分散，投票众数即真实 scale——对大量干扰点鲁棒。
({double scale, double tx, int matches})? _matchAxis1D(
    List<double> imgCoords,
    List<double> cadCoords,
    double minScale,
    double maxScale) {
  if (imgCoords.length < 2 || cadCoords.length < 2) return null;
  final spanI = imgCoords.last - imgCoords.first;
  final spanC = cadCoords.last - cadCoords.first;
  if (spanI < 1e-6 || spanC < 1e-6) return null;

  // 1) 间距比值投票估计 scale
  final imgGaps = <double>[];
  for (var i = 1; i < imgCoords.length; i++) {
    final d = imgCoords[i] - imgCoords[i - 1];
    if (d > 1e-6) imgGaps.add(d);
  }
  final cadGaps = <double>[];
  for (var i = 1; i < cadCoords.length; i++) {
    final d = cadCoords[i] - cadCoords[i - 1];
    if (d > 1e-6) cadGaps.add(d);
  }
  final ratioVotes = <int, int>{};
  const ratioBins = 2000;
  double? bestRatio;
  var bestRatioVotes = 0;
  final logRange = math.log(maxScale / minScale);
  for (final gi in imgGaps) {
    for (final gc in cadGaps) {
      final r = gc / gi;
      if (r < minScale || r > maxScale) continue;
      final bin =
          ((math.log(r / minScale) / logRange) * ratioBins).round().clamp(0, ratioBins);
      final cnt = (ratioVotes[bin] ?? 0) + 1;
      ratioVotes[bin] = cnt;
      if (cnt > bestRatioVotes) {
        bestRatioVotes = cnt;
        bestRatio = r;
      }
    }
  }
  if (bestRatio == null) return null;
  final sMid = bestRatio;

  // 2) 在 sMid 附近 ±5% 精细扫描投票平移 tx。
  //    用「差值投票」消除绝对偏移敏感：以第一条线为基准，投影间距
  //    imgGap_i*scale 与 cad 相邻间距匹配，tol 取 CAD 平均间距的 1/10
  //    （轴网像素误差 ±4px 放大的 mm 误差远小于 1/10 间距）。
  int bestMatches = -1;
  double bestS = sMid, bestT = 0;
  // tol 取「真实网格间距」的 1/10：用中位数估计网格间距，
  // 避免随机干扰点产生的超大/超小间距拉偏平均值。
  final sortedGaps = cadGaps.toList()..sort();
  final medCadGap = sortedGaps.length >= 3
      ? sortedGaps[sortedGaps.length ~/ 2]
      : (sortedGaps.isNotEmpty ? sortedGaps.last : spanC / math.max(1, cadCoords.length - 1));
  final tol = math.max(1.0, medCadGap / 10.0);
  for (var k = 0; k <= 200; k++) {
    final s = sMid * (0.95 + 0.1 * k / 200.0);
    if (s < minScale || s > maxScale) continue;
    final votes = <int, int>{};
    for (var ii = 0; ii < imgCoords.length; ii++) {
      final base = imgCoords[ii] * s;
      for (var ci = 0; ci < cadCoords.length; ci++) {
        final t = cadCoords[ci] - base;
        final bin = (t / tol).round();
        votes[bin] = (votes[bin] ?? 0) + 1;
      }
    }
    var maxV = 0, bestBin = 0;
    votes.forEach((bin, cnt) {
      if (cnt > maxV) {
        maxV = cnt;
        bestBin = bin;
      }
    });
    if (maxV > bestMatches) {
      bestMatches = maxV;
      bestS = s;
      bestT = bestBin * tol;
    }
  }
  if (bestMatches < 2) return null;
  return (scale: bestS, tx: bestT, matches: bestMatches);
}

/// Y 方向坐标对应（像素 Y 向下 → CAD Y 向上）：
/// 已用翻转后的 imgYf 匹配，需把匹配结果映射回原始 imgY。
List<(double, double)> alignY(List<double> imgYs, List<double> cadYs,
    double scale, double tx) {
  // 与 alignX 相同的自适应容差：容忍 min-pooling 的像素级误差。
  final alignTolMm = math.max(5.0, scale * 4.0);
  final out = <(double, double)>[];
  for (final y in imgYs) {
    final proj = (-y) * scale + tx; // imgY 翻转后映射
    var bestD = double.infinity;
    double bestC = 0;
    for (final cc in cadYs) {
      final d = (cc - proj).abs();
      if (d < bestD) {
        bestD = d;
        bestC = cc;
      }
    }
    if (bestD <= alignTolMm) {
      out.add((y, bestC));
    }
  }
  return out;
}

/// 从 [AxisGrid]（已检测的底图轴线）直接计算交点并做自动匹配校准。
///
/// 便捷封装：底图侧交点 + CAD 侧交点 → [matchAxisIntersections]。
AxisMatchResult calibrateByAxisGrid(
  AxisGrid grid,
  List<ui.Offset> cadIntersections,
  double imgW,
  double imgH, {
  int trials = 400,
  double matchRadiusMm = 2000,
  int minInliers = 3,
}) {
  final imgPts = axisIntersections(grid);
  if (imgPts.length < 2) {
    return const AxisMatchResult(
        fit: null, inliers: [], scale: 1, angle: 0, trials: 0);
  }
  return matchAxisIntersections(
    imgPts,
    cadIntersections,
    imgW,
    imgH,
    trials: trials,
    matchRadiusMm: matchRadiusMm,
    minInliers: minInliers,
  );
}
