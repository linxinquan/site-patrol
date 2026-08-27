# -*- coding: utf-8 -*-
"""精确种子 v2：底图渲染 = PDF 物理页面对应 mm（c=0, f=Y_max_print）。
公式: wx = a*px + c, wy = d*py + f
  py=0 -> wy = f = Y_max (CAD 顶端)
  py=H -> wy = d*H + f = Y_min (CAD 底端)
  即 d = (Y_min - Y_max) / H = -Y_range / H
"""
import os, json

PAPER = {
    "dy04_7_D01": (1265.1, 596.9, 150),  # 1:150
    "dy04_7_D03": (843.8, 596.9, 100),   # 1:100
    "dy04_7_D04": (843.8, 596.9, 100),   # 1:100
    # B01: 实测 1:100 + 打印窗口 1120x795mm（PDF 1192x843.8 含边距）
    "dy04_7_B01": (1120.0, 795.0, 100),
}
PX = {
    "dy04_7_D01": (2400, 1133),
    "dy04_7_D03": (2400, 1698),
    "dy04_7_D04": (2400, 1698),
    "dy04_7_B01": (4500, 3186),
}

for key, (W_mm, H_mm, s) in PAPER.items():
    W_px, H_px = PX[key]
    a = W_mm * s / W_px
    d = - H_mm * s / H_px
    c = 0.0  # 底图最左 = CAD X=0
    f = H_mm * s  # 底图最上 = CAD Y_max
    print(f"\n[{key}] PDF {W_mm}x{H_mm}mm 1:{s}  底图 {W_px}x{H_px}px")
    print(f"  a = {a:.6f}, c = {c}")
    print(f"  d = {d:.6f}, f = {f}")
    print(f"  X 范围: [0, {a*W_px:.0f}]mm")
    print(f"  Y 范围: [0, {f:.0f}]mm (底图顶 f 对应 CAD Y_max)")

# 验证：JSON 范围应在底图渲染范围内
print("\n\n验证 JSON 范围是否在底图渲染范围：")
for key in PAPER:
    W_px, H_px = PX[key]
    W_mm, H_mm, s = PAPER[key]
    a = W_mm * s / W_px
    f = H_mm * s
    jsn = os.path.join(r"F:\建筑验收工具\site-patrol\assets\axis_data", f"{key}.json")
    with open(jsn, "r", encoding="utf-8") as fp:
        data = json.load(fp)
    pts = data.get("points", [])
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    x_min, x_max = min(xs), max(xs)
    y_min, y_max = min(ys), max(ys)
    x_in = (x_min >= 0) and (x_max <= a*W_px + 0.5)
    y_in = (y_min >= 0) and (y_max <= f + 0.5)
    print(f"\n  [{key}]")
    print(f"    渲染 X [0, {a*W_px:.0f}]  Y [0, {f:.0f}]")
    print(f"    JSON   X [{x_min:.0f}, {x_max:.0f}]  Y [{y_min:.0f}, {y_max:.0f}]")
    print(f"    JSON in 渲染: X={x_in} Y={y_in}")
