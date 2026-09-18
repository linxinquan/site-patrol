# 偏离总表（DEVIATION REGISTER）

> **用途**：把「拍照验收 / 问题清单 / 两者流转」三份规格里的偏离**去重合并**成唯一待办清单，按"是否需要决策"分批，供排期与验收。
> **收录范围**：`CAPTURE_FLOW.md`（18 条）+ `DEFECTS_FLOW.md`（23 条）+ `CAPTURE_DEFECT_MAPPING.md`（22 条）→ 去重后 **29 条**。
> **不在本表**：**批 3（与后端重建耦合的 5 项）**——按约定不纳入本次，去向见 §5。
> **状态图例**：⏳ 待处理｜✅ 已修
> **基线**：commit `5361996` 之后的提交 + 未提交改动｜**核实日期**：2026-09-18
> **维护规则**：修完一项把状态改 ✅ 并填日期；新增偏离先落到对应源文档，再同步本表。

---

## 0. 总览

| 批次 | 定义 | 条数 | 需你决策 | 建议节奏 |
|---|---|---|---|---|
| **批 0** | 红线/对外可信度问题 | 1 | **1 项** | 单独最优先，先定方案再改 |
| **批 1** | 零决策：纯 bug / 死代码 / 过期注释 / 写死值 | 14 | 0 | ✅ **已修 13 条**（2026-09-18）；DV-03 按指示跳过 |
| **批 2** | 产品语义缺失与口径不统一 | 14 | **13 项** | 你定完一次性改，避免返工 |
| **批 3** | 与后端重建耦合（本表不收） | 5 | — | 随后端一起做，见 §5 |

已修（2026-09-18，不计入上表）：`CAPTURE_FLOW` D1、`MAPPING` A1~A4 与 B7 —— 报告照片断链、anchor 口径、GPS/海拔、记录人、AI 建议透传。
**批 1 的 13 条（除 DV-03）已于同日实施完毕**：`dart analyze lib` → **0 error / 0 warning**（info 级 133 条均为既有的 const/final/deprecated 风格提示，与本次改动无关）。

---

## 1. 批 0 · 红线（最优先）

| 编号 | 问题 | 影响 | 来源 | 需要你定 |
|---|---|---|---|---|
| **DV-01** | ⏳ **「已效验」胶囊是状态推导，不是校验**：`verified = d.status != DefectStatus.draft`（`record_detail_page.dart:390`），未做任何哈希比对，`photoHash` / `watermarkSerial` 两个字段**从未落库** | 界面在宣称一件系统没做的事。**与项目红线「不伪造验证结果」直接冲突**；对甲方/监理交付时是可信度风险 | `DEFECTS_FLOW` D3 + `MAPPING` B8 | **二选一**：<br>A. 补真校验（水印落库 `photoHash`/`watermarkSerial` + 打开详情时比对）<br>B. 改文案为「已提交 / 待复核」（不再宣称"效验"）<br>→ 建议 **B 先行**（成本低、立即消除误导），A 随后排 |

---

## 2. 批 1 · 零决策（可立刻做）

> 全部为纯 bug、死代码、过期注释或写死值，**不涉及产品语义**，改动小、可一次性完成并回归。

| 编号 | 问题 | 状态 | 来源 | 实际处置 |
|---|---|---|---|---|
| **DV-02** | **`Color(0xFF4444)` 缺两位十六进制**（应为 `0xFFFF4444`），该值 alpha=0x00 → **完全透明**。两处：严重程度文字色、`StatusPill` 的 draft 底色 | ✅ 已修 | `DEFECTS_FLOW` D2 | 两处统一改为 `0xFFFF4444` |
| **DV-03** | **孤儿页**：`CaptureEntryPage` 全库仅自身定义命中 | ⏸ **按用户指示跳过**（同事新增，本次不动） | `CAPTURE_FLOW` D4 | 未处理 |
| **DV-04** | **`_CaptureStep.selectFloor` 死枚举值**（从未被赋值），`_buildFloorSelector` 不可达 | ✅ 已修 | `CAPTURE_FLOW` D6 | 移除枚举值、`_buildFloorSelector` 与其唯一使用方 `_FloorOptionTile`（净删 62 行）；`selectPoint`/`capture` 两态保留 |
| **DV-05** | **`_scanTimer` 死字段**：只被 `cancel()`，从未赋值 | ✅ 已修 | `CAPTURE_FLOW` D7 | 删字段 + 4 处 `cancel()` |
| **DV-06** | **`defectSpecialFilterProvider` 死 provider** | ✅ 已修 | `DEFECTS_FLOW` D14 | 删除定义（处置页用的是页面内 `_kind`） |
| **DV-07** | **`_calcStats(all, filtered)` 的 `filtered` 完全未使用** | ✅ 已修 | `CAPTURE_FLOW` D9 | 收敛签名为 `_calcStats(all)` 并补口径注释 |
| **DV-08** | **四处过期注释**：①类头称"真实相机已注释"②结果区"4 段"③时间轴"CustomPainter 占位"④`_StatusSegmented` 选中色 `#0395FF` | ✅ 已修 | `CAPTURE_FLOW` D5/D17 + `DEFECTS_FLOW` D19/D21 | 四处改正为与实现一致 |
| **DV-09** | **写死值**：导出日期下界 `2024-01-01`、项目名兜底 `建筑验收项目`、角色兜底 `设计管理` | ✅ 已修 | `DEFECTS_FLOW` D18/D22 | 日期下界改为「最早缺陷日期，且不晚于当前周期起点」（新增 `_earliestDefectDate`）；兜底改 `未命名项目` / `未设置角色` |
| **DV-10** | **时间轴默认 anchor 写死** `'西楼1F-左病房翼'`（页面 + mock 兜底） | ✅ 已修 | `DEFECTS_FLOW` D20 | 页面默认 anchor 改空串；`MockRepository.getTimeline` 兜底改返回空列表（展示空态而非无关部位） |
| **DV-11** | **`_filterByPeriod` 对时间戳无法解析的记录一律纳入** | ✅ 已修 | `DEFECTS_FLOW` D23 | 改为**排除**并更新注释 |
| **DV-12** | 控制器内注释与缩进异常（顶层私有函数写成"内部使用：Notifier 私有"） | ✅ 已修 | `CAPTURE_FLOW` D18 | 改为顶层私有函数 + 正常缩进 |
| **DV-13** | **`models.dart` 注释与实现不符**：称 `sourceCaptureId` 填 `"${captureId}#${idx}"`，实际填 `captureId` | ✅ 已修 | `CAPTURE_FLOW` D11/D12 | 注释改正，并注明「只写不读」（实现归属 DV-19） |
| **DV-14** | **详情页严重程度恒用橙色**，未按 `severity` 变色 | ✅ 已修 | `DEFECTS_FLOW` D17 | 改用 `d.severity.color`。**遗留**：`models` 与 `defects_page` 两套严重度色值不一致（red `FF3B30` vs `FF4444`、yellow `FADC19` vs `FF9500`），属设计规范问题，另记 |
| **DV-15** | **转入无事务、失败静默**：`markDefectConverted` 返回值被忽略、无 try/catch、最终无条件 `return true` | ✅ 已修 | `CAPTURE_FLOW` D3 | 包 try/catch，失败弹 `转入问题清单失败：…`(danger) 并 `return false`；不改数据结构（事务化留待后端） |

---

## 3. 批 2 · 需决策

> 每条给出「需要你定」的具体选项。定完我一次性实施，避免改一半返工。

| 编号 | 问题 | 影响 | 来源 | **需要你定** |
|---|---|---|---|---|
| **DV-16** | ⏳ **同一次拍照在问题清单留 1+N 条**：保存生成 1 条聚合条（`seed:'capture'`，带照片），转入又生成 N 条（`seed:'capture_convert'`）。报告 `stats.defects` / `open` 把 1+N 全部计入 | 同一照片/部位重复出现；**报告"问题总数"与"未闭合"虚高** | `CAPTURE_FLOW` D2 + `MAPPING` D3 | **三选一**：<br>A. 只保留聚合条（转入不再建 Defect，只回写状态）<br>B. 只保留逐条（保存不再建聚合条，照片挂到各条）<br>C. 保留两条但**明确分工**（聚合条=留痕、转入条=整改项），并让报告只统计其中一类<br>→ 倾向 **A**（最少数据、报告口径最干净） |
| **DV-17** | ⏳ **聚合条与转入条的字段口径分裂**：严重程度（取最高 vs 逐条）、`part`（`部位·楼层·首缺陷等N项` vs `部位`）、`tags`（`拍照记录` vs `验收转工单`）、`note`（多行拼接 vs `note｜desc`）、`resp`（`待指派` vs 空） | 同一拍照在清单里像两件事；报告分组/统计口径不一 | `MAPPING` B2~B6 + `CAPTURE_FLOW` D13 剩余 | **依赖 DV-16 结论**；若选 A/C，需同时定：两条记录是否统一 `part`/`tags`/`note`/`resp` 口径（建议统一，`resp` 统一为「待指派」） |
| **DV-18** | ⏳ **`doing` / `reject` 两个状态无任何写入路径**，只能来自 mock 种子；但报告把 `draft\|\|doing` 计为"未闭合"、首页待办也含 `doing` | 用户无法表达"已开始整改"或"拒绝整改"；报告「整改中」统计永远来自种子数据 | `DEFECTS_FLOW` D1 | **二选一**：<br>A. 补动作（详情页加「开始整改」/「拒绝整改」）<br>B. 收敛状态（从分段/图例/统计中移除，`draft→done` 两态）<br>→ 若要对外交付"整改中"指标，选 A |
| **DV-19** | ⏳ **下游状态回不了上游**：验收记录 entry 的 `defects[].status` 只有 `pending`/`converted`，**不随 Defect 的整改/销项变化**；`sourceCaptureId` 只写不读，无「按来源反查」 | 验收记录里永远看不到"已整改/已销项"，现场照片沉在验收记录里成为信息孤岛 | `MAPPING` D1/D2 + `CAPTURE_FLOW` D12 | **二选一**：<br>A. 做回流（验收记录详情按 `sourceCaptureId` 显示该问题当前状态）<br>B. 明确不做，仅修注释（见 DV-13）<br>→ 倾向 **A**（验收记录是现场唯一留痕，缺状态会反复被问"这个整改了吗"） |
| **DV-20** | ⏳ **专业分类 `category` 恒为 `other`**（两条产生路径都写死），报告「专业分类」永远"其他" | 分类维度形同虚设 | `DEFECTS_FLOW` D13 + `MAPPING` B1 | **三选一**：<br>A. AI 识别返回分类后映射<br>B. 人工在详情页选择<br>C. 报告撤掉该列<br>→ 若暂不做，建议先 C（避免输出"其他"充数） |
| **DV-21** | ⏳ **详情页能力缺口（一组）**：①水印卡是渐变占位、不读 `photoPath` ②不显示备注 `note`（清单页显示、详情页不显示）③无回复照片上传入口（模型有 `replyPhotoPath`）④「待复核」无状态位（只是按钮文案）⑤无"未闭合说明"`closeNote` 入口 | 详情页看不到现场照片；同一记录两页信息不一致；报告「整改后照片」永远空；"待复核"语义无处查询 | `DEFECTS_FLOW` D4/D5/D6/D11/D15 | **逐项勾选**（建议全做）：<br>① 接真实照片？② 补备注块？③ 加回复照片？④ 加"待复核"状态位？⑤ 加未闭合说明入口？ |
| **DV-22** | ⏳ **模型字段名存实亡**：`photoHash`/`watermarkSerial`/`importance`/`building`/`respUnit`/`closeNote`/`replyPhotoPath`/`sourceCaptureId`/`photos` 无写入路径；`conf`（置信度）未映射进 Defect | 模型与实现脱节，字段名存实亡；报告无法标注"低置信需复核" | `DEFECTS_FLOW` D12 + `MAPPING` B9 | **逐字段决定 补实现 or 删字段**（建议：`photoHash`/`watermarkSerial` 随 DV-01 方案定；`importance`/`building` 若报告要用则补入口；`conf` 建议入 Defect 以便报告标注复核） |
| **DV-23** | ⏳ **处置与回复页无任何写操作**，只是"筛选后的清单"，所有操作都要再进详情页 | 与「待设计师处置/待施工方回复」的按钮语义不符，多一次跳转 | `DEFECTS_FLOW` D10 | **二选一**：<br>A. 页内可直接处置/回复<br>B. 维持只读（改为"查看"语义，文案调整） |
| **DV-24** | ⏳ **导出报告用全集，不受状态分段筛选影响** | 用户选「已销项」再导出，仍导出全部，易误判 | `DEFECTS_FLOW` D9 | **二选一**：<br>A. 跟随当前筛选<br>B. 维持全集（在弹窗里明示"按周期导出全部状态"）<br>→ 现状代码注释倾向 B，建议 **B + 明示** |
| **DV-25** | ⏳ **两个"待整改"数字口径不同**：验收记录页数 entry 里 `status != converted` 的 AI 缺陷；问题清单数 `Defect.status == draft`（且聚合条也计入） | 同一批问题两个数字，且**永不相等** | `MAPPING` C3 | **二选一**：<br>A. 统一为"问题清单口径"（验收记录页改为读 Defect 状态）<br>B. 改标题区分（"待转入" vs "待整改"）<br>→ 倾向 **B**（成本低、语义更准） |
| **DV-26** | ⏳ **水印「项目」字段取的是定位点名称**（`_location.name`），不是项目名 | 水印信息语义待确认 | `CAPTURE_FLOW` D16 | **确认是否有意**：A. 有意（定位点即现场标识）B. 改为项目名 |
| **DV-27** | ⏳ **AI 严重程度统一默认 `orange`**（模型未返回 severity） | 报告严重度分布失真、`effectiveImportance` 推导全落"重要不紧急" | `CAPTURE_FLOW` D14 | **二选一**：<br>A. 推动视觉服务返回 severity（`/api/vision` 提示词）<br>B. 详情页允许人工改严重程度 |
| **DV-28** | ⏳ **Web 平台限制**：照片不落盘（内存 Map，刷新即丢）、AI 走 `vlPreset` mock | Web 仅作演示，会话刷新后记录与照片全丢 | `CAPTURE_FLOW` D10/D15 | **建议直接登记不改**（在验收标准写明 Web 为演示端）；如需 Web 持久化请说明 |
| **DV-29** | ⏳ **验收页的量尺校对未接项目级判定门槛**（用页面内 ±10mm/±5%，而拍照量尺页已接 `MeasureThresholdStore`） | 同一报告内两种判定口径 | `CAPTURE_FLOW` D8 | **归属确认**：属量尺模块，建议与量尺规格一起处理（本次仅登记） |

---

## 4. 去重对照（本表 ↔ 源文档）

| 本表编号 | 源文档编号 |
|---|---|
| DV-01 | `DEFECTS_FLOW` D3；`MAPPING` B8 |
| DV-02 | `DEFECTS_FLOW` D2 |
| DV-03 | `CAPTURE_FLOW` D4 |
| DV-04 | `CAPTURE_FLOW` D6 |
| DV-05 | `CAPTURE_FLOW` D7 |
| DV-06 | `DEFECTS_FLOW` D14 |
| DV-07 | `CAPTURE_FLOW` D9 |
| DV-08 | `CAPTURE_FLOW` D5、D17；`DEFECTS_FLOW` D19、D21 |
| DV-09 | `DEFECTS_FLOW` D18、D22 |
| DV-10 | `DEFECTS_FLOW` D20 |
| DV-11 | `DEFECTS_FLOW` D23 |
| DV-12 | `CAPTURE_FLOW` D18 |
| DV-13 | `CAPTURE_FLOW` D11、D12（注释部分） |
| DV-14 | `DEFECTS_FLOW` D17 |
| DV-15 | `CAPTURE_FLOW` D3 |
| DV-16 | `CAPTURE_FLOW` D2；`MAPPING` D3 |
| DV-17 | `MAPPING` B2、B3、B4、B5、B6；`CAPTURE_FLOW` D13（剩余部分） |
| DV-18 | `DEFECTS_FLOW` D1 |
| DV-19 | `MAPPING` D1、D2；`CAPTURE_FLOW` D12（实现部分） |
| DV-20 | `DEFECTS_FLOW` D13；`MAPPING` B1 |
| DV-21 | `DEFECTS_FLOW` D4、D5、D6、D11、D15 |
| DV-22 | `DEFECTS_FLOW` D12；`MAPPING` B9 |
| DV-23 | `DEFECTS_FLOW` D10 |
| DV-24 | `DEFECTS_FLOW` D9 |
| DV-25 | `MAPPING` C3 |
| DV-26 | `CAPTURE_FLOW` D16 |
| DV-27 | `CAPTURE_FLOW` D14 |
| DV-28 | `CAPTURE_FLOW` D10、D15 |
| DV-29 | `CAPTURE_FLOW` D8 |
| ✅ 已修 | `CAPTURE_FLOW` D1；`MAPPING` A1、A2、A3、A4、B7 |

---

## 5. 批 3 · 已排除（不在本表，仅登记去向）

按约定本次不纳入，**源文档中仍保留完整描述**，等接后端时与 `BACKEND_ARCHITECTURE.md` 一起做：

| 项 | 源文档 | 为何推迟 |
|---|---|---|
| 项目隔离两套判据（`is7` 布尔 / drawingKey 集合）→ 统一 `projectId` | `MAPPING` C1；`DEFECTS_FLOW` D7 | 后端表结构已定 `project_id`，现在改一遍、接后端再改一遍 |
| id 三套格式（entry 微秒串 / `cap_` / `<id>#<idx>`）→ `client_uuid` | `MAPPING` C2 | 同步引擎的幂等键 |
| 删除不联动 → `deleted_at` 软删 | `MAPPING` C4 | 软删是同步机制的一部分 |
| `updateDefect` 只查 `_added`、无 try/catch | `DEFECTS_FLOW` D7、D8 | 会被本地仓库重写取代 |
| 扮演式身份切换 → 权限体系 | `DEFECTS_FLOW` D16 | 已被列为后端方案的客户端改造项 |

---

## 6. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-09-18 | 首版：合并三份规格去重为 **29 条**（批 0×1 / 批 1×14 / 批 2×14），批 3×5 排除并登记去向 |
| 2026-09-18 | **批 1 实施**（13 条，DV-03 按指示跳过）：透明色 bug、4 项死代码/死参数清理、4 处过期注释、3 处写死值、时间轴兜底、报告周期脏数据、转入失败静默。涉及 8 个文件；`dart analyze lib` 0 error / 0 warning |
