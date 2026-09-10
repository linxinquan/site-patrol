import 'dart:convert';
import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:gongdi_app/core/utils/homography.dart';
import 'package:gongdi_app/core/utils/measure_math.dart';
import 'package:gongdi_app/data/models.dart';
import 'package:gongdi_app/data/vision_service.dart';

/// 合成「手机斜拍」投影：平面 mm → 归一化图像坐标 0~1。
/// 先投影到像素（乘以 imgW/imgH），再归一化，模拟模型返回的 0~1 坐标。
const double kImgW = 4000, kImgH = 3000;

Offset projectNorm(List<double> h, Offset mm) {
  final d = h[6] * mm.dx + h[7] * mm.dy + h[8];
  final px = (h[0] * mm.dx + h[1] * mm.dy + h[2]) / d;
  final py = (h[3] * mm.dx + h[4] * mm.dy + h[5]) / d;
  return Offset(px / kImgW, py / kImgH);
}

/// 强透视（斜拍）：像素坐标系下求解
const List<double> kSkewPx = [
  0.5, 0, 200, //
  0, 0.5, 150, //
  0.00018, 0.00012, 1, //
];

String gridJson({
  double gridMm = 600,
  int cols = 4,
  int rows = 4,
  double conf = 0.9,
  int? pointCount,
  bool withFence = true,
}) {
  final truth = [
    for (var r = 0; r < rows; r++)
      for (var c = 0; c < cols; c++)
        projectNorm(kSkewPx, Offset(c * gridMm, r * gridMm)),
  ];
  final n = pointCount ?? truth.length;
  final pts = truth.take(n).map((p) => [p.dx, p.dy]).toList();
  final body = jsonEncode({
    'grid': {
      'name': '瓷砖缝',
      'gridMm': gridMm,
      'cols': cols,
      'rows': rows,
      'conf': conf,
      'points': pts,
    }
  });
  return withFence ? '```json\n$body\n```' : body;
}

void main() {
  test('解析模型返回（含 markdown 围栏）→ 网格字段正确', () {
    final g = GridDetection.fromContent(gridJson());
    expect(g, isNotNull);
    expect(g!.name, '瓷砖缝');
    expect(g.gridMm, 600);
    expect(g.cols, 4);
    expect(g.rows, 4);
    expect(g.points.length, 16);
    expect(g.isValid, isTrue);
    // 行优先：第 0 个点在最左上，第 4 个点是第二行第一个 → x 更小、y 更大
    expect(g.points[4].dx < g.points[3].dx, isTrue);
    expect(g.points[4].dy > g.points[0].dy, isTrue);
  });

  test('不合格返回 → null（无网格 / 低置信 / 点数不足 / 格距为 0）', () {
    expect(GridDetection.fromContent('{"grid":null}'), isNull);
    expect(GridDetection.fromContent('不是 JSON'), isNull);
    expect(GridDetection.fromContent(gridJson(conf: 0.1)), isNull);
    expect(GridDetection.fromContent(gridJson(gridMm: 0)), isNull);
    expect(GridDetection.fromContent(gridJson(pointCount: 6)), isNull,
        reason: '点数少于 cols×rows 视为不可用');
  });

  test('AI 识别 → 确认 → 量尺：强透视斜拍下误差 < 0.5mm', () {
    final g = GridDetection.fromContent(gridJson())!;
    // 确认阶段：归一化坐标 × 图像像素 → 图像像素点
    final src = g.points
        .map((p) => Offset(p.dx * kImgW, p.dy * kImgH))
        .toList();
    final pairs = buildGridCorrespondences(
      picks: src,
      cols: g.cols,
      rows: g.rows,
      gridMm: g.gridMm,
    );
    expect(pairs.src.length, 16);

    final hom = Homography.solve(pairs.src, pairs.dst)!;
    final res = Homography.residualMm(hom, pairs.src, pairs.dst);
    // 合成数据无噪声 → 残差应近似 0
    expect(res < 0.5, isTrue, reason: '残差 $res');

    final w = (g.cols - 1) * g.gridMm;
    final hgt = (g.rows - 1) * g.gridMm;
    final calib = PhotoCalib(
      // 与生产代码一致：refMm 取网格对角线（兼容字段，不参与单应路径）
      refMm: (Offset(w, hgt) - Offset.zero).distance,
      ax: pairs.src.first.dx,
      ay: pairs.src.first.dy,
      bx: pairs.src.last.dx,
      by: pairs.src.last.dy,
      imgW: kImgW,
      imgH: kImgH,
      homography: hom.toList(),
      homographyResidualMm: res,
      calibWidthMm: w,
      calibHeightMm: hgt,
      calibPoints: pairs.src.length,
    );

    // 量一段已知尺寸：真值 3 格 = 1800mm（投影后仍应量回 1800）
    final mmA = projectNorm(kSkewPx, const Offset(0, 0));
    final mmB = projectNorm(kSkewPx, const Offset(1800, 0));
    final got = photoMeasuredMmAuto(
      calib,
      mmA.dx * kImgW,
      mmA.dy * kImgH,
      mmB.dx * kImgW,
      mmB.dy * kImgH,
    );
    expect((got - 1800).abs() < 0.5, isTrue, reason: '实测 $got');

    // 同一对点走旧两点比例法：强透视下误差显著（体现校正收益）
    final legacy = photoMeasuredMm(
      calib,
      mmA.dx * kImgW,
      mmA.dy * kImgH,
      mmB.dx * kImgW,
      mmB.dy * kImgH,
    );
    expect((legacy - 1800).abs() > 50, isTrue, reason: '旧算法 ${legacy}');
  });
}
