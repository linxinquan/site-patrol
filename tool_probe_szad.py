# -*- coding: utf-8 -*-
"""探查 SZAD 原始资料的 DWG 命名与目录结构。"""
import os

root = r"F:\设计院工作\SZAD\2020-腾讯大铲湾DY04"

# 列出顶层和几层子目录
print("=== 顶层目录 ===")
for d in sorted(os.listdir(root)):
    p = os.path.join(root, d)
    tag = "DIR" if os.path.isdir(p) else "file"
    print(f"  [{tag}] {d}")

# 找含"7"的子目录
print("\n=== 含 '7' 的路径 ===")
for dirpath, dirnames, filenames in os.walk(root):
    if any(x in dirpath for x in ("效果图", "汇报", "驻地", "网上下载")):
        continue
    if "7" in os.path.basename(dirpath):
        # 统计该目录 DWG
        dwgs = [f for f in filenames if f.lower().endswith(".dwg")]
        print(f"  {dirpath}  (DWG:{len(dwgs)})")
        if dwgs and len(dwgs) < 15:
            for f in sorted(dwgs)[:15]:
                print(f"      {f}")
