import 'package:flutter/services.dart';

/// AR 量尺 MethodChannel 封装（照 vision_service.dart 模式）。
/// viewId 对应原生 ArMeasureView 的 channel 后缀（ar_measure_<viewId>）。
///
/// 交互语义（AR_UX_SMOOTH.md 覆盖版）：
/// - setMode(0) = 暂停；setMode(1) = 连续测量（原生侧自动采 A→B 循环）。
class ArMeasureService {
  final MethodChannel channel;

  ArMeasureService({required int viewId})
      : channel = MethodChannel('ar_measure_$viewId');

  Future<bool> isSupported() async =>
      (await channel.invokeMethod<bool>('isSupported')) ?? false;

  Future<void> startSession() async => channel.invokeMethod('startSession');

  /// 0=暂停，1=连续测量。
  Future<void> setMode(int mode) async => channel.invokeMethod('setMode', mode);

  Future<void> clear() async => channel.invokeMethod('clear');

  Future<void> stopSession() async => channel.invokeMethod('stopSession');
}
