import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;

import '../utils/cad_coord.dart';

/// 轴网（红线）自动识别 + 两点坐标校准。
///
/// 工程图纸上最可靠的定位基准是「轴线」：正交、间距已知（开间/进深，mm）、
/// 贯穿全图，比肉眼找比例尺更准。本模块提供：
///  1. [detectAxisLines]：对图纸位图做降采样 + 暗像素扫描，自动找出横/竖长线
///     （即工程图里的"红线"），叠加在图上供用户对准。
///  2. [fitAffineTwoPoints]：给定两个像素点与其真实图纸坐标（mm），
///     解出仿射系数 {a,b=0,c,d,e=0,f}，无需浏览器端手动导出 JSON。
///
/// 设计动机：移动端/平板端无法打开浏览器版 GStarSDK 校准面板，
/// 用"识别轴线 + 两点坐标"即可在 App 内完成校准（精度取决于点选，<10mm 级）。

/// 一条检测到的轴线（像素坐标，原图坐标系）。
class AxisLine {
  final ui.Offset a;
  final ui.Offset b;
  const AxisLine(this.a, this.b);

  double get length => (a - b).distance;
}

/// 轴网检测结果。
class AxisGrid {
  final List<AxisLine> horizontals;
  final List<AxisLine> verticals;
  const AxisGrid({required this.horizontals, required this.verticals});
}

/// 从 RGBA 位图检测正交轴线。
///
/// [rgba] 为 rawRgba 字节流（4 字节/像素），[imgW]/[imgH] 为原始像素尺寸。
/// 返回检测到的横/竖轴线（原图像素坐标），按长度降序，最多各 [maxLines] 条。
///
/// 算法（针对工程图纸白底黑线）：
///  1. min-pooling 降采样到约 [sampleW] 宽（每块取最暗像素，保住 2px 细线）；
///  2. 逐行/逐列统计"暗像素占比"，占比超阈值的行/列聚合成线（取质心）。
AxisGrid detectAxisLines(
  Uint8List rgba,
  int imgW,
  int imgH, {
  double sampleW = 900,
  double darkThreshold = 128,
  double coverageMin = 0.55,
  int maxLines = 24,
}) {
  if (imgW <= 0 || imgH <= 0) return const AxisGrid(horizontals: [], verticals: []);

  final sw = math.min(sampleW.toInt(), imgW);
  final sh = math.max(1, (imgH * sw / imgW).round());
  final kx = imgW / sw; // 每采样块的像素宽
  final ky = imgH / sh;

  // 1. min-pooling：块内取最暗（灰度最小）
  final g = Int8List(sw * sh); // 0=白 ... 255=黑
  for (var y = 0; y < sh; y++) {
    final y0 = (y * ky).floor();
    final y1 = math.min(imgH - 1, ((y + 1) * ky).floor() + 1);
    for (var x = 0; x < sw; x++) {
      final x0 = (x * kx).floor();
      final x1 = math.min(imgW - 1, ((x + 1) * kx).floor() + 1);
      var darkest = 0;
      for (var yy = y0; yy < y1; yy++) {
        var rowOff = yy * imgW * 4;
        for (var xx = x0; xx < x1; xx++) {
          final off = rowOff + xx * 4;
          // 灰度 = (r+g+b)/3，近似用最大通道？白底图黑线用 min 通道更稳。
          final r = rgba[off];
          final g_ = rgba[off + 1];
          final b = rgba[off + 2];
          final gray = (r * 299 + g_ * 587 + b * 114) ~/ 1000;
          if (gray > darkest) darkest = gray;
        }
        rowOff += imgW * 4;
      }
      g[y * sw + x] = darkest.toInt();
    }
  }

  // 2. 横向扫描：每行暗像素占比
  final hCov = List<double>.filled(sh, 0);
  for (var y = 0; y < sh; y++) {
    var dark = 0;
    for (var x = 0; x < sw; x++) {
      if (g[y * sw + x] > darkThreshold) dark++;
    }
    hCov[y] = dark / sw;
  }
  // 3. 竖向扫描：每列暗像素占比
  final vCov = List<double>.filled(sw, 0);
  for (var x = 0; x < sw; x++) {
    var dark = 0;
    for (var y = 0; y < sh; y++) {
      if (g[y * sw + x] > darkThreshold) dark++;
    }
    vCov[x] = dark / sh;
  }

  // 聚合连续行/列（占比 > coverageMin）为线，取质心位置映射回原图。
  List<AxisLine> collectRows() {
    final lines = <AxisLine>[];
    var y = 0;
    while (y < sh) {
      if (hCov[y] > coverageMin) {
        var runStart = y;
        var sum = 0.0;
        var cnt = 0.0;
        while (y < sh && hCov[y] > coverageMin) {
          sum += y * hCov[y];
          cnt += hCov[y];
          y++;
        }
        final cy = (cnt > 0 ? sum / cnt : (runStart + y - 1) / 2) / sh * imgH;
        lines.add(AxisLine(ui.Offset(0, cy), ui.Offset(imgW.toDouble(), cy)));
      }
      y++;
    }
    return lines;
  }

  List<AxisLine> collectCols() {
    final lines = <AxisLine>[];
    var x = 0;
    while (x < sw) {
      if (vCov[x] > coverageMin) {
        var sum = 0.0;
        var cnt = 0.0;
        while (x < sw && vCov[x] > coverageMin) {
          sum += x * vCov[x];
          cnt += vCov[x];
          x++;
        }
        final cx = (cnt > 0 ? sum / cnt : (x - 1)) / sw * imgW;
        lines.add(AxisLine(ui.Offset(cx, 0), ui.Offset(cx, imgH.toDouble())));
      }
      x++;
    }
    return lines;
  }

  final hs = collectRows()..sort((a, b) => b.length.compareTo(a.length));
  final vs = collectCols()..sort((a, b) => b.length.compareTo(a.length));
  return AxisGrid(
    horizontals: hs.take(maxLines).toList(),
    verticals: vs.take(maxLines).toList(),
  );
}

/// 一组校准点对：像素坐标 + 真实图纸坐标（mm）。
class CalibPointPair {
  final ui.Offset pixel;
  final ui.Offset world;
  const CalibPointPair({required this.pixel, required this.world});
}

/// 最小二乘仿射拟合结果。
class AffineFitResult {
  final CadCoordMapper mapper;
  /// 各点在世界坐标下的残差（欧氏距离，mm），与输入点对一一对应。
  final List<double> residuals;
  /// 平均残差（mm），可用于提示校准质量。
  final double meanResidualMm;
  /// 最大残差（mm）。
  final double maxResidualMm;
  const AffineFitResult({
    required this.mapper,
    required this.residuals,
    required this.meanResidualMm,
    required this.maxResidualMm,
  });
}

/// 完整 6 参数仿射最小二乘拟合（支持旋转/斜交失真）。
///
/// 内部建模：
///   worldX = a*px + b*py + c
///   worldY = dY*px + eY*py + f
/// 返回的 [CadCoordMapper] 已按 `screenToWorld` 语义（Y = d*py + e*px + f，
/// d 是 py 系数）交换 d/e。
///
/// [pairs] 需 ≥3 组且像素点不共线；[imgW]/[imgH] 仅用于构造 mapper 的视图尺寸。
/// 返回 null 表示秩亏（共线/太少）无法解算。
CadCoordMapper? fitAffineLeastSquares(
  List<CalibPointPair> pairs,
  double imgW,
  double imgH,
) {
  if (pairs.length < 3) return null;
  // 构造正规方程 A^T A x = A^T b（3 未知数/输出维度）。
  // X 维：列 [px, py, 1] → 未知 [a, b, c]
  // Y 维：列 [px, py, 1] → 未知 [d, e, f]
  var sxx = 0.0, syy = 0.0, sx = 0.0, sy = 0.0, n = 0.0;
  var sxy = 0.0, sxw = 0.0, syw = 0.0, sw = 0.0;
  for (final p in pairs) {
    final px = p.pixel.dx, py = p.pixel.dy;
    final wx = p.world.dx;
    n += 1;
    sx += px;
    sy += py;
    sxx += px * px;
    syy += py * py;
    sxy += px * py;
    sxw += px * wx;
    syw += py * wx;
    sw += wx;
  }
  // 正规方程矩阵 M = [[sxx, sxy, sx], [sxy, syy, sy], [sx, sy, n]]
  final det = _det3(
    sxx, sxy, sx,
    sxy, syy, sy,
    sx, sy, n,
  );
  if (det.abs() < 1e-12) return null; // 共线或退化

  // X 维解 [a, b, c]
  final bx = _solve3(
    sxx, sxy, sx, sxw,
    sxy, syy, sy, syw,
    sx, sy, n, sw,
  );
  // Y 维（同样的 M，右侧换 [sx, sy, n]×worldY 项）
  var sxwY = 0.0, sywY = 0.0, swY = 0.0;
  for (final p in pairs) {
    final px = p.pixel.dx, py = p.pixel.dy;
    final wy = p.world.dy;
    sxwY += px * wy;
    sywY += py * wy;
    swY += wy;
  }
  final by = _solve3(
    sxx, sxy, sx, sxwY,
    sxy, syy, sy, sywY,
    sx, sy, n, swY,
  );
  if (bx == null || by == null) return null;

  // ★ 注意：此处解出的 Y 维系数为 worldY = by[0]*px + by[1]*py + by[2]，
  //   而 CadCoordMapper.screenToWorld 的 Y 维语义为 wy = d*py + e*px + f
  //   （d 是 py 系数）。因此需交换 by[0]↔by[1] 再传给 mapper。
  return CadCoordMapper.fromAffine(
    viewWidth: imgW,
    viewHeight: imgH,
    a: bx[0], b: bx[1], c: bx[2],
    d: by[1], e: by[0], f: by[2],
  );
}

/// 最小二乘拟合 + 残差剔除（稳健版）。
///
/// 策略：先全量拟合一次 → 计算每点残差 → 剔除残差 > [maxResidualMm] 的点
/// → 用剩余点重拟合（最多迭代 [maxIters] 次）。处理手点个别点歪导致的偏移。
/// 返回 null 表示最终剩余点 <3。
AffineFitResult? fitAffineRobust(
  List<CalibPointPair> pairs,
  double imgW,
  double imgH, {
  double maxResidualMm = 50,
  int maxIters = 3,
}) {
  var cur = List.of(pairs);
  CadCoordMapper? mapper;
  for (var iter = 0; iter < maxIters; iter++) {
    mapper = fitAffineLeastSquares(cur, imgW, imgH);
    if (mapper == null) return null;
    final residuals = <double>[];
    for (final p in cur) {
      final predicted = mapper.screenToWorld(p.pixel.dx, p.pixel.dy);
      residuals.add((predicted - p.world).distance);
    }
    // 计算平均/最大残差
    var sum = 0.0;
    var max = 0.0;
    for (final r in residuals) {
      sum += r;
      if (r > max) max = r;
    }
    final mean = sum / residuals.length;
    // 剔除超差点的下标
    final keep = <CalibPointPair>[];
    for (var i = 0; i < cur.length; i++) {
      if (residuals[i] <= maxResidualMm) keep.add(cur[i]);
    }
    if (keep.length == cur.length || keep.length < 3) {
      return AffineFitResult(
        mapper: mapper,
        residuals: residuals,
        meanResidualMm: mean,
        maxResidualMm: max,
      );
    }
    cur = keep;
  }
  // 最后一次拟合结果
  mapper = fitAffineLeastSquares(cur, imgW, imgH);
  if (mapper == null) return null;
  final residuals = <double>[];
  for (final p in cur) {
    final predicted = mapper.screenToWorld(p.pixel.dx, p.pixel.dy);
    residuals.add((predicted - p.world).distance);
  }
  var sum = 0.0;
  var max = 0.0;
  for (final r in residuals) {
    sum += r;
    if (r > max) max = r;
  }
  return AffineFitResult(
    mapper: mapper,
    residuals: residuals,
    meanResidualMm: sum / residuals.length,
    maxResidualMm: max,
  );
}

double _det3(double a, double b, double c,
    double d, double e, double f,
    double g, double h, double i) =>
    a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);

/// 解 3x3 正规方程 M x = v（克拉默法则）。奇异返回 null。
List<double>? _solve3(double a, double b, double c, double v1,
    double d, double e, double f, double v2,
    double g, double h, double i, double v3) {
  final det = _det3(a, b, c, d, e, f, g, h, i);
  if (det.abs() < 1e-12) return null;
  final x1 = _det3(v1, b, c, v2, e, f, v3, h, i) / det;
  final x2 = _det3(a, v1, c, d, v2, f, g, v3, i) / det;
  final x3 = _det3(a, b, v1, d, e, v2, g, h, v3) / det;
  return [x1, x2, x3];
}

/// 由两个像素点与其真实图纸坐标（mm）解仿射系数。
///
/// 约定图纸坐标系：CAD X 向右 = 像素 X 向右；CAD Y 向上 = 像素 Y 向下，
/// 因此 `a>0, d<0`。公式（无旋转）：
///   worldX = a*px + c
///   worldY = d*py + f
/// 用两对 (px, world) 解出 a/d/c/f。两像素点 x 或 y 相同（如正对）时返回 null。
/// 现内部转调 [fitAffineLeastSquares]（2 点时由最小二乘自然退化），保证语义一致。
CadCoordMapper? fitAffineTwoPoints({
  required double imgW,
  required double imgH,
  required ui.Offset p1Px,
  required ui.Offset p2Px,
  required ui.Offset p1World,
  required ui.Offset p2World,
}) {
  // 2 点退化：直接按无旋转模型解（与旧实现完全一致，避免 2 点时旋转自由度发散）。
  final dpx = p2Px.dx - p1Px.dx;
  final dpy = p2Px.dy - p1Px.dy;
  final dwx = p2World.dx - p1World.dx;
  final dwy = p2World.dy - p1World.dy;
  // 要求两个点沿 X 或 Y 有一定跨度，否则无法确定比例。
  final a = dpx.abs() > 1e-6 ? dwx / dpx : null;
  final d = dpy.abs() > 1e-6 ? dwy / dpy : null;
  if (a == null && d == null) return null;
  // 至少一个方向有跨度即可；缺失方向退化为该像素跨度推导（尽力而为）。
  final ax = a ?? (dpx.abs() > 1e-6 ? dwx / dpx : 0);
  final dy = d ?? (dpy.abs() > 1e-6 ? dwy / dpy : 0);
  final c = p1World.dx - ax * p1Px.dx;
  final f = p1World.dy - dy * p1Px.dy;
  return CadCoordMapper.fromAffine(
    viewWidth: imgW,
    viewHeight: imgH,
    a: ax,
    b: 0,
    c: c,
    d: dy,
    e: 0,
    f: f,
  );
}

/// 把 ui.Image 解码为 RGBA 字节流（并释放 Image 资源）。
Future<Uint8List?> imageToRgba(ui.Image img) async {
  try {
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (_) {
    return null;
  }
}
