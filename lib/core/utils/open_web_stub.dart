/// 非 Web 平台：不支持打开浏览器新窗口。
library;

bool get canOpen => false;

void open(String url) {}
