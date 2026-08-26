# -*- coding: utf-8 -*-
"""
DWG -> DXF 批量转换工具（依赖已安装的 ODA File Converter）。

用法:
    python dwg_to_dxf.py                 # 转换 server/dwg_cache 下所有 .dwg
    python dwg_to_dxf.py B01.dwg         # 仅转换指定文件

说明:
    - 需要 ODA File Converter（免费）已安装。本机安装路径见 ODA_BIN。
    - 输出为 ACAD2018 DXF，写入 dwg_cache，与同名 .dwg 并列。
    - 失败的文件会生成 <name>.dxf.err 占位，可据此判断源文件是否有效。
"""
import os
import sys
import shutil
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "dwg_cache")

# 本机安装的 ODA File Converter 可执行文件
ODA_BIN = r"C:\Program Files\ODA\ODAFileConverter 27.1.0\ODAFileConverter.exe"

# 临时工作目录（避免输入=输出导致的冲突）
WORK = os.path.join(HERE, "_dxf_work")
OUT = os.path.join(HERE, "_dxf_out")


def ensure_oda():
    if not os.path.exists(ODA_BIN):
        raise SystemExit(
            "未找到 ODA File Converter: %s\n请先安装(免费): https://www.opendesign.com/guestfiles/oda_file_converter" % ODA_BIN
        )


def convert_one(dwg_name: str):
    src = os.path.join(CACHE, dwg_name)
    if not os.path.exists(src):
        print("[skip] 源文件不存在:", src)
        return
    os.makedirs(WORK, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    # 只放单个文件到工作目录，避免重复转换其它图
    shutil.copy(src, os.path.join(WORK, dwg_name))
    base = os.path.splitext(dwg_name)[0]
    err_file = os.path.join(CACHE, base + ".dxf.err")
    if os.path.exists(err_file):
        os.remove(err_file)
    try:
        proc = subprocess.run(
            [ODA_BIN, WORK, OUT, "ACAD2018", "DXF", "0", "1"],
            capture_output=True, text=True, timeout=900,
        )
        out_dxf = os.path.join(OUT, base + ".dxf")
        if os.path.exists(out_dxf) and os.path.getsize(out_dxf) > 0:
            shutil.copy(out_dxf, os.path.join(CACHE, base + ".dxf"))
            print("[ok] %s -> %s (%.1f MB)" % (
                dwg_name, base + ".dxf", os.path.getsize(out_dxf) / 1e6))
        else:
            with open(err_file, "w", encoding="utf-8") as f:
                f.write("ODA exit=%s\n%s\n%s\n" % (
                    proc.returncode, proc.stdout, proc.stderr))
            print("[fail] %s 转换失败，详见 %s" % (dwg_name, err_file))
    finally:
        # 清理工作目录里的副本
        try:
            os.remove(os.path.join(WORK, dwg_name))
        except OSError:
            pass


def main():
    ensure_oda()
    targets = sys.argv[1:]
    if not targets:
        targets = [f for f in os.listdir(CACHE) if f.lower().endswith(".dwg")]
    for t in targets:
        convert_one(t)
    print("完成。DXF 输出目录:", CACHE)


if __name__ == "__main__":
    main()
