任务：量房功能 · 段1（地基：数据模型 + 存储 + 几何引擎 + 测试）

范围：只做 `ROOM_MEASURE_IMPL_DETAIL.md` 的 §1~§4。**禁止**实现 §5 及以后的页面/路由/provider（那是段2）。

工作目录：F:\建筑验收工具\site-patrol（Flutter 工程，Windows，不能编 iOS）

──────── 第一步 · 准备工作（先读再动手，不许跳过） ────────
1. 完整读 `ROOM_MEASURE_IMPL_DETAIL.md` 的 §1 模型 / §2 存储 / §3 几何引擎 / §4 测试——四段都给了完整代码，直接采用。
2. 读当前 `lib/data/models.dart`：
   a. 找到 `MeasureItem` 定义。确认它**有没有自带 `toJson` / `fromJson`**（搜 `'drawingMm'`，看它主要在 `measure_store.dart` / `MeasureSession` 里怎么序列化）：
      - 有 → `RoomScanRecord` 序列化直接复用 `MeasureItem.toJson/fromJson`；
      - 没有 → 给 `MeasureItem` **追加** `toJson/fromJson`（放在该类内部，不新建文件；字段名沿用现有序列化写法：`'name'`、`'drawingMm'`、`'photoMm'`、`'source'`——以最新代码实际存在的字段为准，禁止改名或增删现有存储 key）。
   b. 确认文件头已 `import 'package:flutter/material.dart';`（`Offset` 可用）。models.dart 现在若没有 material import 就补，有则不动。
3. 读 `pubspec.yaml` 的 `name:` 字段（决定测试文件的包导入路径），并确认 `test/` 目录存在（不存在则创建）。
4. 读 `pubspec.yaml` 的 dev_dependencies 确认含 `flutter_test`（含则跳过，缺则报告，不擅自加）。

──────── 第二步 · 按序新增 4 处 ────────
1. `lib/data/models.dart` —— 文件**末尾**追加 §1「量房（Room）」段：`WallOpening` → `RoomWall` → `RoomScanRecord` → `RoomScanArgs`（含 copyWith/toJson/fromJson；`fromJson` 所有读取给默认值，任何缺失字段不抛异常）。**只追加，不改不动现有任何行。** `MeasureItem` 序列化按第一步 a 的结论处理。
2. 新建 `lib/core/storage/room_scan_store.dart` —— 用 §2 完整代码；import 相对路径核对：同目录 `local_storage.dart`、模型 `../../data/models.dart`。
3. 新建 `lib/core/room/room_geometry.dart` —— 用 §3 完整代码（含注释），保持纯函数、无 UI 依赖。
4. 新建 `test/room_geometry_test.dart` —— 用 §4 用例；`import 'package:<pubspec的name>/core/room/room_geometry.dart';` 与 `package:flutter/material.dart`、`flutter_test`。

──────── 第三步 · 验证（全绿才算段1完成） ────────
1. `flutter test test/room_geometry_test.dart` → 全绿。
   - 例外容差：`orthoSnap` 是启发式（保长近似）。若"88° 吸附"断言因实现细节不稳，允许把该用例断言放宽为「`snappedIdx` 非空 且 吸附后相邻段夹角≈90°（容差±2°）」；**必须在用例注释里说明原因，不许删用例、不许整用例 skip**。
2. 静态检查：优先 `flutter analyze`。若遇到本机已知的 analysis server 崩溃（exit 255，中文路径环境问题）→ 改用缩小范围 `dart analyze lib/core/room lib/core/storage/room_scan_store.dart lib/data/models.dart`，目标 **0 error**（warning/info 可保留并列出）。
3. `flutter build web --release` 通过（确认新增不破坏整体编译）。

──────── 第四步 · 红线 ────────
- `models.dart` 只追加；不删除/改动任何现有字段与存储 key；`fromJson` 全默认值（null/0/[]/false）
- 不新增任何第三方依赖
- 不实现 §5~§8（页面/路由/provider/报告）与 §9（RoomPlan）的任何代码
- 不调用网络 / 远端服务；不写 iOS/Android 原生
- 不伪造测试结果

──────── 第五步 · 输出（段1结束时交付） ────────
1. 新增/修改文件清单（含行数）
2. `flutter test` 逐用例结果
3. analyze 结果（0 error 确认或错误清单）
4. `MeasureItem` 序列化处理结论：自带 toJson/fromJson？（若没有：你追加了什么，字段名是否与现有存储一致）
5. 遗留风险（如有）
