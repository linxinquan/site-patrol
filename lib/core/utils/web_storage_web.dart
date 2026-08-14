// Web 实现：走 dart:html localStorage。
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' show window;

String? get(String key) => window.localStorage[key];

void set(String key, String value) => window.localStorage[key] = value;

void remove(String key) => window.localStorage.remove(key);
