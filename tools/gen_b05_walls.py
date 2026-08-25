"""生成 B05 演示墙线 JSON（与 providers.dart seedDefaultCalibrations 系数一致）。"""
import json
import os

A = 0.3308888888888889
D = -0.3308888888888889
C = -359.3091448275862
F = 852.4496763746746

WALL_SEGMENTS_REL = [
    ((15.0, 25.0), (40.0, 25.0)),
    ((40.0, 25.0), (40.0, 75.0)),
    ((40.0, 75.0), (15.0, 75.0)),
    ((15.0, 75.0), (15.0, 25.0)),
    ((55.0, 15.0), (55.0, 50.0)),
    ((55.0, 50.0), (85.0, 50.0)),
]

def screen_to_world(px, py):
    return (px - C) / A, (py - F) / D

wall_lines = []
for (r1, r2) in WALL_SEGMENTS_REL:
    px1, py1 = r1[0] / 100 * 4500, r1[1] / 100 * 2551
    px2, py2 = r2[0] / 100 * 4500, r2[1] / 100 * 2551
    wx1, wy1 = screen_to_world(px1, py1)
    wx2, wy2 = screen_to_world(px2, py2)
    wall_lines.append({
        "layer": "WALL",
        "pts": [[round(wx1, 1), round(wy1, 1)],
                [round(wx2, 1), round(wy2, 1)]],
    })

out_dir = os.path.join(os.path.dirname(__file__), "..", "assets", "walls")
out_path = os.path.normpath(os.path.join(out_dir, "dy04_7_B05_walls.json"))
os.makedirs(out_dir, exist_ok=True)
with open(out_path, "w", encoding="utf-8") as f:
    json.dump({"key": "dy04_7_B05", "wall_lines": wall_lines}, f,
              ensure_ascii=False, indent=2)

print(f"[gen_b05_walls] wrote {len(wall_lines)} wall segments to {out_path}")