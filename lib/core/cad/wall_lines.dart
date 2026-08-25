import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../utils/cad_coord.dart';

/// 墙线段加载（P1-2）。
/// 数据由 `server/cad_meta_build.py` 生成到 `assets/walls/<drawingKey>_walls.json`，
/// 字段：{ key, wall_lines: [{layer, pts: [[x,y], ...]}, ...] }（世界坐标 mm）。
///
/// 该函数把世界坐标 mm 经 `CadCoordMapper.worldToScreen` 映射到整图像素，
/// 再换算成相对坐标 0~100（与 PatrolPoint/路线一致）。
///
/// 返回 null = 该图纸未校准（mapper==null）或加载失败（IO/解析），调用方应优雅降级。
Future<List<List<double>>?> loadWallLinesRel(
  String drawingKey,
  CadCoordMapper? mapper,
) async {
  if (mapper == null) return null;
  try {
    final raw = await rootBundle.loadString(
        'assets/walls/${drawingKey}_walls.json');
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final wallLines = (j['wall_lines'] as List<dynamic>? ?? []);
    final rel = <List<double>>[];
    for (final wl in wallLines) {
      final pts = (wl['pts'] as List<dynamic>? ?? []);
      for (var i = 1; i < pts.length; i++) {
        final p0 = pts[i - 1] as List<dynamic>;
        final p1 = pts[i] as List<dynamic>;
        final a = mapper.worldToScreen(
            (p0[0] as num).toDouble(), (p0[1] as num).toDouble());
        final b = mapper.worldToScreen(
            (p1[0] as num).toDouble(), (p1[1] as num).toDouble());
        rel.add([
          (a.dx / mapper.viewWidth * 100).clamp(0.0, 100.0),
          (a.dy / mapper.viewHeight * 100).clamp(0.0, 100.0),
          (b.dx / mapper.viewWidth * 100).clamp(0.0, 100.0),
          (b.dy / mapper.viewHeight * 100).clamp(0.0, 100.0),
        ]);
      }
    }
    return rel;
  } catch (_) {
    // 资产缺失（未构建）/解析失败：返回 null，由调用方降级。
    return null;
  }
}