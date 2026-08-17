/// Web 平台：用 window.open 打开新浏览器窗口。
library;

import 'dart:html' show window;

bool get canOpen => true;

void open(String url) => window.open(url, '_blank');
