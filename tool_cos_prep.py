# -*- coding: utf-8 -*-
"""把第一轮测试CAD的最小文件复制到英文路径，供 COS 上传测试。"""
import os
import shutil

src_dir = r"F:\建筑验收工具\大铲湾DY04_资料\第一轮测试CAD\07_门窗详图"
dst_dir = r"f:\GitHub\site-patrol\server\test_cos"
os.makedirs(dst_dir, exist_ok=True)

# 用字节方式列出文件，避免编码问题
for fn in os.listdir(src_dir):
    full = os.path.join(src_dir, fn)
    if os.path.isfile(full) and fn.lower().endswith(".dwg"):
        sz = os.path.getsize(full)
        print(f"{sz/1024:.0f}KB  {fn!r}")
        # 复制最小的 J04~J05 到英文路径
        if "J04" in fn and sz < 500000:
            dst = os.path.join(dst_dir, "test.dwg")
            shutil.copy2(full, dst)
            print("已复制到:", dst, os.path.getsize(dst), "bytes")
            break
