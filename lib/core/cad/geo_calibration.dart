/// 图纸**地理配准**的离线存储（把现场 GPS 经纬度落到图纸像素上）。
///
/// 与 `CadCoordMapper`（屏幕/图纸坐标校准）是同类东西，存储套路保持一致：
/// 一份 `drawingKey → 配准` 的 JSON 清单，落在本地、离线可用。
///
/// 为什么要它：巡场采集到的轨迹是真实经纬度，底图是像素，中间缺"图纸左上角
/// 对应哪个经纬度 + 每像素多少米"这一环。没有配准就只能算里程、画不出轨迹；
/// 硬把缺字段当 0 画，则整条轨迹会堆在图纸左上角（历史 bug）。
library;

import 'dart:convert';
import 'dart:ui' show Offset;

import '../storage/local_storage.dart';
import '../utils/geo_project.dart';

/// 一张图纸的地理配准参数。
class GeoCalibration {
  final String drawingKey;

  /// 配准时所用的图纸版本（空串 = 未版本化）。底图改版后需重新配准。
  final String drawingVersionId;

  /// 图纸**左上角像素 (0,0)** 对应的真实纬度（度）。
  final double originLat;

  /// 图纸左上角像素 (0,0) 对应的真实经度（度）。
  final double originLng;

  /// 图纸比例（米/像素）。
  final double metersPerPixel;

  const GeoCalibration({
    required this.drawingKey,
    this.drawingVersionId = '',
    required this.originLat,
    required this.originLng,
    required this.metersPerPixel,
  });

  /// 配准是否可用：锚点经纬度 + 米/像素三者齐备且取值合理。
  bool get ready =>
      originLat.abs() > 1e-9 &&
      originLng.abs() > 1e-9 &&
      metersPerPixel > 0;

  /// 经纬度 → 图纸像素。未配准时返回 null（调用方应跳过该点）。
  Offset? project(double lat, double lng) => latLngToDrawingPixel(
        lat: lat,
        lng: lng,
        originLat: originLat,
        originLng: originLng,
        metersPerPixel: metersPerPixel,
      );

  Map<String, dynamic> toJson() => {
        'drawingVersionId': drawingVersionId,
        'originLat': originLat,
        'originLng': originLng,
        'metersPerPixel': metersPerPixel,
      };

  factory GeoCalibration.fromJson(
    String drawingKey,
    Map<String, dynamic> m,
  ) =>
      GeoCalibration(
        drawingKey: drawingKey,
        drawingVersionId: m['drawingVersionId']?.toString() ?? '',
        originLat: (m['originLat'] as num?)?.toDouble() ?? 0,
        originLng: (m['originLng'] as num?)?.toDouble() ?? 0,
        metersPerPixel: (m['metersPerPixel'] as num?)?.toDouble() ?? 0,
      );
}

/// 配准清单的读写。
class GeoCalibrationLibrary {
  GeoCalibrationLibrary(this._storage);

  final LocalStorage _storage;

  static const _kLibraryKey = 'geo_calib_library_v1';

  Future<Map<String, dynamic>> _readAll() async {
    final raw = await _storage.readDoc(_kLibraryKey);
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final j = jsonDecode(raw);
      return j is Map<String, dynamic> ? j : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeAll(Map<String, dynamic> all) async {
    await _storage.writeDoc(_kLibraryKey, jsonEncode(all));
  }

  /// 登记/更新一张图纸的配准。
  Future<void> upsert(GeoCalibration c) async {
    final all = await _readAll();
    all[c.drawingKey] = c.toJson();
    await _writeAll(all);
  }

  /// 移除配准（图纸改版后失效、或填错了要重来）。
  Future<void> remove(String drawingKey) async {
    final all = await _readAll();
    all.remove(drawingKey);
    await _writeAll(all);
  }

  /// 读某张图纸的配准；未登记或数据损坏返回 null。
  Future<GeoCalibration?> read(String drawingKey) async {
    final all = await _readAll();
    final entry = all[drawingKey];
    if (entry is! Map) return null;
    return GeoCalibration.fromJson(drawingKey, entry.cast<String, dynamic>());
  }

  /// 已配准的图纸 key 列表。
  Future<List<String>> listCalibrated() async {
    final all = await _readAll();
    return all.keys.toList();
  }
}
