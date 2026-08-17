# -*- coding: utf-8 -*-
"""测试 COS 上传（脚本内部写路径，避开命令行中文乱码）。"""
import os
import sys

sys.path.insert(0, r"f:\GitHub\site-patrol\server")
from cos_upload import upload_file

# 最小文件 J04~J05
test_file = (r"F:\建筑验收工具\大铲湾DY04_资料\第一轮测试CAD\07_门窗详图\"
             r"建施_AW-7-J04~J05 C02（7栋B座） 门窗详图绑定版-20220831.012149.dwg")
if not os.path.exists(test_file):
    print("文件不存在:", test_file)
    sys.exit(1)
print("文件大小:", os.path.getsize(test_file) / 1024, "KB")
try:
    url = upload_file(test_file, "J04_J05.dwg")
    print("上传成功:", url)
except Exception as e:
    print("上传失败:", str(e)[:500])
