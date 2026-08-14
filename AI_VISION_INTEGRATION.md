# 拍照验收接入 AI 视觉模型（关键步骤）

> 本文档记录「拍照验收」页面接入真实视觉模型（千问 qwen3.8-max）从 0 到联调通过的重要步骤，供后续维护与二次开发参考。

## 一、总体架构

```
[拍照验收页面 CapturePage]
   │ 1. 按平台取图（Web=相册选图 / 移动端=相机）
   │ 2. 图片字节压缩
   ▼
[VisionService.recognizeDefects]   ← lib/data/vision_service.dart
   │ 3. POST http://localhost:3000/api/vision（body 带 dataURL 图片 + prompt）
   ▼
[Express 代理后端]                 ← backend/server.js
   │ 4. 组装消息（text prompt + image_url），带 DashScope key 调 OpenAI SDK
   ▼
[千问视觉模型 qwen3.8-max]
   │ 5. 返回缺陷 JSON
   ▼
[解析 + 页面展示 / Web 暂存]
```

## 二、后端：Express + OpenAI SDK

**文件：`backend/server.js`**

1. **环境变量（`.env`）**
   - `DASHSCOPE_API_KEY`：DashScope（阿里云百炼）API Key
   - `QWEN_BASE_URL`：OpenAI 兼容的 baseURL
   - `QWEN_MODEL`：默认 `qwen3.8-max`

2. **POST `/api/vision`**
   - 请求体：`{ image: "data:image/jpeg;base64,..." | http url, prompt? }`
   - 组装消息：`messages = [{ role:'user', content: [ {type:'text', text: prompt}, {type:'image_url', image_url:{url: image}} ] }]`
   - 返回：`{ content: "<模型返回的 JSON 字符串>" }`
   - 关键点：`express.json({ limit: '5mb' })` —— base64 图片体量大，默认 100kb 会 413，必须调大。

3. **CORS（Web 联调必需）**
   - 后端若未配置 CORS，浏览器会拦截 `localhost:8000 → localhost:3000` 的跨域请求。
   - 手写中间件：`Access-Control-Allow-Origin: *` + 处理 `OPTIONS` 预检返回 204。
   - 启动：`cd backend && node server.js`（默认 3000 端口，`/health` 健康检查）。

## 三、前端 Flutter

### 1. 依赖（`pubspec.yaml`）
```yaml
image_picker: ^1.1.2   # 取图（相机/相册）
image: ^4.2.0          # 图片压缩
http: ^1.6.0           # 调后端 /api/vision
```

### 2. 取图按平台分流（`capture_page.dart` `_pickImage`）
- **Web** → `ImageSource.gallery`（相册选图；桌面浏览器无法直接调相机）
- **Android/iOS** → `ImageSource.camera`，带 `maxWidth: 1280, imageQuality: 82`（原生压缩）
- 用 `kIsWeb` 判断平台（不能用 `dart:io` 的 `Platform`，Web 不可用）。

### 3. 图片压缩（`lib/core/utils/image_compress.dart`）
`compressImage(bytes, {maxDim:1280, quality:82})`：
- `image` 包解码 → 最长边等比缩放 → JPEG 编码
- 解码失败原样返回，不破坏不可解析的图

### 4. 视觉识别服务（`lib/data/vision_service.dart`）
- `VisionService.host`：`String.fromEnvironment('VISION_HOST', defaultValue:'http://localhost:3000')`
  - 上云时：`flutter build web --dart-define=VISION_HOST=https://xxx`
- `recognizeDefects(Uint8List, {prompt})`：
  1. `base64Encode` 图片字节 → `data:image/jpeg;base64,`
  2. POST JSON body
  3. **超时调大**：`.timeout(Duration(seconds: 180))` —— 千问模型冷启动+推理常超 60s，`60s` 会误触发超时（实测约 50s~1.7min）。
- 解析：模型可能返回 markdown 代码块/多余文字 → 用 `content.indexOf('{')`~`lastIndexOf('}')` 截取第一个 JSON 对象再 `jsonDecode`。
- 返回 `VisionResult { count, defects:[{name, desc}] }`。

### 5. 拍照验收页面接入（`capture_page.dart`）
- `_runScan`：有照片 → 调真实模型；映射成 `List<VlDefect>`。
- **Mock 开关**（顶栏 Switch，`_useMock`）：
  - 开 → `vlPreset`（秒级，省模型配额，便于验证 UI）
  - 关 → 真实接口
- **超时/失败**：`on TimeoutException` / `catch(e)` 分别捕获，写入 `_scanError` 状态，页面红字提示（不要静默吞异常）。

### 6. 缺陷卡片展示
- 缺陷卡片独立成区块 `_buildDefectSection`，放在图纸**外部**（`_buildResultPanel` 之后），避免被图纸 Stack 裁剪/遮挡。
- 描述 `desc` 有值则显示在缺陷名下。
- **置信度徽标按 conf 档位**（不是按 severity）：
  - `conf >= 0.8` → 高 / 绿 `#16A34A`
  - `0.5 <= conf < 0.8` → 中 / 橙 `#EA580C`
  - `conf < 0.5` → 低 / 红 `#DC2626`

## 四、Web 端暂存（仅测试用）

**文件：`lib/core/utils/web_storage.dart`**（依赖 `dart:html`，仅 Web）

- 用 `window.localStorage` 持久化识别结果，刷新页面后仍可见。
- `CapturePage`：vision 返回即写入 `_storedResults` 并 `WebStorage.setList`；`initState` 时 `_loadStoredResults()` 恢复。
- 展示在「保存验收记录」按钮下方列表。
- ⚠️ `dart:html` 不兼容 wasm、不可用于移动端；跨平台后续应换 `shared_preferences` 等。

## 五、验证与常见坑

| 现象 | 原因 | 解决 |
| --- | --- | --- |
| 请求发起了但页面停在"等待识别" | 60s 超时太短，模型 50s~1.7min 才返回 | 超时调到 180s；失败红字提示 |
| Web 端请求被拦截 | 后端无 CORS | 后端加 `Access-Control-Allow-Origin` + OPTIONS 204 |
| 后端 413 | body 默认 100kb，图片 base64 大 | `express.json({ limit:'5mb' })` |
| 缺陷卡片被图纸裁剪/显示不全 | 浮层在图纸 Stack 内 | 挪到图纸外部独立区块 |
| 置信度显示"轻微/中等/高" | 误用 severity | 改为按 conf 分低/中/高 |

## 六、运行方式

```bash
# 1. 启动后端
cd backend && node server.js   # http://localhost:3000

# 2. 构建 + 本地静态服务前端（本环境无 python/node，用 PowerShell 脚本）
flutter build web --release
powershell -ExecutionPolicy Bypass -File serve_web.ps1   # http://localhost:8000

# 3. 上云时指定后端地址
flutter build web --release --dart-define=VISION_HOST=https://xxx
```

> `serve_web.ps1` 是临时静态文件服务器（监听 build/web 8000 端口），供开发预览用。
