#!/usr/bin/env python3
"""Flutter Web 预览服务器（禁用缓存版）。

python3 -m http.server 默认不发送 no-cache 头，浏览器会缓存 main.dart.js 等产物，
导致重新构建后刷新仍看到旧界面。本服务器对所有响应加上 no-store 头，
配合 tools/post_build_web.py 的 service worker 自清理脚本，
可在没有 DevTools 的浏览器（如 WorkBuddy 内置浏览器）里刷新即见效。

用法：python3 tools/serve_web.py   （默认 8080 端口）
"""
import functools
import http.server
import os
import sys

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEB = os.path.join(BASE, 'build', 'web')
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Expires', '0')
        super().end_headers()

    def log_message(self, fmt, *args):  # 静音访问日志，避免刷屏
        pass


if __name__ == '__main__':
    if not os.path.isdir(WEB):
        print('build/web not found:', WEB)
        sys.exit(1)
    handler = functools.partial(NoCacheHandler, directory=WEB)
    server = http.server.ThreadingHTTPServer(('', PORT), handler)
    print('serving %s on http://localhost:%d (no-cache)' % (WEB, PORT))
    server.serve_forever()
