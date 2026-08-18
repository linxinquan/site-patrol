#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
浩辰云图 CAD 接入 · Web 服务端（Python，替代 Node 版本）

============================================================
核心省次策略（接入命脉）：
  1) 每张 DWG 只调一次浩辰 dwgToOcf —— 消耗 1 次「按次套餐」
  2) 转换成功后立即把 OCF 二进制下载到本地 ocf_cache 缓存
  3) 前端永远从本服务拉 OCF 渲染（gstarSDK 本地渲染不计次）
=> 同一张图：转换 1 次，巡场/拍照/复看 N 次，只花 1 次
============================================================

已验证的调用方式（对齐 batch_convert.py）：
  - dwgToOcf / getDwgInfo  : POST + JSON body（2dviewer 网关 + AppCode）
  - getTaskStatus          : POST + query 参数（gstarcadsdk 网关 + AK/SK 签名）
  - getDwgInfo / getTaskStatus 不扣次，可安全调用

运行：
  python ocf_server.py [port]     # 默认 8800
  curl http://localhost:8800/api/cad/health
"""
import os
import sys
import json
import time
import zlib
import base64
import urllib.parse
import urllib.request
import urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

# 配置（config.py 或环境变量；config.py 被 gitignore 排除，缺失时用环境变量+默认值兜底）
try:
    import config as C
except ImportError:
    class C:
        API_GATEWAY = os.environ.get("GCAD_API_GATEWAY", "https://2dviewer.apistore.huaweicloud.com")
        APP_CODE = os.environ.get("GCAD_APP_CODE", "")
        APP_TOKEN = os.environ.get("GCAD_API_TOKEN", "")
        APP_KEY = os.environ.get("GCAD_APP_KEY", "")
        APP_SECRET = os.environ.get("GCAD_APP_SECRET", "")
        OCF_DIR = os.environ.get("GCAD_OCF_DIR", os.path.join(HERE, "ocf_cache"))
        POLL_INTERVAL = float(os.environ.get("GCAD_POLL_INTERVAL", "2"))
        POLL_TIMEOUT = float(os.environ.get("GCAD_POLL_TIMEOUT", "180"))
        PORT = int(os.environ.get("CAD_SERVER_PORT", "8800"))
        QWEATHER_KEY = os.environ.get("QWEATHER_KEY", "")
        QWEATHER_HOST = os.environ.get("QWEATHER_HOST", "")

# 华为云 APIG APP 认证签名 SDK（AK/SK 签名）
from apig_sdk import signer

# 配额防误触守卫
import quota_guard as _qg

API_GATEWAY = C.API_GATEWAY
APP_CODE = C.APP_CODE
APP_TOKEN = C.APP_TOKEN
APP_KEY = C.APP_KEY
APP_SECRET = C.APP_SECRET
OCF_DIR = C.OCF_DIR
POLL_INTERVAL = C.POLL_INTERVAL
POLL_TIMEOUT = C.POLL_TIMEOUT

# getTaskStatus 固定走 gstarcadsdk 网关（已验证）
TASK_STATUS_GATEWAY = "https://gstarcadsdk.apistore.huaweicloud.com"

os.makedirs(OCF_DIR, exist_ok=True)


def log(*a):
    print("[ocf_server]", *a, flush=True)


def _valid(v):
    return bool(v) and "YOUR_" not in v


def is_configured():
    return _valid(APP_CODE) or _valid(APP_TOKEN) or (_valid(APP_KEY) and _valid(APP_SECRET))


def auth_headers():
    """基础头：Content-Type + AppCode / Bearer（AK/SK 签名在 _signed_request 处理）。"""
    h = {"Content-Type": "application/json"}
    if _valid(APP_CODE):
        h["X-Apig-AppCode"] = APP_CODE
    if _valid(APP_TOKEN):
        h["Authorization"] = f"Bearer {APP_TOKEN}"
    return h


def _signed_request(url, body_bytes, method="POST"):
    """构造并签名请求。若配置了 AK/SK 则走华为云签名，否则用 AppCode 头。"""
    headers = auth_headers()
    body_str = body_bytes.decode("utf-8") if isinstance(body_bytes, bytes) else (body_bytes or "")
    if _valid(APP_KEY) and _valid(APP_SECRET):
        req = signer.HttpRequest(method, url, headers, body_str)
        sig = signer.Signer()
        sig.Key = APP_KEY
        sig.Secret = APP_SECRET
        sig.Sign(req)
        data = body_str.encode("utf-8") if body_str else None
        return urllib.request.Request(url, data=data, headers=req.headers, method=method)
    data = body_str.encode("utf-8") if body_str else None
    return urllib.request.Request(url, data=data, headers=headers, method=method)


def _guard(path):
    """扣次接口防误触：扣次且未显式允许则抛错。"""
    if _qg.API_CHARGE.get(path, False) and os.environ.get("GCAD_ALLOW_CHARGE", "") != "1":
        desc = _qg.API_DESC.get(path, "")
        raise RuntimeError(f"【配额防误触】{path} 是扣次接口（{desc}）。需设置环境变量 GCAD_ALLOW_CHARGE=1 确认消耗配额。")


def gcad_post(path, payload, timeout=120):
    """POST JSON body 调 2dviewer 网关。扣次接口受 guard 保护。"""
    _guard(path)
    url = API_GATEWAY + path
    body = json.dumps(payload).encode("utf-8")
    req = _signed_request(url, body)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        try:
            detail = e.read().decode("utf-8", errors="replace")
        except Exception:
            detail = ""
        if e.code == 413:
            raise RuntimeError("HTTP 413：APIG 网关 body 限制，建议改用 fileUrl 方式或 zlib 压缩")
        if e.code in (401, 403):
            raise RuntimeError(f"HTTP {e.code} {e.reason}：鉴权/权限问题。{detail[:400]}")
        raise RuntimeError(f"HTTP {e.code} {e.reason}：{detail[:400]}")


def gcad_get_task(request_id, timeout=30):
    """查询任务结果。getTaskStatus 在 gstarcadsdk 网关，requestId 是 query 参数。不扣次。"""
    url = TASK_STATUS_GATEWAY + "/openapi/v1/getTaskStatus?requestId=" + urllib.parse.quote(request_id)
    req = _signed_request(url, b"")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))


def download(url, dest):
    req = urllib.request.Request(url, headers={})
    with urllib.request.urlopen(req, timeout=90) as r, open(dest, "wb") as f:
        f.write(r.read())


def poll_until_done(request_id, ocf_key=None):
    """轮询 getTaskStatus 直到完成。返回 bizData；若指定 ocf_key 则下载 OCF。"""
    waited = 0.0
    while waited < POLL_TIMEOUT:
        time.sleep(POLL_INTERVAL)
        waited += POLL_INTERVAL
        t = gcad_get_task(request_id)
        biz = t.get("bizData", {})
        st = biz.get("status")
        if st == 2:
            if biz.get("resultCode", 1) != 0:
                raise RuntimeError(f"任务失败: {biz.get('resultMsg')}")
            if ocf_key and biz.get("ocfUrl"):
                dest = os.path.join(OCF_DIR, f"{ocf_key}.ocf")
                download(biz["ocfUrl"], dest)
                biz["_ocfPath"] = dest
            return biz
        if st in (0, 1):
            continue
        raise RuntimeError(f"任务异常: {t}")
    raise TimeoutError("任务轮询超时")


def convert_dwg_to_ocf(key, dwg_url=None, file_base64=None, file_name="drawing.dwg"):
    """提交 dwgToOcf 并轮询，返回 (ocf_path, layouts)。扣次。"""
    payload = {"fileName": file_name}
    if dwg_url:
        payload["fileUrl"] = dwg_url
    elif file_base64:
        payload["fileBase64"] = file_base64
    else:
        raise ValueError("需提供 dwg_url 或 file_base64")
    r = gcad_post("/openapi/v1/dwgToOcf", payload)
    if r.get("rtnCode") != "0000000":
        raise RuntimeError(f"提交转换失败: {r}")
    request_id = r["bizData"]["requestId"]
    biz = poll_until_done(request_id, ocf_key=key)
    return biz["_ocfPath"], biz.get("layouts", [])


def submit_dwg_info(file_name, dwg_url=None, file_base64=None):
    """getDwgInfo 仅提交，返回 requestId。不扣次。"""
    payload = {"fileName": file_name}
    if dwg_url:
        payload["fileUrl"] = dwg_url
    elif file_base64:
        payload["fileBase64"] = file_base64
    else:
        raise ValueError("需提供 dwg_url 或 file_base64")
    r = gcad_post("/openapi/v1/getDwgInfo", payload)
    if r.get("rtnCode") != "0000000":
        raise RuntimeError(f"getDwgInfo 提交失败: {r}")
    return r["bizData"]["requestId"]


def save_ocf_as_image(key, ocf_path=None, ocf_base64=None, ocf_url=None,
                      image_width=None, image_height=None, layout=None,
                      layerfilter=None, pt=None):
    """OCF 另存为 PNG 图片，下载到本地 ocf_cache 对应图片。扣次。
    返回本地 PNG 路径。
    """
    if ocf_base64 is None:
        if ocf_path and os.path.exists(ocf_path):
            with open(ocf_path, "rb") as f:
                raw = f.read()
            # zlib 压缩规避 APIG ~12MB body 限制（浩辰 API 支持压缩 base64）
            compressed = zlib.compress(raw, level=6)
            ocf_base64 = base64.b64encode(compressed).decode("ascii")
        elif ocf_url is None:
            raise ValueError("需提供 ocf_base64 / ocf_path / ocf_url 之一")
    payload = {"fileName": f"{key}.ocf"}
    if ocf_url:
        payload["fileUrl"] = ocf_url
    else:
        payload["fileBase64"] = ocf_base64
    if image_width:
        payload["imageWidth"] = int(image_width)
    if image_height:
        payload["imageHeight"] = int(image_height)
    if layout:
        payload["layoutname"] = layout
    if layerfilter:
        payload["layerfilter"] = layerfilter
    if pt:
        payload["pt1x"], payload["pt1y"], payload["pt2x"], payload["pt2y"] = pt
    r = gcad_post("/openapi/v1/ocfSaveAsImage", payload)
    if r.get("rtnCode") != "0000000":
        raise RuntimeError(f"ocfSaveAsImage 提交失败: {r}")
    request_id = r["bizData"]["requestId"]
    biz = poll_until_done(request_id)
    img_url = biz.get("imgUrl")
    if not img_url:
        raise RuntimeError(f"未返回 imgUrl: {biz}")
    dest = os.path.join(OCF_DIR, f"{key}.png")
    download(img_url, dest)
    return dest


# ----------------------------- HTTP 路由 -----------------------------
class Handler(BaseHTTPRequestHandler):
    def _send_json(self, code, obj):
        data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _send_file(self, path):
        with open(path, "rb") as f:
            data = f.read()
        ctype = "application/octet-stream"
        if path.endswith(".png"):
            ctype = "image/png"
        elif path.endswith(".ocf"):
            ctype = "application/octet-stream"
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    # ------------------------------------------------------------------
    # 和风天气（QWeather）免费 API 代理
    # ------------------------------------------------------------------
    def _handle_weather(self):
        """GET /api/weather?lon=&lat=&name=

        调和风天气（开发订阅，免费 1000 次/天）：
          - 当前天气 + 逐小时 2 天 + AQI 空气质量
        未配置 QWEATHER_KEY 时返回 mock（保证前端可渲染）。
        """
        import urllib.parse as _up
        qs = _up.parse_qs(_up.urlparse(self.path).query)
        lon = (qs.get("lon") or [""])[0].strip()
        lat = (qs.get("lat") or [""])[0].strip()
        name = (qs.get("name") or [""])[0].strip()

        if not lon or not lat:
            # 默认深圳大铲湾（7栋）坐标
            lon, lat = "113.9799", "22.5936"

        key = C.QWEATHER_KEY.strip()
        if not key:
            # 未配置 key -> mock 数据
            self._send_json(200, {
                "source": "mock",
                "name": name or "深圳",
                "temp": "32",
                "text": "多云",
                "humidity": "58",
                "windDir": "东南风",
                "windScale": "3级",
                "aqi": 52,
                "category": "良",
                "updateTime": time.strftime("%Y-%m-%d %H:%M"),
                "hint": "未配置 QWEATHER_KEY，返回 mock 天气",
            })
            return

        try:
            data = self._fetch_qweather(lon, lat)
            self._send_json(200, data)
        except Exception as e:
            self._send_json(502, {"source": "error", "msg": str(e)})

    def _fetch_qweather(self, lon, lat):
        """真实调和风天气 V7 + AirQuality V1 API，返回前端友好的扁平结构。

        使用开发者专属 API Host（QWEATHER_HOST，如 xxx.qweatherapi.com）；
        未配置时回退公共域名 devapi.qweather.com。
        """
        key = C.QWEATHER_KEY.strip()
        host = C.QWEATHER_HOST.strip() or "devapi.qweather.com"
        if not host.startswith("http"):
            host = f"https://{host}"

        def _get(url):
            req = urllib.request.Request(url, headers={
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                              "AppleWebKit/537.36 Chrome/120 Safari/537.36",
                "Accept-Encoding": "gzip, deflate",
                "Accept": "application/json",
            })
            with urllib.request.urlopen(req, timeout=8) as resp:
                raw = resp.read()
                if resp.headers.get("Content-Encoding") == "gzip":
                    import gzip
                    raw = gzip.decompress(raw)
                return json.loads(raw.decode("utf-8"))

        # 1) 实时天气 v7
        now_url = f"{host}/v7/weather/now?location={lon},{lat}&key={key}"
        now = _get(now_url)
        if now.get("code") != "200":
            raise RuntimeError(f"和风天气 now 接口错误: {now.get('code')}")
        n = now.get("now", {})
        fx = now.get("fxLink", "")

        # 2) 空气质量 v1（path 参数：lat/lon 各 2 位小数）
        try:
            lat2 = f"{float(lat):.2f}"
            lon2 = f"{float(lon):.2f}"
            aqi_url = f"{host}/airquality/v1/current/{lat2}/{lon2}?key={key}"
            aq = _get(aqi_url)
            aqi_val = aqi_val_disp = aqi_cat = None
            for idx in aq.get("indexes", []):
                if idx.get("code") == "cn-mee":  # 中国国标 AQI
                    aqi_val = idx.get("aqi")
                    aqi_val_disp = idx.get("aqiDisplay")
                    aqi_cat = idx.get("category")
                    break
            if aqi_cat is None and aq.get("indexes"):
                aqi_val = aq["indexes"][0].get("aqi")
                aqi_val_disp = aq["indexes"][0].get("aqiDisplay")
                aqi_cat = aq["indexes"][0].get("category")
        except Exception:
            aqi_val = aqi_val_disp = aqi_cat = None

        # 3) 天气预警 v1（简易取所有 active 预警标题）
        try:
            warn_url = f"{host}/v1/warning/now?location={lon},{lat}&key={key}"
            wr = _get(warn_url)
            warnings = []
            for w in wr.get("warning", []) or []:
                warnings.append({
                    "type": w.get("typeName"),
                    "level": w.get("level"),
                    "title": w.get("title"),
                    "text": w.get("text"),
                })
        except Exception:
            warnings = []

        return {
            "source": "qweather",
            "name": "",
            "temp": n.get("temp"),
            "text": n.get("text"),
            "feelsLike": n.get("feelsLike"),
            "humidity": n.get("humidity"),
            "windDir": n.get("windDir"),
            "windScale": n.get("windScale"),
            "windSpeed": n.get("windSpeed"),
            "precip": n.get("precip"),
            "pressure": n.get("pressure"),
            "vis": n.get("vis"),
            "aqi": aqi_val_disp or aqi_val,
            "category": aqi_cat,
            "warnings": warnings,
            "fxLink": fx,
            "updateTime": n.get("obsTime", ""),
        }
        n = int(self.headers.get("Content-Length", 0))
        if not n:
            return {}
        return json.loads(self.rfile.read(n).decode("utf-8"))

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.end_headers()

    # ---- GET ----
    def do_GET(self):
        path = self.path.split("?")[0]
        if path.startswith("/api/ocf/"):
            key = path.split("/api/ocf/", 1)[1]
            # 支持 .png（图片）与 .ocf（矢量）分发
            if key.endswith(".png"):
                p = os.path.join(OCF_DIR, key)
                if os.path.exists(p):
                    self._send_file(p)
                else:
                    self._send_json(404, {"error": "PNG_NOT_FOUND", "key": key,
                                          "hint": "先调 POST /api/cad/saveAsImage 生成"})
                return
            p = os.path.join(OCF_DIR, f"{key}.ocf")
            if os.path.exists(p):
                self._send_file(p)
            else:
                self._send_json(404, {"error": "OCF_NOT_FOUND", "key": key,
                                      "hint": "先调 POST /api/cad/dwgToOcf 生成，或放置到 ocf_cache/<key>.ocf"})
            return
        if path.startswith("/api/ocf-meta/"):
            key = path.split("/api/ocf-meta/", 1)[1]
            meta_path = os.path.join(OCF_DIR, f"{key}_meta.json")
            if os.path.exists(meta_path):
                try:
                    with open(meta_path, "r", encoding="utf-8") as f:
                        biz = json.load(f)
                    # 只返回 layers 和 deflayout（避免传输 layout 列表过大）
                    self._send_json(200, {
                        "deflayout": biz.get("deflayout"),
                        "layouts": biz.get("layouts", []),
                        "layers": biz.get("layers", []),
                    })
                except Exception as e:
                    self._send_json(500, {"error": "META_READ_FAIL", "msg": str(e)})
            else:
                self._send_json(404, {"error": "META_NOT_FOUND", "key": key,
                                      "hint": "先调 POST /api/cad/getDwgInfo 生成元数据"})
            return
        if path in ("/", "/health", "/api/cad/health"):
            self._send_json(200, {"status": "ok", "ocf_dir": OCF_DIR,
                                  "configured": is_configured(),
                                  "ocf_cached": [f for f in os.listdir(OCF_DIR) if f.endswith(".ocf")]})
            return
        if path == "/api/cad/taskStatus":
            import urllib.parse
            qs = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            request_id = (qs.get("requestId") or [""])[0]
            if not request_id:
                self._send_json(400, {"rtnCode": "0000003", "msg": "缺少 requestId"})
                return
            try:
                t = gcad_get_task(request_id)
                self._send_json(200, t)
            except Exception as e:
                self._send_json(500, {"rtnCode": "9999999", "msg": str(e)})
            return
        if path == "/api/weather":
            self._handle_weather()
            return
        self._send_json(404, {"error": "NOT_FOUND"})

    # ---- POST ----
    def do_POST(self):
        path = self.path.split("?")[0]
        # Flutter 端 cad_service 接口
        if path in ("/api/cad/dwgInfo", "/api/cad/dwgToOcf"):
            body = self._read_body()
            fileName = body.get("fileName")
            if not fileName:
                self._send_json(400, {"rtnCode": "0000003", "msg": "缺少 fileName"})
                return
            fileUrl = body.get("fileUrl")
            fileBase64 = body.get("fileBase64")
            try:
                if path.endswith("dwgInfo"):
                    request_id = submit_dwg_info(fileName, fileUrl, fileBase64)
                    self._send_json(200, {"rtnCode": "0000000", "bizData": {"requestId": request_id}})
                    return
                else:
                    # dwgToOcf：检查省次缓存
                    key = body.get("key") or fileName.replace(".dwg", "").replace(" ", "_")
                    dest = os.path.join(OCF_DIR, f"{key}.ocf")
                    if os.path.exists(dest):
                        self._send_json(200, {"rtnCode": "0000000", "bizData": {
                            "status": 2, "resultCode": 0, "requestId": "cached",
                            "ocfCached": True, "key": key,
                            "size_mb": round(os.path.getsize(dest) / 1048576, 2),
                            "hint": "已缓存，未消耗次数"}})
                        return
                    ocf_path, layouts = convert_dwg_to_ocf(key, fileUrl, fileBase64, fileName)
                    self._send_json(200, {"rtnCode": "0000000", "bizData": {
                        "status": 2, "resultCode": 0, "requestId": "done",
                        "ocfCached": False, "key": key,
                        "size_mb": round(os.path.getsize(ocf_path) / 1048576, 2),
                        "ocfPath": ocf_path, "layouts": layouts,
                        "hint": "已转换并缓存，本次消耗 1 次套餐"}})
                    return
                self._send_json(200, {"rtnCode": "0000000", "bizData": biz})
            except Exception as e:
                self._send_json(500, {"rtnCode": "9999999", "msg": str(e)})
            return
        if path == "/api/cad/saveAsImage":
            # OCF 转 PNG（扣次，受 guard 保护）。优先用本地 OCF 缓存 + 省次 PNG 缓存。
            body = self._read_body()
            key = body.get("key")
            if not key:
                self._send_json(400, {"rtnCode": "0000003", "msg": "缺少 key"})
                return
            png_dest = os.path.join(OCF_DIR, f"{key}.png")
            if os.path.exists(png_dest):
                self._send_json(200, {"rtnCode": "0000000", "bizData": {
                    "status": 2, "resultCode": 0, "pngCached": True, "key": key,
                    "imgUrl": f"/api/ocf/{key}.png",
                    "size_mb": round(os.path.getsize(png_dest) / 1048576, 2),
                    "hint": "PNG 已缓存，未消耗次数"}})
                return
            ocf_path = os.path.join(OCF_DIR, f"{key}.ocf")
            try:
                png_path = save_ocf_as_image(
                    key,
                    ocf_path=ocf_path if os.path.exists(ocf_path) else None,
                    ocf_base64=body.get("ocf_base64"),
                    ocf_url=body.get("ocf_url"),
                    image_width=body.get("imageWidth"),
                    image_height=body.get("imageHeight"),
                    layout=body.get("layout"),
                    layerfilter=body.get("layerfilter"),
                )
                self._send_json(200, {"rtnCode": "0000000", "bizData": {
                    "status": 2, "resultCode": 0, "pngCached": False, "key": key,
                    "imgUrl": f"/api/ocf/{key}.png",
                    "size_mb": round(os.path.getsize(png_path) / 1048576, 2),
                    "hint": "已转 PNG 并缓存，本次消耗 1 次套餐"}})
            except Exception as e:
                self._send_json(500, {"rtnCode": "9999999", "msg": str(e)})
            return
        if path == "/api/convert":
            # 兼容旧 ocf_server 接口：POST {key, dwg_url, file_base64, file_name}
            body = self._read_body()
            key = body.get("key")
            if not key:
                self._send_json(400, {"error": "MISSING_KEY"})
                return
            dest = os.path.join(OCF_DIR, f"{key}.ocf")
            if os.path.exists(dest):
                self._send_json(200, {"status": "cached", "key": key,
                                      "size_mb": round(os.path.getsize(dest) / 1048576, 2),
                                      "hint": "已缓存，未消耗次数"})
                return
            if not is_configured():
                self._send_json(200, {"status": "mock", "key": key,
                                      "hint": "未配置凭证，未真实转换"})
                return
            try:
                convert_dwg_to_ocf(key, body.get("dwg_url"), body.get("file_base64"),
                                   body.get("file_name", f"{key}.dwg"))
                self._send_json(200, {"status": "converted", "key": key,
                                      "size_mb": round(os.path.getsize(dest) / 1048576, 2),
                                      "hint": "已转换并缓存，本次消耗 1 次套餐"})
            except Exception as e:
                self._send_json(500, {"error": "CONVERT_FAILED", "detail": str(e)})
            return
        self._send_json(404, {"error": "NOT_FOUND"})

    def log_message(self, *a):
        pass


def main():
    port = C.PORT
    if len(sys.argv) > 1:
        try:
            port = int(sys.argv[1])
        except ValueError:
            pass
    os.makedirs(OCF_DIR, exist_ok=True)
    srv = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    log(f"listening on :{port}  ocf_dir={OCF_DIR}  configured={is_configured()}  gateway={API_GATEWAY}")
    srv.serve_forever()


if __name__ == "__main__":
    main()
