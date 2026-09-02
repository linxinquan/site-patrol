/// 文件下载工具（条件导入：Web 用 dart:html Blob 下载，非 Web 空实现）。
///
/// 通过条件导入避免 `dart:html` 污染移动端/测试编译（与 open_web.dart 同策略）。
/// 二进制文件（PDF / Word）走 [downloadBytes]，文本（HTML）走 [downloadTextFile]。
library;

import 'dart:typed_data';

import 'report_export_stub.dart'
    if (dart.library.html) 'report_export_web.dart'
    if (dart.library.js_interop) 'report_export_web.dart'
    as impl;

/// 当前平台是否支持下载文件（Web true，其它平台 false）。
bool get canDownloadFile => impl.canDownload;

/// 下载一份文本文件（如 .html 报告）。
///
/// [filename] 含扩展名的文件名；[mimeType] MIME（如 text/html）；[content] 文件内容。
/// 非 Web 平台为空实现（不抛错）。
void downloadTextFile(String filename, String mimeType, String content) =>
    impl.download(filename, mimeType, content);

/// 下载一份二进制文件（如 .pdf / .docx 报告）。
///
/// 非 Web 平台为空实现（不抛错）；移动端请用 `report_share.dart` 的
/// [exportReportFile] 走系统分享。
void downloadBytes(String filename, String mimeType, Uint8List bytes) =>
    impl.downloadBytes(filename, mimeType, bytes);
