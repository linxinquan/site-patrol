import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// AR 量尺 MethodChannel 封装（照 vision_service.dart 模式）。
/// viewId 对应原生 ArMeasureView 的 channel 后缀（ar_measure_<viewId>）。
///
/// 交互语义（docs/archive/AR_UX_SMOOTH.md 覆盖版）：
/// - setMode(0) = 暂停；setMode(1) = 连续测量（原生侧自动采 A→B 循环）。
class ArMeasureService {
  final MethodChannel channel;

  ArMeasureService({required int viewId})
      : channel = MethodChannel('ar_measure_channel');

  Future<bool> isSupported() async =>
      (await channel.invokeMethod<bool>('isSupported')) ?? false;

  Future<void> startSession() async => channel.invokeMethod('startSession');

  /// 0=暂停，1=连续测量。
  Future<void> setMode(int mode) async => channel.invokeMethod('setMode', mode);

  Future<void> clear() async => channel.invokeMethod('clear');

  Future<void> stopSession() async => channel.invokeMethod('stopSession');

  // ——— 面积/体积绘制（把面/体画到真实空间，见 ArMeasureView.swift）———

  /// 在真实空间画一个面域（半透明填充 + 边缘线 + 中央大字）。
  ///
  /// [corners] 为 4 个角的世界坐标（米），顺序：A → B → C → D。
  Future<void> showArea({
    required List<List<double>> corners,
    required String label,
  }) async =>
      channel.invokeMethod('showArea', {
        'corners': corners,
        'label': label,
      });

  /// 在真实空间画一个体积（半透明体 + 边缘线 + 中央大字）。
  ///
  /// [origin] 为底面一角（米）；[w]/[d]/[h] 为三条边向量（长/宽/高，米）。
  Future<void> showVolume({
    required List<double> origin,
    required List<double> w,
    required List<double> d,
    required List<double> h,
    required String label,
  }) async =>
      channel.invokeMethod('showVolume', {
        'origin': origin,
        'w': w,
        'd': d,
        'h': h,
        'label': label,
      });

  /// 清除已画的面/体。
  Future<void> clearAreaVolume() async =>
      channel.invokeMethod('clearAreaVolume');

  /// 拍一张"留图"（相机画面 + 当前 AR 标注层合成一张图），返回 PNG 字节。
  Future<Uint8List?> snapPicture() async {
    final b64 = await channel.invokeMethod<String>('snapPicture');
    if (b64 == null || b64.isEmpty) return null;
    return base64Decode(b64);
  }
}
