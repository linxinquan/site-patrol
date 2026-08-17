# -*- coding: utf-8 -*-
"""检查本地 OCF 文件大小及 base64 大小，评估 APIG body 限制可行性。"""
import os
import base64

for fn in ["dy04_7_B01.ocf", "dy04_7_K01.ocf"]:
    p = os.path.join(r"f:\GitHub\site-patrol\server\ocf_cache", fn)
    if not os.path.exists(p):
        print(fn, "不存在")
        continue
    size = os.path.getsize(p)
    b64_size = base64.b64encode(open(p, "rb").read()).__len__()
    print(f"{fn}: {size/1024/1024:.2f} MB, base64 ~{b64_size/1024/1024:.2f} MB")
