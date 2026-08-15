# -*- coding: utf-8 -*-
"""搜索电脑上是否有 COS 密钥配置（SecretId/SecretKey），避免重复获取。"""
import os, glob, re

# 常见配置位置
search_roots = [
    r"F:\建筑验收工具",
    r"F:\GitHub\site-patrol",
    r"F:\设计院工作",
]
# SecretId 特征：AKID 开头或长字符串；SecretKey 特征
secret_id_pat = re.compile(r"(AKID[a-zA-Z0-9]{10,}|secret[_\-]?id\s*[=:]\s*['\"]?([a-zA-Z0-9+/=]{20,}))", re.I)
secret_key_pat = re.compile(r"(secret[_\-]?key\s*[=:]\s*['\"]?([a-zA-Z0-9+/=]{20,}))", re.I)
bucket_pat = re.compile(r"(site-inspection[\w-]*)", re.I)

found_files = set()
for root in search_roots:
    if not os.path.exists(root):
        continue
    for dirpath, dirnames, filenames in os.walk(root):
        # 跳过无关
        if any(x in dirpath for x in ("__pycache__", "node_modules", ".git", "apig_sdk", "14-总院归档", "效果图", "汇报")):
            continue
        for fn in filenames:
            if not fn.lower().endswith((".py", ".env", ".txt", ".json", ".yaml", ".yml", ".ini", ".conf", ".toml", ".md")):
                continue
            full = os.path.join(dirpath, fn)
            try:
                content = open(full, encoding="utf-8", errors="ignore").read(500000)
            except Exception:
                continue
            has_bucket = bucket_pat.search(content)
            has_sec = secret_id_pat.search(content) or secret_key_pat.search(content)
            if has_bucket or has_sec:
                key = full
                found_files.add(key)
                print(f"候选: {full}")
                # 显示相关行（打码）
                for line in content.splitlines():
                    if any(k in line.lower() for k in ("secretid", "secretkey", "secret_id", "secret_key", "bucket", "site-inspection", "region")):
                        print(f"    {line.strip()[:70]}")

print("\n=== 完成搜索 ===")
if not found_files:
    print("未找到 COS 密钥配置文件，需到控制台获取。")
