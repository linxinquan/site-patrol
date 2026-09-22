/// 「保存到相册」的**移动端实现**（Android / iOS，基于 `gal`）。
///
/// - 需要相册权限：先 `hasAccess()` 查询，无权限再 `requestAccess()` 申请；
/// - 保存到**系统相册默认相册**（不建 App 专属相册，避免用户找不到）；
/// - 任何失败都转成 `(ok:false, message:...)`，**不抛异常**——调用方据此
///   回退到系统分享面板，用户仍能自己选「存储图像」。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:gal/gal.dart';

/// 当前平台是否支持直接保存到系统相册（仅 Android / iOS）。
bool get canSaveToGallery => Platform.isAndroid || Platform.isIOS;

Future<({bool ok, String? message})> saveImageToGallery(
  Uint8List bytes, {
  String name = 'image',
}) async {
  if (!canSaveToGallery) {
    return (ok: false, message: '当前平台不支持直接保存到相册');
  }
  try {
    if (!await Gal.hasAccess()) {
      final granted = await Gal.requestAccess();
      if (!granted) {
        return (ok: false, message: '未获得相册权限：请在系统设置中允许「照片/存储」权限后重试');
      }
    }
    await Gal.putImageBytes(bytes, name: name);
    return (ok: true, message: null);
  } on GalException catch (e) {
    return (ok: false, message: '保存到相册失败：${e.type.message}');
  } catch (e) {
    return (ok: false, message: '保存到相册失败：$e');
  }
}
