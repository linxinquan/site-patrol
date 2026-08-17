# -*- coding: utf-8 -*-
import os, sys, http.server, socketserver, urllib.parse, posixpath

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'web')
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8000

CONTENT_TYPES = {
    '.html': 'text/html; charset=utf-8', '.htm': 'text/html; charset=utf-8',
    '.css': 'text/css; charset=utf-8', '.js': 'application/javascript; charset=utf-8',
    '.json': 'application/json; charset=utf-8', '.png': 'image/png',
    '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.ico': 'image/x-icon',
    '.txt': 'text/plain; charset=utf-8', '.md': 'text/markdown; charset=utf-8',
    '.ocf': 'application/octet-stream',
}


class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write(f"[static] {self.command} {self.path}\n")

    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        rel = parsed.path
        # 修正：把空路径指向 index.html
        if rel in ('', '/'):
            rel = '/index.html'
        rel = rel.lstrip('/')
        rel = posixpath.normpath(rel)
        if rel == '.':
            rel = 'index.html'
        if rel.startswith('..'):
            self.send_error(403)
            return
        full = os.path.join(ROOT, rel.replace('/', os.sep))
        sys.stderr.write(f"  rel={rel!r} full={full!r} exists={os.path.exists(full)}\n")
        if not os.path.exists(full):
            self.send_error(404, f"not found: {rel}")
            return
        if os.path.isdir(full):
            full = os.path.join(full, 'index.html')
            if not os.path.exists(full):
                self.send_error(404, f"dir no index: {rel}")
                return
        ext = os.path.splitext(full)[1].lower()
        ctype = CONTENT_TYPES.get(ext, 'application/octet-stream')
        with open(full, 'rb') as f:
            data = f.read()
        self.send_response(200)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)


socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("0.0.0.0", PORT), H) as httpd:
    print(f"static server on :{PORT}  root={ROOT}", flush=True)
    httpd.serve_forever()