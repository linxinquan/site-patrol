/// 经纬度 ⇄ 图纸像素的**地理配准投影**。
///
/// 背景：巡场采集到的是真实 GPS 经纬度，但底图是像素。中间缺一个"图纸左上角
/// 对应哪个经纬度 + 每像素多少米"的换算（地理配准），没有它就只能拿里程、
/// 画不出轨迹。本模块只做这一件事，保持纯函数以便单测。
///
/// 精度说明：采用**等距圆柱近似**（把经纬度的度数差按当地每度多少米换算成平面米）。
/// 在工地尺度（跨度 < 5 km）误差 < 0.1%，远小于 GPS 本身的民用精度（3~5 m）。
/// 不引入 Web 墨卡托投影，是为了避免为这点精度付出复杂度和额外依赖。
library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

/// 1° 纬度对应的米数（球面平均）。
const double kMetersPerDegreeLat = 111320.0;

/// 某纬度处 1° 经度对应的米数（随纬度向两极收敛）。
double metersPerDegreeLng(double lat) =>
    kMetersPerDegreeLat * math.cos(lat * math.pi / 180.0);

/// 经纬度 → 图纸像素坐标。
///
/// - [originLat] / [originLng]：图纸**左上角像素 (0,0)** 对应的真实经纬度（度）
/// - [metersPerPixel]：图纸比例（米/像素）
///
/// 返回 `null` 表示比例尺非法（未配准）。调用方**必须跳过** null 点，
/// 绝不能当成 (0,0)——那正是旧实现把整条真实轨迹堆到图纸左上角的原因。
Offset? latLngToDrawingPixel({
  required double lat,
  required double lng,
  required double originLat,
  required double originLng,
  required double metersPerPixel,
}) {
  if (metersPerPixel <= 0) return null;
  final dxMeters = (lng - originLng) * metersPerDegreeLng(originLat);
  // 北纬为正方向，但屏幕 y 轴向下 → 取负
  final dyMeters = (lat - originLat) * kMetersPerDegreeLat;
  return Offset(dxMeters / metersPerPixel, -dyMeters / metersPerPixel);
}

/// 图纸像素 → 经纬度（[latLngToDrawingPixel] 的逆运算）。
///
/// 配准 UI 用它做"在图上点一个已知点、反算该点经纬度"，从而把锚点与比例尺
/// 一起定下来。比例尺非法时返回 null。
({double lat, double lng})? drawingPixelToLatLng({
  required Offset pixel,
  required double originLat,
  required double originLng,
  required double metersPerPixel,
}) {
  if (metersPerPixel <= 0) return null;
  final dxMeters = pixel.dx * metersPerPixel;
  final dyMeters = -pixel.dy * metersPerPixel;
  return (
    lat: originLat + dyMeters / kMetersPerDegreeLat,
    lng: originLng + dxMeters / metersPerDegreeLng(originLat),
  );
}

/// 由「图纸比例尺 + 底图像素宽」换算米/像素。
///
/// 比例尺含义：1:100 表示**图上 1 单位 = 实地 100 单位**，即实地距离是纸面距离的
/// [scaleDenominator] 倍。所以：
///
/// ```text
/// 米/像素 = 纸面宽(米) × 比例尺分母 / 底图像素宽
/// ```
///
/// 例：1:100 的 A0 图（纸面 1.189 m 宽）在 3000 px 底图上
/// ⟹ `1.189 × 100 / 3000 ≈ 0.0396` m/px，即整张图覆盖实地约 118.9 m。
double? metersPerPixelFromScale({
  required double paperWidthMeters,
  required double scaleDenominator,
  required double pixelWidth,
}) {
  if (scaleDenominator <= 0 || pixelWidth <= 0) return null;
  return paperWidthMeters * scaleDenominator / pixelWidth;
}

/// 常见图纸幅面的物理宽度（米），供配准 UI 下拉选择。
const Map<String, double> kPaperWidthMeters = {
  'A0': 1.189,
  'A1': 0.841,
  'A2': 0.594,
  'A3': 0.420,
  'A4': 0.297,
};
