# -*- coding: utf-8 -*-
"""列出 7栋 常用平面图 DWG（按类别）供选 10 张。"""
import os

root = r"F:\建筑验收工具\大铲湾DY04_资料\7栋B1施工图"
if not os.path.exists(root):
    root = r"F:\建筑验收工具\大铲湾DY04_资料"

cats = {}
for dirpath, dirnames, filenames in os.walk(root):
    for fn in sorted(filenames):
        if fn.lower().endswith(".dwg"):
            rel = os.path.relpath(dirpath, root)
            size = os.path.getsize(os.path.join(dirpath, fn)) / 1024
            cats.setdefault(rel, []).append((fn, size))

print("=== 7栋 DWG 按目录分类 ===")
for cat in sorted(cats):
    print(f"\n[{cat}] ({len(cats[cat])} 个)")
    for fn, size in cats[cat]:
        print(f"  {size:.0f}KB  {fn}")
