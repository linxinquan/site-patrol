# -*- coding: utf-8 -*-
"""检查是否有 COS 配置、以及后端 API 文档中 DWG 直转图片的接口。"""
import os, re, glob

# 1. 检查可能的 COS 配置
print("=== 搜索 COS 配置 ===")
for pat in [r"f:\GitHub\site-patrol\**\*.env", r"F:\建筑验收工具\**\*.env", r"F:\建筑验收工具\**\*.py"]:
    for f in glob.glob(pat, recursive=True):
        if any(x in f for x in ("__pycache__", "node_modules", ".git")):
            continue
        try:
            content = open(f, encoding="utf-8", errors="ignore").read()
            if any(k in content.upper() for k in ("SECRETID", "SECRETKEY", "COS_", "REGION", "BUCKET", "TENCENT")):
                print(f"  找到: {f}")
                for line in content.splitlines():
                    if any(k in line.upper() for k in ("SECRET", "COS_", "BUCKET", "REGION")):
                        # 打码显示
                        print(f"    {line[:60]}")
        except Exception:
            pass

# 2. 检查后端 API 文档是否有 DWG 直转图片接口
print("\n=== 后端文档接口清单 ===")
api_doc = r"f:\GitHub\site-patrol\backend_api.txt"
if os.path.exists(api_doc):
    text = open(api_doc, encoding="utf-8", errors="ignore").read()
    # 提取所有 openapi/v1/ 接口
    apis = sorted(set(re.findall(r"openapi/v1/[A-Za-z]+", text)))
    print("接口列表:", apis)
