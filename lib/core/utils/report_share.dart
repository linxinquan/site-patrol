/// 报告文件的最终交付出口（条件导入，按平台选实现）：
/// - Web：直接触发浏览器下载；
/// - Android / iOS：写临时文件后拉起系统分享面板（微信 / 邮件 / 网盘 / 钉钉…）；
/// - 桌面（Windows / macOS / Linux）：落盘到下载目录，返回路径。
///
/// 返回落盘路径（Web 与移动端分享成功时返回 null）；调用方据此提示用户。
library;

import 'dart:typed_data';

import 'report_share_stub.dart'
    if (dart.library.html) 'report_share_web.dart'
    if (dart.library.js_interop) 'report_share_web.dart'
    if (dart.library.io) 'report_share_io.dart'
    as impl;

/// 当前平台是否支持导出文件。
bool get canExportReportFile => impl.supported;

/// 导出 [bytes] 为 [filename]（含扩展名）。
Future<String?> exportReportFile(
  String filename,
  String mimeType,
  Uint8List bytes,
) =>
    impl.exportFile(filename, mimeType, bytes);
