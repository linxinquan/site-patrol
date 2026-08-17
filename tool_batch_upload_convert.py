# -*- coding: utf-8 -*-
"""
批量：上传第一轮测试CAD的8张DWG到COS + 调浩辰 dwgToOcf 转OCF。
用法：
  python tool_batch_upload_convert.py upload    # 只上传（不耗浩辰次数）
  python tool_batch_upload_convert.py convert   # 只转换（需先 upload）
"""
import os
import sys

sys.path.insert(0, r"f:\GitHub\site-patrol\server")
os.chdir(r"f:\GitHub\site-patrol\server")

from cos_upload import upload_file
import ocf_server as srv

# 待转换的 8 张（key, 源DWG相对路径, COS 文件名）
TARGETS = [
    ("dy04_7_B02", r"01_平面图\建施_AW-7-B02_V1.0_地下一层顶板分区平面图(一).dwg", "B02.dwg"),
    ("dy04_7_D01", r"03_剖面图\建施_AW-7-D01_V1.0_A座1-1剖面图.dwg", "D01.dwg"),
    ("dy04_7_D03", r"03_剖面图\建施_AW-7-D03~D04 C02（7栋B座） 剖面图绑定版-20220831.011402.dwg", "D03_D04.dwg"),
    ("dy04_7_K02", r"04_墙身详图\建施_AW-7-K02_V1.0_墙身详图（二）.dwg", "K02.dwg"),
    ("dy04_7_E01", r"05_楼梯详图_A座\建施_AW-7-E01_V1.0_A座7A-LT01楼梯详图 （一）.dwg", "E01.dwg"),
    ("dy04_7_F01", r"06_楼梯详图_B座\建施_AW-7-F01~F08 C02（7栋B座） 楼梯剖面图绑定版-20220831.011433.dwg", "F01_F08.dwg"),
    ("dy04_7_J01", r"07_门窗详图\建施_AW-7-J01_V1.0_A座门窗详图（一）.dwg", "J01.dwg"),
    ("dy04_7_J04", r"07_门窗详图\建施_AW-7-J04~J05 C02（7栋B座） 门窗详图绑定版-20220831.012149.dwg", "J04_J05.dwg"),
]

BASE_DIR = r"F:\建筑验收工具\大铲湾DY04_资料\第一轮测试CAD"
OCF_DIR = r"f:\GitHub\site-patrol\server\ocf_cache"


def do_upload():
    os.makedirs(OCF_DIR, exist_ok=True)
    print("=== 上传 8 张 DWG 到 COS ===")
    urls = {}
    for key, rel, cos_fn in TARGETS:
        src = os.path.join(BASE_DIR, rel)
        if not os.path.exists(src):
            print(f"[跳过] {key}: 源文件不存在 {src}")
            continue
        url = upload_file(src, cos_fn)
        urls[key] = url
        print(f"[上传成功] {key} -> {url}")
    # 保存 URL 映射
    with open(os.path.join(OCF_DIR, "urls.json"), "w", encoding="utf-8") as f:
        import json
        json.dump(urls, f, ensure_ascii=False, indent=2)
    print(f"URL 映射已保存: {len(urls)} 个")
    return urls


def do_convert():
    import json
    urls_file = os.path.join(OCF_DIR, "urls.json")
    if not os.path.exists(urls_file):
        print("未找到 urls.json，请先执行 upload")
        return
    urls = json.load(open(urls_file, encoding="utf-8"))
    print(f"=== 转换 {len(urls)} 张 OCF（每张消耗 1 次）===")
    print(f"  已配置凭证: {srv.is_configured()}")
    print(f"  OCF 目录: {OCF_DIR}")
    converted = cached = failed = 0
    for key, rel, cos_fn in TARGETS:
        dest = os.path.join(OCF_DIR, f"{key}.ocf")
        if os.path.exists(dest):
            print(f"[缓存命中] {key} 不消耗次数")
            cached += 1
            continue
        url = urls.get(key)
        if not url:
            print(f"[跳过] {key}: 无 COS URL")
            failed += 1
            continue
        print(f"[转换] {key} <- {cos_fn}", flush=True)
        try:
            path, layouts = srv.convert_dwg_to_ocf(key, dwg_url=url, file_name=cos_fn)
            print(f"[完成] {key} -> {path}  布局: {layouts[:6]}")
            converted += 1
        except Exception as e:
            print(f"[失败] {key}: {str(e)[:200]}")
            failed += 1
    print(f"\n=== 汇总: 转换{converted} 缓存{cached} 失败{failed} ===")


if __name__ == "__main__":
    action = sys.argv[1] if len(sys.argv) > 1 else "upload"
    if action == "upload":
        do_upload()
    elif action == "convert":
        do_convert()
    else:
        print("用法: python tool_batch_upload_convert.py [upload|convert]")
