# 后端架构与技术方案

> 项目：「蓝图落地」工地验收 App（深圳市建筑设计研究总院 · 环境院 AI 中心）
> 客户端：Flutter（iOS / Android / Web）
> 版本：**v2.0 · 2026-09-18** · 状态：**内容定稿（语言/ORM 与部署方式待确认）**
>
> 相关文档：`CAD_MIGRATION_BACKUP.md`（CAD 剥离交接）、`SESSION_CONTEXT.md`（项目上下文）、
> `AUTH_STORAGE_DESIGN.md`（客户端登录与存储，S1/S2 已实施）、
> **`../蓝图落地_后端技术选型重新分析.md`（语言/数据库论证 + 与 09-10 方案的合并结论）**

---

## 0. 一句话方案

客户端数据层与抽象已经就绪，后端**从零重建**为：**模块化单体 + PostgreSQL 16 + Redis 7 + 阿里云 OSS**，
统一走一个入口，离线优先（本地为主、后端做后台同步），AI 从「裸转发」升级为「有治理的网关」。

> **已确定**：对象存储 = 阿里云 OSS（华南1 深圳）· 服务器 = 阿里云现有 ECS node0 `47.106.123.210` · 不考虑预算
> **待确认（2 项）**：① **语言 / ORM**（推荐 Node 22 + TS + Express 5 + Prisma）② **部署方式**（留空）
> → 论证与推荐见 **《蓝图落地_后端技术选型重新分析.md》**
> 本文其余部分（数据模型、同步机制、接口、权限、AI 网关）**不受影响**。

---

## 1. 现状基线（接手盘点结论）

### 1.1 客户端

业务闭环已完整：项目/图纸 → 拍照验收（AI 视觉）→ 缺陷清单（状态机 + 设计师处置 + 施工方回复）
→ 巡场（路线/打卡/GPS）→ 量尺校对 / 量房 → 周报导出（HTML/PDF/DOCX/XLSX，纯客户端生成）。

已具备的正确接缝（**重建后端要顺着它们做，而不是推翻**）：

| 接缝 | 文件 | 说明 |
|---|---|---|
| 仓库接口 | `lib/data/repository/repository.dart` | UI 只依赖接口 |
| 本地仓库实现 | `lib/data/repository/mock_repository.dart` | **已做本地持久化**（`LocalStorage.readDoc/writeDoc`），实际角色是「本地仓库」，名字叫 Mock 属历史遗留 |
| 存储抽象 | `lib/core/storage/local_storage.dart` | 条件导入：Hive + secure_storage + 文件 / localStorage |
| 模型序列化 | `lib/data/models.dart` | `Defect` / `PatrolPlan` / `MeasureSession` / `RoomScanRecord` 等全部 `toJson/fromJson`，且向后兼容 |
| 会话模型 | `lib/core/storage/session_store.dart` | `UserSession{token, refreshToken, expiresAt}` 已按 JWT 建模 |
| 环境开关 | `lib/core/env/env.dart` | `ENV` 目前**不控制数据源**（已明确），保留供后续环境差异 |

### 1.2 现有后端

| 项 | 事实 |
|---|---|
| 线上真实后端 | **只有 1 个接口**：`POST /api/vision`（Express，`120.24.240.129:3000`），**代码仓库分离** |
| 实测 | `GET /health` → 200；`GET /`、`GET /api/vision`、`/api/measurements` → 404（只定义了少量 POST 路由） |
| 密钥 | DashScope Key 存于该服务器环境变量，**非明文入库**，沿用 |

### 1.3 已判定为废案 / 孤儿的东西

| 项 | 判定 |
|---|---|
| 浩辰云图 OCF 链路 + 本地 ODA/ezdxf 转换 | **废案**，整体移交新建的网页版 CAD 项目 → 见 `CAD_MIGRATION_BACKUP.md` |
| `server/ocf_server.py`（:8800） | 随 CAD 迁移删除。其中**和风天气已拆出**为独立服务 `server/weather_server.py`（:8830） |
| `server/measure_server.py`（:8820） | **开发期一次性脚手架，从未上线**。云端 8820 实测不可达，`/api/measurements` 在生产不存在。删除 |
| `server/` 其余 py | 一次性离线脚本 / CAD 依赖 → 随 CAD 迁移走 |
| `lib/data/repository/remote_repository.dart` | **已删除**。空壳（12 个 `UnimplementedError`），且「整体替换式远端仓库」的形态与离线优先冲突 |

### 1.4 起点结论（**这三条决定方案形态**）

1. **后端不是"迁移/接管"，是"从零建"。** 唯一要接管的只有 `/api/vision` 这 1 个接口，且需要的是**升级**而非兼容。
2. **没有存量数据、没有存量调用方**（`measure_server` 从未启用），因此**不需要任何兼容层与数据迁移**，表结构可以一次到位。
3. **CAD 不在本方案范围内**，已剥离；本方案不设计任何 CAD 转换能力。

---

## 2. 目标与设计原则

| # | 原则 | 说明 |
|---|---|---|
| 1 | **离线优先** | 本地是主副本，UI 永远只读本地；后端是汇集点与协作端，不是"数据源" |
| 2 | **不推翻客户端** | 后端顺着现有抽象实现；客户端改造集中在 BASE_URL、Repository 本地化、SyncEngine、登录页 |
| 3 | **一个入口** | 客户端只配一个 `BASE_URL`，所有能力收敛到一个网关（现有 3 个硬编码 host 是主要技术债） |
| 4 | **模块化单体优先** | 1–3 人团队，不上微服务/K8s；用包结构做模块边界，真到瓶颈再拆 worker |
| 5 | **权限点而非角色** | 角色是数据不是代码，加角色不发版（角色名单尚未确定） |
| 6 | **从零建，不带包袱** | 不做兼容层；同步所需字段（`client_uuid` / `version` / `deleted_at`）建表即带上 |
| 7 | **成本可见** | AI 调用与对象存储流量必须可记账、可看板 |

---

## 3. 总体架构

```
┌──────────────────── Flutter (iOS / Android / Web) ─────────────────────┐
│  页面 / Provider                                                        │
│    └── Repository（本地为准，立即返回）                                  │
│          ├── LocalStore（Hive / 文件 / secure_storage）  ← UI 唯一数据源 │
│          └── SyncEngine                                                 │
│                ├── outbox：写本地时同时入队变更                          │
│                └── 后台：push 变更 / pull 增量 → 回写本地                 │
└───────────────────────────────┬────────────────────────────────────────┘
                                │ HTTPS · 单一 BASE_URL · JWT
┌───────────────────────────────▼────────────────────────────────────────┐
│ Nginx（TLS · 限流 · 静态托管 /jianzhu · 访问日志）                       │
├────────────────────────────────────────────────────────────────────────┤
│ 业务服务（模块化单体 · 语言见 §4）                                      │
│  auth · users · projects · drawings · defects · patrol · measure        │
│  · captures · reports · sync · files · notifications · ai · weather     │
├────────────────────────────────────────────────────────────────────────┤
│ PostgreSQL 16（主数据 + 同步变更流）   Redis 7（缓存 / 队列 / 限流）      │
│ 阿里云 OSS · 华南1深圳 · 私有读（照片/图纸/报告）  Worker（AI 批处理）    │
└────────────────────────────────────────────────────────────────────────┘
```

> **代码位置【待定】**：建议后端独立成新仓库（如 `blueprint-server`），与本客户端仓库解耦，CI 独立，
> 与新建的「网页版 CAD 项目」平级。本文档按「独立仓库」撰写。

---

## 4. 技术选型

> **本节 3 处待确认（⚠️）**，论证见《蓝图落地_后端技术选型重新分析.md》§1 §2。
> **推荐**：Node 22 + TS + Express 5 + Prisma —— 理由一句话：现有生产代码就是 Node（`backend/` 3 条路由），
> 09-17 原定 FastAPI 所依据的"服务端 Python 资产"已被本文档 §1.3 自己判为废案；
> 且宝塔「Node 项目」是你**正在使用**的部署路径，选 Node 则**语言数收敛为 1**。

| 层 | 选型 | 理由 / 备选 |
|---|---|---|
| ⚠️ 语言 / 框架 | **Node 22 LTS + TypeScript 5 + Express 5**（推荐）<br>备选：Python 3.12 + FastAPI | 现有 `backend/` 3 条 AI 路由**可原样搬入**，迁移成本≈0；Express 5 已原生支持 async 错误处理。**Express `/api/vision` 逻辑迁入**。备选触发条件见分析文档 §1.5 |
| **数据库** | **PostgreSQL 16**（**已定，无分歧**） | 关系模型清晰（项目-图纸-缺陷-回复-事件）；`JSONB` 承接半结构化字段（`items` / `walls` / `track` / `parties`）。**不用 MySQL**：同步变更流的序号分配需要事务级咨询锁（`pg_advisory_xact_lock`），MySQL 的 `AUTO_INCREMENT` 会让客户端**静默丢数据**；**不用 MongoDB**：关联与约束体系不匹配 |
| 缓存 / 队列 | **Redis 7** | 会话吊销、限流、AI 结果缓存、后台任务队列（BullMQ / RQ / Celery） |
| **对象存储** | **阿里云 OSS · 华南1（深圳）· 私有读**（**已定**） | 与 ECS 同地域 → **内网读免费**；缩图走 `x-oss-process`（服务端不做图）。详见 §8 |
| 认证 | **JWT**（access 15min + refresh 30d 轮换） | 与 `UserSession` 一一对应，客户端零改造 |
| 密码哈希 | argon2id | — |
| ⚠️ ORM / 迁移 | **Prisma**（Node 派生 / 推荐）<br>备选：SQLAlchemy 2.0 async + Alembic | 随语言走；要求**迁移从第一天就有**、每个 migration 可向前兼容（新增字段可空、不删旧字段） |
| 校验 | **Zod** | 承担「AI 返回结构校验 + 失败重试一次」（见 §10），并替代客户端 `indexOf('{')` 截串兜底 |
| ⚠️ 部署 | **留空待定** | 约束与候选路径见 §14。**推荐方向：宝塔 + PM2 + Nginx**（贴合"不碰 SSH"）；`docker compose pull && up -d` 与你的习惯直接冲突 |
| 观测 | structlog + Sentry + `/health` 聚合 | 分阶段接入 |

---

## 5. 统一入口与客户端接入

### 5.1 服务端：路径式同源部署

**`https://<域名>/api/v1/**`**

| 理由 | 说明 |
|---|---|
| 零 CORS | Web 端从 `<域名>/jianzhu/` 提供，API 同域 → 不再需要 `Access-Control-Allow-Origin: *`（现方案既是安全洞又是维护负担） |
| 复用证书 | 不新增域名/证书配置 |
| 原生端一致 | iOS/Android 用同一 URL，无分支 |

**⚠️ 证书**：现有 `certificate.pem` 是**自签证书**（`subject = issuer = CN=yangyuting.cloud`），
iOS ATS 会直接拒绝、Android 7+ 拒绝用户证书、浏览器红锁。**必须换正式 CA 证书**（Let's Encrypt / 云厂商免费 DV）。

### 5.2 客户端改造清单

| # | 改造 | 文件 |
|---|---|---|
| 1 | 新增 API 基址配置（`--dart-define=BASE_URL`） | **新增** `lib/core/api/api_config.dart` |
| 2 | 视觉服务改用基址 | `lib/data/vision_service.dart` |
| 3 | 天气服务改用基址（**已完成**，现为 `WeatherService.host`） | `lib/data/weather_service.dart` |
| 4 | 删除 CAD 服务 | `lib/data/cad_service.dart`（随 CAD 迁移） |
| 5 | 实现真实登录页（当前为占位） | `lib/features/auth/login_page.dart` |
| 6 | 实现 `SyncEngine` + outbox | **新增** `lib/core/sync/` |
| 7 | 统一数据源边界（见 §9.6） | `lib/core/di/providers.dart` 等 |

### 5.3 迁移期兼容

`/api/vision` 旧路径在迁移期保留并内部转发到 `/api/v1/ai/vision`，待客户端切换完成后下线。

---

## 6. 用户体系与权限

### 6.1 核心设计：**代码只认权限点，不认角色**

角色名单尚未确定，因此**不写死枚举**：

```
roles(code PK, name, description, permissions jsonb, sort, is_system)
memberships(id, user_id, project_id, role_code, created_at)      -- 项目级
```

代码里只硬编码**权限点**（稳定的业务动作）：

```
defect.create / defect.reply / defect.close / defect.assign
patrol.run / measure.write / report.export / drawing.manage / member.manage
```

- 角色 → 权限的映射**放数据**（`roles.permissions`）；新增角色不改代码、不发版。
- 建库时 seed 3 个系统角色兜底：`admin` / `editor` / `viewer`；甲方 / 设计院 / 监理 / 施工方等
  **待业务角色确定后往表里加**（见 §15）。
- 校验规则：`(user, project) → role.permissions → 是否含所需权限点`，**role 不放 JWT**
  （避免权限变更后旧 token 继续生效）。

### 6.2 认证流程

```
POST /api/v1/auth/login      → { access, refresh, expiresAt, user, permissions }
POST /api/v1/auth/refresh    → 轮换 refresh（旧的立即失效）
POST /api/v1/auth/logout     → refresh 入 Redis 黑名单
GET  /api/v1/auth/me         → 当前用户 + 项目列表 + 各项目权限
```

### 6.3 施工方接入（两种）

| 方式 | 说明 |
|---|---|
| 受限账号 | 只看指派给自己的缺陷 + 可回复 |
| **分享 token** | 免登录网页 `/share/{token}`，只读 + 可回复，短有效期（对应需求「施工方网页协作链接」） |

### 6.4 客户端影响

- `UserSession` / `SessionStore` **不改**（本就是 JWT 形状）
- `LoginPage` 从占位改为真实表单校验
- `currentUserProvider` 从 `mock_data.users` 切到登录会话
- 「点头像切换用户」的**扮演式开关降级为管理员功能**
- 概念澄清：`Party`（项目参与方档案，展示用）**≠** `User`（系统账号）。
  责任单位/责任人应关联 `memberships`，否则「施工方只看自己的」无法成立

---

## 7. 数据库设计

### 7.1 服务器落地

| 项 | 方案 |
|---|---|
| 服务器 | **阿里云 ECS node0**（16 vCPU / 32 GiB，`47.106.123.210`，**华南1（深圳）**，2027-04-03 到期）——**复用现有实例，不新购** |
| 数据盘 | 新增 **40 GB ESSD PL0 专供 PostgreSQL**。理由是**故障 / IO 隔离**（磁盘写满 → PG 无法写 WAL → 挂死，PG 最高频生产事故），**不是"装不下"** |
| ⚠️ 形式 | **待定**（随部署方案）：<br>A. 宝塔软件商店安装 PostgreSQL 16（推荐，图形化管理 + 计划任务备份）<br>B. Docker Compose 起 `postgres:16-alpine`，数据卷 `pgdata` 持久化 |
| 网络 | **不开公网端口，只监听 `127.0.0.1`**；共机环境不得改变现有业务配置 |
| 字符集 | UTF8；**全部时间列 `timestamptz`** |
| 扩展 | `pgcrypto`（`gen_random_uuid`）、`pg_trgm`（规范条款 / 缺陷文本模糊召回 Top20）；PostGIS 暂不装 |
| 迁移 | 随 ORM 走（Prisma migrate / Alembic），**随部署执行**；每个 migration 必须向前兼容 |
| 备份 | 每日 02:30 `pg_dump -Fc` 压缩 + 保留 7~14 天，产物**转存 OSS `blueprint-backup` 桶**（该桶 30 天自动删除） |
| 规模预估 | 单机 PG 完全够（3 人团队 + 少量项目）；**照片等二进制一律不入库** |

### 7.2 公共列约定（**建表即带，事后补极难**）

```
id                 uuid PK            gen_random_uuid()
client_uuid        uuid               客户端生成，唯一索引 → 幂等
version            int   default 1    每次写入 +1
created_at         timestamptz
updated_at         timestamptz        客户端修改时间（不可信，仅展示）
server_updated_at  timestamptz        服务端写入时间（权威）
deleted_at         timestamptz        软删；NULL = 未删
created_by         uuid → users.id
```

> `client_uuid` / `server_updated_at` / `deleted_at` 是同步机制的命脉，理由见 §9。

### 7.3 表结构（18 张，按模块）

**账号与项目**

| 表 | 关键字段 |
|---|---|
| `users` | username(uniq), display_name, password_hash, phone, email, avatar_key, status, last_login_at |
| `roles` | code PK, name, description, **permissions jsonb**, sort, is_system |
| `memberships` | user_id, project_id, role_code, uniq(user_id, project_id) |
| `projects` | name, client, location, status, site_area, floor_area, beds, concept, **parties jsonb**, **milestones jsonb** |

**图纸与文件**

| 表 | 关键字段 |
|---|---|
| `drawings` | project_id, key(uniq per project), title, crumb, floor, building, variant, source(`asset`/`upload`), width, height, **hotspots jsonb**, base_file_id, thumb_file_id, sort |
| `files` | project_id, owner_id, kind(`photo`/`drawing`/`report`/`reply_photo`/`thumb`), object_key, mime, size, **sha256**, width, height, **exif jsonb** |

**缺陷（主链）**

| 表 | 关键字段 |
|---|---|
| `defects` | project_id, drawing_id, part, type, category, severity, importance, status, anchor, floor, building, gps, lat, lng, world_x, world_y, reporter_id, resp_unit, resp_user_id, note, seed, suggestion, source_capture_id, photo_file_id, photo_hash, watermark_serial, reply, reply_by_id, reply_ts, reply_photo_file_id, close_note, completion, designer_action, designer_note, designer_by_id, designer_ts |
| `defect_events` | defect_id, actor_id, **action**, payload jsonb, created_at |

> `defects` 上的 `reply*` / `designer*` 是**当前态**（便于列表查询与报告渲染）；
> `defect_events` 是**事件流**（审计 + 冲突解决）。两者由同一写路径同时更新。
> `action` ∈ `create/update/assign/reply/designer_fix/designer_confirm/onsite/reject/close/reopen`

**巡场 / 量测 / 量房 / 验收**

| 表 | 关键字段 |
|---|---|
| `patrol_plans` | project_id, drawing_id, name, floor, **points jsonb**, total_km |
| `patrol_records` | plan_id, project_id, drawing_id, operator_id, name, started_at, finished_at, dist_km, point_count, issue_count, **track jsonb**, **checkins jsonb**, checkpoint_total |
| `measure_sessions` | project_id, drawing_id, floor, tol_mm, tol_pct, **calib jsonb**, **items jsonb**, uniq(project_id, drawing_id) |
| `room_scans` | project_id, name, room_use, source, scanned_at_ms, **walls jsonb**, closure_delta_mm, net_height_mm, drawing_id, **checks jsonb**, note |
| `captures` | project_id, drawing_id, floor, anchor, photo_file_id, ai_call_id, **ai_result jsonb**, **confirmed_result jsonb**, reporter_id |

> `measure_sessions` / `room_scans` / `patrol_records` 的 `JSONB` 字段**直接存客户端 `toJson()` 结构**，
> 服务端不解析几何，只做检索与统计——**这是最低成本、零阻抗的落地方式**。
> `captures` 的 `ai_result` + `confirmed_result` 是「缺陷知识库反哺设计」的原始数据来源。

**平台**

| 表 | 关键字段 |
|---|---|
| `reports` | project_id, period, title, format, file_id, **share_token**, share_expires_at, generated_by, status |
| `ai_calls` | project_id, user_id, task_type, model, prompt_version, **image_sha256**, request jsonb, response jsonb, input_tokens, output_tokens, latency_ms, cost, cache_hit, status, error |
| `notifications` | user_id, project_id, type, title, body, ref_type, ref_id, read_at |
| `audit_logs` | actor_id, project_id, action, entity, entity_id, before jsonb, after jsonb, ip, ua |
| **`changes`** | **seq bigserial PK**, project_id, entity, entity_id, op(`upsert`/`delete`), changed_at —— 同步变更流，见 §9 |

### 7.4 索引要点

```sql
defects(project_id, status)
defects(project_id, server_updated_at)
defects(client_uuid)              -- 幂等
changes(project_id, seq)          -- 增量拉取（核心）
files(sha256)                     -- 去重 / 证据链
ai_calls(image_sha256, prompt_version)   -- 结果复用
roles(code) / memberships(user_id, project_id)
```

---

## 8. 对象存储（阿里云 OSS）

> **本节已按定稿改写**（原 09-17 版为腾讯云 COS）。选型与单价明细见《蓝图落地_服务器与存储选型预算.md》§6。

**地域：华南1（深圳）** —— 与 ECS node0 同地域，**内网读取流量免费**。

| 项 | 方案 |
|---|---|
| 桶 | **2 个私有读桶**：`blueprint-prod`（全部业务文件，**绝不配自动删除** —— 取证数据）+ `blueprint-backup`（DB 备份，**30 天自动删除**，必须与业务数据物理隔离） |
| 为什么业务只开一个桶 | 跨桶无法原子操作、权限与生命周期要维护多套；**前缀已能清晰分区** |
| 目录规划 | `photos/{projectId}/{yyyy}/{MM}/{sha256}.jpg`<br>`videos/{projectId}/{yyyy}/{MM}/{sha256}.mp4`<br>`drawings/{projectId}/{drawingKey}/v{n}/{fileName}` + `preview.png`<br>`exports/{projectId}/{yyyyMM}/report_xxx.xlsx` · `avatars/{userId}.png` |
| 命名 | **文件名 = SHA-256** → 同一张照片重复上传**自动去重**（省存储也省流量）；**不存原始文件名**（含中文/emoji 易编码出错），原名记在 `files.file_name` 可选字段 |
| 上传 | **客户端预签名直传**：`POST /files/presign` → **PUT 预签名 URL（10 min，限定 Content-Type 与大小）** → `POST /files/complete {ossKey, sha256, size}` → 服务端 **`HEAD` 校验实际大小 / ETag** → 登记 `files` 表并返回 `fileId`。<br>**根治 base64 塞 body 撞网关体积限制的老坑** |
| **⑥ 校验不可省** | 客户端可能伪造 sha256 或上传非法内容 → 服务端必须 `HEAD` 校验，必要时抽样下载校验哈希。**这是取证级证据链的必要一环** |
| 权限 | **全私有读** + 短时预签名 URL：查看 **1 h**、外部分享 **15 min**（可带水印参数）。工地照片含人员/进度/可能涉密，**公共读一旦 URL 泄露即无法收回** |
| 服务端读图（AI） | 用**内网 endpoint**（`oss-cn-shenzhen-internal`）签发 URL → **AI 识别读图流量归零** |
| **缩图** | **走 OSS `x-oss-process`**：列表 `resize,w_400/quality,q_80`、详情 `resize,w_1600`、分享可叠加 `watermark`。<br>**服务端不做图片处理** —— 免 sharp / imagemagick 依赖与大量 CPU，工地照片量大，自建缩图会成为第一个性能瓶颈 |
| 服务端职责 | 抽 EXIF（时间/GPS，供水印存证）+ 计算 `sha256`（去重 + 证据链）。**不做缩图、不中转字节** |
| 大文件 | 分片上传（> 20 MB） |
| 生命周期 | `photos/**`：**180 天**转低频（¥0.08/GB/月）→ **730 天**转归档（¥0.033）；`videos/**`：90 天转低频；`blueprint-backup/db/**`：30 天删除；**取证数据绝不自动删除** |
| ⚠️ 最低存储时长陷阱 | 低频 30 天 / 归档 60 天 / 冷归档 180 天。**提前删除或转出会补收剩余天数费用** → 规则不要设得过激进（如"7 天转归档"会因反复转出更贵）；上传后直接进归档也是错的（取回要解冻，**取证调取会来不及**） |

**降本要点（按 ROI 排序）**
1. **客户端上传前压缩到长边 2048px** —— 存储、下行流量、AI 图片 tokens **三项同时降 ~80%**（客户端已实现 `image_compress.dart`）
2. 列表页只加载 `x-oss-process` 缩略图（400px）→ 单次浏览流量降 ~70%
3. AI 识别用**内网 endpoint** 读图 → 流量归零
4. 不要过早转归档；下行流量 > 300 GB/月且持续 2 个月，才考虑上 CDN
5. 对象存储**按存量计费**（照片每年新增会堆积），采购方式（按量 / 存储包）见预算文档

---

## 9. 同步机制（离线优先的核心）

### 9.1 问题

后端上线后，两台设备（或手机 + 网页）如何看到同一份数据？

| 做法 | 结果 |
|---|---|
| A. 每次读都请求后端 | 地下室无信号 = 没数据（**必须避免**） |
| B. 只上传不下载 | 看不到别人提交的 |
| **C. 本地为主 + 增量双向同步** | ✅ 采用 |

### 9.2 三个动作

```
① 写：先写本地（立即返回），同时把"我改了什么"记入 outbox（本地表）
② 推：有网时后台把 outbox 逐条发到  POST /api/v1/sync/push
③ 拉：客户端记住游标，只取增量        GET  /api/v1/sync/pull?sinceSeq=&projectId=
```

### 9.3 游标方案：**seq 变更流**（不用时间戳）

服务端维护一张 `changes(seq bigserial, project_id, entity, entity_id, op, changed_at)`：
**任何写操作在事务内同时插一条**。

| 方案 | 问题 |
|---|---|
| 时间戳游标（各表 `server_updated_at > since`） | **边界丢数据**：写入时间恰好等于游标值、且判据是 `>` 时会被漏掉；且需多表多游标 |
| **seq 变更流** | ✅ 客户端只需 1 个游标；"什么可同步"集中在一处定义 |

> ⚠️ **必读修正（v2.0 新增）**：`bigserial` 的**分配**严格递增，但**可见性由提交时间决定** ——
> 两个事务可能"先分配、后提交"：
>
> ```
> T1  事务 A nextval → seq=100（未提交）
> T2  事务 B nextval → seq=101，并在 T3 提交
> T4  客户端拉取，读到 max(seq)=101 → 游标推进到 101
> T5  事务 A 提交，seq=100 才变得可见
> T6  客户端从 101 继续拉 → 100 永远拉不到（静默丢一条变更，无任何报错）
> ```
>
> **解法（PG 下 1 行）**：写 `changes` 的同一事务开头取**事务级咨询锁**，使序号分配被串行化 ——
> 持锁事务提交后下一个才能分配，于是**分配顺序 ≡ 提交顺序**，`seq > cursor` 恢复正确：
>
> ```sql
> SELECT pg_advisory_xact_lock(981001);   -- 事务结束自动释放，不会泄漏
> INSERT INTO changes(project_id, entity, entity_id, op) VALUES (...) RETURNING seq;
> ```
>
> **代价**：变更流写入被串行化。本项目写入 QPS 极低，**代价可忽略**；换来同步永不丢数据。
> **这也是"数据库必须选 PG"最硬的理由**（MySQL 只有会话级 `GET_LOCK`，连接池下配对释放不可靠）——
> 详见《蓝图落地_后端技术选型重新分析.md》§2.3。**建表即带上，事后补极难。**

`pull` 响应：服务端按 seq 顺序取出变更，**连带返回当前记录内容**（已删除则返回 tombstone），
一个来回完成；用 `limit` + `nextSeq` 分页。

**游标过期**：`changes` 定期清理（保留 90 天）。客户端游标早于保留窗口时，服务端返回
`resync_required`，客户端走**全量重同步**。

### 9.4 幂等

所有写接口带 `client_uuid`（客户端生成的 UUID）+ 可选 `Idempotency-Key`。
服务端对 `client_uuid` 建唯一索引：**重发不会产生重复记录**。
（不做的后果：网络超时重试必然造重复数据。）

### 9.5 冲突策略

| 数据类型 | 策略 | 理由 |
|---|---|---|
| **会话型**：量尺会话 / 量房 / 巡场记录 | 整份覆盖，`version` 递增，后写胜（LWW） | 这是"一个人的一次作业成果"，两人同时改同一条的概率 ≈ 0；字段级合并属过度设计 |
| **流程型**：缺陷 | **事件流**：不"修改记录"，而是**追加动作**（指派/回复/销项/驳回） | **动作是事实，事实不会冲突**；最终状态由事件推导，附带审计轨迹（"谁什么时候销的项"） |

缺陷的状态机校验在服务端：非法跃迁拒绝并返回权威状态。

### 9.6 客户端改造：统一数据源边界（**必做**）

现状是**不一致的**：

| 走 `Repository` | **绕过 `Repository`，直接读本地 store** |
|---|---|
| 项目 / 楼层 / 图纸 / 锚点 / 缺陷 / 时间轴 / 量尺会话 | 巡场（`PatrolPlanStore`/`PatrolRecordStore`）、量房（`RoomScanStore`）、量尺（`MeasureStore`）、校准库 |

重建时必须**全部纳入同步范围**，否则会出现「缺陷同步了、巡场没同步」的半吊子状态。

### 9.7 触发时机

启动时、网络恢复时、写操作后 debounce 数秒、下拉刷新、定时（每 N 分钟）。
**页面完全无感**——同步只发生在 `SyncEngine` 内部。

### 9.8 明确不做

CRDT、实时协同编辑、图片走增量同步（图片单独走对象存储后只同步 `file_id`）。

---

## 10. AI 服务网关

现状：单个 Express 路由把图片转发给千问，无鉴权、无限流、无缓存、无记账，
结构化输出靠客户端截字符串兜底，超时 180s 硬扛。

| 能力 | 目标设计 |
|---|---|
| 入口 | `/api/v1/ai/*`，Key 仅在服务端 |
| **Prompt 归属** | **从客户端迁到服务端并版本化**。现有 4 套提示词在 `lib/data/vision_service.dart`（缺陷 / 锚物 / 网格 / 目标）→ 改 Prompt 不发版，支持 A/B |
| 结构化输出 | 服务端 **schema 校验 + 失败自动重试一次** → 客户端只解析、不再兜底（客户端 `indexOf('{')` 截串逻辑可退休） |
| 缓存 | `sha256(image) + prompt_version` 命中直接返回（同一张图重复上传很常见） |
| 记账 | `ai_calls` 表：项目/用户/任务/模型/Prompt 版本/图片哈希/tokens/耗时/成本/是否命中缓存 |
| 限流 | 按项目 + 按用户的令牌桶；服务端开关支持"演示模式"（替代客户端的 `_useMock` 开关） |
| 同步 / 异步 | 缺陷识别保持**同步**（10~60s）；批量与长任务改为 `task_id` 轮询/回调 |
| 失败处理 | **返回明确错误码**，不静默 mock、不静默降级 |
| 知识库 | 识别结果 + **人工确认结果**（`captures.confirmed_result`）→ 结构化沉淀 → `/ai/suggest` 用 RAG 检索历史相似缺陷给出整改建议。**这是「沉淀缺陷知识库反哺设计」的后端本体** |
| 模型 | OpenAI 兼容协议，换模型不动客户端 |

---

## 11. 报告与分享

现状：HTML / PDF / DOCX / XLSX 四端**全部在客户端生成**（纯 Dart 手写 OOXML，零插件）。

**结论：保留客户端导出不动。** 它有真实价值——离线可用、零后端成本、模板随 App 走。
后端只新增客户端做不到的三件事：

| 能力 | 接口 |
|---|---|
| 分享链接（施工方/甲方网页查看） | `POST /reports/{id}/share` → `/share/{token}` |
| 定时 / 批量周报 | 后台任务按周期汇总并推送 |
| 跨项目统计聚合（缺陷库、销项率、专业分布） | `GET /stats/*` |

---

## 12. 通知

站内消息表 + 可插拔通道（APNs / FCM / 邮件 / 企业微信 / 钉钉机器人）。

触发点：缺陷指派给施工方、设计师远程处置、整改回复提交、甲方催办、报告生成完成。

推送通道**不是 P0 阻塞项**，可先做站内消息。

---

## 13. 接口清单（v1）

统一响应：`{ ok, data, err: { code, msg } }`（与该 App 既有调用风格一致）。

| 模块 | 接口 |
|---|---|
| 认证 | `POST /auth/login` · `/auth/refresh` · `/auth/logout` · `GET /auth/me` |
| 项目 | `GET /projects` · `/projects/{id}` · `GET/POST/DELETE /projects/{id}/members` |
| 图纸 | `GET /projects/{id}/drawings` · `/drawings/{id}` |
| 文件 | `POST /files/presign` · `POST /files/complete` · `GET /files/{id}`（签名 URL） |
| 缺陷 | `GET/POST /defects` · `PATCH /defects/{id}` · `POST /defects/{id}/events` · `GET /defects/{id}/events` |
| 巡场 | `GET/POST /patrol/plans` · `GET/POST /patrol/records` |
| 量测 | `GET/POST /measure-sessions` |
| 量房 | `GET/POST /room-scans` |
| 拍照验收 | `GET/POST /captures` |
| 报告 | `POST /reports` · `GET /reports/{id}` · `POST /reports/{id}/share` |
| **同步** | `POST /sync/push` · `GET /sync/pull?sinceSeq=&projectId=&limit=` |
| AI | `POST /ai/vision`（缺陷/锚物/网格/目标，按 `task` 区分）· `POST /ai/suggest` |
| 天气 | `GET /weather?lon=&lat=&name=`（从 `ocf_server.py` 拆出的能力） |
| 通知 | `GET /notifications` · `POST /notifications/{id}/read` |
| 分享 | `GET /share/{token}`（免登录网页） |
| 运维 | `GET /health`（聚合 DB / Redis / OSS / AI 上游） |

---

## 14. 部署与运维（**留空，待确定**）

> 按指示**本节不写方案**。只记录**硬约束**（不可协商）与**候选路径**，供后续拍板。
> 关键：部署是**最后一层** —— 无论选哪条路径，都**不影响** §7 表结构、§9 同步协议、§13 接口清单。

### 14.1 硬约束

| # | 约束 | 来源 |
|---|---|---|
| 1 | **不碰 SSH / 命令行客户端**，运维走**宝塔面板可视化** | 长期工作方式 |
| 2 | 与现有业务**共机**（node0），不得影响现有服务；**重启需协调停机窗口** | 服务器复用决策 |
| 3 | PG / Redis **只监听 `127.0.0.1`**；安全组**不放行** 3000 / 3100 / 5432 / 6379 | 安全基线 |
| 4 | 单入口 `https://<域名>/api/v1/**`（零 CORS、复用证书、原生端一致） | §5.1 |
| 5 | 必须换**正式 CA 证书**（现有 `certificate.pem` 是自签，`CN=yangyuting.cloud`，**iOS ATS 会直接拒连、Android 7+ 拒用户证书**） | §5.1 |
| 6 | 迁移期 `/api/vision` **保留转发**，客户端切换完成后下线 | §5.3 |
| 7 | 环境 dev / staging / prod 三套；密钥全部走**环境变量 + `.env`**（**不入库、不进镜像**）；现有 DashScope Key 沿用服务器环境变量 | — |

### 14.2 候选路径（**待你选**）

| 路径 | 适配你的习惯 | 代价 |
|---|---|---|
| **A. 宝塔 + PM2 + Nginx**（09-10 原案，**推荐**） | ✅ 完全贴合：宝塔「Node 项目」图形化启停、**Git 拉取部署**、一键重启、计划任务做备份 —— **你正在用这条路径跑现有 AI 网关，已验证** | 环境依赖装在宿主机，与现有业务共享 Node / PG |
| **B. Docker Compose**（09-17 原案） | ❌ **冲突**：发布需执行 `docker compose pull && up -d`，与"不碰命令行"直接矛盾（除非包装成宝塔计划任务 / 脚本按钮） | 环境隔离更干净，回滚更简单（镜像 tag 回退） |
| **C. 混合** | 🟠 可行：PG / Redis 用宝塔装（图形化管理），只把 API 放进容器 | 两套运维模型并存，心智负担高 |

> **倾向 A**：若语言最终选 Node（见 §4），路径 A 阻力最小 —— 宝塔 Node 项目管理器就是 PM2 的图形化，是你**已在用**的路径。
> 选 A 时，§7.1 的 PG 安装方式同步改为「宝塔软件商店 → PostgreSQL 16」。
> 具体域名 / 证书 / 备案 / 目录与端口分配，统一见 §15。

---

## 15. 待定项（实施前需补齐）

| # | 项 | 阻塞级别 | 备注 |
|---|---|---|---|
| 1 | **语言 / ORM** | **阻塞** | ⚠️ **待确认**。推荐 **Node 22 + TS + Express 5 + Prisma**，见 §4 与《蓝图落地_后端技术选型重新分析.md》§1 |
| 2 | **部署方式** | **阻塞** | ⚠️ **待确认（本节留空）**。候选：A 宝塔+PM2（推荐）/ B Docker Compose / C 混合，见 §14.2 |
| 3 | **域名 + 正式 TLS 证书** | **阻塞** | 现为自签证书（`CN=yangyuting.cloud`），**iOS 会直接拒连**；定了才能定客户端 `BASE_URL` |
| 4 | 备案 | 阻塞（若换新域名） | 大陆 443 需备案 |
| 5 | **OSS 桶** | **阻塞**（上传相关） | 桶名（`blueprint-prod` / `blueprint-backup`）· **深圳 region** · AccessKey/Secret · 确认**私有读** |
| 6 | ~~服务器~~ | ✅ **已定** | 复用阿里云 **node0 `47.106.123.210`**（华南1 深圳，16C32G）；新增 **40 GB ESSD PL0** 数据盘专供 PG |
| 7 | ~~对象存储~~ | ✅ **已定** | **阿里云 OSS**（华南1 深圳，与 ECS 同地域 → 内网读免费），见 §8 |
| 8 | PostgreSQL | 可后补 | 安装方式随 §14 部署方案定；先跑可用默认值 |
| 9 | **`120.24.240.129` 归属** | **⚠️ 迁移前必须查清** | 跑**现有 AI 网关**的机器，但**不在账号内这 2 台实例中** → 可能属另一账号或已释放 |
| 10 | DashScope | 阻塞（AI 迁移时） | 只需告知服务器上的变量名 |
| 11 | **和风天气 Key** | **⚠️ 尽早导出** | 只在部署机 `server/config.py`，**仓库里没有**；删 CAD 前必须备份 |
| 12 | **业务角色名单** | 可后补 | 设计上不写死（§6.1），先用 admin/editor/viewer |
| 13 | 首个管理员账号 | 可后补 | 建库时 seed |
| 14 | 推送通道 | 可后补 | 可先只做站内消息 |
| 15 | 后端代码位置 | 可后补 | 建议独立新仓库（如 `blueprint-server`），与「网页版 CAD 项目」平级 |
| 16 | 数据合规 | 可后补 | 工地照片含人脸/项目信息，影响留存与权限策略 |

---

## 16. 实施路线

| 阶段 | 周期 | 内容 | 验收 |
|---|---|---|---|
| **P0 骨架与收敛** | 1–2 周 | 新仓库 + **PostgreSQL 16 + Redis 7**（装法随 §14 部署方案）+ ORM 首版建表与迁移 + JWT 登录 + 统一入口 + `/api/v1/ai/vision` 接管（含 schema 校验、记账）+ 天气迁移 | 客户端改一个 `BASE_URL` 后，**现有 AI 识别与天气功能零回归**；旧 `/api/vision` 保留转发 |
| **P1 主链上云** | 2–3 周 | 项目 / 图纸 / 成员 / 缺陷 CRUD + 缺陷事件状态机 + **OSS 上传（预签名直传）** + 客户端 Repository 本地化 + SyncEngine（缺陷先行） | 两台设备协作一条缺陷：A 记录 → B 处置 → 施工方回复，双方状态一致且离线可写 |
| **P2 全量同步 + 分享** | 2–3 周 | 巡场 / 量测 / 量房 / 拍照验收上行 + 增量同步 + 报告分享链接 + 站内通知 | 施工方扫码打开分享链接逐条回复；报告在线可查 |
| **P3 治理与增值** | 持续 | AI 缓存与成本看板、缺陷知识库 RAG（`/ai/suggest`）、跨项目统计、多项目/多租户、审计合规 | AI 成本可见；整改建议来自历史缺陷库 |

---

## 17. 风险与明确不做

**风险**

| 风险 | 对策 |
|---|---|
| 离线优先 + 多人协作的冲突复杂度 | 只对「缺陷」主链做事件溯源，其余实体 LWW；不引入 CRDT |
| 「同步」是最容易出错的部分（丢数据/重复数据） | 幂等键（`client_uuid` 唯一索引）+ seq 游标 + **`pg_advisory_xact_lock` 串行化序号分配（§9.3，否则静默丢数据）** + 游标过期全量重同步；P1 先只做缺陷一条链打通 |
| 团队 1–3 人，运维税是最大敌人 | 模块化单体 + 单机部署，不上 K8s / 微服务 |
| 现有 3 个硬编码 host、自签证书 | P0 一次性收敛，**换正式 CA 证书** |
| **OSS 外网下行（唯一大额成本）** | 上传前压缩到长边 2048px + 列表走 400px `x-oss-process` 缩略图 + **AI 识别走内网 endpoint 读图（流量归零）**；下行 > 300 GB/月且连续 2 个月才评估 CDN |
| ⚠️ 语言 / 部署方式未定 | 均**不阻塞**原型验证：数据模型（§7）、同步协议（§9）、接口（§13）与语言无关；但**定下来之前不要开始写业务代码** |
| 与现有业务共机（node0） | PG/Redis 只监听 127.0.0.1；PM2 设 `max_memory_restart`；**重启需停机窗口** |

**明确不做**：Kubernetes、微服务拆分、GraphQL、自建 IM、实时协同（CRDT/WebSocket 协同编辑）、
自研对象存储、**任何 CAD 转换能力**（已剥离至独立项目，见 `CAD_MIGRATION_BACKUP.md`）。

---

## 18. 变更记录

### v2.0 · 2026-09-18

**定位**：本文档为**后端开发的唯一指导**（09-10 的 `蓝图落地_后端架构技术方案.md` 降级为 **OSS 存储与服务器的依据来源**，其技术栈部分不再适用）。

| # | 项 | v1.0（09-17） | **v2.0** | 依据 |
|---|---|---|---|---|
| 1 | **对象存储** | 腾讯云 COS（ap-guangzhou） | **阿里云 OSS（华南1 深圳）** | 你的指令 |
| 2 | **服务器** | 复用 `120.24.240.129` | **阿里云 node0 `47.106.123.210`**（华南1 深圳，16C32G）+ 40 GB ESSD PL0 数据盘 | 你的指令 |
| 3 | **部署** | Docker Compose + Nginx | **留空待定**（§14 只记硬约束 + 候选路径） | 你的指令 |
| 4 | **缩图** | 服务端生成缩略图 | **OSS `x-oss-process`**，服务端不做图、不中转字节 | 09-10 §6.5 |
| 5 | **变更流** | 「`bigserial` 严格递增，`seq >` 无边界问题」 | **补 `pg_advisory_xact_lock` 串行化序号分配** | 修正原文档技术漏洞，§9.3 |
| 6 | ⚠️ 语言 / ORM | FastAPI + SQLAlchemy + Alembic | **待确认**：推荐 Node 22 + TS + Express 5 + Prisma | 分析文档 §1 |
| 7 | 成本 | — | **不评估**（已确定） | 你的指令 |

**v1.0 保留不改的部分（内容质量高，全部采纳）**：
18 张表结构 · 公共列约定（`client_uuid` / `version` / `deleted_at`）· seq 变更流机制 ·
缺陷事件溯源与 LWW 分级 · 权限点而非角色 · 离线优先原则 · 幂等设计 · §10 AI 网关治理 ·
§11 报告保留在客户端 · P0–P3 路线图 · §17 明确不做清单。

> 语言与 ORM 的完整论证（含被否决选项、翻盘条件、MySQL 的具体缺陷）见
> **`../蓝图落地_后端技术选型重新分析.md`**。
