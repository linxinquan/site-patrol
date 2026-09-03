import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 简单图片压缩：解码后按最长边等比缩放，再转 JPEG 编码。
/// - [maxDim] 最长边上限（像素）。
/// - [quality] JPEG 质量 0~100。
/// 解码失败时原样返回，避免破坏不可解析的图片。
Uint8List compressImage(Uint8List bytes, {int maxDim = 1280, int quality = 82}) {
  img.Image? image;
  try {
    image = img.decodeImage(bytes);
  } catch (_) {
    image = null;
  }
  if (image == null) return bytes;

  final w = image.width;
  final h = image.height;
  if (w > maxDim || h > maxDim) {
    final scale = maxDim / (w > h ? w : h);
    image = img.copyResize(
      image,
      width: (w * scale).round(),
      height: (h * scale).round(),
    );
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: quality));
}

/// 在 isolate 中执行图片压缩，避免阻塞 UI 线程。
///
/// - VM（iOS/Android/desktop）：走 isolate，不阻塞 UI。
/// - Web（dart4web）：`dart:isolate` 不支持，fallback 到主线程同步执行，
///   仍以 `Future` 形式返回（保持接口一致）。
/// - 失败时（如解码错误）返回原始字节，与同步版本语义一致。
Future<Uint8List> compressImageAsync(
  Uint8List bytes, {
  int maxDim = 1280,
  int quality = 82,
}) async {
  try {
    return await Isolate.run(
      () => compressImage(bytes, maxDim: maxDim, quality: quality),
    );
  } on UnsupportedError {
    // Web 平台不支持 dart:isolate，主线程同步执行。
    return compressImage(bytes, maxDim: maxDim, quality: quality);
  }
}
