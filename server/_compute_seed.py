# -*- coding: utf-8 -*-
"""基于 PDF 物理页面 + 打印比例 + axis_data JSON 计算精确种子。
公式: wx = a*px + c, wy = d*py + f
  X_min = c, X_max = a*W_px + c
  Y_min = f, Y_max = f + |d|*H_px
  PDF paper W_mm, H_mm 对应 a*W_px, |d|*H_px"""
import os, json

# PDF 物理页 + 打印比例（实测或标题栏读取）
PAPER = {
    "dy04_7_D01": ("1265.1 x 596.9 mm", 1265.1, 596.9, 150),  # 1:150
    "dy04_7_D03": ("843.8 x 596.9 mm", 843.8, 596.9, 100),    # 1:100
    "dy04_7_D04": ("843.8 x 596.9 mm", 843.8, 596.9, 100),    # 1:100
    "dy04_7_B01": ("1192.0 x 843.8 mm", 1192.0, 843.8, 100),  # 1:100
    "dy04_7_B05": ("1489.1 x 843.8 mm", 1489.1, 843.8, None),  # B05 已知校准
}

# 底图像素
PX = {
    "dy04_7_D01": (2400, 1133),
    "dy04_7_D03": (2400, 1698),
    "dy04_7_D04": (2400, 1698),
    "dy04_7_B01": (4500, 3186),
    "dy04_7_B05": (4500, 2551),
}

# axis_data JSON 范围（mm）
AXIS_JSON = r"F:\建筑验收工具\site-patrol\assets\axis_data"

print("=" * 70)
print("精确校准种子（基于 PDF 物理页面 + 打印比例 + 轴网 JSON）")
print("=" * 70)

for key, (paper_str, paper_w, paper_h, s) in PAPER.items():
    if s is None:
        continue
    W_px, H_px = PX[key]
    a = paper_w * s / W_px
    d = - paper_h * s / H_px
    # 读 JSON 范围
    jsn = os.path.join(AXIS_JSON, f"{key}.json")
    with open(jsn, "r", encoding="utf-8") as f:
        data = json.load(f)
    pts = data.get("points", [])
    if not pts:
        continue
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    x_min, x_max = min(xs), max(xs)
    y_min, y_max = min(ys), max(ys)
    # c = X_min, f = Y_min（设底图最左 = X_min, 最上 = Y_min）
    c = x_min
    f = y_min
    print(f"\n[{key}] {paper_str} 1:{s} 底图 {W_px}x{H_px}px")
    print(f"  JSON 范围: X=[{x_min:.1f}, {x_max:.1f}]  Y=[{y_min:.1f}, {y_max:.1f}]")
    print(f"  计算 a = {a:.6f} mm/px ({paper_w}*{s}/{W_px})")
    print(f"  计算 d = {d:.6f} mm/px (像素Y向下)")
    print(f"  *** 种子: a={a:.6f}, c={c:.2f}, d={d:.6f}, f={f:.2f}")
    print(f"  验证: X 渲染范围 [{c:.0f}, {a*W_px + c:.0f}] = 跨度 {a*W_px:.0f}mm")
    print(f"        Y 渲染范围 [{f:.0f}, {abs(d)*H_px + f:.0f}] = 跨度 {abs(d)*H_px:.0f}mm")
