# -*- coding: utf-8 -*-
"""在原始资料中查找 7栋 的完整楼层平面图。"""
import os

root = r"F:\设计院工作\SZAD\2020-腾讯大铲湾DY04"
# 7栋相关，优先平面图
keywords = ["7栋", "7#", "D7", "DY04-7", "平面图", "floor"]
results = []
for dirpath, dirnames, filenames in os.walk(root):
    if any(x in dirpath for x in ("归档", "效果图", "汇报", "驻地")):
        continue
    for fn in filenames:
        if not fn.lower().endswith(".dwg"):
            continue
        full = os.path.join(dirpath, fn)
        # 7栋相关 或 平面图
        if "7栋" in fn or "7#" in fn or "平面图" in fn:
            size = os.path.getsize(full) / 1024
            results.append((full, size, fn))

print(f"找到 {len(results)} 个候选 DWG")
# 只显示包含"7"和"平面图"的（最可能是 7栋平面图）
plan7 = [r for r in results if "7" in r[2] and "平面图" in r[2]]
print(f"\n=== 含'7'且'平面图'的 ({len(plan7)} 个) ===")
for full, size, fn in sorted(plan7, key=lambda x: x[1]):
    print(f"  {size:.0f}KB  {fn}")

# 也列出所有"平面图"
print(f"\n=== 所有含'平面图'的 DWG (前40) ===")
plans = [r for r in results if "平面图" in r[2]]
for full, size, fn in sorted(plans, key=lambda x: x[1])[:40]:
    print(f"  {size:.0f}KB  {fn}")
