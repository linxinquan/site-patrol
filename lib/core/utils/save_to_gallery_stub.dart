/// 「保存到相册」的**非移动端实现**（Web / 桌面 / 测试）。
///
/// Web 与桌面没有系统相册概念，这里统一返回"不支持"，由调用方回退到
/// 下载（Web）/ 落盘（桌面）/ 分享面板，保证功能链路不断。
library;

import 'dart:typed_data';

/// 当前平台是否支持直接保存到系统相册。
bool get canSaveToGallery => false;

/// 不支持时直接返回失败，不抛异常（调用方据此回退）。
Future<({bool ok, String? message})> saveImageToGallery(
  Uint8List bytes, {
  String name = 'image',
}) async =>
    (ok: false, message: '当前平台不支持直接保存到相册');
