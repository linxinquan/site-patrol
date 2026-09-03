# -*- coding: utf-8 -*-
"""
本地 DWG 转换链路（零配额，替代浩辰 dwgToOcf/getDwgInfo）：

    DWG ──ODA File Converter(免费)──► DXF ──ezdxf──► 图层/布局 JSON + PNG 底图

产物落 server/ocf_cache/{key}_meta.json 与 {key}.png，
前端沿用既有 /api/ocf/{key}.png 与 /api/ocf-meta/{key} 分发，协议零改动。
"""
import json
import os
import shutil
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
DWG_CACHE = os.path.join(HERE, "dwg_cache")
OCF_DIR = os.path.join(HERE, "ocf_cache")
WORK = os.path.join(HERE, "_local_work")
OUT = os.path.join(HERE, "_local_out")

# 本机安装的 ODA File Converter（免费，无限次）
ODA_BIN = r"C:\Program Files\ODA\ODAFileConverter 27.1.0\ODAFileConverter.exe"


def oda_available() -> bool:
    return os.path.exists(ODA_BIN)


def _dxf_deps_ok() -> bool:
    try:
        import ezdxf  # noqa: F401
        from ezdxf.addons.drawing.matplotlib import MatplotlibBackend  # noqa: F401
        return True
    except Exception:
        return False


def local_available() -> bool:
    return oda_available() and _dxf_deps_ok()


def sanitize_key(name: str) -> str:
    """文件名 → 安全 key（仅字母数字/_-）。"""
    base = os.path.splitext(os.path.basename(name))[0]
    keep = "".join(c if (c.isalnum() or c in "_-") else "_" for c in base)
    return keep or "dwg"


def convert_local(key: str, dwg_bytes: bytes, dpi: int = 160) -> dict:
    """DWG 字节 → ocf_cache/{key}_meta.json + {key}.png。返回信息 dict。

    步骤：落盘 dwg_cache → ODA 转 DXF → ezdxf 提取图层/布局 → 渲染 PNG 底图。
    任一步失败抛 RuntimeError（消息给前端可读展示）。
    """
    os.makedirs(DWG_CACHE, exist_ok=True)
    os.makedirs(WORK, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(OCF_DIR, exist_ok=True)

    # 0) 落盘源文件（留档 dwg_cache）
    src = os.path.join(DWG_CACHE, f"{key}.dwg")
    with open(src, "wb") as f:
        f.write(dwg_bytes)

    # 1) ODA: DWG -> DXF（单文件工作目录，避免连带转换其它图）
    probe = os.path.join(WORK, f"{key}.dwg")
    shutil.copyfile(src, probe)
    out_dxf = os.path.join(OUT, f"{key}.dxf")
    if os.path.exists(out_dxf):
        os.remove(out_dxf)
    try:
        proc = subprocess.run(
            [ODA_BIN, WORK, OUT, "ACAD2018", "DXF", "0", "1"],
            capture_output=True, text=True, timeout=900,
        )
    finally:
        try:
            os.remove(probe)
        except OSError:
            pass
    if not (os.path.exists(out_dxf) and os.path.getsize(out_dxf) > 0):
        raise RuntimeError(
            "ODA 转换失败(exit=%s)，请确认文件为有效 DWG。%s"
            % (proc.returncode, (proc.stderr or proc.stdout or "")[:200])
        )
    dxf_path = os.path.join(DWG_CACHE, f"{key}.dxf")
    shutil.copyfile(out_dxf, dxf_path)

    # 2) ezdxf: 图层/布局元数据（复用 cad_meta_server 的解析，等价 getDwgInfo 免费版）
    from cad_meta_server import parse_dwg_to_meta
    meta = parse_dwg_to_meta(dxf_path)
    meta_path = os.path.join(OCF_DIR, f"{key}_meta.json")
    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False)

    # 3) ezdxf drawing: 渲染 PNG 底图（自动选实体最多布局），并取像素尺寸与 CAD 范围
    png_path = os.path.join(OCF_DIR, f"{key}.png")
    png_w, png_h, bounds = _render_png(dxf_path, png_path, dpi=dpi)

    layers = meta.get("layers", []) or []
    layouts = meta.get("layouts", []) or []
    return {
        "key": key,
        "dxf": dxf_path,
        "meta": meta_path,
        "png": png_path,
        "layers_count": len(layers) if isinstance(layers, list) else 0,
        "layouts": [
            l.get("name") if isinstance(l, dict) else str(l) for l in layouts
        ] if isinstance(layouts, list) else [],
        "size_mb": round(os.path.getsize(png_path) / 1048576, 2),
        "png_w": png_w,
        "png_h": png_h,
        "bounds": bounds,
    }


def _render_png(dxf_path: str, png_path: str, dpi: int = 160) -> tuple:
    """渲染 PNG，返回 (宽px, 高px, [xmin,ymin,xmax,ymax] CAD 单位范围)。"""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import ezdxf
    from ezdxf.addons.drawing import RenderContext, Frontend
    from ezdxf.addons.drawing.matplotlib import MatplotlibBackend

    doc = ezdxf.readfile(dxf_path)
    # 选实体最多的布局渲染：很多施工图内容在命名布局（如“7栋组合图”），modelspace 反而接近空。
    target = doc.modelspace()
    best_count = len(target)
    for name in doc.layouts.names():
        if name == "Model":
            continue
        try:
            lay = doc.layouts.get(name)
            cnt = len(lay)
            if cnt > best_count:
                target, best_count = lay, cnt
        except Exception:
            continue
    fig = plt.figure()
    ax = fig.add_axes([0, 0, 1, 1])
    ctx = RenderContext(doc)
    backend = MatplotlibBackend(ax)
    Frontend(ctx, backend).draw_layout(target, finalize=True)
    x0, x1 = ax.get_xlim()
    y0, y1 = ax.get_ylim()
    fig.savefig(png_path, dpi=dpi, facecolor="#FFFFFF")
    w_px = int(round(fig.get_size_inches()[0] * dpi))
    h_px = int(round(fig.get_size_inches()[1] * dpi))
    plt.close(fig)
    # 额外输出 SVG（保留文字/标注/复杂线型/填充；浏览器矢量渲染）
    svg_path = os.path.splitext(png_path)[0] + ".svg"
    _render_svg(dxf_path, svg_path)
    return w_px, h_px, [float(x0), float(y0), float(x1), float(y1)]


def _render_svg(dxf_path: str, svg_path: str) -> None:
    """SVG 输出：保留文字/标注/线型/填充（matplotlib 仅几何，矢量更全）。"""
    import ezdxf
    from ezdxf.addons.drawing import RenderContext, Frontend
    from ezdxf.addons.drawing.svg import SVGBackend
    from ezdxf.addons.drawing.layout import Page, Settings

    doc = ezdxf.readfile(dxf_path)
    target = doc.modelspace()
    best = len(target)
    for name in doc.layouts.names():
        if name == "Model":
            continue
        try:
            lay = doc.layouts.get(name)
            cnt = len(lay)
            if cnt > best:
                target, best = lay, cnt
        except Exception:
            continue
    ctx = RenderContext(doc)
    # 仅渲染有实体的图层（CAD 图常含大量空/装饰图层，剔除后 SVG 大小与渲染开销大幅下降）
    used_layers = set()
    for e in target:
        layer = getattr(e.dxf, "layer", None)
        if layer:
            used_layers.add(layer)
    ctx.layers = used_layers
    backend = SVGBackend()
    Frontend(ctx, backend).draw_layout(target, finalize=True)
    # A4 横向 297×210mm
    page = Page(297, 210)
    settings = Settings()
    svg_str = backend.get_string(page, settings=settings)
    with open(svg_path, "w", encoding="utf-8") as f:
        f.write(svg_str)
