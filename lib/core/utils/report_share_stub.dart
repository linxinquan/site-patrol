/// 兜底空实现（理论上不会被选中，仅为条件导入提供默认分支）。
library;

import 'dart:typed_data';

bool get supported => false;

Future<String?> exportFile(
  String filename,
  String mimeType,
  Uint8List bytes,
) async =>
    null;
