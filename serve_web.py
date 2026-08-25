#!/usr/bin/env python3
"""site-patrol 本地预览服务器。

解决"内置浏览器打开不是最新构建"的缓存问题：
1. 所有响应带 Cache-Control: no-store，禁止 HTTP 层缓存；
2. 拦截 Flutter 的 flutter_service_worker.js，返回"卸载脚本"——
   已注册的 Service Worker 会删除全部 CacheStorage 缓存并自杀，
   之后每次刷新都直接从磁盘读最新构建产物。

用法:
    python3 serve_web.py --port 8765 --directory build/web
"""
import argparse
import http.server
import socketserver

# 拦截 Service Worker：清除历史缓存并注销自身。
SERVICE_WORKER_KILL = b"""self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.map((k) => caches.delete(k)));
    await self.registration.unregister();
  })());
});
"""


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def _no_store_headers(self):
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Expires', '0')

    def do_GET(self):
        # Flutter Service Worker：返回卸载脚本（带版本 query 也能命中）
        if self.path.split('?')[0].endswith('/flutter_service_worker.js'):
            self.send_response(200)
            self.send_header('Content-Type', 'application/javascript; charset=utf-8')
            self.send_header('Content-Length', str(len(SERVICE_WORKER_KILL)))
            self._no_store_headers()
            self.end_headers()
            self.wfile.write(SERVICE_WORKER_KILL)
            return
        super().do_GET()

    def end_headers(self):
        self._no_store_headers()
        super().end_headers()


def main():
    parser = argparse.ArgumentParser(description='No-cache static preview server')
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--host', default='0.0.0.0',
                        help='bind host; 0.0.0.0 允许局域网其他设备访问')
    parser.add_argument('--directory', default='.')
    args = parser.parse_args()

    handler = lambda *a, **kw: NoCacheHandler(*a, directory=args.directory, **kw)
    with socketserver.ThreadingTCPServer((args.host, args.port), handler) as httpd:
        print(f'Serving {os.path.abspath(args.directory)} on http://{args.host}:{args.port} (no-cache)')
        httpd.serve_forever()


if __name__ == '__main__':
    import os
    main()
