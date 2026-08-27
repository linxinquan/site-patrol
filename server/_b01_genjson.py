# -*- coding: utf-8 -*-
"""B01: 用完整 DXF A-Axis 层生成正确轴网交点 JSON（模型空间真实坐标）。"""
import os, sys, logging, json
import ezdxf

logging.disable(logging.CRITICAL)
ezdxf.options.log_unprocessed_tags = False

dxf = r"F:\建筑验收工具\大铲湾DY04_资料\第一轮测试CAD\01_平面图\建施_AW-7-B01_V1.0_地下一层顶板组合平面图.dxf"
doc = ezdxf.readfile(dxf)

# AD-Dote-BF 块被 AD-P-B1D 引用，AD-P-B1D 被 INSERT 在 (0, 1240137.5)
# AD-Dote-BF 在 AD-P-B1D 内 INSERT 在 (0,0) => AD-Dote-BF 局部坐标 + (0, 1240137.5) = 模型坐标
OY = 1240137.5

blk = doc.blocks.get("AD-Dote-BF")
hlines, vlines = [], []
for e in blk.query("LINE"):
    try:
        if not e.dxf.layer.endswith("A-Axis-GRID"):
            # 用 A-Axis-GRID 作为主轴网（更干净），若太少则补充 A-Axis
            continue
        s, t = e.dxf.start, e.dxf.end
        dx, dy = t.x - s.x, t.y - s.y
        if abs(dy) < 1e-6 and abs(dx) > 1e-3:
            hlines.append((s.y, min(s.x, t.x), max(s.x, t.x)))
        elif abs(dx) < 1e-6 and abs(dy) > 1e-3:
            vlines.append((s.x, min(s.y, t.y), max(s.y, t.y)))
    except Exception: pass

def cluster_lines(entries, tol=5):
    entries = sorted(entries, key=lambda c: c[0])
    groups = []
    for c in entries:
        if groups and abs(c[0] - groups[-1][0][0]) <= tol:
            groups[-1].append(c)
        else:
            groups.append([c])
    return [(sum(x[0] for x in g)/len(g), min(x[1] for x in g), max(x[2] for x in g)) for g in groups]

hg = cluster_lines(hlines)
vg = cluster_lines(vlines)
print(f"A-Axis-GRID: 横线 {len(hg)}, 竖线 {len(vg)}")

# 交点
points = []
for hy, hx1, hx2 in hg:
    for vx, vy1, vy2 in vg:
        if (hx1 - 5 <= vx <= hx2 + 5) and (vy1 - 5 <= hy <= vy2 + 5):
            points.append([round(vx, 2), round(hy + OY, 2)])
print(f"交点: {len(points)}")
xs = [p[0] for p in points]
ys = [p[1] for p in points]
print(f"X: [{min(xs):.1f}, {max(xs):.1f}] 跨度 {max(xs)-min(xs):.1f}")
print(f"Y: [{min(ys):.1f}, {max(ys):.1f}] 跨度 {max(ys)-min(ys):.1f}")

# 补充：如果 A-Axis-GRID 太少（9竖29横=261交点够用），则加入 A-Axis 补充更多竖线
# 但 A-Axis-GRID 已经是主轴网，交点够匹配。写 JSON。
data = {
    "key": "dy04_7_B01",
    "points": points,
    "hlines": [round(y + OY, 2) for y, _, _ in hg],
    "vlines": [round(x, 2) for x, _, _ in vg],
    "layer": "AD-Dote-BF$0$A-Axis-GRID",
    "source": "建施_AW-7-B01_V1.0_地下一层顶板组合平面图.dxf",
}
out = r"F:\建筑验收工具\site-patrol\assets\axis_data\dy04_7_B01.json"
with open(out, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False)
print("已写入:", out)

# 验证与底图匹配（scale=66.22 暗列测试）
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

# scale=66.222 搜索 c
scale = 66.222
best_c, best_sc = None, -1
for c in np.arange(-50000, 50000, 500):
    hits = 0
    for vx in sorted(set(xs)):
        px = (vx - c) / scale
        if 0 <= px < ds_W * ds and any(abs(px - p*ds) <= 4 for p in col_c):
            hits += 1
    if hits > best_sc:
        best_sc, best_c = hits, c
print(f"[X] scale=66.222 c={best_c:.0f} 命中 {best_sc}/{len(sorted(set(xs)))}")
best_f, best_fs = None, -1
for f in np.arange(1200000, 1550000, 500):
    hits = 0
    for hy in sorted(set(ys)):
        py = (f - hy) / scale
        if 0 <= py < ds_H * ds and any(abs(py - p*ds) <= 4 for p in row_c):
            hits += 1
    if hits > best_fs:
        best_fs, best_f = hits, f
print(f"[Y] scale=66.222 f={best_f:.0f} 命中 {best_fs}/{len(sorted(set(ys)))}")
