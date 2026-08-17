# -*- coding: utf-8 -*-
"""验证 COS 公网 URL 是否可访问（HEAD 请求，不消耗浩辰次数）。"""
import json
import urllib.request
import urllib.error

urls_file = r"f:\GitHub\site-patrol\server\ocf_cache\urls.json"
urls = json.load(open(urls_file, encoding="utf-8"))

print("=== 验证 COS URL 可达性 ===")
all_ok = True
for key, url in urls.items():
    req = urllib.request.Request(url, method="HEAD")
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            size = int(r.headers.get("Content-Length", 0)) / 1048576
            print(f"  [OK] {key}: {size:.2f}MB  {url}")
    except urllib.error.HTTPError as e:
        print(f"  [FAIL] {key}: HTTP {e.code}")
        all_ok = False
    except Exception as e:
        print(f"  [FAIL] {key}: {e}")
        all_ok = False

print(f"\n结果: {'全部可达' if all_ok else '存在失败'}")
