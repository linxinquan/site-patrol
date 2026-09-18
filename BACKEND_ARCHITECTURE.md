# 后端架构与技术方案

> 项目：「蓝图落地」工地验收 App（深圳市建筑设计研究总院 · 环境院 AI 中心）
> 客户端：Flutter（iOS / Android / Web）
> 版本：v1.0 · 2026-09-17 · 状态：**设计定稿，待实施**
>
> 相关文档：`CAD_MIGRATION_BACKUP.md`（CAD 剥离交接）、`SESSION_CONTEXT.md`（项目上下文）、
> `AUTH_STORAGE_DESIGN.md`（客户端登录与存储，S1/S2 已实施）

---

## 0. 一句话方案

客户端数据层与抽象已经就绪，后端**从零重建**为：**FastAPI 模块化单体 + PostgreSQL + Redis + 腾讯云 COS**，
统一走一个入口，离线优先（本地为主、后端做后台同步），AI 从「裸转发」升级为「有治理的网关」。

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
│ 业务服务（FastAPI 模块化单体）                                          │
│  auth · users · projects · drawings · defects · patrol · measure        │
│  · captures · reports · sync · files · notifications · ai · weather     │
├────────────────────────────────────────────────────────────────────────┤
│ PostgreSQL 16（主数据 + 同步变更流）   Redis（缓存 / 队列 / 限流）        │
│ 腾讯云 COS（照片 / 图纸底图 / 报告）   Worker（AI 批处理 / 报告 / 缩略图） │
└────────────────────────────────────────────────────────────────────────┘
```

> **代码位置【待定】**：建议后端独立成新仓库（如 `blueprint-server`），与本客户端仓库解耦，CI 独立，
> 与新建的「网页版 CAD 项目」平级。本文档按「独立仓库」撰写。

---

## 4. 技术选型

| 层 | 选型 | 理由 / 备选 |
|---|---|---|
| Web 框架 | **FastAPI**（Python 3.12） | 现有 AI 代理是 Node，但服务端已有 Python 资产与团队熟悉度；Pydantic 直接充当数据结构契约。**Express 的 `/api/vision` 逻辑迁入** |
| 数据库 | **PostgreSQL 16** | 关系模型清晰（项目-图纸-缺陷-回复-事件）；`JSONB` 承接半结构化字段（`items` / `walls` / `track` / `parties`）；`bigserial` 做同步变更流。**不用 MongoDB** |
| 缓存 / 队列 | **Redis 7** | 会话吊销、限流、AI 结果缓存、后台任务队列（RQ 或 Celery） |
| 对象存储 | **腾讯云 COS**（已开通） | 私有桶 + 预签名直传。**桶名/region/密钥待定**（见 §15） |
| 认证 | **JWT**（access 15min + refresh 30d 轮换） | 与 `UserSession` 一一对应，客户端零改造 |
| 密码哈希 | argon2id | — |
| ORM / 迁移 | SQLAlchemy 2.0（async）+ **Alembic** | 迁移从第一天就有 |
| 部署 | **Docker Compose** + Nginx | 单机 4C8G 起；不上 K8s |
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
| 形式 | Docker Compose 起 `postgres:16-alpine`，数据卷 `pgdata` 持久化 |
| 网络 | **不开公网端口**，仅在同一 compose 网络内被 API 容器访问 |
| 字符集 | UTF8；全部时间列 `timestamptz` |
| 扩展 | `pgcrypto`（`gen_random_uuid`）、`pg_trgm`（缺陷文本模糊搜索）；PostGIS 暂不装 |
| 迁移 | Alembic，`alembic upgrade head` 随部署执行 |
| 备份 | 每日 `pg_dump` 压缩 + 保留 14 天，产物可另存 COS |
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

## 8. 对象存储

**腾讯云 COS（已开通）**；桶名 / region / 密钥**待定**（见 §15）。代码里现有默认桶名
`site-inspection-1322296918`（ap-guangzhou），需确认是否为正式桶。

| 项 | 方案 |
|---|---|
| 目录规划 | `photos/{projectId}/{yyyymm}/{uuid}.jpg`<br>`drawings/{projectId}/{drawingId}/base.png`<br>`reports/{projectId}/{reportId}.{pdf,xlsx,docx}` |
| 权限 | **私有桶 + 短时预签名 URL**（15min~1h），不做公开读 |
| 上传 | **客户端预签名直传**：`POST /files/presign` → PUT/POST 到 COS → `POST /files/complete` 登记。<br>服务器不中转带宽，并**根治 base64 塞 body 撞网关体积限制的老坑** |
| 大文件 | 分片上传（> 20MB） |
| 服务端职责 | 生成缩略图、抽 EXIF（时间/GPS，供水印存证）、计算 `sha256`（去重 + 证据链） |
| 生命周期 | 缩略图/中间产物 90 天；照片、报告长期 |

> ⚠️ **成本提醒**：应用服务器在**阿里云深圳**，COS 在**广州**，跨云走公网要计流量费且更慢。
> 当前量级可忽略；量上来后需评估换同厂商对象存储。

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
| **seq 变更流** | ✅ `bigserial` 严格递增，`seq >` 无边界问题；客户端只需 1 个游标；"什么可同步"集中在一处定义 |

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
| 运维 | `GET /health`（聚合 DB / Redis / COS / AI 上游） |

---

## 14. 部署与运维

```
docker-compose.yml
├── nginx        TLS 终止 · 静态托管 /jianzhu · 反代 /api → api:8000
├── api          FastAPI（uvicorn/gunicorn，2~4 worker）
├── worker       后台任务（AI 批处理 / 报告 / 缩略图）
├── postgres     16-alpine，卷 pgdata，不开公网端口
├── redis        7-alpine，卷 redisdata
└── minio        （可选，本地开发替代 COS）
```

| 项 | 方案 |
|---|---|
| 环境 | dev / staging / prod 三套 |
| 域名 | `<待定>`（见 §15）；静态站 `/jianzhu/` 与 API 同域 |
| 密钥管理 | 全部环境变量 + `.env`（不入库、不进镜像）；现有 DashScope Key 沿用服务器环境变量 |
| CI/CD | GitHub Actions：构建镜像 → 服务器 `docker compose pull && up -d`；迁移 `alembic upgrade head` |
| 回滚 | 镜像 tag 回退 + 迁移脚本必须可回滚 |
| 备份 | PG 每日全量 + 保留 14 天；COS 生命周期策略 |
| 观测 | `/health` 聚合探活、结构化日志、Sentry、慢查询；AI 成本与配额看板 |

---

## 15. 待定项（实施前需补齐）

| # | 项 | 阻塞级别 | 备注 |
|---|---|---|---|
| 1 | **域名** | **阻塞** | 未定。定了才能定 HTTPS 与客户端 `BASE_URL` |
| 2 | **正式 TLS 证书** | **阻塞** | 现有为自签证书，iOS 会直接拒连 |
| 3 | 备案 | 阻塞（若换新域名） | 大陆 443 需备案 |
| 4 | 服务器 | **阻塞** | 复用 `120.24.240.129`（阿里云深圳）还是新开；Docker 是否已装 |
| 5 | **COS 桶** | **阻塞**（上传相关） | 桶名 / region / SecretId / SecretKey / 是否私有 |
| 6 | PostgreSQL | 可后补 | 用 compose 默认值即可先跑 |
| 7 | DashScope | 阻塞（AI 迁移时） | 只需告知服务器上的变量名 |
| 8 | **和风天气 Key** | **⚠️ 尽早导出** | 只在部署机 `server/config.py`，**仓库里没有**；删 CAD 前必须备份 |
| 9 | **业务角色名单** | 可后补 | 设计上不写死（§6.1），先用 admin/editor/viewer |
| 10 | 首个管理员账号 | 可后补 | 建库时 seed |
| 11 | 推送通道 | 可后补 | 可先只做站内消息 |
| 12 | 后端代码位置 | 可后补 | 建议独立新仓库 |
| 13 | 数据合规 | 可后补 | 工地照片含人脸/项目信息，影响留存与权限策略 |

---

## 16. 实施路线

| 阶段 | 周期 | 内容 | 验收 |
|---|---|---|---|
| **P0 骨架与收敛** | 1–2 周 | 新仓库 + compose（PG/Redis）+ Alembic 首版建表 + JWT 登录 + 统一入口 + `/api/v1/ai/vision` 接管（含 schema 校验、记账）+ 天气迁移 | 客户端改一个 `BASE_URL` 后，**现有 AI 识别与天气功能零回归**；旧 `/api/vision` 保留转发 |
| **P1 主链上云** | 2–3 周 | 项目 / 图纸 / 成员 / 缺陷 CRUD + 缺陷事件状态机 + COS 上传（预签名直传）+ 客户端 Repository 本地化 + SyncEngine（缺陷先行） | 两台设备协作一条缺陷：A 记录 → B 处置 → 施工方回复，双方状态一致且离线可写 |
| **P2 全量同步 + 分享** | 2–3 周 | 巡场 / 量测 / 量房 / 拍照验收上行 + 增量同步 + 报告分享链接 + 站内通知 | 施工方扫码打开分享链接逐条回复；报告在线可查 |
| **P3 治理与增值** | 持续 | AI 缓存与成本看板、缺陷知识库 RAG（`/ai/suggest`）、跨项目统计、多项目/多租户、审计合规 | AI 成本可见；整改建议来自历史缺陷库 |

---

## 17. 风险与明确不做

**风险**

| 风险 | 对策 |
|---|---|
| 离线优先 + 多人协作的冲突复杂度 | 只对「缺陷」主链做事件溯源，其余实体 LWW；不引入 CRDT |
| 「同步」是最容易出错的部分（丢数据/重复数据） | 幂等键 + seq 严格递增游标 + 游标过期全量重同步；P1 先只做缺陷一条链打通 |
| 团队 1–3 人，运维税是最大敌人 | 模块化单体 + Compose，不上 K8s / 微服务 |
| 现有 3 个硬编码 host、自签证书 | P0 一次性收敛 |
| 跨云对象存储流量成本 | 先按量观察，量级上来再评估换同厂商 |

**明确不做**：Kubernetes、微服务拆分、GraphQL、自建 IM、实时协同（CRDT/WebSocket 协同编辑）、
自研对象存储、**任何 CAD 转换能力**（已剥离至独立项目，见 `CAD_MIGRATION_BACKUP.md`）。
