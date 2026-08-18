# -*- coding: utf-8 -*-
"""对比关键文件在两端的 mtime / 大小 / md5，判断以哪边为准。"""
import os, hashlib, datetime

WS = r"F:\建筑验收工具\site-patrol"
GH = r"F:\GitHub\site-patrol"
KEYS = [
    "lib/data/mock/mock_data.dart",
    "lib/features/home/home_page.dart",
    "server/apig_sdk/signer.py",
    "server/apig_sdk/signer_v11.py",
    "server/apig_sdk/sm3_hash.py",
    "server/apig_sdk/signer_test.py",
    "server/apig_sdk/__init__.py",
    "web/GStarSDK.js",
    "CAD_OCF_INTEGRATION.md",
    "server/ocf_server.py",
    "server/config.py",
    "web/cad_viewer.html",
    "lib/features/projects/drawing_viewer_page.dart",
]

def info(path):
    if not os.path.exists(path):
        return None
    st = os.stat(path)
    h = hashlib.md5(open(path, 'rb').read()).hexdigest()[:10]
    return (datetime.datetime.fromtimestamp(st.st_mtime).strftime("%Y-%m-%d %H:%M:%S"),
            st.st_size, h)

for k in KEYS:
    wi = info(os.path.join(WS, k))
    gi = info(os.path.join(GH, k))
    print(k)
    print(f"   WS: {wi}")
    print(f"   GH: {gi}")
    if wi and gi:
        newer = "WS更新" if wi[0] > gi[0] else ("GH更新" if gi[0] > wi[0] else "同时间")
        same = "一致" if wi[2] == gi[2] else "内容不同"
        print(f"   => {newer} | {same}")
    print()
