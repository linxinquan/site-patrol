# CAD 迁移与清理清单

> 用途：把本项目（「蓝图落地」工地验收 App）里的 **CAD 渲染/转换/看图** 能力整体移交到
> 新建的**网页版 CAD 项目**，本仓库随后清除 CAD 相关内容。
>
> 决策前提（已确认）：
> 1. 本项目**不再需要 DWG 上传预览**；
> 2. 浩辰云图（OCF）链路是废案，随新项目一起走；
> 3. 「CAD 坐标系能力」（图纸打点定位 / 量尺图纸侧取值 / 巡场防穿墙）**保留**，不属迁移范围。
>
> 状态：待执行（本文档即备份交接清单）。最后更新 2026-09-17。

---

## 0. 一分钟摘要

| 类别 | 数量（约） | 去向 |
|---|---|---|
| 服务端脚本 `server/` | 14 个 py + `apig_sdk/`(9) | 搬到新项目，**本目录最终整体消失** |
| 客户端代码 | 3 个整文件 + 4 个文件的局部段落 | 搬到新项目，其余保留 |
| Web 资源 | 3 个 html/js + 2 张 png | 搬到新项目 |
| 文档 | 5 份 | 搬到新项目 |
| **必须先备份的凭证** | **2 组**（浩辰 AK/SK、和风 Key） | ★ 只存在部署机 `server/config.py`，仓库里没有 |
| 保留（别删） | 7 项 | 本项目 App 继续用 |

---

## 1. 前提：本项目里「CAD」有两种含义（**别混着删**）

| 含义 | 内容 | 处置 |
|---|---|---|
| **A. CAD 渲染 / 转换 / 看图** | 浩辰 OCF、GStarSDK、本地 ODA+ezdxf、上传 DWG 预览 | ✅ 搬去新网页项目 |
| **B. CAD 坐标系能力** | 屏幕像素 ↔ 图纸 mm 换算、图纸校准、轴网交点、墙线检测 | ❌ **保留**，见第 3 节 |

> 按字面把 A+B 一起删，会直接打断「图纸打点定位 + 量尺图纸侧数值 + 巡场防穿墙」三条主功能。

---

## 2. 搬运清单（→ 新网页版 CAD 项目）

### 2.1 服务端脚本（`server/`）

| 文件 | 说明 |
|---|---|
| `ocf_server.py` | 浩辰云图代理主服务（:8800）。**天气已拆出，可直接搬**（见第 4 节） |
| `cad_local.py` | 本地零配额转换：DWG → ODA → DXF → ezdxf 渲染 PNG/SVG + 图层 JSON |
| `cad_meta_server.py` | 元数据解析服务（`parse_dwg_to_meta`） |
| `cad_meta_build.py` | 离线元数据批量构建 |
| `quota_guard.py` | 浩辰扣次守卫 + 接口扣次清单（有价值，建议新项目保留） |
| `apig_sdk/` | 华为云 APIG 签名 SDK（5 py + 4 pyc） |
| `cos_upload.py` | 上传 DWG 到腾讯云 COS 拿公网 URL（供浩辰 `fileUrl` 方式） |
| `dwg_to_dxf.py` | DWG → DXF 单独转换 |
| `derive_calib_from_dxf.py` | 从 DXF 推导图纸校准系数 |
| `extract_axis_intersections.py` | 从 DXF 提取轴网交点 → **轴网 JSON 的生成者** |
| `_b01_detail.py` / `_b01_genjson.py` | B01 校准验证/生成（一次性脚本） |
| `_compute_seed.py` / `_compute_seed_v2.py` | 校准种子推导（一次性） |
| `_inspect_b01.py` / `_verify_seed.py` | 校准核查（一次性） |
| `DXF_CALIBRATION_README.md` | 轴网校准推导说明 |
| `.env.example` | 凭证模板（浩辰 + 和风） |
| `cad_meta/` | 产物目录 |
| `ocf_cache/` | 产物目录（10 张 7 栋图纸 OCF + PNG + `_meta.json`，体积可能较大） |
| `.quota_state.json` | 浩辰配额本地记录（若存在） |

**接口路由对照（便于新项目复刻）**

| 路由 | 归属 |
|---|---|
| `POST /api/cad/dwgInfo`、`/api/cad/dwgToOcf` | 浩辰 |
| `POST /api/cad/saveAsImage` | 浩辰（OCF→PNG） |
| `GET /api/cad/taskStatus` | 浩辰（任务轮询） |
| `POST /api/upload-dwg-local` | 本地 ODA+ezdxf |
| `POST /api/convert` | 旧版兼容接口 |
| `GET /api/ocf/{key}`（.ocf / .png / .svg） | 缓存静态分发 |
| `GET /api/ocf-meta/{key}` | 元数据分发 |
| `GET /health`、`/api/cad/health` | 健康检查 |

### 2.2 客户端代码（Flutter）

| 文件 | 搬走范围 |
|---|---|
| `lib/data/cad_service.dart` | **整个文件** |
| `lib/shared/widgets/cad_info_panel.dart` | **整个文件**（图层/布局面板，数据来自 `getDwgInfo`） |
| `lib/core/storage/uploaded_drawing_store.dart` | **整个文件**（上传图纸登记） |
| `lib/features/projects/drawing_viewer_page.dart` | ⚠️ **只搬 OCF/GStar 渲染 + 坐标拾取那一段**，此文件同时管普通 PNG 图纸查看，不能整文件搬 |
| `lib/core/di/providers.dart` | `cadServiceProvider` / `cadInfoProvider` / `cadAnnotationsProvider` / `cadPickModeProvider` / `_uploadedToFloor` / `_uploadedToDrawing` / `uploadedDrawingsProvider` |
| `lib/shared/widgets/drawing_image.dart` | 仅「http 网络底图」这一分支（服务上传图纸）；assets 分支本项目仍需要 |
| `lib/features/projects/projects_page.dart` | 「上传 DWG / 我的上传」入口段落 |
| `lib/features/capture/capture_page.dart` | 对 `api/ocf` 的依赖段落 |
| `lib/data/models.dart` | `UploadedDrawing` 类（可搬可删） |

### 2.3 Web 资源

| 文件 | 状态 |
|---|---|
| `web/GStarSDK.js` | 工作区已删除 → 从 git 历史恢复，或重新向浩辰索取 |
| `web/cad_viewer.html` | 工作区已删除 → 从 git 历史恢复 |
| `web/cad_viewer_hybrid.html` | 仓库中仍在 |
| `web/dy04_7_B05_paper_filtered.png`、`dy04_7_B05_paper_hybrid.png` | 混合查看器试验产物，按需搬 |

### 2.4 文档

| 文件 | 备注 |
|---|---|
| `CAD_OCF_INTEGRATION.md` | ⚠️ **含未解决的 git 冲突标记**（`<<<<<<< HEAD` / `=======` / `>>>>>>>`），搬之前先修或注明 |
| `backend_api.txt` / `backend_api.pdf` | 浩辰云图后端 API 文档 |
| `frontend_api.txt` / `frontend_api.pdf` | GStarSDK 前端 SDK 文档 |
| `REQUIREMENTS_0902_IMPL.md` | 其中「任务 3：DWG 自助上传」段落 → 新项目参考 |

### 2.5 ★ 凭证与密钥（**必须先导出，仓库里没有**）

| 位置 | 内容 | 风险 |
|---|---|---|
| 部署机 `server/config.py` | 浩辰 `APP_CODE / APP_TOKEN / APP_KEY / APP_SECRET`、网关地址 | 删 `ocf_server.py` 会一并带走 |
| 部署机 `server/config.py` | **和风天气 `QWEATHER_KEY` / `QWEATHER_HOST`** | ⚠️ 本项目天气功能也要用，**已拆到独立服务**（见第 4 节），key 必须导出 |
| 部署机 `server/cos_config.py` | 腾讯云 COS `SECRET_ID / SECRET_KEY / BUCKET / REGION` | 新项目继续用 COS 则需要 |
| 服务器环境变量 | DashScope Key（AI 视觉） | 本项目后端继续用，**不外迁** |

> `config.py` / `cos_config.py` 均被 gitignore，只在部署机上。**备份动作务必在删除任何文件之前完成。**

---

## 3. 保留清单（本项目 App 继续用，**不要删**）

| 文件 / 资产 | 用途 |
|---|---|
| `lib/core/utils/cad_coord.dart` | `CadCoordMapper`：屏幕像素 ↔ CAD 世界坐标 mm。**图纸打点定位、缺陷坐标回溯的核心** |
| `lib/core/cad/cad_calibration.dart` | 校准库（按图纸持久化校准系数） |
| `lib/core/cad/axis_calibration.dart` | 轴网校准 |
| `lib/core/cad/axis_auto_calibration.dart` | 轴网交点自动套图校准（精度来源） |
| `assets/axis_data/dy04_7_{B01,D01,D03,D04}.json` | 轴网交点数据。**生成脚本搬走，产出必须留下** |
| `lib/core/cad/wall_lines.dart` | 巡场墙线检测 / 防穿墙 |
| `lib/utils/path_metrics.dart` | 巡场路径度量（沿墙走线） |
| `lib/features/{measure,patrol,room,projects}/*` | 业务页面（**局部摘除** CAD 段落，不整删） |

---

## 4. 已完成的解耦（清理的前置动作，2026-09-17）

| 动作 | 文件 | 说明 |
|---|---|---|
| ✅ 天气拆成独立服务 | **新增** `server/weather_server.py` | 从 `ocf_server.py` 的 `_handle_weather` / `_fetch_qweather` 拆出，端口 **8830**，接口 `GET /api/weather?lon=&lat=&name=`（响应结构与原来完全一致，前端无需改协议）。已剔除原实现里 `return` 之后的不可达死代码 |
| ✅ 客户端天气解耦 | **新增** `lib/data/weather_service.dart` | `WeatherService.host` 由 `--dart-define=WEATHER_HOST` 控制，默认 `http://localhost:8830` |
| ✅ 改引用 | `lib/core/di/providers.dart` | `weatherProvider` 的 host：`CadService.host` → `WeatherService.host`（原先天气挂在 CAD 服务上，删 CAD 会连带带崩天气） |

**端口现状**

| 端口 | 服务 | 去向 |
|---|---|---|
| 8800 | `ocf_server.py`（CAD） | 搬走，端口释放 |
| 8820 | `measure_server.py`（量尺落库） | 已判定为开发期孤儿脚本，**删**（见 1.2 结论） |
| **8830** | `weather_server.py`（天气） | **保留** |

---

## 5. 清理顺序（**按序执行，顺序不能错**）

1. **导出凭证**：从部署机备份 `server/config.py`、`server/cos_config.py` 全部字段（★ 第 2.5 节）
2. **备份产物**：`server/ocf_cache/`、`server/cad_meta/`（如需保留历史转换结果）
3. **备份轴网 JSON**：确认 `assets/axis_data/*.json` 已入库（**留在本项目**）与 `extract_axis_intersections.py`（**搬走**）
4. **搬服务端**：`server/` 全部 CAD 脚本 → 新项目（天气已独立，不受影响）
5. **搬 Web 资源与文档**：第 2.3 / 2.4 节
6. **摘客户端代码**：按第 2.2 节，特别注意 `drawing_viewer_page.dart` 是混合文件
7. **清理上传图纸的连带**：`floorsProvider` / `drawingsProvider` 里的 `up_` 前缀合并逻辑要一起摘掉，**注意别弄坏预置图纸列表**（`floors` / `dy7Floors`）
8. **删除**：按第 6 节
9. **验证**：按第 7 节

---

## 6. 删除清单

**服务端**
- `server/` **整个目录**（第 4 步搬完后）：包含 `ocf_server.py`、`cad_local.py`、`cad_meta_server.py`、`cad_meta_build.py`、`quota_guard.py`、`cos_upload.py`、`dwg_to_dxf.py`、`derive_calib_from_dxf.py`、`extract_axis_intersections.py`、`_b01_*.py`、`_compute_seed*.py`、`_inspect_b01.py`、`_verify_seed.py`、`apig_sdk/`、`cad_meta/`、`ocf_cache/`、`DXF_CALIBRATION_README.md`、`.env.example`
- `server/measure_server.py`、`server/measure_data/`、`_test_measure.ps1`（1.2 已判定为孤儿，与本迁移无关但一并清）

**客户端**
- `lib/data/cad_service.dart`
- `lib/shared/widgets/cad_info_panel.dart`
- `lib/core/storage/uploaded_drawing_store.dart`

**Web**
- `web/cad_viewer_hybrid.html`（搬走后）

**文档**
- `CAD_OCF_INTEGRATION.md`、`backend_api.txt/.pdf`、`frontend_api.txt/.pdf`（搬走后）

**连带小尾巴**
- `_serve_web.js`、`_rebuild_serve.ps1` 中的 `.ocf` MIME 类型条目
- `.gitignore` 中的 CAD 专属条目：`web/cad_secret.txt`、`server/dwg_cache/`、`server/ocf_cache.zip`、`*.dxf`、`server/_local_work/`、`server/_local_out/`、`server/axis_data/`

---

## 7. 验证方法

**天气服务（独立后）**

```bash
python server/weather_server.py 8830
curl http://localhost:8830/health
curl "http://localhost:8830/api/weather?lon=113.9799&lat=22.5936"
# 未配置 QWEATHER_KEY 时应返回 {"source":"mock", ...}，属正常
```

> 过渡期若想让客户端零改动，可用 `python weather_server.py 8800` 顶上原端口。

**清理后**

```bash
dart analyze lib                      # 期望 0 error
grep -rn "ocf\|GStar\|dwgToOcf\|uploadDwg\|CadService" lib/     # 期望无残留
```

**保留功能回归（重点，别被误伤）**

- 图纸打点 → 缺陷带 `worldX/worldY` 坐标
- 量尺页「图纸侧数值」正常读出（走 `CadCoordMapper`）
- 巡场页墙线检测 / 防穿墙正常
- 首页天气卡片正常（`source: mock` 或 `qweather` 均算通过）

---

## 8. 遗留与已知问题（一并交接给新项目）

| # | 问题 | 说明 |
|---|---|---|
| 1 | `ocf_server.py` 中 `do_OPTIONS` **重复定义两次** | 后者覆盖前者（`Access-Control-Allow-Headers` 不一致），建议新项目只留一个 |
| 2 | `_fetch_qweather` 末尾有 **不可达死代码** | `return` 之后残留的 read_body 片段，已在新 `weather_server.py` 中剔除 |
| 3 | `CAD_OCF_INTEGRATION.md` **含未解决的 git 冲突标记** | 说明曾有一次合并被直接提交，搬之前需人工确认版本 |
| 4 | 现有 `certificate.pem` 是**自签证书** | `subject=CN=yangyuting.cloud` / `issuer=CN=yangyuting.cloud`；iOS ATS 会拒绝、浏览器红锁。新项目若对外提供服务须换正式证书 |
| 5 | 浩辰配额 | 已开通 50 次体验 + 已下单（订单号 `CS2608121457NG4KM`）；`quota_guard.py` 的扣次清单可复用 |
| 6 | 40MB 级 SVG | `cad_local.py` 输出的文字层 SVG 在 Web 端渲染失败（已知），新项目需另想办法 |
