# -*- coding: utf-8 -*-
"""测试 B01 OCF zlib 压缩后能否低于 APIG ~12MB 限制。"""
import os
import zlib
import base64

p = r"f:\GitHub\site-patrol\server\ocf_cache\dy04_7_B01.ocf"
raw = open(p, "rb").read()
print(f"原始: {len(raw)/1048576:.2f} MB")

for level in [6, 9]:
    comp = zlib.compress(raw, level)
    b64 = base64.b64encode(comp).decode("ascii")
    print(f"zlib level={level}: 压缩后 {len(comp)/1048576:.2f} MB, base64 ~{len(b64)/1048576:.2f} MB")
