# -*- coding: utf-8 -*-
"""检查已上传的 COS 文件，确认是否与 B01/K01 对应。
通过 HTTP HEAD/GET 检查文件是否存在与元数据（不需凭证）。"""
import os
import urllib.request

BASE = "https://site-inspection-1322296918.cos.ap-guangzhou.myqcloud.com"
files = ["B1pingmian.dwg", "B1qiangshen.dwg"]

for fn in files:
    url = f"{BASE}/{fn}"
    req = urllib.request.Request(url, method="HEAD")
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            print(f"{fn}: size={int(r.headers.get('Content-Length', 0))/1048576:.2f}MB  "
                  f"type={r.headers.get('Content-Type', '-')}  status=OK")
    except urllib.error.HTTPError as e:
        print(f"{fn}: HTTP {e.code}")
    except Exception as e:
        print(f"{fn}: ERR {e}")

# 对比本地第一轮测试CAD 文件大小
print("\n=== 本地对应文件大小 ===")
local = [
    (r"F:\建筑验收工具\大铲湾DY04_资料\第一轮测试CAD\01_平面图\建施_AW-7-B01_V1.0_地下一层顶板组合平面图.dwg", "B01 (平面)"),
    (r"F:\建筑验收工具\大铲湾DY04_资料\第一轮测试CAD\04_墙身详图\建施_AW-7-K01_V1.0_墙身详图（一）.dwg", "K01 (墙身)"),
]
for p, label in local:
    if os.path.exists(p):
        sz = os.path.getsize(p) / 1048576
        print(f"  {label}: {sz:.2f}MB")
