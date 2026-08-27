// -*- coding: utf-8 -*-
// 内置种子精度回归测试：验证 builtinCalibrationFor 输出的 a/c/d/f 与
// axis_data JSON 范围 + 底图像素 + PDF 物理推算一致。

import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';

import 'package:gongdi_app/core/di/providers.dart';
import 'package:gongdi_app/core/utils/cad_coord.dart';
import 'package:gongdi_app/data/mock/mock_data.dart';

void main() {
  // PDF 物理页面 + 打印比例（实测）+ 推算的 a/d
  // 这里验证 builtinCalibrationFor 输出与「a, d 来自 PDF+比例」一致，
  // 误差应 < 0.01 mm/px。
  final cases = <(String, double, double)>[
    // (key, expected a mm/px, expected |d| mm/px)
    ('dy04_7_D01', 79.17, 79.024713),  // 1:150, PDF 1265.1x596.9
    ('dy04_7_D03', 35.158333, 35.153121),  // 1:100, PDF 843.8x596.9
    ('dy04_7_D04', 35.158333, 35.153121),
    ('dy04_7_B01', 66.222, 66.222),  // 1:250, PDF 1192x843.8
  ];

  for (final c in cases) {
    test('${c.$1} 内置种子 a/d 精度', () {
      final d = dy7Drawings[c.$1];
      expect(d, isNotNull, reason: '${c.$1} 图纸定义缺失');
      final m = builtinCalibrationFor(d!) as CadCoordMapper;
      expect(m.a, closeTo(c.$2, 0.01),
          reason: 'a 偏离预期 ${c.$2} (mm/px)');
      expect(m.d.abs(), closeTo(c.$3, 0.01),
          reason: '|d| 偏离预期 ${c.$3} (mm/px)');
      // 仿射退化: b == 0, e == 0 (无旋转)
      expect(m.b, 0.0);
      expect(m.e, 0.0);
    });
  }

  test('builtinCalibrationFor 对未知图返回 null', () {
    final m = builtinCalibrationFor(dy7Drawings['dy04_7_K01']!);
    expect(m, isNull, reason: 'K01 无内置种子');
  });
}
