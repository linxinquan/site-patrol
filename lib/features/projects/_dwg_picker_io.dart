import 'dart:typed_data';

Future<({String? name, Uint8List? bytes})> pickerDwg() async {
  // 测试 APK 先关闭移动端 DWG 选择，避免老旧三方依赖阻塞 Android 打包。
  // 上层会把 null 视为“未选择文件”并给出提示。
  return (name: null, bytes: null);
}
