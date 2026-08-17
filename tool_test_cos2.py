# -*- coding: utf-8 -*-
import os, sys
sys.path.insert(0, r"f:\GitHub\site-patrol\server")
from cos_upload import upload_file

# 用 os.listdir 遍历，避免手写中文路径
base = r"F:\建筑验收工具\大铲湾DY04_资料\第一轮测试CAD\07_门窗详图"
print("base exists:", os.path.exists(base))
if os.path.exists(base):
    for fn in os.listdir(base):
        full = os.path.join(base, fn)
        if os.path.isfile(full) and fn.lower().endswith(".dwg"):
            print("found:", fn, os.path.getsize(full))
            if "J04" in fn:
                url = upload_file(full, "J04_J05.dwg")
                print("UPLOAD OK:", url)
                break
