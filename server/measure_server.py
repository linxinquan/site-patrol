# -*- coding: utf-8 -*-
"""
拍照量尺校对 · 后端落库服务（轻量 JSON 文件存储，无需数据库）

与现有 Python 后端（cad_meta_server.py / ocf_server.py）范式一致：
  - BaseHTTPRequestHandler + /health
  - POST /api/measurements   : 保存一次测量会话（按 项目+图纸 唯一）
  - GET  /api/measurements   : 查询（?projectKey=&drawingKey= 或 ?projectKey= 查全部）
  - CORS 放开，供 Flutter Web 跨域调用

落库文件：measure_data/{projectKey}__{drawingKey}.json
（key 中的路径分隔符用 __ 代替，避免目录穿越）

运行：
  python measure_server.py [port]     # 默认 8820
  curl -X POST http://localhost:8820/api/measurements -d @session.json
"""
import os
import sys
import json
import re
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

HERE = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(HERE, "measure_data")
os.makedirs(DATA_DIR, exist_ok=True)

SAFE_RE = re.compile(r"[^A-Za-z0-9_.\-]")


def safe_key(s: str) -> str:
    """把任意 key 变成文件名安全的字符串（替换路径分隔符等）。"""
    s = (s or "").replace("/", "__").replace("\\", "__")
    return SAFE_RE.sub("_", s)


def file_for(project_key: str, drawing_key: str) -> str:
    return os.path.join(DATA_DIR, f"{safe_key(project_key)}__{safe_key(drawing_key)}.json")


def read_body(self) -> dict:
    length = int(self.headers.get("Content-Length", "0") or "0")
    if length <= 0:
        return {}
    raw = self.rfile.read(length)
    try:
        return json.loads(raw.decode("utf-8"))
    except Exception:
        return {}


class Handler(BaseHTTPRequestHandler):
    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "*")

    def _json(self, payload, status=200):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        sys.stderr.write("[measure] " + (fmt % args) + "\n")

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self):
        url = urlparse(self.path)
        path = url.path
        qs = parse_qs(url.query)

        if path == "/health":
            return self._json({
                "ok": True,
                "service": "measure",
                "count": len([f for f in os.listdir(DATA_DIR) if f.endswith(".json")]),
            })

        if path == "/api/measurements":
            project_key = (qs.get("projectKey") or [None])[0]
            drawing_key = (qs.get("drawingKey") or [None])[0]
            if project_key and drawing_key:
                fp = file_for(project_key, drawing_key)
                if not os.path.exists(fp):
                    return self._json({"ok": True, "found": False, "session": None})
                with open(fp, "r", encoding="utf-8") as f:
                    return self._json({"ok": True, "found": True, "session": json.load(f)})
            if project_key:
                # 列出该项目下所有图纸的会话
                items = []
                prefix = f"{safe_key(project_key)}__"
                for fname in os.listdir(DATA_DIR):
                    if fname.endswith(".json") and fname.startswith(prefix):
                        try:
                            with open(os.path.join(DATA_DIR, fname), "r", encoding="utf-8") as f:
                                items.append(json.load(f))
                        except Exception:
                            pass
                return self._json({"ok": True, "items": items})
            return self._json({"ok": False, "err": "projectKey 必填"}, status=400)

        self._json({"ok": False, "err": "not found"}, status=404)

    def do_POST(self):
        url = urlparse(self.path)
        path = url.path
        if path != "/api/measurements":
            return self._json({"ok": False, "err": "not found"}, status=404)

        body = read_body(self)
        project_key = body.get("projectKey")
        drawing_key = body.get("drawingKey")
        if not project_key or not drawing_key:
            return self._json(
                {"ok": False, "err": "projectKey / drawingKey 必填"}, status=400)

        # 规范化：补全服务端时间戳
        body["serverSavedAt"] = int(time.time() * 1000)
        fp = file_for(project_key, drawing_key)
        with open(fp, "w", encoding="utf-8") as f:
            json.dump(body, f, ensure_ascii=False, indent=2)

        return self._json({
            "ok": True,
            "saved": True,
            "file": os.path.basename(fp),
            "items": len(body.get("items", [])),
        })


def main():
    port = int(os.environ.get("MEASURE_PORT", "8820"))
    print(f"[measure] 启动端口 {port}")
    print(f"[measure] 落库目录: {DATA_DIR}")
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
