# 0902 需求 — 现状盘点 + 差距任务实施文档（交付 CodeBuddy）

> 重要：代码近期迭代很快，**动手前必须先读最新文件确认现状**，本表标注 ✅已完成 的不再重做；标 ✅部分 的在其基础上叠加；标 ❌ 的为新增。字段类修改全部向后兼容（默认 null/false）。
> 工作目录：`F:\建筑验收工具\site-patrol`。

---

## A. 现状盘点（已读代码核实，2026-09 基线）

| 需求 | 状态 | 已存在的代码（文件/要点） | 差距 |
|---|---|---|---|
| 1 AI整改意见 | ✅ 部分完成 | `VlDefect/DefectItem/Defect.suggestion`；`core/utils/defect_suggestions.dart` 本地规则库兜底（约11条）；`capture_page` 识别后模型值优先→本地库兜底；缺陷卡显示"AI整改建议"；报告含建议 | 本地库词条少；后端是否两段式返回未知 |
| 3 无信号记点位 | ❌ 未做 | 巡场已建模：`PatrolPlan`(models 1213)/`PatrolRecord`(models 1284)/`PatrolPlanStore` | 无打卡机制（checkins 不存在） |
| 4 手机看CAD | ✅ 部分 | DWG→OCF 管线与查看器已有（`backend_api.txt` 有 dwgToOcf API；dy7 已转 10 张） | 无"用户上传DWG→自动转换"入口 |
| 5 巡场报告 | ✅ 大部分 | **完整报告生成器**：`weekly_report.dart`/`report_builder.dart`(html)/`report_pdf.dart`/`report_docx.dart`/`report_xlsx.dart`/`report_content.dart`；`defects_page` 导出报告（PDF/Word/Excel/HTML+分享）；版式对齐 LDI 巡场报告单（三段式：巡场意见/整改回复/闭合确认）；`Defect` 已扩：building/importance/reply/replyBy/replyTs/completion/closeNote/suggestion/photoPath | 巡场(PatrolRecord)数据未进报告；网页链接待后端 |
| 6 施工方协作 | ❌ | `Defect.reply/replyBy/replyTs`（整改回复数据模型已就绪）；报告已含整改回复区 | 无施工方填写入口(UI/网页)；网页链接待后端 |
| 7 远程解决/取信甲方 | ✅ 部分 | 缺陷证据链字段齐全（照片/坐标/时间/水印哈希）；`Defect.reply` 支持整改回复流；状态机 draft/doing/done/reject | 无"设计师远程处置"动作标记与统计 |

---

## B. 实施任务（按优先级）

### 任务1【P0】扩充本地整改建议库（需求1 收尾）

文件：`lib/core/utils/defect_suggestions.dart`

1. 先读现有 `_rules`（约11条：空鼓/裂缝/渗漏/露筋…）
2. 增补高频缺陷到 **30+ 条**，至少覆盖：结构（蜂窝麻面/孔洞/施工缝渗漏/保护层不足/胀模/错台）、砌筑（灰缝不饱满/通缝/构造柱漏设/拉结筋遗漏）、防水（卷材搭接不足/阴阳角未做附加层/止水带偏位）、装饰（平整度超标/阴阳角不顺直/瓷砖空鼓已覆盖）、机电（套管未封堵/桥架跨接缺失/管道支架间距）
3. 每条格式照现有 `(keywords, suggestion)`：suggestion 写"①…②…③…"分步处置 + 末尾"处理后报监理/设计复核"
4. 验收：`suggestionFor('蜂窝麻面')` 有值；`flutter analyze` 通过

### 任务2【P0】巡场检查点打卡制（需求3）

1. **模型**（先读 `models.dart` 1284 行 `PatrolRecord` 与 `patrol_plan_store.dart`/巡场页现状，若字段已存在则跳过）：
   ```dart
   class CheckIn {
     final int pointIdx;   // 对应 PatrolPlan.points 下标
     final int tsMs;       // 打卡时间
     final String? note;   // 备注（可空）
     // toJson/fromJson
   }
   // PatrolRecord 增加: final List<CheckIn> checkins;（默认 const []）
   ```
2. **巡场页**（`lib/features/patrol/patrol_page.dart`）：运行中底部操作条加"到达打卡"按钮（或长按当前位置=打卡）：
   - 记录当前所在路线最近检查点下标（按 progress 对应最近 checkpoint，或让用户选）
   - 打卡成功 → 顶部提示"已打卡 检查点X/共Y"；重复打卡同一检查点 → 提示已打过
   - 完成后 `PatrolRecord.checkins` 存入 `PatrolRecordStore`（照 patrol_plan_store 模式）
3. **达成率**：完成页/历史详情显示"打卡 已到 n/m（达成率 xx%）"，漏检的检查点在路线图上标红
4. 验收：真机/Web模拟巡场→走2个检查点打卡→完成→历史记录含checkins与达成率；`flutter analyze`+Web构建通过

### 任务3【P0】DWG 自助上传 → OCF 手机查看（需求4）

1. **入口**：`projects_page`（图纸库）或图纸列表页加"上传DWG"按钮（iOS/Android选文件用 `file_picker` 或 `image_picker`不支持dwg→用 file_picker 包；Web 用 file 选择器，`file_picker` 支持全平台；若不愿加依赖，Web先支持+移动端用系统"文件"选择器）
2. **流程**：
   - 选 .dwg → 上传到转换服务（复用 `backend_api.txt` 的浩辰华为云 API：`dwgToOcf` 提交 → 拿 requestId → 轮询 `getTaskStatus` 至 status=2）→ 得 ocfUrl → 落 `server/ocf_cache/` 并登记到项目图纸库（照 `cad_meta_build.py`/`ocf_server.py` 现有逻辑）
   - 转换中显示进度；失败给可读错误（超时/配额/格式）
3. **服务端位置**：先确认 Python 服务（`ocf_server.py`/`cad_meta_server.py`）是否在跑、是否有上传端点；没有则新增 `POST /api/upload-dwg`（multipart）→ 调浩辰转换 → 回调/轮询 → 存 ocf_cache → 返回 drawingKey
4. ⚠️ 商用红线：调用浩辰转换消耗配额，UI 提示"转换中，约 1-2 分钟"
5. 验收：上传1张真实DWG → 图纸库出现 → 手机查看器可打开（图层/测量可用）

### 任务4【P1】设计师远程处置（需求7）

1. **模型**（`Defect` 增加，先读现有字段 363~560 行）：
   ```dart
   /// 设计师处置动作：null=未处置 / remoteFix=远程已解决 / remoteConfirm=远程已答复 / onsite=需到场
   final String? designerAction;  // 'remoteFix'|'remoteConfirm'|'onsite'
   final String? designerNote;    // 处置说明
   final String? designerBy;      // 设计师（默认当前用户）
   final String? designerTs;
   ```
2. **缺陷详情页**（`record_detail_page.dart`）加"设计师处置"卡（仅设计师身份/当前用户）：
   - 三个动作按钮：`远程已解决(销项)` / `远程已答复` / `需到场`
   - 选远程已解决 → 填说明 → status=done、填 designerAction/Note/By/Ts
3. **列表/筛选**：`defects_page` 筛选项加"待设计师处置"（designerAction==null 且 需要处置）；缺陷卡显示设计师处置结果
4. **报告体现**：report_content/stats 增加"设计师远程解决 N 条"，HTML/PDF/DOCX 输出
5. 验收：处置一条→状态与统计正确→报告含"N条远程解决"；字段兼容旧数据

### 任务5【P1】巡场数据进报告 + 施工方回复入口（需求5/6 App 内闭环，网页链接待后端）

> 后端（Express/网页托管）当前目录不存在——**网页链接/施工方网页端一律不做**，先做 App 内闭环，报告照常导出分享。

1. **施工方回复 UI**（利用已有 `Defect.reply/replyBy/replyTs`，目前只有 mock 数据无填写入口）：
   - `record_detail_page.dart` 加"整改回复"卡：施工方角色填 reply（文字）+ 可选整改后照片（复用 image_picker/compress）+ 提交 → 写 reply/replyBy/currentUser/replyTs + status=doing→done（可选"申请复核"）
   - `defects_page` 加筛选项"待回复"（reply 为空）
2. **巡场汇总入报告**：`WeeklyReport`/`report_content.dart` 的板块列表加 `PatrolBlock`（可选）：一次巡场的数据（名称/时间/打卡达成率/里程/问题数）渲染进报告"巡场记录"区——若 PatrolRecord 尚未与 WeeklyReport 打通，先做"周报素材增加巡场小结字段（App内可填）"，巡场模块稳定后再自动注入
3. 验收：施工方回复一条→详情显示→导出报告含"整改回复"；flutter analyze/Web 构建通过

### 任务6【调研】安卓 AR 量尺调研报告（需求2，只出文档不写功能代码）

产出 `ANDROID_AR_RESEARCH.md`，内容：
1. ARCore 支持设备清单口径与国行无 GMS 现实（需实测1台有GMS安卓验证 `ar_flutter_plugin_plus` 示例能否跑通与量距精度 ±?）
2. 华为 AR Engine（HMS）在 Flutter 的实现成本评估（无官方插件→原生插件≈iOS LiDAR 插件工作量）
3. 结论建议（预计：安卓主路径=照片标定量尺；AR 仅 iOS Pro 展示；若必须安卓真AR，选 ARCore POC 并注明覆盖机型）
4. 给决策的一句话 + 若立项的排期估算

### 任务7【P2 待后端确认】施工方网页协作链接（需求6 延伸，本期不做代码）

需求确认点：后端部署位置与接口现状 → 再设计：带 token 链接（查看报告/逐条回复/照片上传）。本期只在文档 `REQUIREMENTS_0902_SOLUTIONS.md` 需求5/6 保留设计说明。

---

## C. 全局约束与验收

1. 每任务先读最新文件（models.dart 已到 1355+ 行，字段以现状为准，存在即跳过/叠加，不重复造）
2. 全部新增字段向后兼容（fromJson 默认 null/false/[]）
3. 分任务交付：每任务 `flutter analyze` 无新增 error + Web 构建通过 + 输出改动清单
4. 不碰与任务无关的功能；不动 AR/iOS 原生（除非任务3涉及后端 Python 服务）
5. 后端（Express/网页）未确认前不做网页链接；改 Python 服务前先确认运行方式（`_start_server.py`/各 server 启动脚本）

## D. 交付顺序建议

任务1（半小时）→ 任务2（1天）→ 任务3（1~1.5天）→ 任务4（0.5~1天）→ 任务5（0.5~1天）→ 任务6 调研文档（并行产出）→ 任务7 待后端
