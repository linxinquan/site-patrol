import 'package:flutter/material.dart';

/// CAD 坐标换算工具。
///
/// 核心目标：屏幕像素坐标 <-> 真实 CAD 图纸坐标（毫米/米），
/// 用于「巡场坐标精度标注」——在图上点选，得到图纸坐标系中的真实位置。
///
/// 数据来源：
///  - 后端 `getPixelImage` 返回的 `viewsize`（描述视图范围）
///  - 前端 `screenToWorld({x, y})`（GStarSDK 能力）
///  - 本文实现通用换算，便于在 GStarSDK.js 接入前先行验证与联调。
///
/// 换算原理：
///   viewsize 定义图纸坐标 → 视图像素的缩放比例（单位像素 = viewsize.width / 图宽）。
///   worldX = (screenX / scale) + worldLeft；worldY = worldTop - (screenY / scale)。
class CadCoordMapper {
  /// 视图像素宽（整图渲染宽度，px）
  final double viewWidth;

  /// 视图像素高（px）
  final double viewHeight;

  /// 视图左下角图纸坐标（X 最小值，mm）
  final double worldLeft;

  /// 视图右上角图纸坐标（Y 最大值，mm）
  final double worldTop;

  /// 图纸坐标宽度范围（mm）：worldRight - worldLeft
  final double worldWidth;

  /// 图纸坐标高度范围（mm）：worldTop - worldBottom
  final double worldHeight;

  // ---- 仿射校准模式（截图底图 + 单点/两点校准生成 {a,b,c,d,e,f}）----
  /// 是否使用仿射系数模式（而非视图范围模式）。
  final bool useAffine;
  /// 仿射系数：worldX = a*px + c ；worldY = d*py + f
  final double a;
  final double b;
  final double c;
  final double d;
  final double e;
  final double f;

  const CadCoordMapper({
    required this.viewWidth,
    required this.viewHeight,
    required this.worldLeft,
    required this.worldTop,
    required this.worldWidth,
    required this.worldHeight,
    this.useAffine = false,
    this.a = 0,
    this.b = 0,
    this.c = 0,
    this.d = 0,
    this.e = 0,
    this.f = 0,
  });

  /// 从仿射校准系数 {a,b,c,d,e,f} 构建（截图底图校准模式）。
  /// 像素坐标 (px,py) → 世界坐标：X = a*px + b*py + c；Y = d*px + e*py + f。
  /// 常规截图底图（无旋转、X 单向、Y 单向）时 b=e=0，即为：
  ///   X = a*px + c；Y = d*py + f。
  factory CadCoordMapper.fromAffine({
    required double viewWidth,
    required double viewHeight,
    double a = 0,
    double b = 0,
    double c = 0,
    double d = 0,
    double e = 0,
    double f = 0,
  }) =>
      CadCoordMapper(
        viewWidth: viewWidth,
        viewHeight: viewHeight,
        worldLeft: 0,
        worldTop: 0,
        worldWidth: 0,
        worldHeight: 0,
        useAffine: true,
        a: a,
        b: b,
        c: c,
        d: d,
        e: e,
        f: f,
      );

  /// 从校准数据 JSON Map 构建（兼容 HTML 端 `cad_calib` / 分享链接 / 离线文件格式）。
  /// 接受的 key：{a,b,c,d,e,f}（必），可带 imgW/imgH（可选，用于校验/提示）。
  factory CadCoordMapper.fromCalibrationMap(Map<String, dynamic> m) {
    num n(dynamic k, [num def = 0]) => (m[k] as num?) ?? def;
    return CadCoordMapper.fromAffine(
      viewWidth: n('imgW', 1).toDouble(),
      viewHeight: n('imgH', 1).toDouble(),
      a: n('a').toDouble(),
      b: n('b').toDouble(),
      c: n('c').toDouble(),
      d: n('d').toDouble(),
      e: n('e').toDouble(),
      f: n('f').toDouble(),
    );
  }

  /// 仿射系数序列化（用于本地持久化 / 导出 / 分享）。
  Map<String, dynamic> toCalibrationMap() => {
        'imgW': viewWidth,
        'imgH': viewHeight,
        'a': a,
        'b': b,
        'c': c,
        'd': d,
        'e': e,
        'f': f,
      };

  /// 从后端 getPixelImage 返回的 viewsize 构建换算器。
  ///
  /// [viewsize] 典型结构（浩辰返回）：
  ///   {
  ///     "width": 像素宽, "height": 像素高,
  ///     "minx": 世界X最小, "maxx": 世界X最大,
  ///     "miny": 世界Y最小, "maxy": 世界Y最大
  ///   }
  factory CadCoordMapper.fromViewsize(Map<String, dynamic> viewsize) {
    final vw = (viewsize['width'] as num?)?.toDouble() ?? 1;
    final vh = (viewsize['height'] as num?)?.toDouble() ?? 1;
    final minx = (viewsize['minx'] as num?)?.toDouble() ?? 0;
    final maxx = (viewsize['maxx'] as num?)?.toDouble() ?? 0;
    final miny = (viewsize['miny'] as num?)?.toDouble() ?? 0;
    final maxy = (viewsize['maxy'] as num?)?.toDouble() ?? 0;
    return CadCoordMapper(
      viewWidth: vw,
      viewHeight: vh,
      worldLeft: minx,
      worldTop: maxy,
      worldWidth: (maxx - minx).abs(),
      worldHeight: (maxy - miny).abs(),
    );
  }

  /// 像素缩放比例：每像素对应的图纸坐标单位（mm/px）。
  double get scaleX => worldWidth <= 0 ? 1 : worldWidth / viewWidth;
  double get scaleY => worldHeight <= 0 ? 1 : worldHeight / viewHeight;

  /// 屏幕像素坐标 -> 图纸坐标（未考虑平移/缩放变换）。
  /// [px]、[py] 为整图坐标系下的像素位置（0..viewWidth, 0..viewHeight）。
  Offset screenToWorld(double px, double py) {
    if (useAffine) {
      // 仿射校准：worldX = a*px + b*py + c；worldY = d*px + e*py + f
      final wx = a * px + b * py + c;
      final wy = d * px + e * py + f;
      return Offset(wx, wy);
    }
    final wx = worldLeft + px * scaleX;
    final wy = worldTop - py * scaleY; // Y 轴向下为屏幕正向，图纸 Y 向上
    return Offset(wx, wy);
  }

  /// 图纸坐标 -> 屏幕像素坐标（screenToWorld 的逆变换）。
  Offset worldToScreen(double wx, double wy) {
    if (useAffine) {
      // 仅支持无旋转情形（b=e=0）：px=(wx-c)/a；py=(wy-f)/d
      final px = (a.abs() > 1e-9) ? (wx - c) / a : 0.0;
      final py = (d.abs() > 1e-9) ? (wy - f) / d : 0.0;
      return Offset(px, py);
    }
    final px = (wx - worldLeft) / scaleX;
    final py = (worldTop - wy) / scaleY;
    return Offset(px, py);
  }

  /// 在已有 [InteractiveViewer] 变换矩阵（含缩放/平移）下，把
  /// 屏幕点击位置（相对 widget 的局部坐标）换算为整图像素坐标。
  ///
  /// [localPos] 为点击点在 widget 局部坐标系的位置；
  /// [matrix] 为 TransformationController.value（交互变换）；
  /// [containedSize] 为整图在屏幕上按 BoxFit.contain 显示的实际宽高。
  Offset localToViewPixel(
    Offset localPos,
    Matrix4 matrix,
    Size containedSize,
  ) {
    // 1. 整图被 matrix 变换后的实际屏幕尺寸
    final scale = matrix.getMaxScaleOnAxis();
    final dispW = containedSize.width * scale;
    final dispH = containedSize.height * scale;
    // 2. 变换后图片的左上角在 widget 坐标系中的位置
    final tx = matrix.getTranslation();
    final originX = tx.x + (containedSize.width - dispW) / 2;
    final originY = tx.y + (containedSize.height - dispH) / 2;
    // 3. 点击位置相对图片左上角的像素
    final px = (localPos.dx - originX) / scale;
    final py = (localPos.dy - originY) / scale;
    return Offset(px.clamp(0, containedSize.width), py.clamp(0, containedSize.height));
  }
}
