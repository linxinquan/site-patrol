# -*- coding: utf-8 -*-
"""B01: 用新 JSON 验证 scale=66.222, c=19500, f=1430000 的每条线像素位置 vs 暗列/暗行。"""
import json
import numpy as np
from PIL import Image

img = np.asarray(Image.open(r"F:\建筑验收工具\site-patrol\assets\drawings\dy04_7_B01.png").convert("L"), dtype=np.int16)
H_px, W_px = img.shape
ds = 4
sub = img[:H_px//ds*ds, :W_px//ds*ds]
ds_img = sub.reshape(H_px//ds, ds, W_px//ds, ds).min(axis=(1, 3))
ds_H, ds_W = ds_img.shape
dark = ds_img < 128
col_dark = dark.mean(axis=0)
row_dark = dark.mean(axis=1)

def cluster_idxs(idx_list, tol):
    if not idx_list: return []
    idx_list = sorted(idx_list)
    groups = []
    for i in idx_list:
        if groups and i - groups[-1][-1] <= tol:
            groups[-1].append(i)
        else:
            groups.append([i])
    return [sum(g)/len(g) for g in groups]

col_c = cluster_idxs([i for i, v in enumerate(col_dark) if v > 0.5], 2)
row_c = cluster_idxs([i for i, v in enumerate(row_dark) if v > 0.5], 2)
print(f"底图 {W_px}x{H_px}")
print(f"暗列: {[round(c*ds) for c in col_c]}")
print(f"暗行: {[round(c*ds) for c in row_c]}")

with open(r"F:\建筑验收工具\site-patrol\assets\axis_data\dy04_7_B01.json", encoding="utf-8") as f:
    data = json.load(f)
vlines = data["vlines"]
hlines = data["hlines"]

scale = 66.222
c = 19500.0
f = 1430000.0

print("\n竖线投影 (scale=66.222, c=19500):")
for vx in vlines:
    px = (vx - c) / scale
    in_img = 0 <= px < W_px
    near = any(abs(px - p*ds) <= 4 for p in col_c)
    print(f"  X={vx:.0f} -> px={px:.1f} 在底图={in_img} 命中暗列={near}")

print("\n横线投影 (scale=66.222, f=1430000):")
for hy in hlines:
    py = (f - hy) / scale
    in_img = 0 <= py < H_px
    near = any(abs(py - p*ds) <= 4 for p in row_c)
    print(f"  Y={hy:.0f} -> py={py:.1f} 在底图={in_img} 命中暗行={near}")
