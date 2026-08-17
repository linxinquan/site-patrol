# -*- coding: utf-8 -*-
"""查看 7栋 DWG 文件和 OCF 来源。"""
import os

roots = [
    r"F:\建筑验收工具\大铲湾DY04_资料",
    r"F:\建筑验收工具\web-demo",
]
for root in roots:
    print("=" * 50)
    print("ROOT:", root)
    if not os.path.exists(root):
        print("  不存在")
        continue
    for dirpath, dirnames, filenames in os.walk(root):
        # 跳过无关目录
        if any(x in dirpath for x in (".git", "__pycache__", "node_modules")):
            continue
        for fn in filenames:
            low = fn.lower()
            if low.endswith(".dwg") or low.endswith(".ocf"):
                full = os.path.join(dirpath, fn)
                sz = os.path.getsize(full)
                print(f"  {sz/1024:.0f}KB  {full}")
