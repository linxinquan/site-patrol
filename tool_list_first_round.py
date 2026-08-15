# -*- coding: utf-8 -*-
"""列出第一轮测试CAD的文件，对照已有OCF。"""
import os

root = r"F:\建筑验收工具\大铲湾DY04_资料\第一轮测试CAD"
ocf_dir = r"f:\GitHub\site-patrol\server\ocf_cache"

print("=== 第一轮测试CAD 文件 ===")
for dirpath, dirnames, filenames in os.walk(root):
    rel = os.path.relpath(dirpath, root)
    for fn in sorted(filenames):
        if fn.lower().endswith(".dwg"):
            full = os.path.join(dirpath, fn)
            size = os.path.getsize(full) / 1024
            print(f"  {size:.0f}KB  [{rel}]  {fn}")

print("\n=== 已有 OCF 缓存 ===")
for fn in sorted(os.listdir(ocf_dir)):
    if fn.endswith(".ocf"):
        size = os.path.getsize(os.path.join(ocf_dir, fn)) / 1024
        print(f"  {size:.0f}KB  {fn}")

print("\n=== 已有 PNG 缓存 ===")
for fn in sorted(os.listdir(ocf_dir)):
    if fn.endswith(".png"):
        size = os.path.getsize(os.path.join(ocf_dir, fn)) / 1024
        print(f"  {size:.0f}KB  {fn}")
