# -*- coding: utf-8 -*-
"""本地 CAD 渲染管线（零云配额版）。

流程：DWG/DXF -> ODA File Converter -> DXF -> ezdxf 渲染 PNG 底图 + 文字层叠加。

已知限制（关于"几何图元缺失 / 尺寸数字缺失"）：
- ezdxf 的 matplotlib 后端默认不渲染文字；天正/自定义对象 ACAD_PROXY_ENTITY
  无法被 ODA/ezdxf 解析。因此：
  1) 标注数字若以 TArch 代理对象形式存在，本地无法还原，需走「专业看图」(浩辰云图 GStarSDK)。
  2) 普通 TEXT/MTEXT/ATTDEF/块属性等可恢复文字，本模块用 PIL 直接叠加到 PNG，
     彻底解决"底图无文字/标题栏空白"问题，默认视图即可见。
- 另：DXF 中若图层被关闭/冻结，ezdxf 默认不绘制 -> 强制全部可见以还原几何。
"""
import io
import json
import os
import shutil
import subprocess

import ezdxf
from ezdxf.addons.drawing import RenderContext, Frontend
from ezdxf.addons.drawing.matplotlib import MatplotlibBackend

HERE = os.path.dirname(os.path.abspath(__file__))

TARCH_PROXY_THRESHOLD = 20  # 代理实体数量阈值，超过即判定为天正/自定义对象图纸


# --------------------------------------------------------------------------- #
#  对外 API
# --------------------------------------------------------------------------- #
def local_available():
    return os.path.exists(_oda_bin()) or shutil.which("ODAFileConverter") is not None


def sanitize_key(name):
    out = []
    for ch in name:
        if ch.isalnum() or ch in "._-":
            out.append(ch)
        else:
            out.append("_")
    return "".join(out).strip("_") or "drawing"


def convert_local(key, dwg_bytes, dpi=160):
    """返回 dict：含 key/ok/png/png_w/png_h/bounds/text_count/
    proxy_count/tarch_proxy/note/layers_count/layouts/size_mb。
    ok=False 表示本地无法完整转换（通常为天正代理对象导致 ODA 导出 DXF 损坏）。"""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    from cad_meta_server import parse_dwg_to_meta

    key = sanitize_key(key)
    work_in = os.path.join(HERE, "_local_work", "in")
    work_out = os.path.join(HERE, "_local_work", "out")
    out = _out_dir()
    for d in (work_in, work_out):
        os.makedirs(d, exist_ok=True)
        for f in os.listdir(d):
            try:
                os.remove(os.path.join(d, f))
            except OSError:
                pass
    os.makedirs(out, exist_ok=True)

    is_dxf = _looks_like_dxf(dwg_bytes)
    src_name = key + (".dxf" if is_dxf else ".dwg")
    src_path = os.path.join(work_in, src_name)
    with open(src_path, "wb") as f:
        f.write(dwg_bytes)

    # 1) 得到 DXF
    dxf_path = None
    if is_dxf:
        dxf_path = src_path
    else:
        try:
            _oda_convert(work_in, work_out)
        except Exception as ex:
            return _proxy_failure(key, "ODA 转换失败: %s" % ex)
        for f in os.listdir(work_out):
            if f.lower().endswith(".dxf"):
                dxf_path = os.path.join(work_out, f)
                break

    if not dxf_path or not _is_valid_dxf(dxf_path):
        return _proxy_failure(
            key, "ODA 无法导出该图纸的有效 DXF（天正/自定义对象常导致 DXF 损坏）")

    doc = ezdxf.readfile(dxf_path)

    # 2) 渲染底图（强制图层可见 + 按图纸比例）
    png_path = os.path.join(out, key + ".png")
    png_w, png_h, bounds = _render_png(dxf_path, png_path, dpi=dpi)

    # 3) 用 PIL 叠加可恢复文字（标题栏、标注说明等）
    text_count = _overlay_text_on_png(dxf_path, png_path, bounds, png_w, png_h)

    # 4) 文字层 SVG（按需切换时使用的可缩放文字层）
    svg_path = os.path.join(out, key + ".svg")
    try:
        _render_text_svg(dxf_path, svg_path, bounds, png_w, png_h)
    except Exception:
        svg_path = None

    # 5) 元数据
    try:
        meta = parse_dwg_to_meta(dxf_path)
        with open(os.path.join(out, key + "_meta.json"), "w", encoding="utf-8") as f:
            json.dump(meta, f, ensure_ascii=False)
    except Exception:
        meta = {}

    layouts = list(doc.layouts.names())
    layers_count = len(doc.layers)
    size_mb = round(os.path.getsize(dxf_path) / 1024.0 / 1024.0, 2)

    # 6) 代理对象探测（天正/自定义对象 -> 尺寸数字与部分图元本地无法还原）
    proxy_count = _count_proxies(doc)
    tarch_proxy = proxy_count >= TARCH_PROXY_THRESHOLD
    note = ""
    if tarch_proxy:
        note = ("检测到大量天正/自定义代理实体(%d个)：本地渲染会缺失尺寸数字与"
                "部分图元。建议使用「专业看图」(浩辰云图 GStarSDK) 以获得完整标注。"
                % proxy_count)

    return {
        "key": key,
        "ok": True,
        "dxf": dxf_path,
        "meta": meta,
        "png": png_path,
        "layers_count": layers_count,
        "layouts": layouts,
        "size_mb": size_mb,
        "png_w": png_w,
        "png_h": png_h,
        "bounds": bounds,
        "text_count": text_count,
        "proxy_count": proxy_count,
        "tarch_proxy": tarch_proxy,
        "note": note,
        "svg": svg_path,
    }


def _proxy_failure(key, error):
    return {
        "key": key,
        "ok": False,
        "error": error,
        "tarch_proxy": True,
        "note": ("该图纸含天正/自定义对象，本地 ODA 无法导出有效 DXF，尺寸数字与部分图元"
                 "无法本地还原。请使用「专业看图」(浩辰云图 GStarSDK) 渲染完整标注。"),
        "png": None,
        "png_w": 0,
        "png_h": 0,
        "bounds": None,
        "layers_count": 0,
        "layouts": [],
        "size_mb": 0,
        "text_count": 0,
        "proxy_count": 0,
        "svg": None,
    }


# --------------------------------------------------------------------------- #
#  路径 / ODA
# --------------------------------------------------------------------------- #
def _out_dir():
    d = os.environ.get("GCAD_OCF_DIR")
    if d:
        os.makedirs(d, exist_ok=True)
        return d
    d = os.path.join(HERE, "ocf_cache")
    os.makedirs(d, exist_ok=True)
    return d


def _looks_like_dxf(b):
    head = b[:256].upper()
    return (b"SECTION" in head) or (b"AUTOCAD" in head) or (b"ACAD" in head)


def _is_valid_dxf(path):
    try:
        ezdxf.readfile(path)
        return True
    except Exception:
        return False


def _oda_bin():
    base = r"C:\Program Files\ODA"
    if os.path.isdir(base):
        for name in os.listdir(base):
            cand = os.path.join(base, name, "ODAFileConverter.exe")
            if os.path.exists(cand):
                return cand
    return "ODAFileConverter.exe"


def _oda_convert(src_dir, dst_dir):
    bin_path = _oda_bin()
    if not os.path.exists(bin_path):
        bin_path = "ODAFileConverter.exe"
    subprocess.run(
        # audit=1（修复模式）：天正/TArch 代理对象会导致 audit=0 写 DXF 时抛
        # "AcDbDictionary can't be cast to AcDbBlockTableRecord"（DXF 损坏），
        # 开 audit 后 ODA 自动修复可正常导出（K03 实测 303MB 有效 DXF）。
        [bin_path, src_dir, dst_dir, "ACAD2018", "DXF", "0", "1"],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=600,
    )


# --------------------------------------------------------------------------- #
#  布局选择
# --------------------------------------------------------------------------- #
def _choose_layout(doc):
    """选择实体最多的布局（优先模型/图纸空间里内容更完整的那一个）。"""
    target = doc.modelspace()
    best_name = "Model"
    best_count = len(target)
    for name in doc.layouts.names():
        if name == "Model":
            continue
        try:
            lay = doc.layouts.get(name)
            c = len(lay)
            if c > best_count:
                target, best_count, best_name = lay, c, name
        except Exception:
            continue
    return target, best_name


# --------------------------------------------------------------------------- #
#  PNG 底图渲染
# --------------------------------------------------------------------------- #
def _render_png(dxf_path, png_path, dpi=160):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    # 让 ezdxf 自身渲染的文字不可见（白字白底），统一由 PIL 叠加，避免重复/乱码
    matplotlib.rcParams["text.color"] = "white"
    matplotlib.rcParams["axes.unicode_minus"] = False

    doc = ezdxf.readfile(dxf_path)
    target, _ = _choose_layout(doc)

    def _build(fig):
        ax = fig.add_axes([0, 0, 1, 1], facecolor="white")
        ax.set_axis_off()
        ctx = RenderContext(doc)
        # ★ 强制所有图层可见：避免 DXF 中关闭/冻结图层导致图元缺失
        for lp in ctx.layers.values():
            try:
                lp.is_visible = True
            except Exception:
                pass
        Frontend(ctx, MatplotlibBackend(ax)).draw_layout(target, finalize=True)
        return ax

    # 第一遍：取数据范围，按图纸原始宽高比设置画布（避免拉伸变形）
    fig = plt.figure(facecolor="white")
    ax = _build(fig)
    x0, x1 = ax.get_xlim()
    y0, y1 = ax.get_ylim()
    span_x = (x1 - x0) or 1.0
    span_y = (y1 - y0) or 1.0
    plt.close(fig)

    base_w = 10.0
    fig_h = max(0.5, base_w * span_y / span_x)

    # 第二遍：按正确比例渲染并保存
    fig = plt.figure(figsize=(base_w, fig_h), facecolor="white")
    ax = _build(fig)
    x0, x1 = ax.get_xlim()
    y0, y1 = ax.get_ylim()
    fig.savefig(png_path, dpi=dpi, facecolor="white")
    w_px = int(round(fig.get_size_inches()[0] * dpi))
    h_px = int(round(fig.get_size_inches()[1] * dpi))
    plt.close(fig)
    return w_px, h_px, [float(x0), float(y0), float(x1), float(y1)]


# --------------------------------------------------------------------------- #
#  文字实体提取（TEXT / MTEXT / ATTDEF / ATTRIB / DIMENSION / MLEADER）
# --------------------------------------------------------------------------- #
def _iter_text_entities(entities):
    """展开所有含文字实体，递归处理块(INSERT)内属性。"""
    for e in entities:
        t = e.dxftype()
        if t == "INSERT":
            try:
                yield from _iter_text_entities(e.virtual_entities())
            except Exception:
                pass
        else:
            yield e


def _mtext_plain(e):
    try:
        return (e.plain_text() or "").strip()
    except Exception:
        pass
    raw = str(getattr(e, "text", "") or "")
    import re
    raw = re.sub(r"\\f[^{;]*;", "", raw)
    raw = re.sub(r"\\pxi[^;]*;?", "", raw)
    raw = raw.replace("\\P", "\n").replace("\\p", "\n")
    raw = re.sub(r"[{}]", "", raw)
    return raw.strip()


def _extract_text_info(doc, e):
    """返回 (text, x, y, height, rotation) 或 None。"""
    try:
        t = e.dxftype()
        if t == "TEXT":
            text = str(e.dxf.text or "").strip()
            ins = e.dxf.insert
            height = float(e.dxf.height or 0)
            rotation = float(getattr(e.dxf, "rotation", 0) or 0)
            return (text, float(ins.x), float(ins.y), height, rotation)

        if t == "MTEXT":
            text = _mtext_plain(e)
            ins = e.dxf.insert
            height = float(getattr(e.dxf, "char_height", 0)
                           or getattr(e.dxf, "height", 0) or 0)
            rotation = float(getattr(e.dxf, "rotation", 0) or 0)
            return (text, float(ins.x), float(ins.y), height, rotation)

        if t in ("ATTDEF", "ATTRIB"):
            text = str(getattr(e.dxf, "text", "") or "").strip()
            if not text:
                text = str(getattr(e.dxf, "prompt", "") or "").strip()
            try:
                ins = e.dxf.insert
            except Exception:
                try:
                    ins = e.dxf.alignment_point
                except Exception:
                    return None
            height = float(getattr(e.dxf, "height", 0) or 0)
            rotation = float(getattr(e.dxf, "rotation", 0) or 0)
            return (text, float(ins.x), float(ins.y), height, rotation)

        if t == "DIMENSION":
            try:
                text = (e.get_text() or "").strip()
            except Exception:
                text = str(getattr(e.dxf, "text", "") or "").strip()
            if not text:
                return None
            try:
                ins = e.dxf.text_midpoint
            except Exception:
                try:
                    ins = e.dxf.dim_line_location
                except Exception:
                    return None
            height = float(getattr(e.dxf, "text_height", 0) or 0)
            if height <= 0:
                try:
                    ds = doc.dimstyles.get(e.dxf.dimstyle)
                    height = float(getattr(ds.dxf, "dimtxt", 0) or 0)
                except Exception:
                    height = 0
            rotation = float(getattr(e.dxf, "angle", 0) or 0)
            return (text, float(ins.x), float(ins.y), height, rotation)

        if t == "MLEADER":
            try:
                text = (e.get_text() or "").strip()
            except Exception:
                text = str(getattr(e.dxf, "text", "") or "").strip()
            try:
                ins = e.dxf.text_insertion_point
            except Exception:
                try:
                    ins = e.dxf.insert
                except Exception:
                    return None
            height = float(getattr(e.dxf, "char_height", 0) or 0)
            return (text, float(ins.x), float(ins.y), height, 0.0)
    except Exception:
        return None
    return None


def _resolve_font():
    p = os.path.join(HERE, "..", "assets", "fonts", "NotoSansSC-Regular.ttf")
    if os.path.exists(p):
        return os.path.abspath(p)
    for c in (
        "C:/Windows/Fonts/NotoSansSC-Regular.ttf",
        "C:/Windows/Fonts/simhei.ttf",
        "C:/Windows/Fonts/msyh.ttf",
        "C:/Windows/Fonts/simsun.ttc",
    ):
        if os.path.exists(c):
            return c
    return None


# --------------------------------------------------------------------------- #
#  PIL 文字叠加（画到 PNG 上，解决"底图无文字/标题栏空白"）
# --------------------------------------------------------------------------- #
def _overlay_text_on_png(dxf_path, png_path, bounds, w_px, h_px):
    from PIL import Image, ImageDraw, ImageFont

    doc = ezdxf.readfile(dxf_path)
    target, _ = _choose_layout(doc)
    x0, y0, x1, y1 = bounds
    span_x = (x1 - x0) or 1.0
    span_y = (y1 - y0) or 1.0
    font_path = _resolve_font()

    def to_px(x, y):
        return ((x - x0) / span_x * w_px,
                (1 - (y - y0) / span_y) * h_px)

    def font_for(size):
        size = max(6, int(round(size)))
        if font_path:
            try:
                return ImageFont.truetype(font_path, size)
            except Exception:
                pass
        for c in ("C:/Windows/Fonts/simhei.ttf",
                 "C:/Windows/Fonts/msyh.ttf",
                 "C:/Windows/Fonts/simsun.ttc"):
            try:
                return ImageFont.truetype(c, size)
            except Exception:
                continue
        return ImageFont.load_default()

    img = Image.open(png_path).convert("RGBA")
    draw = ImageDraw.Draw(img)
    count = 0

    for e in _iter_text_entities(target):
        info = _extract_text_info(doc, e)
        if not info:
            continue
        text, x, y, height, rotation = info
        text = text.strip()
        if not text:
            continue
        px, py = to_px(x, y)
        fs = max(6.0, height / span_y * h_px)
        font = font_for(fs)
        stroke = max(1, int(fs // 12))
        # 白描边提高在彩色线条/底图上的可读性
        if rotation and abs(rotation) > 0.5:
            _paste_rotated(img, px, py, text, font, rotation, stroke)
        else:
            draw.text((px, py), text, font=font, fill=(20, 20, 20),
                      anchor="mm", stroke_width=stroke,
                      stroke_fill=(255, 255, 255))
        count += 1

    img.convert("RGB").save(png_path)
    return count


def _paste_rotated(img, px, py, text, font, rotation, stroke):
    from PIL import Image as _PIL, ImageDraw as _PDraw
    measure = _PDraw.Draw(_PIL.new("RGBA", (1, 1)))
    bbox = measure.textbbox((0, 0), text, font=font, stroke_width=stroke)
    w = int(bbox[2] - bbox[0]) + 8
    h = int(bbox[3] - bbox[1]) + 8
    tmp = _PIL.new("RGBA", (max(1, w), max(1, h)), (0, 0, 0, 0))
    td = _PDraw.Draw(tmp)
    td.text((-bbox[0] + 4, -bbox[1] + 4), text, font=font, fill=(20, 20, 20),
            stroke_width=stroke, stroke_fill=(255, 255, 255))
    rotated = tmp.rotate(-rotation, expand=True, resample=_PIL.BICUBIC)
    img.alpha_composite(rotated, (int(px - rotated.width / 2),
                                  int(py - rotated.height / 2)))


# --------------------------------------------------------------------------- #
#  文字层 SVG（按需切换时使用的可缩放文字层）
# --------------------------------------------------------------------------- #
def _render_text_svg(dxf_path, svg_path, bounds, w_px, h_px):
    from xml.sax.saxutils import escape as _esc

    doc = ezdxf.readfile(dxf_path)
    target, _ = _choose_layout(doc)
    x0, y0, x1, y1 = bounds
    span_x = (x1 - x0) or 1.0
    span_y = (y1 - y0) or 1.0

    def to_px(x, y):
        return ((x - x0) / span_x * w_px,
                (1 - (y - y0) / span_y) * h_px)

    parts = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w_px}" '
        f'height="{h_px}" viewBox="0 0 {w_px} {h_px}">',
    ]
    for e in _iter_text_entities(target):
        info = _extract_text_info(doc, e)
        if not info:
            continue
        text, x, y, height, rotation = info
        if not text.strip():
            continue
        px, py = to_px(x, y)
        fs = max(6.0, height / span_y * h_px)
        parts.append(
            f'<text x="{px:.1f}" y="{py:.1f}" font-size="{fs:.1f}" '
            f'text-anchor="middle" fill="#111111" '
            f'font-family="sans-serif"'
            + (f' transform="rotate({-rotation:.2f} {px:.1f} {py:.1f})"'
               if rotation else "") +
            f'>{_esc(text)}</text>'
        )
    parts.append("</svg>")
    with open(svg_path, "w", encoding="utf-8") as f:
        f.write("\n".join(parts))


# --------------------------------------------------------------------------- #
#  代理对象探测
# --------------------------------------------------------------------------- #
def _count_proxies(doc):
    cnt = 0

    def inc(e):
        nonlocal cnt
        if e.dxftype() == "ACAD_PROXY_ENTITY":
            cnt += 1

    for name in doc.layouts.names():
        try:
            for e in doc.layouts.get(name):
                inc(e)
                if e.dxftype() == "INSERT":
                    try:
                        for ve in e.virtual_entities():
                            inc(ve)
                    except Exception:
                        pass
        except Exception:
            pass
    return cnt


if __name__ == "__main__":
    import sys
    k = sys.argv[1] if len(sys.argv) > 1 else "test"
    data = open(sys.argv[2], "rb").read() if len(sys.argv) > 2 else b""
    if not data:
        print("usage: python cad_local.py <key> <dwg_or_dxf_path>")
        raise SystemExit(1)
    res = convert_local(k, data)
    print("ok:", res.get("ok"), "png:", res.get("png"),
          res.get("png_w"), "x", res.get("png_h"))
    print("text_count:", res.get("text_count"),
          "proxy_count:", res.get("proxy_count"),
          "tarch_proxy:", res.get("tarch_proxy"))
    print("note:", res.get("note"))
