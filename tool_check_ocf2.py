# -*- coding: utf-8 -*-
import os
ocf_dir = r"f:\GitHub\site-patrol\server\ocf_cache"
print("=== OCF 缓存完整清单 ===")
total = 0
for fn in sorted(os.listdir(ocf_dir)):
    if fn.endswith(".ocf"):
        size = os.path.getsize(os.path.join(ocf_dir, fn)) / 1048576
        total += 1
        print(f"  {size:.2f}MB  {fn}")
print(f"\n共 {total} 个 OCF")
