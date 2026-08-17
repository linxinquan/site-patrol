/// 打开新浏览器窗口（仅 Web 生效；其他平台为空实现）。
/// 通过条件导入避免 `dart:html` 污染移动端/测试编译。
library;

import 'open_web_stub.dart'
    if (dart.library.html) 'open_web_web.dart'
    if (dart.library.js_interop) 'open_web_web.dart'
    as impl;

/// 是否支持在新窗口打开网页（Web 平台 true，移动端 false）。
bool get canOpenWebWindow => impl.canOpen;

/// 打开 URL 新窗口（Web 生效；移动端忽略）。
void openWebWindow(String url) => impl.open(url);
