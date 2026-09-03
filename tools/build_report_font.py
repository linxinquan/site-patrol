# -*- coding: utf-8 -*-
"""生成「报告导出」用的中文字体资源（PDF 渲染需要可嵌入的 TrueType 字体）。

背景
----
`package:pdf` 只支持 sfnt TrueType（glyf 轮廓）字体，不能直接吃 CFF/OTF，
默认字体也没有中文 glyph，所以 PDF 导出必须自带一份中文字体。

字体选择
--------
Noto Sans SC（思源黑体）· SIL Open Font License 1.1，可自由分发、可商用。
Google Fonts 提供的 .woff 是 glyf 轮廓的压缩 sfnt，解压 + 子集化后即可直接用。

产出
----
  assets/fonts/NotoSansSC-Regular.ttf   （默认，PDF 正文 / 表格 / 标题）
  assets/fonts/NotoSansSC-Bold.ttf      （可选 --weight 700）

子集范围：常用拉丁 + 中文标点 + CJK 基本区 U+4E00–U+9FFF + 全角/符号，
覆盖率满足工程报告；CJK 扩展 A/B、兼容汉字等极生僻区被裁掉以控制体积。

用法
----
    python tools/build_report_font.py                    # Regular
    python tools/build_report_font.py --weight 700       # Bold
    python tools/build_report_font.py --src local.woff   # 用本地字体，不联网

依赖：pip install fonttools brotli（仅构建期，运行期 App 不依赖）
"""
from __future__ import annotations

import argparse
import io
import os
import sys
import urllib.request

from fontTools import subset
from fontTools.ttLib import TTFont

# Google Fonts CSS2 接口：带旧版 UA 会返回 .woff（glyf 轮廓）而非 woff2。
_UA = (
    "Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/30.0.1599.101 Safari/537.36"
)
_CSS = "https://fonts.googleapis.com/css2?family=Noto+Sans+SC:wght@{w}"

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "fonts")

# 保留的字符区间（工程报告实际会用到的全部字符类别）
_RANGES = [
    (0x0020, 0x00FF),  # 基本拉丁 + 拉丁补充
    (0x0100, 0x017F),  # 拉丁扩展 A（少量人名/单位符号）
    (0x2000, 0x206F),  # 通用标点（— ‘ ’ “ ” … 等）
    (0x20A0, 0x20BF),  # 货币符号
    (0x2100, 0x214F),  # 类字母符号（℃ ℡ 等）
    (0x2190, 0x21FF),  # 箭头
    (0x2460, 0x24FF),  # 带圈数字 ①②③
    (0x2500, 0x257F),  # 制表符
    (0x25A0, 0x25FF),  # 几何图形 ■▲●
    (0x2600, 0x26FF),  # 杂项符号 ☆★⚠
    (0x3000, 0x303F),  # 中文标点 。、《》【】
    (0x3200, 0x32FF),  # 带圈中日韩字符 ㈠ ㈡ ㊤
    (0x3300, 0x33FF),  # CJK 兼容字符 ㎡ ㎥ ㎏（工程报告高频）
    (0x4E00, 0x9FFF),  # CJK 基本汉字（20989 字，覆盖全部规范汉字）
    (0xFE10, 0xFE1F),  # 竖排标点
    (0xFE30, 0xFE4F),  # CJK 兼容形式
    (0xFF00, 0xFFEF),  # 全角字符
]


def _unicodes() -> list[int]:
    out: list[int] = []
    for lo, hi in _RANGES:
        out.extend(range(lo, hi + 1))
    return out


def _fetch_woff(weight: int) -> bytes:
    """从 Google Fonts 取指定字重的 Noto Sans SC（woff/glyf）。"""
    req = urllib.request.Request(_CSS.format(w=weight), headers={"User-Agent": _UA})
    css = urllib.request.urlopen(req, timeout=60).read().decode("utf-8")
    urls = []
    for line in css.splitlines():
        if "src:" in line and "url(" in line:
            urls.append(line.split("url(", 1)[1].split(")", 1)[0])
    if not urls:
        raise SystemExit("未能从 Google Fonts 解析到字体地址，请改用 --src 指定本地字体")
    print(f"  下载 {urls[0]}")
    return urllib.request.urlopen(urls[0], timeout=180).read()


def build(src: bytes | None, weight: int, out_name: str) -> str:
    data = src if src is not None else _fetch_woff(weight)
    font = TTFont(io.BytesIO(data))
    if "glyf" not in font:
        raise SystemExit(
            f"{out_name}: 字体为 CFF 轮廓（{font.sfntVersion}），package:pdf 不支持，"
            "请改用 glyf/TrueType 版本"
        )

    before = font["maxp"].numGlyphs
    opts = subset.Options()
    opts.layout_features = []          # 丢弃 GSUB/GPOS，报告不需要复杂排版
    opts.notdef_outline = True
    opts.recalc_bounds = True
    opts.desubroutinize = True
    opts.hinting = False               # PDF 直接渲染轮廓，hinting 纯属体积负担
    # 竖排/基线标签/TrueType 指令表对报告无用，一并裁掉
    opts.drop_tables += [
        "DSIG", "GSUB", "GPOS", "GDEF", "MATH", "meta",
        "BASE", "STAT", "vhea", "vmtx", "VORG", "gasp", "hdmx", "LTSH",
    ]

    s = subset.Subsetter(options=opts)
    s.populate(unicodes=_unicodes())
    s.subset(font)

    font.flavor = None                 # 去 woff 压缩，还原为裸 TTF
    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.normpath(os.path.join(OUT_DIR, out_name))
    font.save(out)
    size = os.path.getsize(out) / 1024 / 1024
    print(
        f"  {out_name}: {before} -> {font['maxp'].numGlyphs} glyphs, "
        f"{size:.2f} MB (tables: {sorted(font.keys())})"
    )
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="构建报告导出用中文字体资源")
    ap.add_argument("--weight", type=int, default=400, choices=[400, 700], help="字重")
    ap.add_argument("--src", help="本地 woff/ttf/otf 字体路径（不联网）")
    ap.add_argument("--out", help="输出文件名")
    args = ap.parse_args()

    name = args.out or f"NotoSansSC-{'Bold' if args.weight == 700 else 'Regular'}.ttf"
    raw = None
    if args.src:
        with open(args.src, "rb") as f:
            raw = f.read()
        print(f"  使用本地字体 {args.src}")
    build(raw, args.weight, name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
