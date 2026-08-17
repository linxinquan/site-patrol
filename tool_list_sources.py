# -*- coding: utf-8 -*-
"""查看两个资料目录的 CAD 文件。"""
import os

roots = [
    r"F:\建筑验收工具\大铲湾DY04_资料",
    r"F:\设计院工作\SZAD\2020-腾讯大铲湾DY04",
]
for root in roots:
    print("=" * 60)
    print("ROOT:", root)
    if not os.path.exists(root):
        print("  不存在")
        continue
    dwg_count = 0
    pdf_count = 0
    # 先列顶层目录
    try:
        top = sorted(os.listdir(root))
        print("  顶层目录/文件:", top[:30])
    except Exception as e:
        print("  读取失败:", e)
        continue
    print("  --- 递归统计 ---")
    for dirpath, dirnames, filenames in os.walk(root):
        for fn in filenames:
            low = fn.lower()
            if low.endswith(".dwg"):
                dwg_count += 1
            elif low.endswith(".pdf"):
                pdf_count += 1
    print(f"  DWG 文件数: {dwg_count}, PDF 文件数: {pdf_count}")
