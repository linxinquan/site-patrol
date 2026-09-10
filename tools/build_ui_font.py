# -*- coding: utf-8 -*-
"""生成 App UI 用的 MiSans 字体子集（小米 MiSans，免费商用）。

背景
----
全局 UI 字体用小米 MiSans（家族名 `MiSans`，见 lib/core/theme/app_theme.dart）。
官方 TTF 每档约 7.9 MB（29093 glyphs，含 CJK 扩展等生僻区），四档一起进包接近
32 MB，Web 首屏要全量下载。这里按「报告字体」同一套字符区间裁一刀，只保留
工程现场实际会用到的字符，体积降到约 6 MB/档，字形覆盖与原来的思源黑体子集一致。

与 build_report_font.py 的差别
------------------------------
报告字体（PDF 嵌入）为了体积把 hinting / GSUB / GPOS 全丢了；UI 字体不能这么干——
浏览器与 Skia 都靠这些表做 kerning/连字，丢了字距会变丑。所以这里保留全部排版表，
只裁字符集 + 丢掉垂直书写（vhea/vmtx）等 UI 用不到的表。

用法
----
    # 单档
    python tools/build_ui_font.py --src MiSans-Regular.ttf --out MiSans-Regular.ttf
    # 四档一起（--src-dir 下需有 MiSans-{Regular,Medium,Demibold,Semibold}.ttf）
    python tools/build_ui_font.py --all --src-dir /tmp/misans

依赖：pip install fonttools（仅构建期，运行期 App 不依赖）
"""
from __future__ import annotations

import argparse
import os
import sys

from fontTools import subset
from fontTools.ttLib import TTFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# 字符区间与「报告字体」保持一致（拉丁 + 中文标点 + CJK 基本区 + 全角/符号）
from build_report_font import _unicodes  # noqa: E402

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "fonts")

# UI 用不到的表：垂直书写度量、图形/数学扩展、光学尺寸提示
_DROP = ["vhea", "vmtx", "VORG", "MATH", "BASE", "meta", "gasp"]

# 四档字重 → 源文件名（MiSans 官方命名：Demibold=600、Semibold 视觉上更重，占 700 位）
WEIGHTS = {
    "MiSans-Regular.ttf": "MiSans-Regular.ttf",
    "MiSans-Medium.ttf": "MiSans-Medium.ttf",
    "MiSans-Demibold.ttf": "MiSans-Demibold.ttf",
    "MiSans-Semibold.ttf": "MiSans-Semibold.ttf",
}


def build(src: str, out_name: str) -> str:
    font = TTFont(src)
    if "glyf" not in font:
        raise SystemExit(f"{src}: 不是 glyf/TrueType 轮廓，Flutter 无法直接使用")
    before = font["maxp"].numGlyphs

    opts = subset.Options()
    opts.notdef_outline = True   # 保留 .notdef 轮廓，缺字时显示方框而不是空白
    opts.recalc_bounds = True
    opts.drop_tables += _DROP    # 保留 GSUB/GPOS/GDEF（kerning、连字）

    s = subset.Subsetter(options=opts)
    s.populate(unicodes=_unicodes())
    s.subset(font)

    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.normpath(os.path.join(OUT_DIR, out_name))
    font.save(out)
    size = os.path.getsize(out) / 1024 / 1024
    print(f"  {out_name}: {before} -> {font['maxp'].numGlyphs} glyphs, {size:.2f} MB")
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="构建 App UI 用 MiSans 字体子集")
    ap.add_argument("--src", help="源 MiSans TTF 路径")
    ap.add_argument("--out", help="输出文件名（默认与源同名）")
    ap.add_argument("--all", action="store_true", help="按 WEIGHTS 批量构建四档")
    ap.add_argument("--src-dir", help="配合 --all：源 TTF 所在目录")
    args = ap.parse_args()

    if args.all:
        if not args.src_dir:
            raise SystemExit("--all 需要同时给 --src-dir")
        for src_name, out_name in WEIGHTS.items():
            build(os.path.join(args.src_dir, src_name), out_name)
        return 0

    if not args.src:
        raise SystemExit("需要 --src（或 --all --src-dir）")
    build(args.src, args.out or os.path.basename(args.src))
    return 0


if __name__ == "__main__":
    sys.exit(main())
