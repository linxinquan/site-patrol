// Web 端选文件实现：用 dart:html 触发原生 input type=file 选择。
// 解决 file_picker 8.x 在 Flutter Web HTML 渲染器下偶发不可用的问题。
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

/// 选择一个 .dwg 文件；返回 (name, bytes)；取消则 bytes 为 null。
Future<({String? name, Uint8List? bytes})> pickerDwg() async {
  final completer =
      Completer<({String? name, Uint8List? bytes})>();
  final input = html.FileUploadInputElement()
    ..accept = '.dwg'
    ..multiple = false
    ..style.display = 'none';
  html.document.body?.append(input);

  void reset() {
    try {
      input.remove();
    } catch (_) {}
  }

  void onCancel() {
    reset();
    if (!completer.isCompleted) {
      completer.complete((name: null, bytes: null));
    }
  }

  input.onChange.listen((e) {
    final files = input.files;
    if (files == null || files.isEmpty) {
      onCancel();
      return;
    }
    final f = files.first;
    final reader = html.FileReader();
    reader.onLoadEnd.listen((_) {
      Uint8List? bytes;
      final r = reader.result;
      if (r is Uint8List) {
        bytes = r;
      } else if (r is List<int>) {
        bytes = Uint8List.fromList(r);
      }
      reset();
      if (!completer.isCompleted) {
        completer.complete((name: f.name, bytes: bytes));
      }
    });
    reader.onError.listen((_) {
      reset();
      if (!completer.isCompleted) {
        completer.complete((name: null, bytes: null));
      }
    });
    reader.readAsArrayBuffer(f);
  });

  input.click();

  // 兜底：3 秒内若未触发 onChange（用户取消），返回 null。
  Timer(const Duration(seconds: 180), () {
    if (!completer.isCompleted) onCancel();
  });
  return completer.future;
}