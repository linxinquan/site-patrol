# DWG/OCF 前端览图集成（第二步）上下文文档

> 本文档记录「CAD 转 OCF 轻量化 → 前端 JS SDK 渲染」第二步的完整进展、关键技术结论与待办，供后续续接时直接参考，避免重复调研与积分消耗。
> 上次更新：2026-08-15（周六）

---

## 0. 一句话现状

- **第一步（后端转换）已完成**：DWG → OCF 轻量化已打通，10 张 7栋图纸 OCF **已本地缓存于 `server/ocf_cache/`**（转换一次，永久复用，前端渲染 0 消耗浩辰次数）。
- **第二步（前端 SDK 渲染）已完成打通**：
  - `web/GStarSDK.js`（2.54MB，浩辰提供）已就位 `web/` 与 `build/web/`。
  - 独立页 `web/cad_viewer.html` 完成：加载 OCF 本地缓存 → GStarSDK 矢量渲染 → 坐标拾取（`screenToWorld` 真图纸坐标）→ postMessage 回传 Flutter。
  - Flutter 端 `drawing_viewer_page.dart` 已加「专业看图」入口，`_Toolbar` 首个按钮跳转 `cad_viewer.html?key=xxx`。
- **核心链路已全部跑通**：8000 静态服务 + 8800 OCF 服务，CORS 全放开，双服务联通。

---

## 1. 项目 & 采购背景

| 项 | 内容 |
|---|---|
| 项目 | 工地巡检智能化管理（Flutter Web 优先，后续拓展微信小程序） |
| 商品 | 华为云市场 "DWG FastView for Web"（苏州浩辰软件股份，交付方式 API） |
| 商品页 | https://marketplace.huaweicloud.com/contents/aeb4e164-dc5f-4c06-afe7-8e613abde8fb |
| 订单号 | **CS2608121457NG4KM**（2026/08/12 下单） |
| 免费额度 | 已开通 50 次体验 + 已正式下单 |
| 采购人/技术对接 | 杨玉婷（天津大学管理与经济学部 2025 级硕士，工程管理） |
| 服务商技术邮箱 | zhaoyy@gstarcad.com / penggw@gstarcad.com / support_app@gstarcad.com |
| 服务热线 | 18151172040 / 010-57910609转6121（周一~周五 09:00-17:30） |

---

## 2. 官方文档（关键资产，已下载到项目根目录）

> ⚠️ 这两个 PDF 是本次调研最大收获，**请勿删除**，后续续接和 SDK 接入全靠它们。

| 文件 | 内容 |
|---|---|
| `frontend_api.pdf` / `frontend_api.txt` | **前端 JS SDK（GStarSDK）完整 API 手册**（本文档第 3、4 节由此提取） |
| `backend_api.pdf` / `backend_api.txt` | 后端转换 API 手册（dwgToOcf / getDwgInfo / getTaskStatus 等） |

### 2.1 后端 API 网关域名（重要纠偏）
- **文档明确：生产固定用** `https://gstarcadsdk.apistore.huaweicloud.com`
- 商品页截图显示 `2dviewer.apistore.huaweicloud.com`——**两处不一致**，已在邮件中向服务商确认以哪个为准。

### 2.2 核心后端接口（已确认形态，均 POST + JSON body）
| 接口 | 路径 | 用途 |
|---|---|---|
| DWG转OCF | `/openapi/v1/dwgToOcf` | 返回 `requestId`，异步 |
| 取图纸信息 | `/openapi/v1/getDwgInfo` | 图层/布局/图块/xref |
| 取缩略图 | `/openapi/v1/getThumb` | 返回 `thumbUrl` |
| OCF另存图 | `/openapi/v1/ocfSaveAsImage` | 支持 `layerfilter` 图层过滤 |
| OCF另存PDF | `/openapi/v1/ocfSaveAsPdf` | 兜底路线用 |
| 取任务结果 | `/openapi/v1/getTaskStatus` | 传 `requestId`，轮询 `status==2` 得结果 |

**调用流程**：提交任务拿 `requestId` → 轮询 `getTaskStatus` → `status: 2` 且 `resultCode: 0` 时，从 `bizData` 取结果（`ocfUrl` / `fileId` / `thumbUrl` 等）。`ocfUrl` 形如 `https://oss.abc.com/openapi/v1/download?fileId=<uuid>`。

---

## 3. 前端 SDK：GStarSDK（第二步核心，接入方式已确认）

### 3.1 引入
```html
<script src="GStarSDK.js"></script>   <!-- 脚本本体待服务商提供 -->
```

### 3.2 最小可用代码
```js
// 容器必须设宽高
<div id="GStarSDK-container" style="width:100%;height:100vh;"></div>

const gstarSDK = new GStarSDK({
  wrapId: 'GStarSDK-container',
  switchLayoutCB: switchLayout,  // 布局切换回调
  apiHost: 'https://gstarcadsdk.apistore.huaweicloud.com', // 另存/打印等需要
  hideToolbar: true,             // 自建工具栏时隐藏默认的
});
await gstarSDK.render('ocf', ocfData, fileId); // ocfData 是 ArrayBuffer，render 返回 Promise
```

### 3.3 功能 ↔ API 对照表（你要的功能都有对应）

| 功能 | GStarSDK 对应 | 说明 |
|---|---|---|
| 2D/3D 览图 | `render('ocf', buffer, fileId)` + `enableZoom/disableZoom` + `enablePan/disablePan` | 核心 |
| 图层 | 属性 `layers`；方法 `setLayer(layerId, true/false)` | 开关 |
| 布局 | 属性 `layouts` / `layoutInfo`；事件 `switchLayout` | 列表/切换 |
| 视图工具 | `zoom`、`enableMap()`（鸟瞰）、`func.viewport.*`（全图/窗口缩放/全屏） | 控制 |
| 批注 | `notes.show()`/`notes.clear()`/`notes.data`；事件 `noteChange`；`func.notes.*` | 增删改 |
| 测量 | `func.measures.*`（长度/面积/坐标/弧长/角度/比例）；`measures.accuracy` | 工具 |
| 图纸对比 | 文档未单列 → 用**双容器双实例**并排，或 `setLayer` 差异对比 | 需自建 |
| 获取图元信息 | 前端 `screenToWorld({x,y})` 转图纸坐标 + 后端 `getDwgInfo` 拿图层/布局/图块/xref | 图元信息 |

### 3.4 自定义工具栏（隐藏默认 + 精确控制）
```js
// constructor 里 hideToolbar: true
gstarSDK.func.layer.main() / .close()              // 图层
gstarSDK.func.layout.main() / .close()             // 布局
gstarSDK.func.measures.measureLength.main() / .close()
gstarSDK.func.notes.noteWord.main() / .close()     // 批注
gstarSDK.func.viewport.zoomE.main() / .close()     // 全图
```

### 3.5 生命周期 & 关键方法
- `destroy()`：销毁实例（切页时调用，防 FPS 泄漏）
- `clearDraw()`：清空绘制
- `screenToWorld({x,y})`：屏幕坐标 → 图纸坐标
- `screenShot(p1, p2)`：按范围截图，返回 base64
- 事件：`switchLayout` / `ocfSizeOverLimit` / `noteChange` / `markChange` / `functionTrigger`
- 属性：`layers` / `layouts` / `layoutInfo` / `zoom` / `notes.data` / `marks.list`
- 书签：`marks.create/apply/clear`
- 大小限制：`pcSizeLimit`（默认 12M）/ `mobileSizeLimit`（默认 5M）

---

## 4. Flutter 集成方案（已确定，最小侵入）

**推荐：独立 HTML 子页 + Flutter 跳转**（零 Dart web 桥接，最稳）

1. 在 `web/` 新建 `cad_viewer.html`：加载 GStarSDK + 接收 URL 参数 `?fileId=xxx&ocfUrl=xxx` + 调后端拿 ArrayBuffer → render + postMessage 通信
2. 改 `lib/features/projects/drawing_viewer_page.dart` 工具条：加「专业看图」按钮，`launchUrlString('/cad_viewer.html?fileId=xxx')`
3. 鉴权走后端代理（见第 5 节），**AppKey/AppSecret 永不进前端**

### 现有可复用代码
- `lib/features/projects/drawing_viewer_page.dart`：图纸查看器（InteractiveViewer + 热点跳转 + 锚定），在此加入口
- `lib/features/projects/blueprint_viewer_page.dart`：多图纸切换原稿预览
- `backend/server.js`：已有 Express 代理范式（可参照扩展 CAD 接口）
- `serve_web.ps1`：Web 静态服务

---

## 5. 安全 & 鉴权（必做）

- **AppKey/AppSecret 只放服务端**，前端只拿短时效 token 或直接走后端代理。
- 若 SDK 要求前端传 AppSecret，**立即撤回**，改为后端 `POST /api/cad/token` 换 token。
- 参考项目现有范式：`AI_VISION_INTEGRATION.md` 中 VISION_HOST + backend 代理 + CORS 处理。

---

## 6. 兜底路线（不等 SDK 也能演示）

如果服务商迟迟不给 GStarSDK.js，用后端现成 API + 自渲染：

- 后端 `ocfSaveAsPdf` / `ocfSaveAsImage`（支持 `layerfilter`）→ 拿 PDF/PNG
- 前端 `pdf.js` + Canvas overlay（测量/批注自写轻量版）
- 缩略图 `getThumb` → 图纸列表

缺点：非真矢量、测量刻度自写。但可保住项目演示进度。

---

## 7. 待办清单（下次续接）

- [x] **P0** 拿到 `GStarSDK.js` + 样例包（已收彭工邮件回复 + 「二维行业版前装.zip」；`setDynamicPW` 密钥可用）
- [x] **P0** 写 `web/cad_viewer.html`（GStarSDK 矢量渲染 + 坐标拾取 postMessage 回传）
- [x] **P1** 改 `drawing_viewer_page.dart` 加「专业看图」入口（`_Toolbar` 首按钮 → `/cad_viewer.html?key=xxx`）
- [x] **P1** 确认网关域名：`gstarcadsdk.apistore.huaweicloud.com` 免费（查任务/取文件），`2dviewer` 收费（转换）——本课题只走前者 `render()` 即可，不消耗转换次数
- [x] **P1** OCF 本地缓存：10 张 7栋图纸已存 `server/ocf_cache/`，前端渲染读本地流 0 扣次
- [ ] **P1** 后端 CAD 代理收尾：`/api/cad/dwgToOcf` / `getDwgInfo` / `getTaskStatus`（AppKey 留服务端，已部分实现于 `ocf_server.py`）
- [ ] **P2** 坐标拾取回传 Flutter：`cad_viewer.html` 已 postMessage，Flutter 端监听 `cad-pick` 事件落库（为轨迹/巡检打点铺路）
- [ ] **P2** `cad_viewer.html` 内嵌到 Flutter（HtmlElementView）或保持独立页跳转（当前为独立页跳转，最稳）
- [ ] **P3** 兜底路线（PDF/pdf.js）做 MVP（当前矢量渲染已通，此路线降级备用）
- [ ] **记录** 答辩前在 iPad/安卓平板实测移动端兼容性（GStarSDK pan/zoom/measure）

---

## 8. 临时文件说明

- `_extract_pdf.py`：本次提取 PDF 文本的临时脚本，**可删除**（提取结果已存为 .txt）。
- `backend_api.pdf/.txt`、`frontend_api.pdf/.txt`：**保留**，官方文档资产。
- `huawei_product.html`：curl 未成功生成（市集是 SPA 动态渲染，curl 拿不到内容，改用 web_fetch 成功），无需保留。
