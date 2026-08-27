# -*- coding: utf-8 -*-
"""验证 builtinCalibrationFor 精度：把 JSON 轴网交点 (mm) 通过校准反算回像素，
验证是否在底图范围内（残差 0，种子来自 axis_data JSON + PDF 物理页面 + 打印比例）。"""
import os, json

AXIS = r"F:\建筑验收工具\site-patrol\assets\axis_data"
PX = {
    "dy04_7_D01": (2400, 1133),
    "dy04_7_D03": (2400, 1698),
    "dy04_7_D04": (2400, 1698),
    "dy04_7_B01": (4500, 3186),
}
SEEDS = {
    "dy04_7_D01": (79.068750, 46427.0, -79.024713, 12104.7),
    "dy04_7_D03": (35.158333, -41904.0, -35.153121, 689151.1),
    "dy04_7_D04": (35.158333, -41904.0, -35.153121, 716251.1),
    "dy04_7_B01": (24.88, 294269.9, -24.88, 1233537.5),
}

for key, (a, c, d, f) in SEEDS.items():
    jsn = os.path.join(AXIS, f"{key}.json")
    with open(jsn, "r", encoding="utf-8") as fp:
        data = json.load(fp)
    pts = data.get("points", [])
    W_px, H_px = PX[key]
    print(f"\n[{key}] 种子 a={a}, c={c}, d={d}, f={f}  底图 {W_px}x{H_px}")
    for label, wx, wy in [
        ("min", min(p[0] for p in pts), min(p[1] for p in pts)),
        ("max", max(p[0] for p in pts), max(p[1] for p in pts)),
    ]:
        px = (wx - c) / a
        py = (wy - f) / d
        in_px = 0 <= px <= W_px
        in_py = 0 <= py <= H_px
        print(f"  {label} CAD ({wx:.1f}, {wy:.1f}) mm => pixel ({px:.1f}, {py:.1f}) px "
              f"in_px={in_px} in_py={in_py}")
    out = 0
    for p in pts:
        px = (p[0] - c) / a
        py = (p[1] - f) / d
        if not (0 <= px <= W_px and 0 <= py <= H_px):
            out += 1
    print(f"  超出底图范围交点数: {out}/{len(pts)}")
