# 后端设计

> 项目：「蓝图落地」工地验收 App（深圳市建筑设计研究总院 · 环境院 AI 中心）
> 定位：**技术选型已定 → 本文档设计后端的具体内容**（表结构 · 接口 · 同步 · 存储 · AI 接入 · 权限）。
> 版本：**v3.2 · 2026-09-22** · 状态：**待开发**

---

## 1. 前提与范围

### 1.1 技术栈（已定，本文档不再讨论）

> 完整论证见同目录《蓝图落地\_后端技术选型（定稿）.md》；本节只列落地要遵守的结论。

| 层          | 选型                                                          | 落地要点                                                                                     |
| ----------- | ------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| 语言 / 框架 | **Python 3.12 + FastAPI**                                     | 自动出 `openapi.json`（前后端契约，见 §5.8）                                                  |
| ORM / 迁移  | **SQLAlchemy 2.0 async（`asyncpg`）+ Alembic**                | 迁移从第一天就有；⚠️ **3 处必须手写 SQL**：部分索引、GIN、`pg_advisory_xact_lock`（§6.2）    |
| 校验        | **Pydantic v2**                                               | 请求 / 响应模型即 schema —— 也是"AI 返回落库"的校验层（§8）                                  |
| 数据库      | **PostgreSQL**（版本由运维提供的实例决定）                    | 依赖 `pg_advisory_xact_lock` / `gen_random_uuid` / `pg_trgm`（§2.1）                         |
| 缓存 / 队列 | Redis —— **第一版不装**                                       | 会话吊销 / 限流 / AI 缓存 / 任务队列初期都能用 PG 顶掉；有压力再加，接口层不用改             |
| 对象存储    | **阿里云 OSS · 华南1（深圳）· 私有读**                        | 缩图走 `x-oss-process`，服务端不做图（§7）                                                   |
| 认证        | **JWT**（access 15min + refresh 30d 轮换）                    | 与客户端 `UserSession` 一一对应（§3.3）                                                      |
| 密码哈希    | **Python 标准库 `hashlib.scrypt`**                            | **镜像不引入任何需要编译的依赖**                                                             |
| 依赖管理    | **`uv` + `pyproject.toml`（`uv.lock`）**                      | 零原生依赖 → 构建确定、可复现                                                                |
| 观测        | **structlog**（JSON 到 stdout）+ Sentry + `GET /health`       | k8s 下日志不写文件（§11）                                                                    |
| 部署        | **k8s**（由团队内运维成员执行）；应用侧交付两个镜像 + 配置项 | `api`（本文档对象）+ `admin`（后台界面，独立仓库）；对代码的约束见 §11                       |

### 1.2 本文档的范围

表结构与索引 · 接口清单与角色权限 · 同步协议 · 对象存储用法 · AI 接入 · 权限模型 · 部署对代码的约束 · 实施路线。

### 1.3 三个仓库

| 仓库                 | 是什么                              | 与本文档的关系                                     |
| -------------------- | ----------------------------------- | -------------------------------------------------- |
| `site-patrol`        | Flutter App（iOS / Android / Web）  | 接口的主要消费方；其数据模型是本文档表结构的来源   |
| **`site-patrol-backend`** | **业务后端（本文档的设计对象）**    | ——                                                 |
| `site-patrol-admin`  | 后台操作界面（Vue 3 + Vite，静态）  | 与 App **共用同一套接口**，不另开命名空间（§4）     |

### 1.4 总体形态

**模块化单体**（不拆微服务）+ 一个异步 Worker。

```
┌────────────────────── 调用方 ──────────────────────┐
│  App（site-patrol）        后台界面（site-patrol-admin）│
└───────────────────────────┬────────────────────────┘
                            │ HTTPS · 单一入口 /api/v1/** · JWT
┌───────────────────────────▼────────────────────────┐
│ Ingress（TLS · 限流 · 访问日志）—— 运维成员             │
├────────────────────────────────────────────────────┤
│ 业务服务（FastAPI · 无状态 · 可多副本）                │
│  auth · users · projects · drawings · defects       │
│  · captures · patrol · measure · reports            │
│  · progress · sync · files · notifications · ai      │
├────────────────────────────────────────────────────┤
│ PostgreSQL（主数据 + 同步变更流）                      │
│ 阿里云 OSS（照片 / 图纸 / 报告，私有读）                │
│ Worker（AI 批处理；第一版与 api 同镜像、不同启动命令） │
└────────────────────────────────────────────────────┘
                            │ 内部转发（不搬入）
                    ┌───────▼────────┐
                    │ 现有 AI 网关    │ 多项目共用，留原位（§8）
                    └────────────────┘
```

> **单入口 `https://<域名>/api/v1/**`** —— 零 CORS、复用证书、原生端一致。
> `GET /health` 不在 `/api/v1` 下（探针用，见 §11.2）。

### 1.5 设计原则

| # | 原则 | 说明 |
|---|---|---|
| 1 | **离线优先** | App 本地是主副本，后端是汇集点与协作端 |
| 2 | **顺着客户端既有模型建表** | 客户端模型即契约（§2.3）；不另创一套字段命名 |
| 3 | **权限点而非角色** | 角色是数据不是代码，加角色不发版（§3.1） |
| 4 | **不带包袱** | 不做兼容层；同步所需字段（`client_id` / `version` / `deleted_at`）**建表即带** |
| 5 | **成本可见** | AI 调用与 OSS 流量必须可记账、可看板 |

---

## 2. 数据库设计

### 2.1 实例与落地口径

| 项       | 方案                                                                                                                                                                                    |
| -------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 实例     | **由运维成员提供 PostgreSQL 实例**（托管或集群内 Operator；机型 / 数据盘 / 高可用 / 备份归运维成员）。应用侧**只依赖 `DATABASE_URL`** → 换实例、换集群都不改代码                            |
| 网络     | **不开公网端口**；只接受集群内网访问                                                                                                                                                    |
| 字符集   | UTF8；**全部时间列 `timestamptz`**                                                                                                                                                      |
| 扩展     | `pgcrypto`（`gen_random_uuid`）、`pg_trgm`（规范条款 / 缺陷文本模糊召回 Top20）；PostGIS 暂不装                                                                                         |
| 迁移     | **Alembic**，每个 migration 必须**向前兼容**（新增字段可空、不删旧字段）；**执行方式待与运维成员确认**（§11.3）                                                                          |
| 备份     | **由运维成员负责**。应用侧的补充要求：保留 ≥7 天、可恢复到任意天；另建议每日 `pg_dump -Fc` 转存 OSS `blueprint-backup` 桶（该桶 30 天自动删除）作独立副本                              |
| 规模预估 | 3 人团队 + 少量项目，任意规格实例都够；**照片等二进制一律不入库**（走 OSS）                                                                                                             |

### 2.2 公共列约定（**建表即带，事后补极难**）

> 与客户端 `SyncMeta`（`lib/data/sync_meta.dart`）对齐：客户端把这 7 个字段**平铺**在实体 JSON 顶层，
> 键名为 `clientId` / `version` / `createdAtMs` / `updatedAtMs` / `serverUpdatedAtMs` /
> `deletedAtMs` / `createdBy`；**时间一律以 epoch 毫秒传输**，服务端在边界转 `timestamptz`。

```
id                 text PK            客户端 ULID（26 位）或服务端 uuid
client_id          text               客户端生成（ULID），唯一索引 → 幂等
version            int   default 1    每次写入 +1
created_at         timestamptz        客户端创建时间
updated_at         timestamptz        客户端修改时间（不可信，仅展示）
server_updated_at  timestamptz        服务端写入时间（权威）
deleted_at         timestamptz        软删；NULL = 未删
created_by         text → users.id
```

> **`client_id` 是 ULID 文本，不是 UUID**：48bit 时间戳 + 80bit 随机，字典序即时间序、
> 多端并发生成不撞号，且字符集排除了易混淆的 `I/L/O/U`。客户端 `newId()` 生成，同毫秒内自增保证单调。
>
> **哪些表带这组列**（= 客户端**可写**实体）：
> `memberships` · `defects` · `captures` · `measure_sessions` · `room_scans` ·
> `patrol_plans` · `patrol_records` · `progress_entries` · `reports` · `site_locations`。
>
> **不带**（= 服务端维护、客户端只读的档案类）：`orgs` / `users` / `projects` /
> `drawings` / `drawing_versions` —— 这些走**全量拉取覆盖**，数据量极小，
> 不做增量同步，因此不需要 `client_id` 与软删列。

### 2.3 表结构（23 张 = 客户端建模 16 + 服务端 7）

> **阅读约定**
>
> - 标 **jsonb** 的列：**原样存客户端 `toJson()` 结构**，服务端不解析；
> - 标 `*` 的列：客户端模型里有这个**展示字段**，服务端可由 FK/join 回填，不必单独维护；
> - 客户端未建模的表：服务端自有，客户端只消费其投影；
> - 所有业务表都**必须带 `project_id`**。

#### 契约来源（**先看这里**）

表结构不是凭空设计的 —— 每一张表对应客户端的一个模型。客户端模型已按**域**拆成 11 个文件，
`lib/data/models.dart` 只做 re-export（**唯一契约入口**，barrel，已完整覆盖）。
下表「入口文件」= 后端打开那一个文件即可对照字段。

| 域                | 入口文件                       | 实体                                                                      | 去向                                                                     |
| ----------------- | ------------------------------ | ------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| 账号与组织        | `models/account.dart`          | `Org` `Discipline` `User` `Membership`                                    | `orgs` `disciplines` `users` `memberships`（`roles` 服务端自有，入口＝后台界面，§3.1） |
| 认证授权          | `models/auth.dart`             | `UserSession` `AuthTokens` `LoginResult` `AuthProfile` `PermissionScope`  | **不建表**：`/auth/*` 响应载体 + 本机会话                                 |
| 项目档案          | `models/project.dart`          | `Project` `Party` `Milestone` `SiteLocation` `ProgressEntry`              | `projects` `site_locations` `progress_entries`（**无 `floors` 表**）     |
| 缺陷              | `models/defect.dart`           | `Defect` + 4 个分级枚举                                                   | `defects` `defect_events`                                                |
| 图纸与版本        | `models/drawing.dart`          | `Drawing` `DrawingVersion` `Hotspot` `Calibration`                        | `drawings` `drawing_versions`（`files` 服务端自有）                      |
| 拍照验收          | `models/capture.dart`          | `CaptureRecord` `CaptureDefectItem` `VlDefect`                            | `captures`                                                               |
| 量尺              | `models/measure.dart`          | `MeasureSession` `MeasureItem` `PhotoCalib`                               | `measure_sessions`                                                       |
| 巡场              | `models/patrol.dart`           | `PatrolPlan` `PatrolRecord` `PatrolPoint` `CheckIn`                       | `patrol_plans` `patrol_records`                                          |
| 量房              | `models/room.dart`             | `RoomScanRecord` `RoomWall` `WallOpening`                                 | `room_scans`                                                             |
| 报告归档          | `models/report.dart`           | `ReportRecord`                                                            | `reports`                                                                |
| AI 视觉（调用侧） | `lib/data/vision_service.dart` | `VisionResult` `DefectItem` `AnchorDetection` `GridDetection` `MeasureTarget` | **不建表**：落 `ai_calls.response`（§8）                                 |
| 周报导出          | `lib/data/weekly_report.dart`  | `WeeklyReport` `WeeklyPhoto` `WeeklyProgressRow` …                        | **不建表**：正文客户端生成（§9）                                         |
| 同步元数据        | `lib/data/sync_meta.dart`      | `SyncMeta`                                                                | 各表公共列（§2.2）                                                       |

**账号与组织**

| 表            | 列                                                                                                                                                 | 客户端模型                              |
| ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------- |
| `orgs`        | id, name, short_name, type, sort                                                                                                                   | `Org`                                   |
| `disciplines` | code PK, name, sort, is_system                                                                                                                     | `Discipline`                            |
| `users`       | id, name, username(uniq), org_id, role\*, avatar, phone, email, status, password_hash, last_login_at                                               | `User`                                  |
| `memberships` | id, user_id, project_id, org_id, role_code, role_name\*, **disciplines text[]**, **permissions jsonb**, status, uniq(user_id, project_id) + 公共列 | `Membership`                            |
| `roles`       | code PK, name, description, **permissions jsonb**（权限点 code 数组）, sort, is_system, updated_at                                                  | —（客户端只消费 `Membership.roleCode`） |

> `users.name` 是**姓名**，`username` 是**登录名**（两者都有）。
> `memberships.permissions` 直接落权限点数组 —— **代码只认权限点、不认角色名**（§3.1）。
>
> **`roles` 的三点口径**（表格只列字段，语义在 §3.1）：
>
> - `permissions` 里的每个元素必须是 §3.1 权限点目录中的 code，**写入时逐个校验**，目录外一律拒绝。
> - `is_system = true` = 内置角色（第一版 seed 的 7 条）；不可删、`code` 不可改，`name` / `description` /
>   `permissions` 可改（负责人确实要能调自己的权限）。
> - **「在用人数」不建列**：由 `memberships` 按 `role_code` 聚合，属派生数据 ——
>   存计数列就得处理一致性与并发，不值当（界面侧见《后端操作界面设计》§4.6）。
>
> **`memberships` 是「职责 × 专业 × 单位」三个正交维度**，不要把专业拼进 `role_code`：
>
> | 维度 | 列                        | 回答               |
> | ---- | ------------------------- | ------------------ |
> | 职责 | `role_code` + `permissions` | 能做什么动作       |
> | 专业 | `disciplines`（`text[]`） | 能看 / 管哪一类数据 |
> | 单位 | `org_id`                  | 代表哪一方         |
>
> - **`disciplines` 空数组 = 不限专业**（项目负责人 / 监理 / 管理类），不要造 `'all'` 伪值；
>   驻场、施工方、监理的成员**同样带专业**（他们也是按专业分包的）。
> - 专业与权限点是**「与」关系**：`can('defect.reply')` **且** 缺陷专业被覆盖。
>   App 端唯一判定入口是 `PermissionScope.canOn(permission, categoryCode)`；
>   `Membership` 只承载数据，不做判定（避免记录级与合并级两套语义）。
> - **`disciplines` 的 code 与 `defects.category` 复用同一套取值**，否则「暖通负责人看暖通缺陷」
>   要维护映射表。⚠️ 客户端 `DefectCategory` 是 Dart enum（未知 code 回落 `other`）→
>   **扩展专业清单必须与客户端发版同步**；`memberships.disciplines` 是 String，不受此限。
> - **第一版范围**：后端 seed **只 `structure` 一条**，业务上只做「结构专业」或「不分专业」；
>   **不实现按专业过滤的逻辑**（空数组天然放行全部）。这一维度只是先把结构与取值定下来，
>   后续加专业（暖通 / 给排水 / 幕墙…）不改表、不发版。

**项目档案**

| 表               | 列                                                                                                                                                        | 客户端模型                                              |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| `projects`       | id, name, client, location, status, site_area, floor_area, beds, concept, lat, lng, **parties jsonb**, **milestones jsonb**, **measure_thresholds jsonb** | `Project` / `Party` / `Milestone` / `MeasureThresholds` |
| `site_locations` | id, project_id(可空), name, address, lat, lng, altitude + 公共列                                                                                          | `SiteLocation`                                          |

> **楼层不单独建表**：`Floor` 是**图纸（图名）解析出的标签**，随 `drawings` 走，没有独立录入入口。
> `floor` / `building` 作为普通列落在 `defects` / `captures` / `measure_sessions` /
> `patrol_plans` / `patrol_records` 上。后台只需维护图纸（含「楼栋 / 楼层」字段），
> App 端楼层列表由图纸派生。
>
> **`site_locations` 由项目内用户填写**（App 拍照页「附近定位」）：
> `project_id` 非空 = 项目专属点位，`null` = 跨项目公共地标；客户端可写 → 带公共列。
> 它是**无信号时手选定位**的兜底来源，**不构成位置证据**（取址优先级：设备定位 → 项目坐标 → 手选点）。
>
> `milestones[]` 里 `done` 缺省时由 `actualDate` 推导，服务端只需存 `date`（计划）+ `actualDate`（实际）。
> `measure_thresholds` 就是项目级量尺门槛（`tolMm` / `tolPct` / `judgeMaxErrorMm`）。

**图纸与版本**

| 表                 | 列                                                                                                                                                                                                                  | 客户端模型                                   |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------- |
| `drawings`         | project_id, key(uniq per project), title, crumb, variant, discipline, sort, published_version_id → `drawing_versions.id`, w\*, h\*, **hotspots jsonb**\*                                                            | `Drawing`                                    |
| `drawing_versions` | id, drawing_id, version, version_date, state(`draft`/`published`/`archived`), base_image_path, width, height, bounds, **hotspots jsonb**, **calibration jsonb**, calibration_updated_at, published_at, published_by | `DrawingVersion` / `Hotspot` / `Calibration` |
| `files`            | project_id, owner_id, kind(`photo`/`drawing`/`report`/`reply_photo`/`thumb`), object_key, mime, size, **sha256**, width, height, **exif jsonb**                                                                     | —（客户端不建模）                            |

> `drawings` 上的 `w` / `h` / `hotspots` 是「**当前发布版本**」的冗余快照（渲染端直接用，不必 join）；
> 权威数据在 `drawing_versions`。
>
> **校准与热点都绑版本**：`calibration` 落在 `drawing_versions` 行上。图纸改版 → 新版本行没有
> `calibration` → 客户端按「当前发布版本」取校准，**旧版本的校准不会被套用**，
> **不做自动坐标迁移**。
>
> `state='published'` 同一 `drawing_id` 只允许一行，旧版置 `archived` 锁只读 ——
> 发布的一致性与事务边界见 §4.2。
>
> **待设计**：**「后台发布的校准」与「App 端本机微调」的合并与优先级规则** ——
> 本次不下定论，后续单独设计。已知诉求：后台那份为默认值、App 微调**不覆盖**它。
> （本版后台界面不做校准，见 §4.3。）

**缺陷主链**

| 表              | 列                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | 客户端模型        |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------- |
| `defects`       | id, project_id, drawing_id, drawing_version_id, part, type, category, severity, importance, status, anchor, floor, building, gps, lat, lng, alt, world_x, world_y, found_at, reporter_id, reporter\*, resp_unit, resp_user_id, **tags jsonb**, note, seed, suggestion, source_capture_id, source_capture_index, photo_file_id, photo_path\*, photo_hash, watermark_serial, **photos jsonb**, reply, reply_by_id, reply_at, reply_photo_file_id, close_note, completion, designer_action, designer_note, designer_by_id, designer_at + 公共列 | `Defect`          |
| `defect_events` | defect_id, actor_id, **action**, payload jsonb, created_at                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | —（服务端事件流） |

> `defects` 上的 `reply*` / `designer*` 是**当前态**（便于列表查询与报告渲染）；
> `defect_events` 是**事件流**（审计 + 冲突解决）。两者由**同一写路径**同时更新。
> `action` ∈ `create/update/assign/reply/designer_fix/designer_confirm/onsite/reject/close/reopen`
>
> **时间字段**：客户端 `ts` / `replyTs` / `designerTs` 是展示文本（`yyyy-MM-dd HH:mm[:ss]`），
> 模型另提供 `tsMs` / `replyTsMs` / `designerTsMs` 取 epoch 毫秒 → 入库为
> `found_at` / `reply_at` / `designer_at`。
>
> `photo_path` 是**本地相对路径**，只作溯源；正式照片走 `files`。
> `photo_hash` + `watermark_serial` 是**取证四要素**中的两个（另两个是 GPS 与拍摄时间），
> **必须落库** —— 只烧在图片像素里等于数据库查不到。

**现场采集**

| 表                 | 列                                                                                                                                                                                                                                       | 客户端模型       |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| `captures`         | id, project_id, drawing_id, drawing_version_id, floor, anchor, world_x, world_y, captured_at, gps, alt, reporter_id, reporter\*, photo_file_id, photo_path\*, note, **ai_result jsonb**, **confirmed_result jsonb**, ai_call_id + 公共列 | `CaptureRecord`  |
| `measure_sessions` | id, project_id, drawing_id, drawing_version_id, floor, tol_mm, tol_pct, **calib jsonb**, **items jsonb**, updated_at + 公共列                                                                                                            | `MeasureSession` |
| `room_scans`       | id, project_id, name, room_use, source, scanned_at, **walls jsonb**, closure_delta_mm, net_height_mm, drawing_id, drawing_version_id, **checks jsonb**, note + 公共列                                                                    | `RoomScanRecord` |
| `patrol_plans`     | id, project_id, drawing_id, drawing_version_id, name, floor, **points jsonb**, total_km, updated_at + 公共列                                                                                                                             | `PatrolPlan`     |
| `patrol_records`   | id, plan_id, project_id, drawing_id, drawing_version_id, operator_id, name, started_at, finished_at, dist_km, point_count, issue_count, **track jsonb**, **checkins jsonb**, checkpoint_total + 公共列                                   | `PatrolRecord`   |
| `progress_entries` | id, project_id, milestone_id, status, date, note, **photos jsonb**, declared_by, source + 公共列                                                                                                                                         | `ProgressEntry`  |

> 上述 JSONB 字段**直接存客户端 `toJson()`**，服务端不解析几何，只做检索与统计 —— 最低成本、零阻抗。
> `captures.ai_result` = AI 原始识别；`confirmed_result` = 同一数组加上人工确认/转入状态。
> 二者是「缺陷知识库反哺设计」的原始数据来源（§8）。
>
> **`progress_entries.source` 区分填报身份**，⚠️ **两者不得混标**：
>
> | 值           | 含义                                       | 身份可信度 |
> | ------------ | ------------------------------------------ | ---------- |
> | `admin`      | **第一版唯一写入路径**：后台界面按里程碑录入 | 可信       |
> | `contractor` | 施工方免登录自报（分享页，**v1.2 起**）      | 自报       |
>
> 后台录入的数据若标成 `contractor`，报告会凭空多一条免责声明；
> 反之则把不可证的身份说成可信。客户端**构造默认 = `admin`**（漏传不该误标自报），
> `fromJson` 缺字段时仍回落 `contractor`（那批历史数据只可能是自报语义）。
>
> **量尺会话的唯一键口径**：客户端本地按「项目 + 图纸」**一个格子**存
> （存储键 `measure:<projectKey>:<drawingKey>`），换图纸版本会**覆盖**同一格子，
> 与 §6.5「会话型数据整份覆盖、后写胜」一致。
> 因此服务端用 `uniq(project_id, drawing_id)`，**不要**把 `drawing_version_id` 放进唯一键；
> `drawing_version_id` 仍照常落库（说明"这次量的是哪版图"）。
> 若将来需保留**逐版本**量测历史，客户端需改存储键 + 迁移旧键，届时再定。
> 对照：需要按版本回溯的 `defects` / `captures` 是**逐条记录**（不是单格子），不会被覆盖。

**平台**

| 表              | 列                                                                                                                                                                                          | 客户端模型                |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------- |
| `reports`       | id, project_id, title, period, reporter\*, **formats jsonb**, defect_count, open_count, done_count, urgent_count, note, created_at, file_id, share_token, share_expires_at, status + 公共列 | `ReportRecord`            |
| `ai_calls`      | project_id, user_id, task_type, model, prompt_version, **image_sha256**, request jsonb, response jsonb, input_tokens, output_tokens, latency_ms, cost, cache_hit, status, error             | —（客户端只消费返回结构） |
| `notifications` | user_id, project_id, type, title, body, ref_type, ref_id, read_at                                                                                                                           | —                         |
| `audit_logs`    | actor_id, project_id, action, entity, entity_id, before jsonb, after jsonb, ip, ua                                                                                                          | —                         |
| **`changes`**   | **seq bigserial PK**, project_id, entity, entity_id, op(`upsert`/`delete`), changed_at —— 同步变更流，见 §6                           | —                         |

> `reports.formats` 是**数组**：同一份报告导出 PDF / Word / Excel / 网页链接时**合并为一条**，
> 不做重复建卡。客户端归档只存元数据，正文按需重导（§9）。
>
> `audit_logs` 与 `defect_events` 的分工：前者是**面向管理动作**的通用留痕（谁在后台改了什么），
> 后者是**缺陷业务语义**的事件流。二者不互相替代。

**不建表的结构**

| 结构                                                | 原因                                                      |
| --------------------------------------------------- | --------------------------------------------------------- |
| `MeasureThresholds`                                 | 已并入 `projects.measure_thresholds jsonb`                |
| `ArScaleCalibration`                                | 本机尺度校正，**不跨设备共享**（机型 / 系统版本相关）     |
| `TimelinePhoto`                                     | 派生数据：由缺陷 + 照片按部位实时生成                     |
| `PhotoAnchor` / `AnchorPhoto`                       | 应改为派生（按「图纸版本 + 坐标」对缺陷聚类）             |
| `Floor` / `Floor.cached` / `Floor.progress`         | **不建表**：由图纸（图名）解析出的标签；后两者是本地缓存态 |
| `CaptureArgs` / `MeasureArgs` / `RoomScanArgs` / …  | 路由参数（非持久化）                                      |
| `VisionResult` / `DefectItem` / `AnchorDetection` / `GridDetection` / `MeasureTarget` | AI 调用侧结构，落 `ai_calls.response` |
| `WeeklyReport` 系列                                 | 报告正文客户端生成，后端不建表                            |
| **权限点目录**（`GET /permissions`）                 | **代码常量**：权限点硬编码在代码里，中文名与分组只服务界面显示；**不落库**（§3.1） |

### 2.4 索引要点

```sql
defects(project_id, status)
defects(project_id, server_updated_at)
defects(client_id)                         -- 幂等（ULID 文本）
defects(project_id, drawing_version_id)    -- 按图纸版本回溯坐标
defects(source_capture_id)                 -- 验收记录 ↔ 缺陷 回流
changes(project_id, seq)                   -- 增量拉取（核心）
files(sha256)                              -- 去重 / 证据链
ai_calls(image_sha256, prompt_version)     -- 结果复用
roles(code) / memberships(user_id, project_id)
memberships(role_code)                     -- 「角色在用人数」聚合 + 删角色前查引用（§3.1 约束 3）
memberships GIN(disciplines)               -- 按专业过滤（「专业负责人只看本专业」）
drawing_versions(drawing_id, state)        -- 取当前发布版本
drawings(project_id)                       -- 档案类按项目全量拉取
site_locations(project_id)                 -- 按项目取附近定位点（NULL = 公共地标）
site_locations(client_id)                  -- 幂等（客户端填写）
```

---

## 3. 用户体系与权限

### 3.1 核心设计：**代码只认权限点，不认角色**

**角色名单已定（7 个，见 §5.5），但仍不写死枚举** —— 名字放数据，代码只认权限点：

```
roles(code PK, name, description, permissions jsonb, sort, is_system)
disciplines(code PK, name, sort, is_system)                        -- 专业字典
memberships(id, user_id, project_id, org_id, role_code,
            disciplines text[], permissions jsonb, created_at)      -- 项目级；三维度
```

代码里只硬编码**权限点**（稳定的业务动作，与 §5.5 的矩阵一一对应）。以下 24 个即**权限点目录**
—— ⚠️ **它是代码常量：不建表、不是配置项**。增删权限点 = 改代码 + 发版：

| 分组       | 权限点                                                                                    | 中文名（界面显示用）                                       |
| ---------- | ----------------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| 项目       | `project.read` · `project.create` · `project.update`                                      | 查看项目 · 新建项目 · 编辑项目                             |
| 成员与账号 | `member.manage` · `user.create`                                                           | 管理成员 · 就地建号                                        |
| 图纸       | `drawing.read` · `drawing.manage` · `drawing.calibrate`                                   | 查看图纸 · 管理图纸 · 校准图纸                             |
| 缺陷       | `defect.read` · `defect.create` · `defect.reply` · `defect.update` · `defect.assign`      | 查看缺陷 · 上报缺陷 · 回复缺陷 · 修改缺陷状态 · 指派缺陷   |
| 现场作业   | `patrol.run` · `measure.write` · `room.write` · `capture.create` · `siteloc.write`        | 巡场 · 量尺 · 量房 · 拍照验收 · 场地定位                   |
| 进度与报告 | `progress.read` · `progress.write` · `report.export`                                      | 查看进度 · 填报进度 · 导出报告                             |
| 同步       | `sync.push` · `sync.pull`                                                                 | 同步上行 · 同步下行                                        |
| AI         | `ai.invoke`                                                                               | 调用 AI 识别                                               |

`GET /permissions`（§5.3）返回的就是这张目录 —— **中文名与分组只活在代码里**：
库里不存显示名，前端也不硬编码（界面侧见《后端操作界面设计》§4.6）。

**角色 → 权限点的映射放数据**（`roles.permissions`），加角色不改代码、不发版。
每个角色的权限点取值 = **§5.5 矩阵里它那一列**。

- 角色由**后台界面的「角色管理」页维护**（《后端操作界面设计》§4.6）：新增角色、勾权限点都在界面上做。
  后端 seed 一次 §5.5 的 7 条内置角色作为**初始数据** —— 它是数据来源之一，不是唯一入口。
- **写 `roles.permissions` 时必须逐个校验是否在目录内**，目录外的 code 一律拒绝（400）。
  这类脏数据**存进去也不生效且不报错**，是本模块唯一的静默故障源。
- 校验规则：`(user, project) → role.permissions → 是否含所需权限点`。
  **`role` 不放 JWT**（避免权限变更后旧 token 继续生效）。
- ⚠️ **`memberships.permissions` 是下发快照，不是校验依据**（§2.3）：
  校验永远现读 `roles.permissions`；快照只是给 App 本地判定的副本。
  因此**角色权限点被改动后，同一 `role_code` 的所有成员快照需刷新**（同事务或后台任务），
  否则 App 端会按旧快照放行 / 拦截。第一版 App 不消费权限点（§5.5 末注），
  该刷新**不阻塞第一版**，但改角色的接口必须**预留这个动作**（否则将来是补不回来的静默错误）。
- ⚠️ **第一版只按权限点放行，不按专业过滤**（§2.3）：`memberships.disciplines` 先只做数据落位 ——
  §5.5 矩阵里「本专业」那几格，**实现上暂时等同「本项目」**。

**角色的四条数据约束**（后台「角色管理」页直接受它约束，界面侧见《后端操作界面设计》§4.6）：

| # | 约束                                                                | 违反后果                                             |
| - | ------------------------------------------------------------------- | ---------------------------------------------------- |
| 1 | `code` 建后**不可改**（要换只能新建一条 + 迁成员）                   | 既有 `memberships.role_code` 全部悬空                |
| 2 | `is_system = true` 的内置角色**不可删**，`code` 不可改               | 同上；且 seed 会把它重新写回来，产生两份语义          |
| 3 | **有成员在用**（`memberships.role_code` 命中）的角色**不可删**       | 成员权限悬空，且无报错                               |
| 4 | `admin` 行**只读**（权限点恒为全部 24 个）                           | 可把操作者自己锁在门外（本界面唯一使用者）            |

> 删除一律用**先查引用再删**，不靠数据库外键报错兜底 —— 报错信息在界面上落不成人话。

### 3.2 项目可见性

`memberships` 是**项目可见性的唯一依据** —— 没有成员关系就看不到该项目，
这条对后台界面与 App 同时生效。

### 3.3 认证

```
POST /api/v1/auth/login      → { access, refresh, expiresAt, user, permissions }
POST /api/v1/auth/refresh    → 轮换 refresh（旧的立即失效）
POST /api/v1/auth/logout     → refresh 吊销（第一版不装 Redis → 落表 + `status`）
GET  /api/v1/auth/me         → 当前用户 + 项目列表 + 各项目权限
```

`GET /auth/me` 是后台界面与 App 的**共同入口**：登录后一次拿到"我能看到哪些项目、在各项目能做什么"。

### 3.4 施工方接入（两种）

| 方式           | 说明                                                                                   |
| -------------- | -------------------------------------------------------------------------------------- |
| 受限账号       | 只看指派给自己的缺陷 + 可回复                                                          |
| **分享 token** | 免登录网页 `/share/{token}`，只读 + 可回复，短有效期（对应「施工方网页协作链接」需求） |

---

## 4. 后台操作界面的后端支撑

> 后台界面（`site-patrol-admin`）自身的产品设计见《蓝图落地\_后端操作界面设计.md》；
> 本节只写**后端要为它提供什么**。
>
> **一句话原则：后台界面不新开一套接口。** 它是本文档接口的一类调用方，
> 与 App 共用同一套 `/api/v1/**` —— 同源、同契约、同一套权限校验。

### 4.1 界面 → 后端能力的对应

界面共 **6 个页面**（登录 / 项目列表 / 成员 / 图纸 / 进度 / 角色管理），后端侧对应关系：

| 页面     | 要做的动作                                     | 落到哪张表                                | 走哪个接口（§5.2~5.4）                                               |
| -------- | ---------------------------------------------- | ----------------------------------------- | -------------------------------------------------------------------- |
| 登录     | 管理员账号 + 密码                              | `users`                                   | `POST /auth/login` · `GET /auth/me`                                  |
| 项目列表 | 列表 / 新建（含里程碑与参与方）                | `projects`（`milestones`/`parties` jsonb） | `GET/POST /projects`                                                 |
| 成员     | 加人 / 改角色 / 移除 / **就地建号**             | `memberships` · `users`                   | `GET/POST/DELETE /projects/{id}/members` · `POST /users`             |
| 图纸     | 上传 / 改名与楼层 / 传新版本 / 删除 / **发布**  | `drawings` · `drawing_versions` · `files` | `POST /files/presign` → `/files/complete` → `POST /drawings/{id}/versions` → `POST /drawings/{id}/versions/{vid}/publish` |
| 进度     | 按里程碑回填（状态 / 日期 / 备注 / 照片）       | `progress_entries`（`source=admin`）      | `GET/POST /progress-entries`                                          |
| 角色管理 | 新增角色 / 勾权限点 / 改名与说明 / 删除                 | `roles`（权限点目录＝代码常量，§3.1）       | `GET/POST /roles` · `PATCH/DELETE /roles/{code}` · `GET /permissions` |

**三处必须由后端提供的"看不见"的能力**：

1. **就地建号**（成员页）：界面填「姓名 + 手机号 + 单位」时，若 `users` 里没有这个人，
   后端要能在同一请求里建号 + 建成员关系，并返回可用账号。⚠️ `users.username` 唯一，需要防重。
2. **专业字典 seed**：`disciplines`（第一版只 `structure` 一条）由后端在**建库 migration / seed 脚本**里写入
   —— ⚠️ **它至今没有维护页**（界面 6 个页面里没有字典页），但图纸页要选「专业」，
   所以字典**必须在**，否则专业变自由文本（「暖通 / 通风 / 暖通空调」三种写法），
   `memberships GIN(disciplines)` 的过滤会失效。扩专业清单时再加页。
3. **内置角色 seed**（角色管理页）：7 条内置角色（§5.5）由 seed 写入 —— 没有它，
   角色管理页与成员页下拉都是空的。**seed 只是初始数据**：之后的新增角色 / 改权限点全部走界面
   （§5.3 的角色与权限接口），不需要改代码。

### 4.2 「发布」在后端的语义（本界面的关键动作）

**发布是整个链路唯一的显式生效点 —— 上传 ≠ App 能看到。**

| 步 | 服务端动作                                                                                          |
| -- | --------------------------------------------------------------------------------------------------- |
| 1  | 上传完成 → 写 `drawing_versions` 行，`state='draft'`（App 拉不到）                                  |
| 2  | **发布（一个事务内做完 4 件事）**：① 该 `drawing_id` 原有 `published` 行 → `archived`；② 目标行 → `published` + `published_at` / `published_by`；③ 回写 `drawings.published_version_id` / `w` / `h` / `hotspots`；④ **写 `changes` 一条** |
| 3  | 置 `archived` 的行**锁定只读**（`calibration` / 底图不允许再改）                                    |

**硬约束**：

| # | 约束 | 违反后果 |
|---|---|---|
| 1 | 同一 `drawing_id` 任一时刻**只有一行** `state='published'` | App 拉到两张底图 |
| 2 | 发布**必须写 `changes`**，与状态变更同事务 | 状态改了但 App 永远拉不到（静默失效） |
| 3 | **已发布的版本不允许删除** | 历史 `defects` / `captures` 指向它的 `drawing_version_id` → 坐标回溯断裂 |
| 4 | 重复发布同一版本 → **幂等返回**（不报错、不重复写 `changes`） | 界面双击产生两条无效变更 |

### 4.3 后台不做的事（后端相应不留接口位）

| 项                        | 原因                                                                     |
| ------------------------- | ------------------------------------------------------------------------ |
| **图纸校准**              | 本版不在后台界面（见《后端操作界面设计》§5）。`calibration` 列保留，口径见 §2.3「待设计」 |
| 统计 / 概览 / 看板        | 演示不需要                                                               |
| 账号停用 / 重置密码       | 账号个位数，需要时直接改库                                               |
| 项目归档 / 删除 · 批量操作 | 量级不够                                                                 |

---

## 5. 接口清单

统一响应：`{ ok, data, err: { code, msg } }`（与 App 既有调用风格一致）；全部在 `/api/v1/**` 下。

### 5.1 按「数据由谁产出」分三类

| 类                     | 数据由谁产出                | 调用方   | 判据                             |
| ---------------------- | --------------------------- | -------- | -------------------------------- |
| **A · 客户端业务接口** | **现场产生**（App 采集）    | App      | App 的核心业务动作，后台界面不调 |
| **B · 后台录入接口**   | **后台录进来**（App 只读）  | 后台界面 | 没有它，App 打开是空的           |
| **C · 基础与通道**     | ——（与业务数据无关）        | 两边 / 外部 | 登录 · 文件 · 健康检查 · 免登录分享页 |

> **判据看「数据由谁产出」，不看「路径属于谁」。**
> 少数接口两边都会调（如 `GET /projects`：App 要「我参与的项目」、后台要「全部项目」）——
> 同一个接口，**返回范围由 `memberships` 决定，不另开接口**（§3.2）。

**为什么图纸接口（含「查看」）全在 B 类**：App 需要的图纸数据是**通过 `sync/pull` 落到本地**的，
不直接调图纸 REST 接口 —— 所以图纸接口的调用方只有后台界面。这与离线优先的架构一致（§6）。

### 5.2 A 类 · 客户端业务接口（App）

| 模块           | 接口                                                                                                               |
| -------------- | ------------------------------------------------------------------------------------------------------------------ |
| 项目（读）     | `GET /projects` · `GET /projects/{id}`                                                                             |
| 场地位置       | `GET /projects/{id}/site-locations` · `POST/PATCH /site-locations/{id}`（App 拍照页「附近定位」写入，§2.3）          |
| 缺陷           | `GET /defects` · `POST /defects` · `PATCH /defects/{id}` · `POST /defects/{id}/events` · `GET /defects/{id}/events` |
| 巡场           | `GET/POST /patrol/plans` · `GET/POST /patrol/records`                                                              |
| 量测           | `GET/POST /measure-sessions`                                                                                       |
| 量房           | `GET/POST /room-scans`                                                                                             |
| 拍照验收       | `GET/POST /captures`                                                                                               |
| 施工进度（读） | `GET /progress-entries?projectId=&milestoneId=`                                                                    |
| 报告           | `POST /reports` · `GET /reports/{id}` · `POST /reports/{id}/share`                                                  |
| **同步**       | `POST /sync/push` · `GET /sync/pull?sinceSeq=&projectId=&limit=`                                                   |
| AI             | `POST /ai/vision`（缺陷 / 锚物 / 网格 / 目标，按 `task` 区分）· `POST /ai/suggest`                                   |
| 通知           | `GET /notifications` · `POST /notifications/{id}/read`                                                             |

### 5.3 B 类 · 后台录入接口

> 全部**只由后台界面调用**；数据的消费者是 App —— **后台不录，App 就是空的**。

| 模块           | 接口                                                                                                          | 录入什么                                              |
| -------------- | ------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| 角色与权限     | `GET/POST /roles` · `PATCH/DELETE /roles/{code}` · `GET /permissions`                                          | 角色名 / code / 说明 / 权限点勾选（权限点目录＝代码常量，§3.1） |
| 组织与用户     | `GET/POST /orgs` · `GET/POST /disciplines` · `GET/POST /users` · `POST /users/{id}/invite`                     | 单位 · 专业字典 · **就地建号**（§4.1）                |
| 项目           | `POST /projects` · `GET /projects`（全部项目视角）                                                             | 建档（含里程碑 / 参与方）                             |
| 成员           | `GET/POST/DELETE /projects/{id}/members`                                                                       | **可见性的唯一依据**（§3.2）                          |
| 量尺阈值       | `GET/PUT /projects/{id}/measure-thresholds`                                                                    | 项目级 `tolMm` / `tolPct` / `judgeMaxErrorMm`         |
| 图纸           | `GET /projects/{id}/drawings` · `GET /drawings/{id}`                                                           | 查看。**楼层随前者返回，不单独开接口**                |
| 图纸版本       | `GET/POST /drawings/{id}/versions` · `POST /drawings/{id}/versions/{vid}/publish`                              | 上传与**发布**（事务语义见 §4.2）                     |
| 图纸校准       | `PUT /drawings/{id}/versions/{vid}/calibration`                                                                | ⚠️ **本版不接**（校准不在本版界面，§4.3）；接口位保留  |
| 施工进度（写） | `POST /progress-entries`                                                                                       | 第一版由后台登录态录入 → `source=admin`（§2.3）；施工方自报走 `/share/{token}`，**v1.2** |

> **角色与权限这一组只对 `admin` 开放** —— 其余角色的权限点里不含它们，§5.5 矩阵因此不列此组。
> `GET /permissions` 是**只读目录**（不含业务数据），列在这里是因为它只服务角色管理页，
> 与 `roles` 的写入路径同属一个模块。`roles` 的写入校验与约束见 §3.1。
>
> **这一组的模型**（Pydantic，前端照它生成 `types.ts`，不手写字段名 —— §5.8）：
>
> | 模型         | 字段                                                                        | 用在哪                                  |
> | ------------ | --------------------------------------------------------------------------- | --------------------------------------- |
> | `Role`       | `code` · `name` · `description` · `permissions[]` · `sort` · `isSystem` · `memberCount` | 列表 / 详情响应                         |
> | `RoleCreate` | `code` · `name` · `description` · `permissions[]` · `sort`                  | `POST /roles`                           |
> | `RoleUpdate` | `name?` · `description?` · `permissions[]?` · `sort?` —— **无 `code`**       | `PATCH /roles/{code}`                   |
> | `Permission` | `code` · `name` · `group` · `sort`                                          | `GET /permissions`（来自代码常量）      |
>
> - `Role.memberCount` 是**派生字段**（`memberships` 聚合，§2.3），**库里不存**。
> - `RoleUpdate` **刻意不带 `code`** —— 让「建后不可改」（§3.1 约束 1）在**类型层面**就表达出来，
>   前端不会去试、也不会误传。
> - `Permission.name` / `group` 是 §3.1 权限点目录里的**中文显示名与分组**；库里的 `roles.permissions`
>   只存 code 数组，不存显示名。

### 5.4 C 类 · 基础与通道接口（两边共用 / 免登录）

| 模块   | 接口                                                                                                                       |
| ------ | -------------------------------------------------------------------------------------------------------------------------- |
| 认证   | `POST /auth/login` · `/auth/refresh` · `/auth/logout` · `GET /auth/me`（返回结构见 §2.3 的 `LoginResult` / `AuthProfile`） |
| 文件   | `POST /files/presign` · `POST /files/complete` · `GET /files/{id}`（签名 URL）                                              |
| 运维   | `GET /health`（聚合 DB / OSS / AI 上游）                                                                                    |
| 分享页 | `GET /share/{token}`（免登录网页，施工方侧）                                                                                |

### 5.5 业务角色名单与接口权限

**内置名单（seed 的 7 个角色 · `is_system`，不可删、`code` 不可改 —— §3.1 约束 2）**

| code              | 名称                 | 层级     | 数据范围               | 用哪个端     |
| ----------------- | -------------------- | -------- | ---------------------- | ------------ |
| `admin`           | 后台管理员（操作者） | **全局** | **全部项目**           | 后台界面     |
| `project_manager` | 项目负责人           | 项目     | 本项目全部             | 后台 + App   |
| `discipline_lead` | 专业负责人           | 项目     | 本项目 · **本专业**    | App          |
| `designer`        | 设计人员             | 项目     | 本项目 · **本专业**    | App          |
| `site_engineer`   | 驻场工程师           | 项目     | 本项目全部（现场记录） | App          |
| `contractor`      | 施工方               | 项目     | **仅指派给自己的缺陷** | App / 分享页 |
| `viewer`          | 只读（业主 / 监理）  | 项目     | 本项目 · 只读          | App          |

> - **`admin` 是唯一破例**：**不进 `memberships`**，可见性 = 全部项目。它是操作者、不是项目参与者 ——
>   若照 §3.2 走，它一个项目都看不到。
> - 其余 6 个角色活在 `memberships.role_code` 上，**可见性一律由 `memberships` 决定**；
>   专业维度由 `memberships.disciplines` 承载（空数组 = 不限专业，§2.3）。
> - **角色名单由后台界面维护**（§3.1）：seed 的 7 条是**初始数据**；新增角色 / 改权限点走界面，不改代码、不发版。

**角色 → 接口**
（`✓` 允许 · `读` 只读 · `仅指派` 只看得见指派给自己的 · `本项目` / `本专业` = 数据范围 · `—` 不允许）

| 接口（§5.2~5.4）                                        | 类 | 负责人 | 专业   | 设计   | 驻场   | 施工方     | 只读 |
| ------------------------------------------------------- | -- | ------ | ------ | ------ | ------ | ---------- | ---- |
| 认证 `/auth/*`                                          | C  | ✓      | ✓      | ✓      | ✓      | ✓          | ✓    |
| 项目 读                                                 | A  | ✓      | ✓      | ✓      | ✓      | ✓          | ✓    |
| 场地位置 读写                                           | A  | ✓      | ✓      | ✓      | ✓      | —          | 读   |
| 缺陷 读                                                 | A  | 本项目 | 本专业 | 本专业 | 本项目 | **仅指派** | 只读 |
| 缺陷 创建 `POST /defects`                               | A  | ✓      | ✓      | —      | ✓      | —          | —    |
| 缺陷 回复 `POST /defects/{id}/events`                   | A  | ✓      | ✓      | ✓      | ✓      | ✓          | —    |
| 缺陷 改状态 / 指派 `PATCH /defects/{id}`                | A  | ✓      | ✓      | ✓      | ✓      | —          | —    |
| 巡场 · 量测 · 量房 · 拍照验收                           | A  | ✓      | —      | —      | ✓      | —          | —    |
| 进度 读                                                 | A  | ✓      | ✓      | ✓      | ✓      | ✓          | ✓    |
| 报告 生成 / 分享                                        | A  | ✓      | ✓      | —      | ✓      | —          | 读   |
| 同步 `push` / `pull`                                    | A  | ✓      | ✓      | ✓      | ✓      | —          | —    |
| AI `vision` / `suggest`                                 | A  | ✓      | —      | —      | ✓      | —          | —    |
| 通知                                                    | C  | ✓      | ✓      | ✓      | ✓      | ✓          | ✓    |
| 分享页 `/share/{token}`                                 | C  | —      | —      | —      | —      | 免登录     | —    |
| 建项目 · 成员 · 就地建号 · 图纸（上传/发布/删除）· 阈值 | B  | ✓      | —      | —      | —      | —          | —    |
| 图纸 查看                                               | B  | ✓      | 读     | 读     | 读     | —          | 读   |
| 进度 写                                                 | B  | ✓      | —      | —      | —      | v1.2       | —    |
| 图纸校准 `PUT .../calibration`                          | B  | —      | —      | —      | —      | —          | —    |

> 列名 = 项目负责人 / 专业负责人 / 设计人员 / 驻场工程师 / 施工方 / 只读（业主 · 监理）。
> **`admin` 不进这张表** —— 它是操作者，权限 = **A + B + C 全部**；B 类的调用方就是它。
> **每一格都要落成权限点**（§3.1）：角色是数据、权限点是代码 —— 加角色只改数据（走界面，§5.3），不改代码。
> 矩阵里的 `读` 表示**数据可见性**（能看见），不一定是「能直接调这个接口」—— 例如专业 / 设计 / 驻场
> 看图纸走的是 `sync/pull` 落到本地（§5.1），并不是他们去调 B 类接口。
>
> **第一版实际会用到的角色**：`admin`（后台）+ `site_engineer`（现场）。
> 成员页的角色下拉默认选中 **`site_engineer`**，常用三项 = `project_manager` / `discipline_lead` / `site_engineer`；
> ⚠️ 但下拉的**数据源是角色表全量**（`GET /roles`），不是写死这三项 ——
> 否则在角色管理页新建的角色，成员页选不到（界面侧见《后端操作界面设计》§4.3）。
> 其余角色先 seed 入库、先有权限定义，**不等实现**（表结构与接口不为它们设障）。
> 第一版 App 端**不消费权限点**（只按 `memberships` 判可见性），这套定义是为后续角色登录铺的路。

### 5.6 迁移期兼容

现有 AI 网关的 `/api/vision` 旧路径在迁移期**保留并内部转发**到 `/api/v1/ai/vision`，
待 App 侧切换完成后下线。

### 5.7 命名口径

接口路径**不带 `admin` 前缀** —— 后台界面与 App 调的是同一套接口。
哪些调用方能用哪些接口，由权限点决定（§3.1），不由路径决定。

### 5.8 接口契约（`openapi.json`）

FastAPI 从 Pydantic 模型自动生成 `/openapi.json` —— 这是**前后端唯一的黏合剂**：

| 侧               | 约定                                                                                  |
| ---------------- | ------------------------------------------------------------------------------------- |
| 后端             | **改字段 ＝ 改契约**；改完必须通知前端重新生成                                          |
| 前端             | 用 `openapi-typescript` 从 `openapi.json` 生成 `types.ts`，**不手写字段名**             |
| 两仓协作         | 改 schema 时**同一个发布窗口内**改完                                                    |

> **契约先行的开发顺序**：后端可以先只出**返回 501 的骨架路由**，让 `openapi.json` 提前可用，
> 前端照着它并行写页面 —— 不必等后端实现完成。

---

## 6. 同步机制（离线优先的核心）

### 6.1 三个动作

```
① 写：先写本地（立即返回），同时把"我改了什么"记入 outbox（本地表）
② 推：有网时后台把 outbox 逐条发到  POST /api/v1/sync/push
③ 拉：客户端记住游标，只取增量        GET  /api/v1/sync/pull?sinceSeq=&projectId=
```

**同步范围必须覆盖全部客户端可写实体**（§2.2 那张带公共列的清单）。
现状里有几类数据绕过了统一数据源边界（巡场 / 量房 / 量尺 / 校准库各有一份本地 store），
后端侧的要求是**它们全部纳入 `changes` 流**，否则会出现「缺陷同步了、巡场没同步」的半吊子状态。

### 6.2 游标方案：**seq 变更流**（不用时间戳）

服务端维护 `changes(seq bigserial, project_id, entity, entity_id, op, changed_at)`：
**任何写操作在事务内同时插一条**。

| 方案                                           | 问题                                                                            |
| ---------------------------------------------- | ------------------------------------------------------------------------------- |
| 时间戳游标（各表 `server_updated_at > since`） | **边界丢数据**：写入时间恰好等于游标值、且判据是 `>` 时会被漏掉；且需多表多游标 |
| **seq 变更流**                                 | ✅ 客户端只需 1 个游标；"什么可同步"集中在一处定义                              |

> ⚠️ **必读（这是本文档最硬的一条结论）**：`bigserial` 的**分配**严格递增，
> 但**可见性由提交时间决定** —— 两个事务可能"先分配、后提交"：
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
> **这也是"数据库必须选 PG"最硬的理由** —— MySQL 只有会话级 `GET_LOCK`，
> 连接池下配对释放不可靠。**建表即带上，事后补极难。**

`pull` 响应：服务端按 seq 顺序取出变更，**连带返回当前记录内容**（已删除则返回 tombstone），
一个来回完成；用 `limit` + `nextSeq` 分页。

**游标过期**：`changes` 定期清理（保留 90 天）。客户端游标早于保留窗口时，
服务端返回 `resync_required`，客户端走**全量重同步**。

### 6.3 幂等

所有写接口带 `client_id`（客户端生成的 **ULID 文本**，见 §2.2）+ 可选 `Idempotency-Key`。
服务端对 `client_id` 建唯一索引：**重发不会产生重复记录**。
（不做的后果：网络超时重试必然造重复数据。）

### 6.4 缺陷的状态机校验

缺陷的状态流转**在服务端校验**：非法跃迁拒绝并返回权威状态。
客户端以服务端返回为准（避免离线期间两边各推进一步产生分叉）。

### 6.5 冲突策略

| 数据类型                               | 策略                                                              | 理由                                                                                 |
| -------------------------------------- | ----------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| **会话型**：量尺会话 / 量房 / 巡场记录 | 整份覆盖，`version` 递增，后写胜（LWW）                           | 这是"一个人的一次作业成果"，两人同时改同一条的概率 ≈ 0；字段级合并属过度设计         |
| **流程型**：缺陷                       | **事件流**：不"修改记录"，而是**追加动作**（指派 / 回复 / 销项 / 驳回） | **动作是事实，事实不会冲突**；最终状态由事件推导，附带审计轨迹（"谁什么时候销的项"） |

### 6.6 触发时机

启动时、网络恢复时、写操作后 debounce 数秒、下拉刷新、定时（每 N 分钟）。
**页面完全无感** —— 同步只发生在 `SyncEngine` 内部。

### 6.7 明确不做

CRDT、实时协同编辑、图片走增量同步（图片单独走对象存储后只同步 `file_id`）。

---

## 7. 对象存储（阿里云 OSS）

**地域：华南1（深圳）** —— 与业务服务器同地域，**内网读取流量免费**。

| 项                   | 方案                                                                                                                                                                                                                                                    |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 桶                   | **2 个私有读桶**：`blueprint-prod`（全部业务文件，**绝不配自动删除** —— 取证数据）+ `blueprint-backup`（DB 备份，**30 天自动删除**，必须与业务数据物理隔离）                                                                                            |
| 为什么业务只开一个桶 | 跨桶无法原子操作、权限与生命周期要维护多套；**前缀已能清晰分区**                                                                                                                                                                                        |
| 目录规划             | `photos/{projectId}/{yyyy}/{MM}/{sha256}.jpg`<br>`videos/{projectId}/{yyyy}/{MM}/{sha256}.mp4`<br>`drawings/{projectId}/{drawingKey}/v{n}/{fileName}` + `preview.png`<br>`exports/{projectId}/{yyyyMM}/report_xxx.xlsx` · `avatars/{userId}.png`        |
| 命名                 | **文件名 = SHA-256** → 同一张照片重复上传**自动去重**（省存储也省流量）；**不存原始文件名**（含中文 / emoji 易编码出错），原名记在 `files.file_name` 可选字段                                                                                           |
| 上传                 | **预签名直传**：`POST /files/presign` → **PUT 预签名 URL（10 min，限定 Content-Type 与大小）** → `POST /files/complete {ossKey, sha256, size}` → 服务端 **`HEAD` 校验实际大小 / ETag** → 登记 `files` 表并返回 `fileId`。<br>**根治 base64 塞 body 撞网关体积限制的老坑** |
| **校验不可省**       | 客户端可能伪造 sha256 或上传非法内容 → 服务端必须 `HEAD` 校验，必要时抽样下载校验哈希。**这是取证级证据链的必要一环**                                                                                                                                  |
| 权限                 | **全私有读** + 短时预签名 URL：查看 **1 h**、外部分享 **15 min**（可带水印参数）。工地照片含人员 / 进度 / 可能涉密，**公共读一旦 URL 泄露即无法收回**                                                                                                     |
| 服务端读图（AI）     | 用**内网 endpoint**（`oss-cn-shenzhen-internal`）签发 URL → **AI 识别读图流量归零**                                                                                                                                                                     |
| **缩图**             | **走 OSS `x-oss-process`**：列表 `resize,w_400/quality,q_80`、详情 `resize,w_1600`、分享可叠加 `watermark`。<br>**服务端不做图片处理** —— 免 sharp / imagemagick 依赖与大量 CPU；工地照片量大，自建缩图会成为第一个性能瓶颈                                |
| 服务端职责           | 抽 EXIF（时间 / GPS，供水印存证）+ 计算 `sha256`（去重 + 证据链）。**不做缩图、不中转字节**                                                                                                                                                              |
| 大文件               | 分片上传（> 20 MB）                                                                                                                                                                                                                                     |
| 生命周期             | `photos/**`：**180 天**转低频 → **730 天**转归档；`videos/**`：90 天转低频；`blueprint-backup/db/**`：30 天删除；**取证数据绝不自动删除**                                                                                                                |
| ⚠️ 最低存储时长陷阱  | 低频 30 天 / 归档 60 天 / 冷归档 180 天。**提前删除或转出会补收剩余天数费用** → 规则不要设得过激进；上传后直接进归档也是错的（取回要解冻，**取证调取会来不及**）                                                                                          |

**降本要点（按 ROI 排序）**

1. **上传前压缩到长边 2048px** —— 存储、下行流量、AI 图片 tokens **三项同时降 ~80%**
2. 列表页只加载 `x-oss-process` 缩略图（400px）→ 单次浏览流量降 ~70%
3. AI 识别用**内网 endpoint** 读图 → 流量归零
4. 不要过早转归档；下行流量 > 300 GB/月且持续 2 个月，才考虑上 CDN
5. 对象存储**按存量计费**（照片每年新增会堆积），采购方式（按量 / 存储包）见《服务器与存储选型预算》

---

## 8. AI 服务接入

**现状**：现有一个多项目共用的 AI 网关（Express），把图片转发给千问。
无鉴权、无限流、无缓存、无记账；结构化输出靠客户端截字符串兜底，超时 180s 硬扛。

> **定：不搬入该网关** —— 它的 `/chat`、`/video/*` 是**其他项目在用的**，搬走会打断它们。
> 新后端只在它前面加一层：`POST /api/v1/ai/*` 做 ① JWT 鉴权 + 配额 ② `ai_calls` 记账
> ③ 缓存命中 ④ 返回 schema 校验 + 失败重试一次，然后**转发**给现有网关。

| 能力            | 目标设计                                                                                                                                      |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| 入口            | `/api/v1/ai/*`，上游 Key 仅在服务端                                                                                                           |
| **Prompt 归属** | **从客户端迁到服务端并版本化**。现有 4 套提示词（缺陷 / 锚物 / 网格 / 目标）→ 改 Prompt 不发版，支持 A/B                                      |
| 结构化输出      | 服务端 **schema 校验 + 失败自动重试一次** → 客户端只解析、不再兜底（客户端截字符串逻辑可退休）                                                |
| 缓存            | `sha256(image) + prompt_version` 命中直接返回（同一张图重复上传很常见）                                                                        |
| 记账            | `ai_calls` 表：项目 / 用户 / 任务 / 模型 / Prompt 版本 / 图片哈希 / tokens / 耗时 / 成本 / 是否命中缓存                                        |
| 限流            | 按项目 + 按用户的令牌桶；服务端开关支持"演示模式"                                                                                              |
| 同步 / 异步     | 缺陷识别保持**同步**（10~60s）；批量与长任务改为 `task_id` 轮询 / 回调                                                                         |
| 失败处理        | **返回明确错误码**，不静默 mock、不静默降级                                                                                                    |
| 知识库          | 识别结果 + **人工确认结果**（`captures.confirmed_result`）→ 结构化沉淀 → `/ai/suggest` 用 RAG 检索历史相似缺陷给出整改建议。**这是「沉淀缺陷知识库反哺设计」的后端本体** |
| 模型            | OpenAI 兼容协议，换模型不动客户端                                                                                                             |

**AI 结论的边界（红线）**：AI 输出**不直接改任何工单状态**。
它的所有判断都是**建议**，必须经人工确认后才成为业务状态 ——
这条决定了 `captures.ai_result`（AI 原始）与 `confirmed_result`（人工确认后）**必须分列存放**。

---

## 9. 报告与分享

现状：HTML / PDF / DOCX / XLSX 四端**全部在客户端生成**（纯 Dart 手写 OOXML，零插件）。

**结论：保留客户端导出不动。** 它有真实价值 —— 离线可用、零后端成本、模板随 App 走。
后端只新增客户端做不到的三件事：

| 能力                                       | 接口                                          |
| ------------------------------------------ | --------------------------------------------- |
| 分享链接（施工方 / 甲方网页查看）          | `POST /reports/{id}/share` → `/share/{token}` |
| 定时 / 批量周报                            | 后台任务按周期汇总并推送                      |
| 跨项目统计聚合（缺陷库、销项率、专业分布） | `GET /stats/*`                                |

---

## 10. 通知

站内消息表 + 可插拔通道（APNs / FCM / 邮件 / 企业微信 / 钉钉机器人）。

触发点：缺陷指派给施工方、设计师远程处置、整改回复提交、甲方催办、报告生成完成。

推送通道**不是 P0 阻塞项**，可先做站内消息。

---

## 11. 部署对代码的约束（k8s · 已定）

> 部署到 **k8s**，**由团队内运维成员执行**（「运维成员」= 团队内新增的负责部署的成员）。
> **本节不展开集群细节** —— 命名空间 / Ingress / 域名 / 证书 / 副本与资源配额 /
> PG 实例 / 备份均由运维成员决定。这里只写两件事：**责任边界**（11.1）
> 与 **对应用代码的约束**（11.2），以及待确认项（11.3）。
>
> 部署是**最后一层** —— 不影响 §2 表结构、§6 同步协议、§5 接口清单。

### 11.1 责任边界

| 归属                   | 内容                                                                                                                                                                                                                              |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **运维成员**（团队内） | 集群 · 命名空间 · Ingress / 域名 · **TLS 证书** · **PostgreSQL 实例与备份** · Secret 注入 · 副本数 / 资源配额 / 自动伸缩 · 日志与监控采集 · 发布流水线                                                                            |
| **研发成员**（团队内） | 应用代码 · **两个容器镜像**（`api` / `admin`，各自 `Dockerfile` 随各自仓库）· **配置项清单**（环境变量名与含义）· `GET /health`（仅 `api`）· 数据库 migration · **接口契约** `openapi.json`（前端据此生成类型）                    |

**收口原则**：应用**只依赖环境变量**，不依赖任何集群特性 —— 换集群、换 PG 实例、换域名，
都**只改配置、不改代码**。

### 11.2 对代码的约束（k8s 下不可协商）

| #   | 约束                                                                                                                                | 原因                                                                                       |
| --- | ----------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| 1   | **无状态**：会话 / 文件 / 缓存**不落本地盘**；上传走 OSS                                                                            | 进程随时会被重建，或被调度到另一个节点；多副本才能水平扩                                   |
| 2   | **配置全走环境变量**（含 `DATABASE_URL`）；密钥走 **k8s Secret**（**不入库、不进仓库**）；本地开发用 `.env`                         | 12-factor；Secret 的注入方式由运维定                                                       |
| 3   | **日志到 stdout / stderr**（`structlog` 输出 JSON），**不写文件、不做日志轮转**                                                     | 由集群统一采集                                                                             |
| 4   | **`GET /health`**：liveness = 进程存活；readiness = DB / OSS / AI 上游可达，不通过返回 `503`                                        | 探针依赖它；避免把坏实例挂进流量                                                           |
| 5   | **优雅退出**：收到 `SIGTERM` 后停止收新请求、等在途请求结束                                                                           | 滚动更新时不打断客户端                                                                     |
| 6   | **前端为独立镜像**（仓库 `site-patrol-admin`，纯静态产物）；Ingress 按路径分流：`/api/*` → `api`、`/admin/*` → `admin`             | 同源零 CORS；前后端**独立发布与回滚**；对使用者仍是同一个域名。契约靠 `openapi.json`（§5.8） |
| 7   | **migration 与发布解耦**（见 §11.3 第 1 条）                                                                                        | 多副本同时启动时，不能让每个副本都去跑迁移                                                 |
| 8   | 依赖用 **`uv` + `pyproject.toml`（锁文件 `uv.lock`）**，**零原生依赖**                                                              | 镜像构建确定、可复现                                                                       |

> **适用范围**：第 1~5、7、8 条针对 **`api` 镜像**；第 6 条针对 **`admin` 镜像**
> （前端只要求"能构建出静态产物 + 能托管"，**不涉及数据库 / migration / 探针**）。

### 11.3 待与运维成员确认（**不阻塞写代码**）

| #   | 项                                                                                                                                     | 影响                                                                 |
| --- | -------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| 1   | **migration 怎么执行** —— 发布前 Job 跑 / entrypoint 跑 / 应用侧手动跑                                                                 | 决定 `alembic upgrade head` 放在哪；**多副本下不可放进应用启动流程** |
| 2   | **镜像仓库地址与命名规则**（`api` / `admin` **两个镜像**）                                                                             | 决定两套 CI 的推送目标                                               |
| 3   | **探针路径与超时**（配合 `/health`）                                                                                                   | 决定端点实现细节                                                     |
| 4   | **Ingress 域名 + 正式 TLS 证书**（现为自签证书，**iOS ATS 会直接拒连**）；以及 **`/api/*` 与 `/admin/*` 两条路径分流**                  | 定了才能定客户端 `BASE_URL`                                          |
| 5   | 环境划分（dev / staging / prod）与对应命名空间                                                                                         | 决定配置项有几套                                                     |

> **与部署方式无关、仍然有效**：单入口 `https://<域名>/api/v1/**`（§1.4）·
> 迁移期 `/api/vision` **保留转发**、客户端切换完成后下线（§5.6）。

---

## 12. 实施路线

| 阶段                   | 周期   | 内容                                                                                                                                                                                 | 验收                                                                          |
| ---------------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------- |
| **P0 骨架与收敛**      | 1–2 周 | 新仓库 + **PostgreSQL**（Redis 延后）+ ORM 首版建表与迁移 + JWT 登录 + 统一入口 + `/api/v1/ai/vision` **鉴权 / 记账 / 缓存层（转发现有网关，不搬入）**                                | App 只改一个 `BASE_URL` 后**现有 AI 识别零回归**；旧 `/api/vision` 保留转发    |
| **P1 主链上云**        | 2–3 周 | 项目 / 图纸 / 成员 / 缺陷 CRUD + 缺陷事件状态机 + **OSS 预签名直传** + **后台操作界面可用**（项目 → 成员 → 图纸 → 发布 → 进度）+ SyncEngine（缺陷先行）                              | 两台设备协作一条缺陷：A 记录 → B 处置 → 施工方回复，双方状态一致且离线可写；**后台传的图 = App 用的图** |
| **P2 全量同步 + 分享** | 2–3 周 | 巡场 / 量测 / 量房 / 拍照验收上行 + 增量同步 + 报告分享链接 + 站内通知                                                                                                                | 施工方扫码打开分享链接逐条回复；报告在线可查                                  |
| **P3 治理与增值**      | 持续   | AI 缓存与成本看板、缺陷知识库 RAG（`/ai/suggest`）、跨项目统计、多项目 / 多租户、审计合规                                                                                             | AI 成本可见；整改建议来自历史缺陷库                                           |

> **P1 是演示版的分水岭**：它同时交付「后台能录」与「App 能用」。

---

## 13. 风险与明确不做

**风险**

| 风险                                          | 对策                                                                                                                                                |
| --------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| 离线优先 + 多人协作的冲突复杂度               | 只对「缺陷」主链做事件溯源，其余实体 LWW；不引入 CRDT                                                                                               |
| 「同步」是最容易出错的部分（丢数据 / 重复数据） | 幂等键（`client_id` 唯一索引）+ seq 游标 + **`pg_advisory_xact_lock` 串行化序号分配（§6.2）** + 游标过期全量重同步；P1 先只做缺陷一条链打通          |
| 团队 1–3 人，运维税是最大敌人                 | 模块化单体 + **部署由团队内运维成员执行（k8s）**，本团队不出容器编排能力；**不拆微服务**                                                             |
| AI 网关无鉴权（**当前裸奔**）                 | 现有网关已被多个项目在用且无鉴权 → **排第 1 周加鉴权 + 配额**（在它前面加层，不搬入）；一夜烧空上游账户是真实风险                                    |
| **OSS 外网下行（唯一大额成本）**              | 上传前压缩到长边 2048px + 列表走 400px `x-oss-process` 缩略图 + **AI 识别走内网 endpoint 读图（流量归零）**；下行 > 300 GB/月且连续 2 个月才评估 CDN |
| **部署责任落在运维成员**                      | 发布节奏 / 证书 / PG 实例不由应用侧控制 → **提前把 §11.3 的 5 项问清**；本地用 Docker 起 PG 开发，**不依赖集群才能写代码**                           |

**明确不做**：微服务拆分、自研容器编排能力、GraphQL、自建 IM、
实时协同（CRDT / WebSocket 协同编辑）、自研对象存储、**任何 CAD 转换能力**（已剥离至独立项目）。

---

## 14. 待定项

| #   | 项                                     | 阻塞级别                 | 备注                                                                                                     |
| --- | -------------------------------------- | ------------------------ | -------------------------------------------------------------------------------------------------------- |
| 1   | **域名 + 正式 TLS 证书**               | **阻塞**（运维成员交付） | 现为自签证书，**iOS 会直接拒连**；定了才能定客户端 `BASE_URL`（§11.3 第 4 条）                             |
| 2   | 备案                                   | 阻塞（若换新域名）       | 大陆 443 需备案                                                                                          |
| 3   | **OSS 桶**                             | **阻塞**（上传相关）     | 桶名（`blueprint-prod` / `blueprint-backup`）· **深圳 region** · AccessKey / Secret · 确认**私有读**       |
| 4   | AI 上游凭据                            | 阻塞（AI 迁移时）        | 只需告知服务端环境变量名                                                                                 |
| 5   | **后台发布的校准 vs App 本机微调**     | 非阻塞（后续设计）       | 合并与优先级规则本次不定论（§2.3）                                                                        |
| 6   | **就地建号的初始凭据策略**             | 非阻塞                   | 管理员设初始密码 / 生成一次性口令 —— 界面侧细节（§4.1）                                                   |
| 7   | 首个管理员账号                         | 可后补                   | 建库时 seed                                                                                              |
| 8   | 推送通道                               | 可后补                   | 可先只做站内消息                                                                                         |
| 9   | 数据合规                               | 可后补                   | 工地照片含人脸 / 项目信息，影响留存与权限策略                                                            |
| 10  | **Redis 时机**                         | 非阻塞                   | **第一版不装**：会话吊销 / 限流 / AI 缓存 / 队列初期都能用 PG 顶掉；有压力再加，接口层不用改               |
| 11  | **权限快照刷新时机**                   | 非阻塞                   | 改角色权限点后 `memberships.permissions` 快照怎么刷（同事务 / 后台任务）；第一版 App 不消费权限点，可后补（§3.1） |

---

## 15. 变更记录

| 版本 | 日期       | 变更                                                                                                                            |
| ---- | ---------- | ------------------------------------------------------------------------------------------------------------------------------- |
| v3.2 | 2026-09-22 | **角色可维护**：删除「第一版不出角色维护界面」旧结论（§3.1 / §4.3 / §5.5）；§3.1 新增**权限点目录**（24 个 · 分组 + 中文名，代码常量不建表）与**角色四条数据约束**；新增角色接口 `GET/POST/PATCH/DELETE /roles` + `GET /permissions`（§5.3）；§4.1 补角色管理页一行与内置角色 seed；§2.3 补 `roles` 字段口径与「权限点目录不建表」；§5.3 补该组接口模型（`Role` / `RoleCreate` / `RoleUpdate` / `Permission`） |
| v3.1 | 2026-09-22 | **接口清单按「数据由谁产出」分三类**（A 客户端业务 / B 后台录入 / C 基础，§5.1~5.4）；新增 **§5.5 业务角色名单与接口权限**（7 个角色 × 接口矩阵）；§3.1 权限点清单补全至与矩阵一一对应；§1.2 只留范围内定论；关闭原待定项 7 / 8 |
| v3.0 | 2026-09-22 | **按「选型已定 → 设计后端具体内容」重新组织**：数据库设计前置（§2）；新增 **§4 后台操作界面的后端支撑**（含「发布」的事务语义）；删除客户端改造相关内容（归 `site-patrol` 仓库）；清理已定结论的中间态与悬空引用 |
| v2.9 | 2026-09-22 | 前端**独立成仓**（`site-patrol-admin`）+ 独立镜像；Ingress 按路径分流（`/api/*` → api、`/admin/*` → admin）；契约走 `openapi.json` |
| v2.8 | 2026-09-22 | 新增选型定稿文档；部署责任表述统一为「团队内运维成员」                                                                           |
| ≤v2.7 | 2026-09-21 | 数据契约按客户端模型重写（v2.1 / v2.2 / v2.3）；语言与部署定稿（v2.6 / v2.7）。细节见《技术选型（定稿）》与《讨论稿》            |
