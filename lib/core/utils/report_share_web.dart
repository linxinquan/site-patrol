/// Web 实现：交给浏览器的 Blob 下载（与 HTML 报告同一条通道）。
library;

import 'dart:typed_data';

import 'report_export.dart';

bool get supported => canDownloadFile;

Future<String?> exportFile(
  String filename,
  String mimeType,
  Uint8List bytes,
) async {
  downloadBytes(filename, mimeType, bytes);
  return null;
}
