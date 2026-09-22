/// 图片交付出口：**移动端优先「一键直存相册」**，其余平台回退下载/分享。
///
/// 为什么要有这层：
/// - Android/iOS 有系统相册，用户点一下就该存好，不该被迫走分享面板；
/// - Web/桌面没有相册，走浏览器下载或落盘；
/// - 直存失败（无权限/空间不足）时**必须回退**到分享面板，否则用户拿不到图。
///
/// 平台差异通过条件导入隔离（与 `report_share.dart` 同策略），
/// 保证 `gal` 不会污染 Web 构建。
library;

import 'dart:typed_data';

import 'report_share.dart';
import 'save_to_gallery_stub.dart'
    if (dart.library.io) 'save_to_gallery_io.dart' as impl;

// 对外暴露平台判定（UI 可据此决定按钮文案：「保存到相册」还是「下载」）。
export 'save_to_gallery_stub.dart'
    if (dart.library.io) 'save_to_gallery_io.dart'
    show canSaveToGallery;

/// 一次交付的结果：是否存进了相册 / 是否走了回退通路 / 给用户看的提示。
typedef ImageDelivery = ({bool savedToGallery, bool fellBack, String message});

/// 交付一张图片（PNG 等字节）。
///
/// - 移动端：先尝试直存相册；成功 → `savedToGallery: true`；失败 → 回退系统分享；
/// - Web/桌面：直接走 `exportReportFile`（下载 / 落盘）。
///
/// [filename] 为回退时的文件名（含扩展名）；[name] 为相册里的文件名（不含扩展名）。
Future<ImageDelivery> deliverImage(
  Uint8List bytes, {
  required String filename,
  String mimeType = 'image/png',
  String name = 'image',
}) async {
  if (impl.canSaveToGallery) {
    final r = await impl.saveImageToGallery(bytes, name: name);
    if (r.ok) {
      return (savedToGallery: true, fellBack: false, message: '已保存到系统相册');
    }
    // 直存失败（无权限等）：回退分享面板，用户仍可自行「存储图像」
    await exportReportFile(filename, mimeType, bytes);
    return (
      savedToGallery: false,
      fellBack: true,
      message: '${r.message ?? '保存到相册失败'}；已改为打开分享面板，可选「存储图像」保存',
    );
  }
  await exportReportFile(filename, mimeType, bytes);
  return (
    savedToGallery: false,
    fellBack: true,
    message: '已导出（网页端为浏览器下载）',
  );
}
