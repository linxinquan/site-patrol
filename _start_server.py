"""临时脚本：用 Python 起 build/web 静态服务（8000），并验证 cad_viewer.html 可访问。"""
import http.server
import socketserver
import threading
import urllib.request
import os
import sys

ROOT = r"f:\GitHub\site-patrol\build\web"
PORT = 8000


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=ROOT, **kw)

    def log_message(self, *a):
        pass


def start():
    os.chdir(ROOT)
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("", PORT), Handler) as httpd:
        t = threading.Thread(target=httpd.serve_forever, daemon=True)
        t.start()
        print(f"Serving {ROOT} at http://localhost:{PORT}/")
        # 验证关键资源
        for path in ("/cad_viewer.html", "/GStarSDK.js", "/index.html"):
            try:
                r = urllib.request.urlopen(f"http://localhost:{PORT}{path}", timeout=5)
                print(f"  OK  {path}  -> HTTP {r.status}, {len(r.read())} bytes")
            except Exception as e:
                print(f"  ERR {path}  -> {e}")
        # 保持服务
        while True:
            import time
            time.sleep(60)


if __name__ == "__main__":
    start()
