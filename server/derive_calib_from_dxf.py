# -*- coding: utf-8 -*-
"""
从 DXF 推算图纸校准系数（图纸空间视口法）。

原理：
  1. AutoCAD 布局(Layout/PaperSpace) 的「视口(VIEWPORT)」实体同时记录：
       - center: 视口框在图纸空间的中心 (mm)
       - size:   视口框在图纸空间的宽高 (mm)
       - view_center_point: 视口内模型空间的中心 (mm)
       - view_height:       视口内模型空间的视图高度 (mm)
  2. 底图 PNG = 布局页面的渲染，因此：
       - 布局实体 extents (mm)  → 底图像素 (px) 的缩放：
            mm_per_px = extents_w_mm / imgW
       - 视口把「图纸空间坐标」映射到「模型空间坐标」：
            model_x = vcx + (paper_x - pcx) * (model_scale_x)
            model_y = vcy + (paper_y - pcy) * (model_scale_y)
       其中 model_scale_x = 视口内容宽度 / 视口框宽度
             model_scale_y = view_height / vp_height
  3. 组合得到 像素 → 模型坐标(mm) 的仿射，即校准系数。

用法：
  python derive_calib_from_dxf.py <dxf路径> <imgW> <imgH>
  例：python derive_calib_from_dxf.py dwg_cache/D01.dxf 2400 1133

输出：布局信息 + 各视口映射 + 建议校准系数（中心对齐版）。
注意：真实精度需结合「至少一个已知坐标点」验证；若布局含多视口/图框，
extents 与底图渲染范围需人工核对。
"""
import sys
import os
import json

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ROOT)
import ezdxf
from ezdxf import bbox as ezbbox


def paper_extents(doc, layout_name):
    """布局(图纸空间)所有实体包围盒 (mm)。"""
    layout = doc.layouts.get(layout_name)
    try:
        b = ezbbox.extents(layout)
        if b.has_data:
            return {
                "min": [b.extmin.x, b.extmin.y],
                "max": [b.extmax.x, b.extmax.y],
                "w": b.extmax.x - b.extmin.x,
                "h": b.extmax.y - b.extmin.y,
            }
    except Exception as e:
        return {"err": str(e)}
    return None


def layout_page_size(doc, layout_name):
    """布局页面尺寸 (mm)。"""
    try:
        ps = doc.layouts.get(layout_name).page_setup
        sz = ps.get_size() if hasattr(ps, "get_size") else None
        if sz:
            return [float(sz[0]), float(sz[1])]
    except Exception as e:
        return {"err": str(e)}
    return None


def viewports_info(doc, layout_name):
    """解析布局内所有视口。"""
    out = []
    for vp in doc.layouts.get(layout_name).viewports():
        try:
            # 排除 *Active 主视口（无几何）
            if str(vp.dxf.name).startswith("*"):
                continue
            out.append({
                "name": str(vp.dxf.name),
                "center_mm": [float(vp.dxf.center.x), float(vp.dxf.center.y)],
                "size_mm": [float(vp.dxf.width), float(vp.dxf.height)],
                "view_center_model": [
                    float(vp.dxf.view_center_point.x),
                    float(vp.dxf.view_center_point.y),
                ],
                "view_height_model": float(vp.dxf.view_height),
                # 视口内模型→图纸 缩放（mm 模型 / mm 图纸）
                "model_per_paper_x": (float(vp.dxf.view_height) *
                                      (float(vp.dxf.width) / float(vp.dxf.height)) /
                                      float(vp.dxf.width))
                if float(vp.dxf.width) > 0 else None,
                "model_per_paper_y": float(vp.dxf.view_height) /
                                     float(vp.dxf.height)
                if float(vp.dxf.height) > 0 else None,
            })
        except Exception as e:
            out.append({"err": str(e)})
    return out


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        sys.exit(1)
    dxf_path = sys.argv[1]
    imgW = float(sys.argv[2])
    imgH = float(sys.argv[3])
    if not os.path.exists(dxf_path):
        print(f"✗ 文件不存在: {dxf_path}")
        sys.exit(1)

    print(f"读取 DXF: {dxf_path}")
    doc = ezdxf.readfile(dxf_path)
    print(f"布局: {[l.name for l in doc.layouts if not l.name.lower().startswith('model')]}")

    for layout in doc.layouts:
        if layout.name.lower().startswith("model"):
            continue
        print("\n" + "=" * 60)
        print(f"布局: {layout.name}")
        page = layout_page_size(doc, layout.name)
        print(f"  页面尺寸(mm): {page}")
        ext = paper_extents(doc, layout.name)
        print(f"  图纸空间实体 extents(mm): {ext}")
        vps = viewports_info(doc, layout.name)
        print(f"  视口数: {len(vps)}")
        for v in vps:
            print(f"    {v}")
        if ext and isinstance(ext.get("w"), (int, float)) and ext["w"] > 0:
            mm_per_px_x = ext["w"] / imgW
            mm_per_px_y = ext["h"] / imgH
            print(f"\n  ▶ 建议校准（图纸空间整体→像素，中心对齐，需验证）:")
            print(f"    a = {mm_per_px_x:.6f}   (mm/px X)")
            print(f"    d = {-mm_per_px_y:.6f}   (mm/px Y, 像素Y向下)")
            print(f"    c = {-ext['min'][0] - ext['w'] / 2:.1f} + imgW/2*{mm_per_px_x:.6f} "
                  f"(中心对齐估算)")
            print(f"    f = {ext['max'][1] - ext['h'] / 2:.1f} + imgH/2*{-mm_per_px_y:.6f} "
                  f"(中心对齐估算)")
            print(f"\n  注：a/d 由 extents/像素比得到（可靠）；c/f 需至少一个真实坐标点校正。")


if __name__ == "__main__":
    main()
