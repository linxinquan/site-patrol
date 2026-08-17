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

  const CadCoordMapper({
    required this.viewWidth,
    required this.viewHeight,
    required this.worldLeft,
    required this.worldTop,
    required this.worldWidth,
    required this.worldHeight,
  });

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
    final wx = worldLeft + px * scaleX;
    final wy = worldTop - py * scaleY; // Y 轴向下为屏幕正向，图纸 Y 向上
    return Offset(wx, wy);
  }

  /// 图纸坐标 -> 屏幕像素坐标（screenToWorld 的逆变换）。
  Offset worldToScreen(double wx, double wy) {
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
