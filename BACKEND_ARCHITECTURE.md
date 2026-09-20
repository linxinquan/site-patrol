# 后端架构与技术方案

> 项目：「蓝图落地」工地验收 App（深圳市建筑设计研究总院 · 环境院 AI 中心）
> 客户端：Flutter（iOS / Android / Web）
> 版本：**v2.2 · 2026-09-20** · 状态：**内容定稿（语言/ORM 与部署方式待确认）**
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
| 模型序列化 | `lib/data/models/`（入口仍是 `lib/data/models.dart`） | 已按域拆 **11 个文件**：`account` / `auth` / `project` / `defect` / `drawing` / `capture` / `measure` / `patrol` / `room` / `report` / `cad_archive`（CAD 待剥离）。全部 `toJson/fromJson` 且向后兼容，`fromJson` **一律容错**（缺字段回落默认值，不抛异常）。**按域索引见 §7.3 开头** |
| 同步元数据 | `lib/data/sync_meta.dart` | `SyncMeta{clientId, version, createdAtMs, updatedAtMs, serverUpdatedAtMs, deletedAtMs, createdBy}`，平铺进实体顶层 JSON；**只给客户端可写实体挂**（见 §7.2） |
| 会话 / 登录模型 | `lib/data/models/auth.dart` | `UserSession`（JWT 形状，持久化实现在 `core/storage/session_store.dart`）+ `AuthTokens` / `LoginResult` / `AuthProfile` / `PermissionScope` |
| 客户端 ID 生成 | `lib/core/utils/ids.dart` | `newId()` → **ULID**（26 位 Crockford Base32）：时间有序、多端不撞、同毫秒自增、时钟回拨不倒退 |
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
| 6 | **从零建，不带包袱** | 不做兼容层；同步所需字段（`client_id` / `version` / `deleted_at`）建表即带上 |
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
disciplines(code PK, name, sort, is_system)                        -- 专业字典
memberships(id, user_id, project_id, org_id, role_code,
            disciplines text[], permissions jsonb, created_at)      -- 项目级；三维度
```

代码里只硬编码**权限点**（稳定的业务动作）：

```
defect.create / defect.reply / defect.close / defect.assign
patrol.run / measure.write / report.export / drawing.manage / member.manage
```

#### 成员是「职责 × 专业 × 单位」三个正交维度

| 维度 | 列 | 回答的问题 |
|---|---|---|
| 职责 | `role_code`（+ `permissions`） | 这个人**能做什么动作** |
| 专业 | `disciplines`（`text[]`） | 这个人**能看 / 管哪一类数据** |
| 单位 | `org_id` | 这个人**代表哪一方** |

例：`中建四局 × 暖通 × 专业负责人` = 一条成员关系 → 可回复暖通类整改，且只看暖通类。

- **不要把专业拼进 `role_code`**（`discipline_lead_hvac` 之类会让角色按「职责 × 专业」组合爆炸，
  也违背「角色是数据不是代码」）。
- **`disciplines` 空数组 = 不限专业**（项目负责人 / 监理 / 管理类天然全专业），**不要**造 `'all'`
  伪值。驻场、施工方、监理的成员**同样带专业**（他们也是按专业分包的）。
- **第一版范围（明确约定）**：只做**「结构专业」或「不分专业」**——
  不分专业 → 留空数组（默认）；只分结构 → 下发单条 `structure`。
  因此**第一版不需要任何按专业过滤的业务逻辑**（空数组天然放行全部），
  这一维度只是**先把结构与取值定下来**，让后续加专业（暖通 / 给排水 / 幕墙…）不改表、不发版。
- 专业与权限点是**「与」关系**：`can('defect.reply')` **且** 缺陷专业被覆盖 —— 客户端**唯一判定入口**是
  `PermissionScope.canOn(permission, categoryCode)`（`AuthProfile.scopeOf(projectId)` 取得）。
  `Membership` 只承载数据，**不再提供 `can` / `canOn`**（v2.2 收敛，避免记录级与合并级两套语义）。
- **专业 code 与 `defects.category` 复用同一套取值**，否则「暖通负责人看暖通缺陷」要维护映射表。
  ⚠️ 客户端 `DefectCategory` 目前是 Dart enum（未知 code 回落 `other`）→
  **扩展专业清单必须与客户端发版同步**；`memberships.disciplines` 是 String code，不受此限。

#### 角色 → 权限的映射

- 角色 → 权限的映射**放数据**（`roles.permissions`）；新增角色不改代码、不发版。
- 建议的角色 code 最小集（**职责**维度，不含专业）：`project_manager` / `discipline_lead` /
  `designer` / `site_engineer` / `contractor` / `viewer`；
  建库时仍先 seed `admin` / `editor` / `viewer` 兜底，业务角色待名单确定后往表里加（见 §15）。
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
- 成员表新增**专业维度**（`Membership.disciplines`）：既是「专业负责人只读视图」的数据基础，
  也是把责任单位/责任人从**自由文本**改为关联成员（`org_id` + 专业）的前提

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

> **本节已按客户端 `SyncMeta` 对齐**（`lib/data/sync_meta.dart`）。
> 客户端把这 7 个字段**平铺**在实体 JSON 顶层，键名为
> `clientId` / `version` / `createdAtMs` / `updatedAtMs` / `serverUpdatedAtMs` /
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
> 多端并发生成不撞号，且字符集排除了易混淆的 `I/L/O/U`。客户端 `newId()` 生成，
> 同毫秒内自增保证单调（见 `lib/core/utils/ids.dart`）。
>
> **哪些表带这组列**（= 客户端**可写**实体）：
> `memberships` · `defects` · `captures` · `measure_sessions` · `room_scans` ·
> `patrol_plans` · `patrol_records` · `progress_entries` · `reports`。
>
> **不带**（= 服务端维护、客户端只读的档案类）：`orgs` / `users` / `projects` /
> `floors` / `site_locations` / `drawings` / `drawing_versions` —— 这些走**全量拉取覆盖**，
> 数据量极小，不做增量同步，因此不需要 `client_id` 与软删列。

### 7.3 表结构（24 张 = 客户端建模 17 + 服务端 7）

> **本节以客户端模型为准**（`lib/data/models/`；下表即为权威索引，`models.dart` 顶部是同源简表）。
> 阅读约定：
> - 标 **jsonb** 的列：**原样存客户端 `toJson()` 结构**，服务端不解析；
> - 标 `*` 的列：客户端模型里有这个**展示字段**，服务端可由 FK/join 回填，不必单独维护；
> - 客户端未建模的表：服务端自有，客户端只消费其投影。
> - 所有业务表都**必须带 `project_id`**（客户端模型已全部对齐，见 §4「一条必须先改的结构问题」）。

#### 客户端契约入口索引（**先看这里**）

读契约**不要翻整个 `lib/data/`**：模型已按**域**拆成 11 个文件，`lib/data/models.dart`
只做 re-export（**唯一契约入口**，barrel，**已完整覆盖，无例外**）。
下表的「入口文件」= 后端打开那一个文件即可。

| 域 | 入口文件 | 实体 | 去向 |
|---|---|---|---|
| 账号与组织（A） | `models/account.dart` | `Org` `Discipline` `User` `Membership` | `orgs` `disciplines` `users` `memberships`（`roles` 服务端自有） |
| 认证授权 | `models/auth.dart` | `UserSession` `AuthTokens` `LoginResult` `AuthProfile` `PermissionScope` | **不建表**：`/auth/*` 响应载体 + 本机会话；`PermissionScope` 是 `Membership` 的派生视图 |
| 项目档案（B） | `models/project.dart` | `Project` `Party` `Milestone` `Floor` `SiteLocation` `ProgressEntry` | `projects` `floors` `site_locations` `progress_entries` |
| 缺陷 | `models/defect.dart` | `Defect` + 4 个分级枚举 | `defects` `defect_events` |
| 图纸与版本（C1/C2） | `models/drawing.dart` | `Drawing` `DrawingVersion` `Hotspot` `Calibration` | `drawings` `drawing_versions`（`files` 服务端自有） |
| 拍照验收 | `models/capture.dart` | `CaptureRecord` `CaptureDefectItem` `VlDefect` | `captures` |
| 量尺 | `models/measure.dart` | `MeasureSession` `MeasureItem` `PhotoCalib` | `measure_sessions` |
| 巡场 | `models/patrol.dart` | `PatrolPlan` `PatrolRecord` `PatrolPoint` `CheckIn` | `patrol_plans` `patrol_records` |
| 量房 | `models/room.dart` | `RoomScanRecord` `RoomWall` `WallOpening` | `room_scans` |
| 报告归档 | `models/report.dart` | `ReportRecord` | `reports` |
| AI 视觉（调用侧） | `lib/data/vision_service.dart` | `VisionResult` `DefectItem` `AnchorDetection` `GridDetection` `MeasureTarget` | **不建表**：落 `ai_calls.response`（§10） |
| 周报导出（客户端） | `lib/data/weekly_report.dart` | `WeeklyReport` `WeeklyPhoto` `WeeklyProgressRow` `WeeklyLedger` `WeeklyIssue` `WeeklyNote` `MeasureCheck` | **不建表**：正文客户端生成（§11） |
| CAD（已判废案） | `models/cad_archive.dart` | `DwgInfo` `CadLayer` `CadLayout` `CadAnnotation` `CadTaskStatus` `UploadedDrawing` | **不建表**（§1.3） |
| 同步元数据 | `lib/data/sync_meta.dart` | `SyncMeta` | 各表公共列（§7.2） |

> **全部入库模型都从 `models.dart` 取**（barrel 已完整覆盖，无例外）。
> 后三行（AI 视觉 / 周报导出 / CAD）**不需要建表**，列在此处只为让后端知道「这些结构会出现」。

**账号与组织（A 类）**

| 表 | 列 | 客户端模型 |
|---|---|---|
| `orgs` | id, name, short_name, type, sort | `Org` |
| `disciplines` | code PK, name, sort, is_system | `Discipline` |
| `users` | id, name, username(uniq), org_id, role\*, avatar, phone, email, status, password_hash, last_login_at | `User` |
| `memberships` | id, user_id, project_id, org_id, role_code, role_name\*, **disciplines text[]**, **permissions jsonb**, status, uniq(user_id, project_id) + 公共列 | `Membership` |
| `roles` | code PK, name, description, **permissions jsonb**, sort, is_system | —（客户端只消费 `Membership.roleCode`） |

> `users.name` 是**姓名**，`username` 是**登录名**（两者都有，客户端模型已分开）。
> `memberships.permissions` 直接落权限点数组，客户端按 `PermissionScope.can('defect.close')`
> 判定——**代码只认权限点、不认角色名**（§6.1）。
>
> **`memberships` 是「职责 × 专业 × 单位」三个正交维度**，不要把专业拼进 `role_code`：
> | 维度 | 列 | 回答 |
> |---|---|---|
> | 职责 | `role_code` + `permissions` | 能做什么动作 |
> | 专业 | `disciplines`（`text[]`） | 能看 / 管哪一类数据 |
> | 单位 | `org_id` | 代表哪一方 |
>
> - **`disciplines` 空数组 = 不限专业**（项目负责人 / 监理 / 管理类），不要造 `'all'` 伪值；
>   驻场、施工方、监理的成员**同样带专业**。
>   **第一版只用 `structure`（或全部留空 = 不分专业）**，不实现按专业过滤的逻辑（见 §6.1）。
> - 专业与权限点是**「与」关系**：客户端 `PermissionScope.canOn(permission, code)` 一次判定两轴
>   （判定入口唯一 —— `Membership` 只承载数据，不做判定，见 v2.2 变更记录）。
> - **`disciplines` 的 code 与 `defects.category` 复用同一套取值**，避免维护映射表。
>   ⚠️ 客户端 `DefectCategory` 是 Dart enum（未知 code 回落 `other`）→
>   **扩展专业清单必须与客户端发版同步**；`disciplines` 用 String code，不受此限。
> - `disciplines` 表按可扩展设计（总图 / 景观 / 幕墙 / 智能化 / 室内…），
>   第一批可只 seed 与 `DefectCategory` 对齐的 7 项。

**项目档案（B 类）**

| 表 | 列 | 客户端模型 |
|---|---|---|
| `projects` | id, name, client, location, status, site_area, floor_area, beds, concept, lat, lng, **parties jsonb**, **milestones jsonb**, **measure_thresholds jsonb** | `Project` / `Party` / `Milestone` / `MeasureThresholds` |
| `floors` | project_id, key, name, index, building, floor, uniq(project_id, key) | `Floor` |
| `site_locations` | id, project_id(可空), name, address, lat, lng, altitude | `SiteLocation` |

> `floors` **不存** `cached` / `progress`：那是客户端本地缓存态（图纸是否已下载），
> 由客户端 `floorCacheProvider` 管理。
> `milestones[]` 里 `done` 缺省时由 `actualDate` 推导，服务端只需存 `date`（计划）+ `actualDate`（实际）。
> `measure_thresholds` 就是 B7「项目级量尺门槛」（`tolMm` / `tolPct` / `judgeMaxErrorMm`）。

**图纸与版本（C1 / C2）**

| 表 | 列 | 客户端模型 |
|---|---|---|
| `drawings` | project_id, key(uniq per project), title, crumb, variant, discipline, sort, published_version_id → `drawing_versions.id`, w\*, h\*, **hotspots jsonb**\* | `Drawing` |
| `drawing_versions` | id, drawing_id, version, version_date, state(`draft`/`published`/`archived`), base_image_path, width, height, bounds, **hotspots jsonb**, **calibration jsonb**, calibration_updated_at, published_at, published_by | `DrawingVersion` / `Hotspot` / `Calibration` |
| `files` | project_id, owner_id, kind(`photo`/`drawing`/`report`/`reply_photo`/`thumb`), object_key, mime, size, **sha256**, width, height, **exif jsonb** | —（客户端不建模） |

> `drawings` 上的 `w` / `h` / `hotspots` 是「**当前发布版本**」的冗余快照（渲染端直接用，不必 join）；
> 权威数据在 `drawing_versions`。
> **校准与热点都绑版本**：`calibration` 落在 `drawing_versions` 行上。图纸改版 → 新版本行没有
> `calibration` → 客户端按「当前发布版本」取校准，**旧版本的校准不会被套用**（表现为该版本未校准，
> 走正常校准流程），**不做自动坐标迁移**（§5 第 2、3 条）。
> 客户端已实现的部分：存储键按版本分档 `cad_calib_v4_<key>__<versionId>`，旧键读到即迁移；
> 启动时套用校准库会按当前版本校验，版本不匹配的条目跳过。
> **尚未实现**的是「主动提示驻场重锚」的 UI（数据层已保证不会静默错位）。
> `state='published'` 同一 `drawing_id` 只允许一行，旧版置 `archived` 锁只读。

**缺陷主链**

| 表 | 列 | 客户端模型 |
|---|---|---|
| `defects` | id, project_id, drawing_id, drawing_version_id, part, type, category, severity, importance, status, anchor, floor, building, gps, lat, lng, alt, world_x, world_y, found_at, reporter_id, reporter\*, resp_unit, resp_user_id, **tags jsonb**, note, seed, suggestion, source_capture_id, source_capture_index, photo_file_id, photo_path\*, photo_hash, watermark_serial, **photos jsonb**, reply, reply_by_id, reply_at, reply_photo_file_id, close_note, completion, designer_action, designer_note, designer_by_id, designer_at + 公共列 | `Defect` |
| `defect_events` | defect_id, actor_id, **action**, payload jsonb, created_at | —（服务端事件流） |

> `defects` 上的 `reply*` / `designer*` 是**当前态**（便于列表查询与报告渲染）；
> `defect_events` 是**事件流**（审计 + 冲突解决）。两者由同一写路径同时更新。
> `action` ∈ `create/update/assign/reply/designer_fix/designer_confirm/onsite/reject/close/reopen`
>
> **时间字段**：客户端 `ts` / `replyTs` / `designerTs` 是展示文本（`yyyy-MM-dd HH:mm[:ss]`），
> 模型另提供 `tsMs` / `replyTsMs` / `designerTsMs` 取 epoch 毫秒 → 入库为
> `found_at` / `reply_at` / `designer_at`。
> `photo_path` 是**本地相对路径**（移动端文件），只作溯源；正式照片走 `files`。
> `photo_hash` + `watermark_serial` 是**取证四要素**中的两个（另两个是 GPS 与拍摄时间），
> 必须落库 —— 只烧在图片像素里等于数据库查不到（§1 三处问题之一）。

**现场采集（C4 + D 类）**

| 表 | 列 | 客户端模型 |
|---|---|---|
| `captures` | id, project_id, drawing_id, drawing_version_id, floor, anchor, world_x, world_y, captured_at, gps, alt, reporter_id, reporter\*, photo_file_id, photo_path\*, note, **ai_result jsonb**, **confirmed_result jsonb**, ai_call_id + 公共列 | `CaptureRecord` |
| `measure_sessions` | id, project_id, drawing_id, drawing_version_id, floor, tol_mm, tol_pct, **calib jsonb**, **items jsonb**, updated_at + 公共列 | `MeasureSession` |
| `room_scans` | id, project_id, name, room_use, source, scanned_at, **walls jsonb**, closure_delta_mm, net_height_mm, drawing_id, drawing_version_id, **checks jsonb**, note + 公共列 | `RoomScanRecord` |
| `patrol_plans` | id, project_id, drawing_id, drawing_version_id, name, floor, **points jsonb**, total_km, updated_at + 公共列 | `PatrolPlan` |
| `patrol_records` | id, plan_id, project_id, drawing_id, drawing_version_id, operator_id, name, started_at, finished_at, dist_km, point_count, issue_count, **track jsonb**, **checkins jsonb**, checkpoint_total + 公共列 | `PatrolRecord` |
| `progress_entries` | id, project_id, milestone_id, status, date, note, **photos jsonb**, declared_by, source + 公共列 | `ProgressEntry` |

> `measure_sessions` / `room_scans` / `patrol_records` / `patrol_plans` 的 JSONB 字段
> **直接存客户端 `toJson()`**，服务端不解析几何，只做检索与统计 —— 最低成本、零阻抗。
> `captures.ai_result` = `CaptureRecord.defects`（AI 原始识别）；
> `confirmed_result` = 同一数组加上人工确认/转入状态（`CaptureDefectItem.status`）。
> 二者是「缺陷知识库反哺设计」的原始数据来源。
> `progress_entries.source` 固定为 `contractor`（施工方免登录自报）——
> 报告与界面**必须**标注自报身份，不得表述成设计院核实结论（§C4）。
>
> **量尺会话的唯一键口径（已定）**：客户端本地按「项目 + 图纸」**一个格子**存
> （存储键 `measure:<projectKey>:<drawingKey>`），换图纸版本会**覆盖**同一格子，
> 这与 §9.5「会话型数据整份覆盖、后写胜」一致。
> 因此服务端用 `uniq(project_id, drawing_id)`，**不要**把 `drawing_version_id` 放进唯一键。
> `drawing_version_id` 仍照常落库（每条会话记录自己带版本，便于说明"这次量的是哪版图"）。
>
> 若将来确需保留**逐版本**的量测历史，客户端需把存储键改为
> `measure:<projectKey>:<drawingKey>:<versionId>` 并做旧键迁移，届时再定。
> 对照：真正需要按版本回溯的 `defects` / `captures` 是**逐条记录**（不是单格子），
> 已带 `drawing_version_id` 且不会被覆盖。

**平台**

| 表 | 列 | 客户端模型 |
|---|---|---|
| `reports` | id, project_id, title, period, reporter\*, **formats jsonb**, defect_count, open_count, done_count, urgent_count, note, created_at, file_id, share_token, share_expires_at, status + 公共列 | `ReportRecord` |
| `ai_calls` | project_id, user_id, task_type, model, prompt_version, **image_sha256**, request jsonb, response jsonb, input_tokens, output_tokens, latency_ms, cost, cache_hit, status, error | —（客户端只消费返回结构） |
| `notifications` | user_id, project_id, type, title, body, ref_type, ref_id, read_at | — |
| `audit_logs` | actor_id, project_id, action, entity, entity_id, before jsonb, after jsonb, ip, ua | — |
| **`changes`** | **seq bigserial PK**, project_id, entity, entity_id, op(`upsert`/`delete`), changed_at —— 同步变更流，见 §9 | — |

> `reports.formats` 是**数组**：同一份报告（标题 + 周期相同）导出 PDF / Word / Excel / 网页链接时
> **合并为一条**，不做重复建卡。客户端归档仍**只存元数据**，正文按需重导（§11）。
> `ai_calls.response` 装视觉模型返回；客户端侧的返回结构见
> `VisionResult` / `DefectItem` / `AnchorDetection` / `GridDetection` / `MeasureTarget`。

**客户端明确不入库的模型（不要建表）**

| 模型 | 原因 |
|---|---|
| `MeasureThresholds` | 已并入 `projects.measure_thresholds jsonb`（B7 项目级门槛） |
| `ArScaleCalibration` | 本机尺度校正，**不跨设备共享**（机型/系统版本相关） |
| `TimelinePhoto` | 派生数据：由缺陷 + 照片按部位实时生成（§2⑤） |
| `PhotoAnchor` / `AnchorPhoto` | 应改为派生（按「图纸版本 + 坐标」对缺陷聚类），当前仍是预置常量 |
| `Floor.cached` / `Floor.progress` | 客户端本地缓存态 |
| `CaptureArgs` / `MeasureArgs` / `RoomScanArgs` / `PatrolArgs` | 路由参数（非持久化） |
| `CadLayer` / `CadLayout` / `DwgInfo` / `CadAnnotation` / `CadTaskStatus` / `UploadedDrawing` | CAD 链路已判废案（§1.3），随迁移删除 |

### 7.4 索引要点

```sql
defects(project_id, status)
defects(project_id, server_updated_at)
defects(client_id)                         -- 幂等（ULID 文本）
defects(project_id, drawing_version_id)    -- 按图纸版本回溯坐标
defects(source_capture_id)                 -- 验收记录 ↔ 缺陷 回流（DV-19）
changes(project_id, seq)                   -- 增量拉取（核心）
files(sha256)                              -- 去重 / 证据链
ai_calls(image_sha256, prompt_version)     -- 结果复用
roles(code) / memberships(user_id, project_id)
memberships GIN(disciplines)               -- 按专业过滤（「专业负责人只看本专业」）
drawing_versions(drawing_id, state)        -- 取当前发布版本
floors(project_id) / drawings(project_id)  -- 档案类按项目全量拉取
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

所有写接口带 `client_id`（客户端生成的 **ULID 文本**，见 §7.2）+ 可选 `Idempotency-Key`。
服务端对 `client_id` 建唯一索引：**重发不会产生重复记录**。
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
| 认证 | `POST /auth/login` · `/auth/refresh` · `/auth/logout` · `GET /auth/me`（返回结构见 §7.3 的 `LoginResult` / `AuthProfile`） |
| 组织与用户 | `GET/POST /orgs` · `GET/POST /disciplines` · `GET/POST /users` · `POST /users/{id}/invite`（A1 / A2 + 专业字典） |
| 项目 | `GET /projects` · `/projects/{id}` · `GET/POST/DELETE /projects/{id}/members`（B1~B4 / B6） |
| 项目档案 | `GET /projects/{id}/floors` · `GET /projects/{id}/site-locations` · `GET/PUT /projects/{id}/measure-thresholds`（B5 / B2 / B7） |
| 图纸 | `GET /projects/{id}/drawings` · `/drawings/{id}` |
| 图纸版本 | `GET/POST /drawings/{id}/versions` · `POST /drawings/{id}/versions/{vid}/publish` · `PUT /drawings/{id}/versions/{vid}/calibration`（C1 / C2：**上传与校准必须同一流程**） |
| 文件 | `POST /files/presign` · `POST /files/complete` · `GET /files/{id}`（签名 URL） |
| 缺陷 | `GET/POST /defects` · `PATCH /defects/{id}` · `POST /defects/{id}/events` · `GET /defects/{id}/events` |
| 巡场 | `GET/POST /patrol/plans` · `GET/POST /patrol/records` |
| 量测 | `GET/POST /measure-sessions` |
| 量房 | `GET/POST /room-scans` |
| 拍照验收 | `GET/POST /captures` |
| 施工进度 | `GET/POST /progress-entries?projectId=&milestoneId=`（C4；`source` 固定 `contractor`，**免登录填报**走 `/share/{token}` 通道） |
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
| 「同步」是最容易出错的部分（丢数据/重复数据） | 幂等键（`client_id` 唯一索引）+ seq 游标 + **`pg_advisory_xact_lock` 串行化序号分配（§9.3，否则静默丢数据）** + 游标过期全量重同步；P1 先只做缺陷一条链打通 |
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

### v2.1 · 2026-09-20

**定位**：客户端模型体系已定稿，本版**以客户端模型为准**重写数据契约（§7.2 / §7.3 / §7.4）。

| # | 项 | v2.0 | **v2.1** | 依据 |
|---|---|---|---|---|
| 1 | 表数量 | 18 张 | **24 张**（客户端建模 17 + 服务端 7） | 新增 `orgs` / `floors` / `site_locations` / `drawing_versions` / `progress_entries`；`roles` / `files` / `defect_events` / `ai_calls` / `notifications` / `audit_logs` / `changes` 归服务端自有 |
| 2 | 幂等键 | `client_uuid uuid` | **`client_id text`（ULID）** | 客户端 `SyncMeta` + `ids.dart`（ULID 时间有序、多端不撞、免易混淆字符） |
| 3 | 主键 | `uuid PK gen_random_uuid()` | **`text PK`（客户端 ULID）** | 客户端离线先建记录，服务端不能另发主键 |
| 4 | 公共列范围 | 所有业务表 | **仅客户端可写实体**（9 张）；档案类走全量拉取覆盖 | 档案量级极小，增量同步得不偿失 |
| 5 | 坐标绑定 | 无 | **`drawing_version_id` 全链贯通**（`defects` / `captures` / `measure_sessions` / `room_scans` / `patrol_plans` / `patrol_records`）+ 校准与热点落在 `drawing_versions` | 客户端模型已对齐；改版即失效重校，不做自动坐标迁移 |
| 6 | 取证字段 | `photo_hash` / `watermark_serial` | 同 v2.0，但**明确客户端模型已具备写入位**（`Defect.photoHash` / `watermarkSerial`），剩余为接线工作 | §1「取证链是断的」 |
| 7 | 项目地理位置 | 无 | `projects.lat / lng`（B2，水印 GPS 兜底来源）+ `site_locations` 表 | 客户端 `Project.lat/lng` / `SiteLocation` |
| 8 | 项目级量尺门槛 | `measure_sessions.tol_mm/tol_pct`（仅会话级） | 增 `projects.measure_thresholds jsonb`（B7 项目级门槛） | 客户端 `MeasureThresholds` 按项目唯一 |
| 9 | 报告格式 | `reports.format`（单值） | **`reports.formats jsonb`（数组）** | 客户端同一份报告多格式**合并为一条** |
| 10 | 施工进度 | 无表 | 新增 **`progress_entries`**（C4，`source` 固定 `contractor`） | 客户端 `ProgressEntry` |
| 11 | **成员维度** | `memberships` 只有 `role_code`（无法表达专业） | 增 **`org_id` + `disciplines text[]`**：成员 = **职责 × 专业 × 单位** 三个正交维度；**空数组 = 不限专业**；专业与权限点「与」判定 | 解决「专业负责人（暖通 / 给排水 / 结构…）」如何落库；是「专业负责人只读视图」与责任指派的数据基础 |
| 12 | **专业字典** | 无 | 新增 **`disciplines` 表**（code / name / sort / is_system） | 专业清单可后台扩展（总图 / 景观 / 幕墙 / 智能化 / 室内…），code 与 `defects.category` 复用同一套 |
| 13 | 角色最小集 | 仅 seed `admin`/`editor`/`viewer` | 建议业务角色（**职责**维度）：`project_manager` / `discipline_lead` / `designer` / `site_engineer` / `contractor` / `viewer` | 客户端 `Membership.role*` 常量；真实名单仍由后台 `roles` 表定义 |

**唯一键口径**：`measure_sessions` 按 `uniq(project_id, drawing_id)`，与客户端单格子存储及
§9.5 会话型 LWW 一致；`drawing_version_id` 照常落库但不进唯一键（详见 §7.3）。
如需逐版本历史，客户端改存储键即可，属增量演进、不阻塞首版建表。

### v2.2 · 2026-09-20

**定位**：客户端模型按**域**整理完毕（数据契约对齐落地），本版补齐**契约入口索引**（§7.3 开头）
与若干口径修正，并把「已就位 / 待接线」分开写清，便于后端判断哪些列已有写入方。

| # | 项 | v2.1 | **v2.2** | 依据 |
|---|---|---|---|---|
| 1 | **契约入口** | 只说「已按域拆 8 个文件」 | 新增 **「客户端契约入口索引」**（§7.3 开头，14 行）：域 → 入口文件 → 实体 → 表，含**不建表**的结构 | 后端不必翻 `lib/data/`；同时明确「哪些结构不必建表」 |
| 2 | 账号与组织 | 与项目档案混在 `models/project.dart` | **拆出 `models/account.dart`**：`Org` / `Discipline` / `User` / `Membership`；`project.dart` 只留 `Project` / `Party` / `Milestone` / `Floor` / `SiteLocation` / `ProgressEntry` | `Membership` 归「项目档案」还是「账号」本来有歧义 |
| 3 | 判定入口 | `Membership` 与 `PermissionScope` 都有 `can` / `coversDiscipline` / `canOn` | **收敛为唯一入口 `PermissionScope`**（`AuthProfile.scopeOf(projectId)`）；`Membership` 只留数据（仅 `isAllDisciplines`） | 同一判断两套语义（记录级 vs 合并级）会误用；本版把 §7.3 里 `canOn` 的表述同步改为 `PermissionScope.canOn` |
| 4 | 同步公共列 | 契约已定，客户端未落 | **`SyncMeta` 已挂到全部可写实体**：`Defect` / `CaptureRecord` / `MeasureSession` / `RoomScanRecord` / `PatrolPlan` / `PatrolRecord` / `ReportRecord`（+ 档案侧的 `Membership` / `ProgressEntry`） | §7.2 的公共列已有写入位，后端建表即带不会再被动 |
| 5 | `defects` 列 | 部分列「客户端尚无写入位」 | `Defect` 补齐 **`projectId`（required，编译期强制）** / `lat` / `lng` / `photoHash` / `watermarkSerial` / `respUserId` / `reporterId` / `replyById` / `designerById` | 取证四要素与「责任人关联 `memberships`」具备数据基础 |
| 6 | `captures` | 客户端存**裸 Map**（`stored_vision_results`） | 新增 **`CaptureRecord` / `CaptureDefectItem`**，写入方与读取方共用同一 `toJson/fromJson`；`count` 改为由 `defects` 派生 | 后端不必再猜 Map 结构；历史数据可直接读回，**无需迁移** |
| 7 | 专业维度 | 只定义了结构 | **明确第一版范围**：只做「结构专业」或「不分专业」（空数组 = 不限），**不实现按专业过滤的逻辑** | 避免过度设计；后续加专业不改表不发版（§6.1 / §7.3） |
| 8 | 时间字段 | 未定 | `Defect.ts` / `replyTs` / `designerTs` **保留展示文本**（不改类型：mock 是 `const`、10+ 渲染点直接展示），另提供 `tsMs` / `replyTsMs` / `designerTsMs` 取 epoch 毫秒入 `found_at` / `reply_at` / `designer_at` | 项目现状优先；入库用派生 getter，零渲染改动 |
| 9 | 文档路径 | `lib/data/models/sync_meta.dart` | **`lib/data/sync_meta.dart`** | 该文件本就在 `lib/data/` 下，§1.1 与 §7.2 一并修正 |
| 10 | **barrel 完整性** | `ReportRecord` 留在 `lib/data/report_record.dart`，**未纳入 `models/` 也未导出**（全项目 5 处按路径直接 import） | **迁入 `models/report.dart` 并在 barrel 导出**，5 处直接 import 一并改为从 barrel 取 | 入库实体全部经 `models.dart`，契约入口唯一；后端只需认一个文件 |

**v2.2 之后仍待接线（有列、但写入方还没填值 —— 不阻塞建表）**：

| 列 | 现状 | 缺什么 |
|---|---|---|
| `defects.lat` / `lng` | 字段已就位 | 拍照/图纸打点目前只透传 `gpsText` 文本（`SiteLocation` 有数值经纬度），**未写入数值** |
| `defects.photo_hash` / `watermark_serial` | 字段已就位 | 哈希与水印凭证号的计算/回传未接（`WatermarkMeta` 已有 serial） |
| `defects.reporter_id` / `resp_user_id` / `reply_by_id` / `designer_by_id` | 字段已就位 | 目前只写人名字符串；需在登录态接入后填用户 id |
