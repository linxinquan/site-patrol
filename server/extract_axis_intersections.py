# -*- coding: utf-8 -*-
"""
从 DXF 提取轴网交点（毫米坐标），供 App 端"轴网套图"自动校准使用。

用法:
    python extract_axis_intersections.py <dxf路径> <输出json路径> [轴网层名]

若省略轴网层名，脚本会按以下优先级自动探测：
    A-AXIS-GRID > AXIS > A-Axis > 名称含"轴"或"axis"或"grid"或"dote" 的层

输出 JSON 结构:
    {
      "points": [[x1, y1], [x2, y2], ...],   # 轴网交点（毫米，CAD Y 向上）
      "hlines": [y1, y2, ...],               # 横向轴线纵坐标
      "vlines": [x1, x2, ...],               # 纵向轴线横坐标
      "layer": "A-AXIS-GRID",
      "source": "<文件名>"
    }

说明:
    - 要求 DXF 是「天正 T3 导出」或原生 CAD 的含完整轴网版本；
      ODA 直转的天正 DWG 会丢失自定义轴网对象（仅剩少量直线），不适用。
    - 交点由横线×竖线求交得到；线按坐标容差聚类（默认 0.5mm）。
"""
import sys
import os
import json

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ezdxf

AXIS_LAYER_PRIORITY = ["A-AXIS-GRID", "AXIS", "A-Axis", "A-AXIS"]
TOL = 0.5  # 聚类容差（mm）


def find_axis_layers(doc):
    """按优先级返回轴网层候选列表。"""
    names = []
    for l in doc.layers:
        try:
            names.append(l.dxf.name)
        except Exception:
            pass
    cands = []
    for pri in AXIS_LAYER_PRIORITY:
        for n in names:
            if n.lower() == pri.lower():
                cands.append(n)
    if not cands:
        for n in names:
            ll = n.lower()
            if any(k in ll for k in ["轴", "axis", "grid", "dote"]):
                cands.append(n)
    # 去重保持顺序
    seen = set()
    out = []
    for c in cands:
        if c not in seen:
            seen.add(c)
            out.append(c)
    return out


def collect_grid_lines(msp, layer):
    """从指定层提取横/竖轴线（聚类后坐标列表）。"""
    hlines = []  # (y, xmin, xmax)
    vlines = []  # (x, ymin, ymax)
    for e in msp.query("LINE"):
        try:
            if e.dxf.layer != layer:
                continue
            s, t = e.dxf.start, e.dxf.end
            dx, dy = t.x - s.x, t.y - s.y
            if abs(dy) < 1e-6 and abs(dx) > 1e-3:
                hlines.append((s.y, min(s.x, t.x), max(s.x, t.x)))
            elif abs(dx) < 1e-6 and abs(dy) > 1e-3:
                vlines.append((s.x, min(s.y, t.y), max(s.y, t.y)))
        except Exception:
            pass
    # 聚类：坐标相近（容差内）合并
    def cluster(coords_getter, is_h):
        coords = sorted(coords_getter())
        groups = []
        for c in coords:
            if groups and abs(c[0] - groups[-1][0][0]) <= TOL:
                groups[-1].append(c)
            else:
                groups.append([c])
        out = []
        for g in groups:
            # 取质心 + 覆盖范围（合并同轴线片段）
            pos = sum(x[0] for x in g) / len(g)
            rng = (min(x[1] for x in g), max(x[2] for x in g))
            out.append((pos, rng[0], rng[1]))
        return out

    hg = cluster(lambda: [(y, x1, x2) for y, x1, x2 in hlines], True)
    vg = cluster(lambda: [(x, y1, y2) for x, y1, y2 in vlines], False)
    return hg, vg


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    dxf_path = sys.argv[1]
    out_path = sys.argv[2]
    layer_override = sys.argv[3] if len(sys.argv) > 3 else None
    if not os.path.exists(dxf_path):
        print("✗ 文件不存在:", dxf_path)
        sys.exit(1)

    print("读取 DXF:", dxf_path)
    doc = ezdxf.readfile(dxf_path)
    msp = doc.modelspace()

    layer = layer_override
    if not layer:
        cands = find_axis_layers(doc)
        if not cands:
            print("✗ 未找到轴网层（请检查是否 T3 导出的 DXF）")
            sys.exit(2)
        layer = cands[0]
        print("自动选择轴网层:", layer)
    else:
        print("使用指定轴网层:", layer)

    hg, vg = collect_grid_lines(msp, layer)
    print("横向轴线数:", len(hg), " 纵向轴线数:", len(vg))
    if len(hg) < 2 or len(vg) < 2:
        print("✗ 轴网不完整（横/竖线 <2），无法求交点。"
              "天正 DWG 请用「整图导出 → T3」得到完整轴网。")
        sys.exit(3)

    # 求交点
    points = []
    for hpos, hx1, hx2 in hg:
        for vpos, vy1, vy2 in vg:
            # 要求竖线在横线覆盖范围内（或横线在竖线覆盖范围内）
            if (hx1 - TOL <= vpos <= hx2 + TOL) and (vy1 - TOL <= hpos <= vy2 + TOL):
                points.append([round(vpos, 3), round(hpos, 3)])
    print("轴网交点数:", len(points))
    if len(points) < 3:
        print("✗ 交点 <3，无法用于仿射拟合。")
        sys.exit(4)

    data = {
        "points": points,
        "hlines": [round(y, 3) for y, _, _ in hg],
        "vlines": [round(x, 3) for x, _, _ in vg],
        "layer": layer,
        "source": os.path.basename(dxf_path),
    }
    os.makedirs(os.path.dirname(os.path.abspath(out_path)) or ".", exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)
    print("已写入:", out_path)


if __name__ == "__main__":
    main()
