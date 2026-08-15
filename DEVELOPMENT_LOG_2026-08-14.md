# 工地验收 App · 开发上下文与今日工作记录

> 更新日期：2026-08-14（周五）
> 用途：换电脑交接用上下文文档。此前在公司电脑开发，现转至家里电脑继续。

---

## 〇、项目功能结构（通读全项目梳理）

Flutter App（`lib/`），Riverpod + GoRouter + Hive：

```
lib/
├── app.dart              # 路由表（登录守卫 + ShellRoute 底部导航）
├── main.dart             # Hive 初始化 + AuthBootstrap
├── core/
│   ├── theme/            # 主题、design_tokens.dart（色板/间距）
│   ├── di/providers.dart # 全部 Provider（含 CAD 相关）
│   ├── env/env.dart      # dev/prod 切换
│   ├── storage/          # LocalStorage（Hive，图纸 seed）
│   └── utils/            # image_compress、web_storage、cad_coord
├── data/
│   ├── models.dart       # 全部数据模型（含 CAD 模型）
│   ├── vision_service.dart  # AI 视觉（调云端 120.24.240.129:3000）
│   ├── cad_service.dart     # CAD 接入（调本地 8800）
│   ├── mock/             # mock_data.dart（南科大项目数据）
│   └── repository/       # Repository 模式（Mock/Remote）
├── features/
│   ├── auth/             # 登录（Hive 会话）
│   ├── home/             # 首页：项目概览/快捷操作/今日待办
│   ├── projects/         # 项目图纸列表 + 图纸查看器 + PDF蓝图
│   ├── patrol/           # 巡场（轨迹动画状态机）
│   ├── capture/          # 拍照验收（AI 识别）
│   └── defects/          # 缺陷列表/详情/时间线对比
└── shared/widgets/       # 通用组件（含 cad_info_panel）
```

**图纸查看页 `drawing_viewer_page.dart` 已增强**（今日）：图层/布局面板 + 坐标标注。
**图纸数据当前是南科大 PNG**（`mock_data.dart` 的 `nkf_*`），7栋真实 CAD 尚未接入图纸列表。

---

## 一、项目是什么

**工地巡检智能化管理 Flutter App**（iOS / Android / Web 三端）。

- 技术栈：Flutter 3.47 + Dart 3.13、Riverpod、GoRouter、Hive、`http`
- 功能模块：登录、首页、项目图纸、巡场、缺陷记录、拍照验收（AI 视觉识别）、图纸浏览
- 项目有两个演示项目：**南科大附属医院（`nkf`，PNG 假图纸）** 与 **腾讯大铲湾 DY04·7栋（`tencent-dy04-7`，真实 CAD）**
- `allProjects = [tencentProject, project]`，**默认选中第一个 = 7栋**

## 二、核心业务：浩辰云图 CAD 接入（当前主线）

目标：把 7栋真实 DWG 图纸解析、浏览、标注（巡场精度要求高——图纸坐标标注）。

### 1. 华为云市场商品
- 商品页：https://marketplace.huaweicloud.com/contents/aeb4e164-dc5f-4c06-afe7-8e613abde8fb
- **额度**：按次套餐 50 次，**当前已用 11+ 次，剩余不多，务必精打细算**

### 2. 关键凭证
| 凭证 | 值 | 存放 |
|---|---|---|
| 浩辰 AppKey | `38f55d60d4a04e2790b5d1fac8359fe8` | `server/config.py` |
| 浩辰 AppSecret | `69e0a835a24f4094bee5f6a4dddcadf0` | 同上 |
| 浩辰 AppCode | `ed74a030b50e428597c5e16cdf58fbf68aa57a27c42e435aad3bd4869b6d843b` | 同上 |
| **COS 桶** | `site-inspection-1322296918`（region ap-guangzhou） | `server/cos_config.py` |
| COS SecretId | `<已脱敏，见本地server/cos_config.py>` | 同上 |
| COS SecretKey | `<已脱敏，见本地server/cos_config.py>` | 同上 |

⚠️ 以上 `config.py`、`cos_config.py` 均已 `server/.gitignore` 排除，**不会提交**。

### 3. 浩辰 API 关键接口（后端文档 `backend_api.txt`）
| 接口 | 路径 | 网关 | 鉴权 | 扣次 |
|---|---|---|---|---|
| getDwgInfo | `/openapi/v1/getDwgInfo` | **2dviewer** | AppCode | ❌ 不扣 |
| getTaskStatus | `/openapi/v1/getTaskStatus` | **gstarcadsdk**（写死）| AK/SK 签名 | ❌ 不扣 |
| dwgToOcf | `/openapi/v1/dwgToOcf` | 2dviewer | AppCode/签名 | ✅ 扣 1 |
| ocfSaveAsImage | `/openapi/v1/ocfSaveAsImage` | 2dviewer | AppCode/签名 | ✅ 扣 1 |
| ocfSaveAsPdf | `/openapi/v1/ocfSaveAsPdf` | 2dviewer | AppCode/签名 | ✅ 扣 1 |
| getPixelImage | `/openapi/v1/getPixelImage` | 2dviewer | AppCode/签名 | ✅ 扣 1（含 viewsize，坐标换算关键）|

**网关双地址**：提交/转换走 `https://2dviewer.apistore.huaweicloud.com`；查状态固定走 `https://gstarcadsdk.apistore.huaweicloud.com`。

**关键参数**：
- `dwgToOcf`/`getDwgInfo`：POST + JSON body（`fileName` + `fileUrl`/`fileBase64`）
- `getTaskStatus`：POST + query 参数（`?requestId=xxx`）+ AK/SK 签名 + 空 body
- 大文件（>~9MB DWG，base64>12MB）会触发 **APIG 413 body 限制**，必须用 **fileUrl（COS 公网 URL）** 绕过，或 zlib 压缩 base64

### 4. 已部署的后端
- **AI 视觉识别后端**：已上云 `http://120.24.240.129:3000`，模型 qwen3.8-max，`/health` 正常。前端 `vision_service.dart` 默认指向它，**不依赖本地 backend/server.js**（该文件已丢失，但无需重建）。
- **CAD Python 服务端**：本地 `server/ocf_server.py`，端口 **8800**，封装浩辰全部 CAD 接口 + OCF 缓存省次。

## 三、本机 CAD Python 服务端（`server/`）

```
server/
├── config.py          # 浩辰凭证（gitignore）
├── cos_config.py      # COS 凭证（gitignore）
├── cos_upload.py      # COS 上传（官方 cos-python-sdk-v5）
├── ocf_server.py      # 主服务（端口 8800）
├── quota_guard.py     # 扣次防误触
├── apig_sdk/          # 华为云 AK/SK 签名 SDK（复用下午验证）
├── .env.example
├── ocf_cache/         # OCF 缓存（省次核心）
└── .gitignore
```

**服务端接口**（Flutter `CadService` 对接）：
- `GET /api/cad/health`：健康检查
- `POST /api/cad/dwgInfo`：提交 getDwgInfo，返回 requestId（不扣次）
- `GET /api/cad/taskStatus?requestId=`：查状态（不扣次）
- `POST /api/cad/dwgToOcf`：转换，含省次缓存（扣 1）
- `POST /api/cad/saveAsImage`：OCF→PNG（扣 1，含 PNG 缓存）
- `GET /api/ocf/<key>.ocf|.png`：分发 OCF/PNG

**省次策略**：同图只转 1 次，OCF 缓存到 `ocf_cache/`，前端永远从本地服务拉取，不重复扣次。

**启动**：`cd server && python ocf_server.py 8800`
（扣次接口需环境变量 `GCAD_ALLOW_CHARGE=1`）

## 四、7栋图纸转换成果（今日完成）

第一轮测试 10 张 7栋 CAD 已全部转成 OCF，缓存于 `server/ocf_cache/`：

| OCF key | 图纸 | 大小 |
|---|---|---|
| dy04_7_B01 | 地下一层顶板组合平面图 | 9.31MB |
| dy04_7_B02 | 地下一层顶板分区平面图(一) | 9.31MB |
| dy04_7_D01 | A座1-1剖面图 | 1.26MB |
| dy04_7_D03 | 剖面图绑定版 | 1.48MB |
| dy04_7_K01 | 墙身详图（一）| 0.55MB |
| dy04_7_K02 | 墙身详图（二）| 0.45MB |
| dy04_7_E01 | A座楼梯详图 | 0.34MB |
| dy04_7_F01 | B座楼梯剖面图 | 2.25MB |
| dy04_7_J01 | A座门窗详图（一）| 0.20MB |
| dy04_7_J04 | 门窗详图绑定版 | 0.81MB |

**转换方式**：DWG 上传腾讯云 COS（生成公网 URL）→ 调浩辰 `dwgToOcf`（fileUrl）→ OCF 落盘缓存。**共消耗 8 次额度**（B01/K01 是下午转换的，复用缓存未再扣次）。

**COS 已上传的 DWG**（供浩辰 fileUrl 下载）：
`B1pingmian.dwg`、`B1qiangshen.dwg`、`B02.dwg`、`D01.dwg`、`D03_D04.dwg`、`K02.dwg`、`E01.dwg`、`F01_F08.dwg`、`J01.dwg`、`J04_J05.dwg`
公网域名：`https://site-inspection-1322296918.cos.ap-guangzhou.myqcloud.com/<文件名>`

## 五、Flutter 端 CAD 接入（已实现）

| 文件 | 作用 |
|---|---|
| `lib/data/cad_service.dart` | `CadService` 封装，调本地代理 `http://localhost:8800`（`CAD_HOST` 可覆盖）|
| `lib/data/models.dart` | `CadLayer`/`CadLayout`/`DwgInfo`/`CadTaskStatus`/`CadAnnotation` 模型 |
| `lib/core/utils/cad_coord.dart` | `CadCoordMapper`：viewsize 坐标换算（screenToWorld/worldToScreen）|
| `lib/shared/widgets/cad_info_panel.dart` | 图层开关 + 布局切换面板 |
| `lib/core/di/providers.dart` | `cadServiceProvider`、`cadInfoProvider`、`cadAnnotationsProvider`、`cadPickModeProvider` |

**图纸查看页 `drawing_viewer_page.dart` 已加**：
- 「图层」按钮 → 打开 CAD 面板（图层开关 / 布局切换）
- 「坐标」按钮 → 拾取模式，点击图纸打点 → 换算图纸坐标 → 红色图钉标记

**已验证**：`getDwgInfo` 真实调用成功拿到 23 个图层、3 个布局（Model/布局1/布局2），全程不扣次。

## 六、当前未完成 / 待办

1. **7栋 10 张图接入项目图纸列表**：当前 `floors`/`drawings` 还是南科大 PNG，未按项目区分。需让 7栋项目显示 7栋图纸。
2. **图纸展示方式未定**：OCF 需 **GStarSDK.js** 矢量渲染（**尚未拿到**，正等浩辰 `zhaoyy@gstarcad.com` 邮件，订单 `CS2608121457NG4KM`）。可选：转 PNG（扣次）/ 等 SDK / 占位。
3. **坐标标注落地**：`CadCoordMapper` 框架已建，真实渲染需 GStarSDK。
4. **额度精打细算**：已用 11+ 次，剩余每次调用都需用户确认。

## 七、本地资料路径

| 内容 | 路径 |
|---|---|
| 项目资料（7栋施工图） | `F:\建筑验收工具\大铲湾DY04_资料` |
| 原始资料（全项目 1859 DWG） | `F:\设计院工作\SZAD\2020-腾讯大铲湾DY04` |
| 浩辰 API PDF 文档 | `F:\建筑验收工具\浩辰云图网页版软件` |
| 下午 web-demo（batch_convert 参考） | `F:\建筑验收工具\web-demo` |

## 八、环境清单（家里电脑）

| 组件 | 版本 | 位置 |
|---|---|---|
| Flutter | 3.47.0 (Dart 3.13) | `D:\flutter` |
| JDK | 17.0.20 | `D:\java\jdk-17.0.20+8` |
| Android SDK | API 36 | `D:\Android` |
| Chrome | 最新 | `C:\Program Files\Google\Chrome` |
| Node.js | v24.19.0 | `C:\Program Files\nodejs` |
| Python | 3.14.3 | 系统 |
| Web 预览 | `http://localhost:8000`（serve_web.ps1）| — |
| CAD 服务 | `http://localhost:8800`（ocf_server.py）| — |

**构建命令**：`flutter build web`；本地 serve 用 `serve_web.ps1`。
**验证**：`flutter analyze` 应零问题。

## 九、安全与操作偏好（用户要求）

1. **文件列表里的文件全部保留**，不删除、不再询问。
2. **危险命令 / 高危操作默认直接运行**，不需要用户再点击确认。
3. ⚠️ **例外**：浩辰 API 按次计费，**每次消耗额度的调用仍需用户明确同意**（额度珍贵）。
4. COS 密钥等敏感信息已配置于 `server/*.py`（gitignore），勿提交。
