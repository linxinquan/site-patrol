// 移动端（Android/iOS）选文件实现：继续用 file_picker。
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<({String? name, Uint8List? bytes})> pickerDwg() async {
  final r = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['dwg'],
    allowMultiple: false,
  );
  final f = r?.files.single;
  return (name: f?.name, bytes: f?.bytes);
}