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
