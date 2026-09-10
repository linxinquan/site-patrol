import 'dart:convert';

import 'local_storage.dart';

/// AR/LiDAR 的**系统偏差校正**（尺度系数 k）。
///
/// 为什么必须有它：AR 页显示的 `±误差带` 来自**同一尺寸重复测量的离散度**
/// （`spreadHalfRange`），它只反映**重复性 precision**，不含**系统偏差 accuracy**。
/// 若 LiDAR 整体偏大 1%，三次读数会高度一致 → 误差带很小 → 系统却判为"可信"，
/// 但结果整体是错的。所以要用一个**已知长度**（A4 长边 297、瓷砖 600、
/// 卷尺 1000…）实测若干次，求出 k = 真值 / 实测中位，后续读数统一乘 k。
///
/// 注意：k 在单机上稳定但不通用——不同机型/系统版本可能有不同偏差，
/// 因此只在本机校正、不跨设备共享。
class ArScaleCalibration {
  /// 已知长度真值（mm）。
  final double refMm;

  /// 该长度的实测中位数（mm）。
  final double measuredMm;

  /// 采样次数（≥2 才有意义）。
  final int samples;

  /// 标定时间（毫秒时间戳）。
  final int ts;

  const ArScaleCalibration({
    required this.refMm,
    required this.measuredMm,
    required this.samples,
    required this.ts,
  });

  /// 尺度系数：读数 × k = 修正后的真实值。
  double get k => measuredMm <= 0 ? 1.0 : refMm / measuredMm;

  double apply(double mm) => mm * k;

  /// 校正量与相对偏差（%）：正表示原来读数偏小。
  double get deltaMm => refMm - measuredMm;
  double get deltaPct => measuredMm <= 0 ? 0 : deltaMm / measuredMm * 100;

  /// 是否可用：样本足够且偏差不超过 15%（超过说明不是系统偏差，而是测错了）。
  bool get isUsable =>
      measuredMm > 0 && samples >= 2 && (k - 1).abs() <= 0.15;

  Map<String, dynamic> toJson() => {
        'refMm': refMm,
        'measuredMm': measuredMm,
        'samples': samples,
        'ts': ts,
      };

  factory ArScaleCalibration.fromJson(Map<String, dynamic> m) =>
      ArScaleCalibration(
        refMm: (m['refMm'] as num? ?? 0).toDouble(),
        measuredMm: (m['measuredMm'] as num? ?? 0).toDouble(),
        samples: (m['samples'] as num? ?? 0).toInt(),
        ts: (m['ts'] as num? ?? 0).toInt(),
      );
}

/// 本机 AR 尺度校正的持久化（KV 文档，键固定）。
class ArScaleCalibrationStore {
  const ArScaleCalibrationStore._();

  static const String key = 'ar_scale_calib_v1';

  static Future<ArScaleCalibration?> load() async {
    final raw = await LocalStorage.instance.readDoc(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final c = ArScaleCalibration.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
      return c.isUsable ? c : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(ArScaleCalibration c) async {
    await LocalStorage.instance.writeDoc(key, jsonEncode(c.toJson()));
  }

  static Future<void> clear() async {
    await LocalStorage.instance.deleteDoc(key);
  }
}
