# -*- coding: utf-8 -*-
"""用 B01 OCF 转 PNG（扣 1 次）。验证链路，若 413 超限则提示。"""
import json
import urllib.request
import urllib.error

BASE = "http://localhost:8800"

# 调本地代理 /api/cad/saveAsImage，key=dy04_7_B01
# 服务端会从 ocf_cache 读 dy04_7_B01.ocf 转 base64 上传
body = json.dumps({
    "key": "dy04_7_B01",
    "imageWidth": 3000,   # 高清大图
    "imageHeight": 3000,
}).encode("utf-8")

req = urllib.request.Request(BASE + "/api/cad/saveAsImage", data=body,
                             headers={"Content-Type": "application/json"}, method="POST")
try:
    with urllib.request.urlopen(req, timeout=300) as r:
        resp = json.loads(r.read().decode("utf-8"))
    print("响应:", json.dumps(resp, ensure_ascii=False, indent=2))
except urllib.error.HTTPError as e:
    detail = e.read().decode("utf-8", errors="replace")
    print(f"HTTP {e.code}: {detail[:500]}")
except Exception as e:
    print("异常:", str(e)[:500])
