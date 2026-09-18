# 拍照验收 → 问题记录 · 数据流转与字段对照（MAPPING）

> **用途**：审计「拍照验收」到「问题清单」这条链路的**数据阻塞**与**字段一致性**，作为两侧改动时的契约基线。
> **维护规则**：任一侧字段/口径变更，必须同步本表；每处结论可在源码复核。
> **代码基线**：commit `5361996` 之后的提交 + 未提交工作区改动｜**核实日期**：2026-09-18
> **关联**：`docs/specs/CAPTURE_FLOW.md`、`docs/specs/DEFECTS_FLOW.md`、`FEATURE_INVENTORY.md`

---

## 0. 结论速览

> ✅ **2026-09-18 已实施**：**A1 / A2 / A3 / A4 / B7 已修复**（并附带消除报告「楼层重复显示」）。
> ⏳ **仍待处理**：C 类（4 项全部）、D 类（3 项全部）、B1~B6 / B8 / B9。
> 下文 §2 保留**审计发现时**的原貌，实施记录见 §4，变更见 §6。

**有阻塞，且不是一处。** 共 4 类 **22 项**：

| 类别 | 数量 | 性质 |
|---|---|---|
| **A 到不了下游** | 4 | 照片、时间轴、GPS、记录人 在"转入"路径上丢失（数据在，但没传） |
| **B 传递中语义丢失/写死** | 9 | 专业分类、AI 建议、置信度、标签、责任人… 或写死或未写 |
| **C 口径不一致** | 4 | 同一来源的两条记录用两套规则；项目隔离用两套判据；id 三套格式 |
| **D 回不了上游** | 3 | 下游的整改/销项状态无法回到验收记录（纯单向） |

**字段对得上的**：部位、楼层、发现时间、图纸坐标（4 项）。
**字段对不上的**：部位命名、严重程度、状态语义、记录人、责任人、GPS/海拔、照片、备注、标签、专业分类、AI 建议、置信度（12 项）。
**字段根本没有落库的**：置信度、水印凭证、专业分类、重要性、楼栋（5 项）。

> ⚠️ 根因只有一条：**验收记录的 entry JSON 只存了"看图说话"所需的最少字段**（`:857-869`），而「转入」是从 entry 重新构造 Defect 的。**entry 里没有的，转入后一定没有**——除非在构造时补写（现在只补了图纸坐标和照片列表）。

---

## 1. 链路全图

```
拍照（内存态：_shotPhoto / _originalPhoto / _location / _noteController / _defects / _drawPointWorld*）
  │
  ├─[出口 A·保存]─────────────────────────────────────────────┐
  │   capture_page.dart:846-976                              │
  │   ① 写照片文件 photos/<ts>.jpg                            │
  │   ② entry JSON  → LocalStorage『stored_vision_results』   │
  │   ③ 聚合 Defect(1 条) → repo.addDefect → 『added_defects_v1』
  │
  └─[出口 B·转入]─────────────────────────────────────────────┐
      读 entry（stored_vision_results）
      capture_records_controller.dart:279-319
      ④ 逐条 Defect(N 条) → repo.addDefect → 『added_defects_v1』

『added_defects_v1』(+ 项目种子 defects/dy7Defects)
  → defectsProvider
  → 清单页 / 处置回复页 / 记录详情页 / 时间轴
  → 导出报告（唯一入口在清单页）→ 归档『report_records_v1_<projectId>』
```

**三套存储互不引用**：`stored_vision_results`（验收记录）、`added_defects_v1`（缺陷）、`report_records_v1_<projectId>`（报告归档）。

---

## 2. 阻塞清单

### A 类 · 数据到不了下游（数据存在但没传）

| # | 阻塞 | 证据 | 后果 |
|---|---|---|---|
| **A1** | **照片断链**：转入的 Defect 只写 `photos:[photo]`，**没写 `photoPath`**；报告四端只读 `photoPath` | `capture_records_controller.dart:316` vs `report_builder.dart:516, 536`、`report_pdf.dart:754`、`report_docx.dart:557`、`defects_page.dart:178` | 转入的缺陷在报告里**连照片区块都不渲染**（`_photoBlock` 对 null 返回空串，静默省略）。`Defect.photos` 全库无消费方 |
| **A2** | **时间轴永远取不到转入条的照片**：时间轴按 `d.anchor == anchor` **精确匹配**，而两条路径的 anchor 命名不同 | 匹配：`mock_repository.dart:145`；聚合条 `anchor='部位 · 楼层'`（`capture_page.dart:905, 938`）；转入条 `anchor='部位'`（`controller:303`） | ① 同一部位的两组记录**互相匹配不到**；② 只有聚合条有照片 → 转入条**永不出现在时间轴**；③ 详情页传 `d.anchor`（`record_detail_page.dart:305`），转入条查不到任何照片时**回落到写死 anchor**，页面显示"西楼1F-左病房翼"的 demo 数据（`mock_repository.dart:205`） |
| **A3** | **GPS/海拔**：entry **不存** gps/alt（`capture_page.dart:857-869` 无该字段） | 聚合条有（`:941-942`）；转入条固定空（`controller:306-307`） | 报告出现空值行「GPS / 海拔： · 」——`report_content.dart:469` 拼成 `' · '`，`.trim()` 后是 `'·'` 非空，逃过 `where` 过滤 |
| **A4** | **记录人**：entry 不存记录人 | 聚合条 `reporter=_currentUser`（`:944`）；转入条写死 `'验收记录'`（`controller:309`） | 报告「记录人」显示"验收记录"而非真实拍摄人 |

### B 类 · 传递中语义丢失 / 写死

| # | 字段 | 现状 | 证据 |
|---|---|---|---|
| **B1** | 专业分类 `category` | 两条路径**都写死 `other`** → 报告「专业分类」永远是"其他" | `capture_page.dart:935`、`controller:300` |
| **B2** | 严重程度 | 聚合条**取最高**（1 个）；转入条**逐条**（N 个）→ 同一照片在报告里严重度分布不同 | `capture_page.dart:910-915` vs `controller:301` |
| **B3** | 部位命名 `part` | 聚合条 `部位·楼层·首缺陷等N项`；转入条 `部位` → 清单页同一拍照出现两种标题，看起来像两件事 | `capture_page.dart:931-933` vs `controller:298` |
| **B4** | 标签 `tags` | 聚合 `['拍照记录', 各缺陷名]`；转入 `['验收转工单','验收#<id>']` → 两套标签体系 | `capture_page.dart:945` vs `controller:310` |
| **B5** | 备注/巡场意见 `note` | 聚合条 = 无缺陷说明 + 未落盘说明 + 各 desc + 用户描述（多行拼接）；转入条 = `用户描述｜该条 desc` → 同一条缺陷在两处文字不同 | `capture_page.dart:917-922` vs `controller:311` |
| **B6** | 责任人 `resp` | 聚合条 `'待指派'`；转入条 `''` → 报告「责任人」一处显示"待指派"、一处是空行 | `capture_page.dart:943` vs `controller:308` |
| **B7** | AI 建议 `suggestion` | 聚合条**写**；转入条**未写** → 报告「AI整改建议（施工单位）」在转入条上整体缺失 | `capture_page.dart:952` vs `controller:296-318`（无该字段） |
| **B8** | 水印凭证 | 水印 burn 进图片，`photoHash` / `watermarkSerial` **从未落库** → 详情页"已效验"只能用 status 推导（`DEFECTS_FLOW` D3，触及红线） | `record_detail_page.dart:390`；模型 `models.dart:448, 451` |
| **B9** | 置信度 `conf` | entry 的 `defects[].conf` **未映射进 Defect**（Defect 也无该字段）→ 报告无法标注"低置信需人工复核" | entry `capture_page.dart:867` vs `controller:296-318` |

### C 类 · 口径不一致

| # | 不一致 | 证据 | 后果 |
|---|---|---|---|
| **C1** | **项目隔离两套判据**：验收记录按 `drawingsProvider` 的 drawingKey 集合过滤（drawingKey 空则保留）；缺陷按 `is7` 布尔过滤 | `capture_records_controller.dart:205-218` vs `mock_repository.dart:90` + `providers.dart:306` | 两侧可见范围可能不一致：验收记录里看不到、缺陷里却在（或反之） |
| **C2** | **id 三套格式**：entry `id` = 纯微秒数字串；聚合 Defect `id` = `cap_<微秒>`；转入 Defect `id` = `<entryId>#<idx>`。且 Defect 有 `sourceCaptureId` 但**无任何读取方** | `capture_page.dart:858, 930`、`controller:297, 317` | 从 Defect 无法回到 entry（除手工拼 id）；「验收↔问题」双向追溯实际是单向 |
| **C3** | **"待整改"两个数字**：验收记录页数 entry 里 `status != converted` 的 AI 缺陷；问题清单数 `Defect.status == draft` | `capture_records_page.dart:288-296` vs `report_content.dart:306-309` | 同一批问题两个口径，且因聚合条也计入清单而**永不相等** |
| **C4** | **删除不联动**：删验收记录只动 `stored_vision_results`（不删已转入的 Defect）；Defect 侧**无删除入口** | `controller:69-115` | 产生"孤儿缺陷"，其 `sourceCaptureId` 指向已不存在的 entry |

### D 类 · 回不了上游（纯单向）

| # | 缺失的回流 | 证据 | 后果 |
|---|---|---|---|
| **D1** | entry 的 `defects[].status` 只有 `pending` / `converted` 两态，**不随 Defect 的整改/销项变化** | `capture_page.dart:867`、`controller:120-157` | 验收记录里永远看不到"已整改/已销项"，现场照片沉在验收记录里成为信息孤岛 |
| **D2** | 无「按 `sourceCaptureId` 反查」的实现 | 全库 `sourceCaptureId` 仅 `controller:317` 一处写入 | 无法在验收记录上标注"该问题已销项" |
| **D3** | **重复计数**：保存已生成 1 条聚合缺陷，转入又生成 N 条；报告 `stats.defects` 与 `open` 把 1+N 全部计入 | `report_content.dart:298-315`（`defects: defects.length`、`open: draft\|\|doing`） | **报告"问题总数"与"未闭合"虚高**；同一张照片在报告里出现 1+N 次 |

---

## 3. 字段对照表

图例：✅ 对齐｜⚠️ 口径不一致｜❌ 丢失/写死｜— 不适用

| 业务字段 | ① entry（验收记录存储） | ② 聚合 Defect（保存路径 A） | ③ 转入 Defect（路径 B） | ④ 清单卡/详情页 | ⑤ 报告 | 判定 |
|---|---|---|---|---|---|---|
| 部位 | `anchor`（纯部位名） | `part`=`部位·楼层·首缺陷…`；`anchor`=`部位 · 楼层` | `part`=`anchor`=`部位` | 清单显示 `part`；详情显示 `part` | `part` + 「缺陷位置」=`anchor` | ⚠️ B3 |
| 缺陷类型 | `defects[].name`（多条） | `type`=首缺陷名 | `type`=该条 name | 清单「问题缺陷」 | 「缺陷类型」 | ⚠️ 聚合为合并名 |
| 专业分类 | 无 | `other`（写死） | `other`（写死） | 不显示 | 「专业分类」=其他 | ❌ B1 |
| 严重程度 | `defects[].severity` | **取最高** | **逐条** | 清单带色文字；详情**恒橙** | 分组/统计/排序基准 | ⚠️ B2 |
| 状态 | `defects[].status`∈{pending,converted} | `status`=draft | `status`=draft | `StatusPill` | `closed`/`open` 统计 | ⚠️ C3 / D1 |
| 楼层 | ✓ | ✓ | ✓ | 参数卡「楼层部位」 | 「楼层部位」 | ✅ |
| 发现时间 | `ts` | `ts` | `ts` | 清单「发现时间」/参数卡 | 「发现时间」 | ✅ |
| 记录人 | **无** | 当前用户 | 写死 `验收记录` | 清单「记录人」 | 「记录人」 | ❌ A4 |
| 责任人 | **无** | `待指派` | `''`（空） | 清单「责任人」/详情 | 「责任人」（空行） | ⚠️ B6 |
| GPS / 海拔 | **无** | 有 | 空 | 详情参数卡 | 「GPS / 海拔」（空值行） | ❌ A3 |
| 图纸坐标 | `worldX/worldY` | 透传 | 透传 | 详情不显示 | 「图纸坐标」（`coordText`） | ✅ |
| 照片 | `photo`（相对路径） | **`photoPath` ✓** | `photos:[…]` 但 **`photoPath` 空** | 两页都不显示照片 | 靠 `photoPath` | ❌ A1 |
| 备注/描述 | `note` | 合并长文本 | `note｜desc` | 清单**显示** / 详情**不显示** | 「巡场意见」 | ⚠️ B5 |
| AI 建议 | `defects[].suggestion` | 写（聚合） | **未写** | 两页都不显示 | 「AI整改建议」 | ❌ B7 |
| 标签 | 无 | `['拍照记录',…]` | `['验收转工单',…]` | 不显示 | 「标签」 | ⚠️ B4 |
| 置信度 | `defects[].conf` | — | **未映射** | 不显示 | 无字段可用 | ❌ B9 |
| 水印凭证 | 无（burn 在图里） | 未写 | 未写 | 详情用 status 推导"已效验" | — | ❌ B8 |
| 完成状态 | 无 | 详情页写 | 详情页写 | 底部操作栏 | 「闭合确认」 | ✅（仅下游） |
| 重要性 | 无 | 无 | 无 | 不显示 | 靠 `effectiveImportance` 推导 | ❌ |
| 楼栋 | 无 | 无 | 无 | 不显示 | 分组回退到「严重程度」 | ❌ |

---

## 4. 修复建议（按投入产出排序）

| 优先级 | 动作 | 成本 | 收益 |
|---|---|---|---|
| 1 | 转入时补 `photoPath: capture['photo']` | **1 行** | ✅ **已修**（2026-09-18）→ 修复 A1，报告照片恢复 |
| 2 | 转入时补 `suggestion: vlDefect['suggestion']` | **1 行** | ✅ **已修** → 修复 B7，报告「AI整改建议」恢复 |
| 3 | 统一 `anchor` 口径 | 2 行 | ✅ **已修** → 修复 A2 主体（两条路径 anchor 均为「部位」，时间轴可跨路径聚合）。**附带修复**：报告 PDF/DOCX/HTML 渲染 `'${d.anchor} · ${d.floor}'`，而聚合条 anchor 原本已含楼层 → **楼层重复显示**，一并消除 |
| 4 | entry 增记 `gps` / `alt` / `reporter` 并透传 | ~10 行 | ✅ **已修** → 修复 A3、A4（旧 entry 缺字段时回落空串 / `验收记录`，向后兼容）。**注**：B6（责任人 `resp` 仍为空）不在本次范围 |
| 5 | 修报告 GPS 空值行 | 1 行 | ✅ **已修** → 两值皆空时整行不再输出 |
| 6 | 明确「聚合条 vs 转入条」分工（是否都要入清单） | 需产品决策 | 修复 D3 重复计数、报告虚高 |
| 7 | 专业分类接 AI 分类或人工选择；否则报告撤列或改「未分类」 | 需决策+开发 | 修复 B1 |
| 8 | 下游状态回流验收记录（或明确不做） | 需决策 | 修复 D1/D2 |
| 9 | 项目隔离统一为 `projectId`（替代 `is7` 布尔与 drawingKey 集合两套） | 较大 | 修复 C1，也是接后端的前置 |
| 10 | 删除联动（删 entry 时处理其已转入 Defect） | 需决策 | 修复 C4 |

**验证**：`dart analyze lib` → **0 error**；改动文件 `read_lints` 干净。
**改动文件**：`lib/features/capture/capture_page.dart`、`lib/features/capture_records/capture_records_controller.dart`、`lib/features/defects/report_content.dart`

---

## 5. 溯源索引

> ⚠️ **行号漂移**：本表行号为 2026-09-18 实施修复**之前**的基线。修复后 `capture_page.dart` 第 869 行之后整体 **+9**；`capture_records_controller.dart` 第 283 行之后为 **+8~+10**（新增透传字段）。**引用时优先看「环节」对应的函数名与字段名。**

| 环节 | 文件:行 |
|---|---|
| entry 写入 | `lib/features/capture/capture_page.dart:846-976`（结构 `:857-869`，照片 `:875-885`） |
| 聚合 Defect 写入 | `lib/features/capture/capture_page.dart:929-953` |
| 转入 Defect 构造 | `lib/features/capture_records/capture_records_controller.dart:279-319` |
| 转入副作用序列 | `lib/features/capture_records/capture_records_page.dart:236-270` |
| 缺陷合并/隔离/持久化 | `lib/data/repository/mock_repository.dart:82-97, 117-134`（`added_defects_v1` `:22`） |
| 时间轴构造与匹配 | `lib/data/repository/mock_repository.dart:137-206` |
| 报告照片 | `lib/features/defects/report_builder.dart:508-519, 536, 547` |
| 报告字段集 | `lib/features/defects/report_content.dart:461-487` |
| 报告统计 | `lib/features/defects/report_content.dart:298-323` |
| 报告数据源与周期过滤 | `lib/features/defects/defects_page.dart:119-162, 199-211` |
| 验收记录统计/删除 | `lib/features/capture_records/capture_records_page.dart:274-299`、`capture_records_controller.dart:69-115` |

---

## 6. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-09-18 | 首版：审计 4 类 22 项阻塞；订正 `CAPTURE_FLOW.md` D1（报告照片是"静默省略"而非"显示占位"）与 `DEFECTS_FLOW.md` D4（详情页照片在报告中也仅聚合条可见） |
| 2026-09-18 | **实施 §4 第 1~5 项**：转入补 `photoPath`/`suggestion`、统一 anchor 口径、entry 增记 `gps/alt/reporter` 并透传、报告 GPS 空值行条件化。修复 A1/A2/A3/A4/B7，附带消除报告「楼层重复」；`dart analyze lib` 0 error |
