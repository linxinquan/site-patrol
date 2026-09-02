/// 移动端 / 桌面实现：移动端点分享面板，桌面端直接落盘并返回路径。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

bool get supported => true;

Future<String?> exportFile(
  String filename,
  String mimeType,
  Uint8List bytes,
) async {
  final mobile = Platform.isAndroid || Platform.isIOS;
  final dir = mobile
      ? await getTemporaryDirectory()
      : await _desktopTargetDir();
  final file = File(p.join(dir.path, filename));
  await file.writeAsBytes(bytes, flush: true);

  if (mobile) {
    await Share.shareXFiles(
      [XFile(file.path, mimeType: mimeType)],
      subject: filename,
    );
    return null;
  }
  return file.path;
}

/// 桌面端落盘目录：优先下载目录，取不到再用应用文档目录。
Future<Directory> _desktopTargetDir() async {
  final downloads = await getDownloadsDirectory();
  if (downloads != null) return downloads;
  return getApplicationDocumentsDirectory();
}
