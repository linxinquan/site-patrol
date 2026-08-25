# -*- coding: utf-8 -*-
"""
DWG 元数据服务
- 不重转 OCF（保留 OCF 缓存）
- 用 ezdxf 离线解析 DWG 原文件，输出 {key}.json：
    { layers: [{name, on, frozen, color}], layouts: [name], bboxes: {layer: {min,max}} }
- 前端 cad_viewer.html 启动时 GET /api/cad-meta/{key}.json，
  setLayer 强制全开后按 JSON 关掉 on=false 的图层。
- 支持布局切换（AutoCAD 的"模型"+"布局1"等图纸空间）
"""
import os
import sys
import json
import glob
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

# 引入 COS 配置（仅用于元数据备份，不下载 DWG 到本地）
sys.path.insert(0, os.path.dirname(__file__))
try:
    from cos_config import COS_BUCKET, COS_REGION, COS_HOST
except Exception:
    COS_BUCKET = "site-inspection-1322296918"
    COS_REGION = "ap-guangzhou"
    COS_HOST = f"{COS_BUCKET}.cos.{COS_REGION}.myqcloud.com"

ROOT = os.path.dirname(os.path.abspath(__file__))
DWG_CACHE = os.path.join(ROOT, "dwg_cache")
META_DIR = os.path.join(ROOT, "cad_meta")
os.makedirs(DWG_CACHE, exist_ok=True)
os.makedirs(META_DIR, exist_ok=True)

# ---- ezdxf 加载（不可用时给出友好提示）----
try:
    import ezdxf
    from ezdxf import bbox
    HAS_EZDXF = True
except Exception as e:
    HAS_EZDXF = False
    EZDXF_ERR = str(e)


def parse_dwg_to_meta(dwg_path):
    """用 ezdxf 解析 DWG，输出元数据 JSON dict"""
    doc = ezdxf.readfile(dwg_path)
    msp = doc.modelspace()

    # 1) 图层
    layers = []
    for ly in doc.layers:
        layers.append({
            "name": ly.dxf.name,
            "on": ly.is_on(),
            "frozen": ly.is_frozen(),
            "off": ly.is_off(),
            "color": int(ly.dxf.color) if ly.dxf.hasattr("color") else 7,
        })

    # 2) 布局
    layouts = [l.name for l in doc.layouts]

    # 3) 模型空间 bbox（按图层聚合，便于前端按图层显示范围）
    try:
        b = bbox.BoundingBox()
        for e in msp:
            try:
                b.extend([e.dxf.start, e.dxf.end])
            except Exception:
                pass
        model_bbox = {
            "min": [b.extmin.x, b.extmin.y, b.extmin.z],
            "max": [b.extmax.x, b.extmax.y, b.extmax.z],
        } if b.has_data else None
    except Exception:
        model_bbox = None

    # 4) 实体统计
    ent_types = {}
    for e in msp:
        t = e.dxftype()
        ent_types[t] = ent_types.get(t, 0) + 1

    # 5) 墙线段（P1-1）：遍历 LINE + LWPOLYLINE，过滤 WALL/墙 图层、排除 COL/柱。
    #    输出世界坐标 mm，前端用 worldToScreen 映射到相对坐标 0-100 后做穿墙检测。
    wall_lines = []
    for ent in msp.query('LINE LWPOLYLINE'):
        try:
            layer_name = ent.dxf.layer if ent.dxf.hasattr('layer') else ''
            name_upper = layer_name.upper()
            if 'COL' in name_upper:
                continue  # 柱不是墙
            if 'WALL' not in name_upper and '墙' not in layer_name:
                continue  # 只取墙图层
            t = ent.dxftype()
            pts = []
            if t == 'LINE':
                pts = [[float(ent.dxf.start.x), float(ent.dxf.start.y)],
                       [float(ent.dxf.end.x),   float(ent.dxf.end.y)]]
            else:  # LWPOLYLINE
                verts = list(ent.get_points('xyseb'))
                if not verts:
                    continue
                for (x, y, *_rest) in verts:
                    pts.append([float(x), float(y)])
                # 闭合多段线去重（最后一点 == 第一点）
                if len(pts) >= 2 and abs(pts[0][0] - pts[-1][0]) < 1e-3 \
                        and abs(pts[0][1] - pts[-1][1]) < 1e-3:
                    pts = pts[:-1]
                if len(pts) < 2:
                    continue
            wall_lines.append({
                "layer": layer_name,
                "pts": pts,
            })
        except Exception:
            continue

    return {
        "ok": True,
        "source": os.path.basename(dwg_path),
        "layers": layers,
        "layouts": layouts,
        "bbox": model_bbox,
        "ent_types": ent_types,
        "layer_count": len(layers),
        "on_count": sum(1 for l in layers if l["on"]),
        "frozen_count": sum(1 for l in layers if l["frozen"]),
        "wall_lines": wall_lines,
        "wall_seg_count": sum(max(0, len(w["pts"]) - 1) for w in wall_lines),
    }


def meta_path_for(key):
    return os.path.join(META_DIR, key + ".json")


class Handler(BaseHTTPRequestHandler):
    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "*")

    def _json(self, payload, status=200):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        sys.stderr.write("[cad_meta] " + (fmt % args) + "\n")

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self):
        url = urlparse(self.path)
        path = url.path

        # 健康检查
        if path == "/health":
            return self._json({
                "ok": True,
                "has_ezdxf": HAS_EZDXF,
                "ezdxf_err": EZDXF_ERR if not HAS_EZDXF else None,
                "dwg_cache_count": len(glob.glob(os.path.join(DWG_CACHE, "*.dwg"))),
                "meta_count": len(glob.glob(os.path.join(META_DIR, "*.json"))),
            })

        # 元数据接口：GET /api/cad-meta/{key}.json
        if path.startswith("/api/cad-meta/"):
            key = path[len("/api/cad-meta/"):].rstrip(".json")
            mp = meta_path_for(key)
            if not os.path.exists(mp):
                return self._json({"ok": False, "err": f"未找到 {key} 的元数据。先运行 cad_meta_build.py 构建。"}, status=404)
            with open(mp, "rb") as f:
                data = f.read()
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self._cors()
            self.end_headers()
            self.wfile.write(data)
            return

        # 列已构建元数据
        if path == "/api/cad-meta-list":
            files = []
            for f in glob.glob(os.path.join(META_DIR, "*.json")):
                base = os.path.basename(f).rstrip(".json")
                try:
                    with open(f, "r", encoding="utf-8") as fp:
                        d = json.load(fp)
                    files.append({
                        "key": base,
                        "layers": d.get("layer_count"),
                        "on": d.get("on_count"),
                        "frozen": d.get("frozen_count"),
                        "layouts": d.get("layouts"),
                    })
                except Exception:
                    pass
            return self._json({"ok": True, "items": files})

        self._json({"ok": False, "err": "not found"}, status=404)

    def do_POST(self):
        # 触发构建：POST /api/cad-meta-build/{key}
        url = urlparse(self.path)
        path = url.path
        if path.startswith("/api/cad-meta-build/"):
            key = path[len("/api/cad-meta-build/"):]
            dwg = os.path.join(DWG_CACHE, key + ".dwg")
            if not os.path.exists(dwg):
                return self._json({"ok": False, "err": f"dwg_cache/{key}.dwg 不存在"}, status=404)
            if not HAS_EZDXF:
                return self._json({"ok": False, "err": f"ezdxf 未安装: {EZDXF_ERR}"}, status=500)
            try:
                meta = parse_dwg_to_meta(dwg)
                out = meta_path_for(key)
                with open(out, "w", encoding="utf-8") as f:
                    json.dump(meta, f, ensure_ascii=False, indent=2)
                return self._json({"ok": True, "out": out, "layers": meta["layer_count"]})
            except Exception as e:
                return self._json({"ok": False, "err": str(e)}, status=500)
        self._json({"ok": False, "err": "not found"}, status=404)


def main():
    port = int(os.environ.get("CAD_META_PORT", "8810"))
    if not HAS_EZDXF:
        print(f"[cad_meta] ⚠ ezdxf 未安装: {EZDXF_ERR}")
        print(f"[cad_meta] 安装: pip install ezdxf")
    print(f"[cad_meta] 启动端口 {port}")
    print(f"[cad_meta] DWG 缓存目录: {DWG_CACHE}")
    print(f"[cad_meta] 元数据输出:  {META_DIR}")
    print(f"[cad_meta] COS 桶:      {COS_BUCKET}")
    HTTPServer(("0.0.0.0", port), Handler).serve_forever()


if __name__ == "__main__":
    main()