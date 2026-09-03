/// 非 Web 平台空实现：移动端不依赖 dart:html，下载请走 `report_share.dart`
/// 的系统分享（save / share sheet）。
library;

import 'dart:typed_data';

bool get canDownload => false;

void download(String filename, String mimeType, String content) {}

void downloadBytes(String filename, String mimeType, Uint8List bytes) {}
