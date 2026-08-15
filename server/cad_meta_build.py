# -*- coding: utf-8 -*-
"""
构建 DWG 元数据：从本地原图目录扫描 10 张 7栋 DWG，用 ezdxf 解析输出 JSON。
不消耗浩辰次数（OCF 缓存保留，渲染仍走 GStarSDK）。
"""
import os
import sys
import glob
import json

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ROOT)
from cad_meta_server import parse_dwg_to_meta, META_DIR, HAS_EZDXF

if not HAS_EZDXF:
    print("[build_meta] ⚠ ezdxf 未安装：pip install ezdxf")
    sys.exit(1)

# OCF key → 真实 DWG 文件路径
DWG_SOURCE_ROOT = r"F:\建筑验收工具\大铲湾DY04_资料\7栋B1施工图"
OCF_KEYS = ['dy04_7_B01','dy04_7_B02','dy04_7_D01','dy04_7_D03',
            'dy04_7_E01','dy04_7_F01','dy04_7_J01','dy04_7_J04',
            'dy04_7_K01','dy04_7_K02']


def find_dwg(short):
    """根据 OCF 简称（去掉 dy04_7_ 前缀）找 DWG"""
    # 在 DWG_SOURCE_ROOT 下递归找文件名包含 short 的 .dwg
    matches = []
    for dp, _, fns in os.walk(DWG_SOURCE_ROOT):
        for fn in fns:
            if fn.lower().endswith('.dwg') and short in fn:
                matches.append(os.path.join(dp, fn))
    if not matches:
        return None
    # 优先选最大文件（含完整信息）
    matches.sort(key=lambda p: os.path.getsize(p), reverse=True)
    return matches[0]


print(f"[build_meta] 源目录：{DWG_SOURCE_ROOT}")
print(f"[build_meta] 目标目录：{META_DIR}")
print(f"[build_meta] 解析 {len(OCF_KEYS)} 张图...\n")

ok_count = 0
for key in OCF_KEYS:
    short = key.split('_', 2)[-1]  # B01 / D01
    dwg = find_dwg(short)
    if not dwg:
        print(f"[{key}]  ✗ 未找到 DWG")
        continue
    rel = os.path.relpath(dwg, DWG_SOURCE_ROOT)
    size_mb = os.path.getsize(dwg) / 1048576
    print(f"[{key}]  源文件: {rel}  ({size_mb:.1f} MB)")
    try:
        meta = parse_dwg_to_meta(dwg)
        meta['key'] = key
        meta['source_dwg'] = rel
        out = os.path.join(META_DIR, key + ".json")
        with open(out, "w", encoding="utf-8") as f:
            json.dump(meta, f, ensure_ascii=False, indent=2)
        print(f"  → 图层 {meta['layer_count']} (开 {meta['on_count']} 冻 {meta['frozen_count']})")
        print(f"  → 布局 {meta['layouts']}")
        print(f"  → 实体类型 {len(meta['ent_types'])} 种")
        ok_count += 1
    except Exception as e:
        print(f"  ✗ 解析失败：{e}")
    print()

print(f"[build_meta] 完成：{ok_count}/{len(OCF_KEYS)} 张元数据生成成功")
print(f"[build_meta] 元数据输出目录：{META_DIR}")