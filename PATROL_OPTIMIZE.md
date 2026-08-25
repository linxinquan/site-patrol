# 巡场功能优化 — 完整实现文档（交付 CodeBuddy）

> 目标：把巡场从"南科大医院西楼的硬编码demo"改造成"按当前项目、数据驱动、可自定义路线、真实里程/GPS、有历史记录"的功能。
> 共 7 项，分 3 个阶段实现。先读本文件与相关代码，按阶段顺序执行，每阶段结束 `flutter analyze` 无新增 error。
> 工作目录：`F:\建筑验收工具\site-patrol`（Flutter，iOS/Android/Web；本机 Windows 只能跑 analyze + Web 构建）。

---

## 0. 现状盘点（先读这些文件）

| 文件 | 现状问题 |
|---|---|
| `lib/features/patrol/patrol_page.dart` | 底图写死 `assets/drawings/nkf_west_1f.png`；路线/检查点/楼层/里程(0.52km)/时长(16s)/点数(48)全是常量；历史轨迹是假 SnackBar；`_markIssue` 传 `floor:'西楼1F'` 写死 |
| `lib/utils/path_metrics.dart` | `patrolPathPoints`（34点，0-100相对坐标）、`patrolCheckpoints`、`patrolPlanKey='nkf_west_1f'` 硬编码；`PatrolOverlayPainter` 渲染可复用 |
| `lib/data/mock/mock_data.dart` | `allProjects=[tencentProject(id:'tencent-dy04-7'), project(id:'nkf')]`；`dy7Drawings`（B05 有 PNG+校准种子，10张真实图纸）；`drawings`（南科大 PNG） |
| `lib/core/di/providers.dart` | `projectProvider/currentProjectIdProvider/is7DongProjectProvider/drawingsProvider/floorsProvider` 按项目切换已就绪；`cadCalibrationMapProvider/loadCadCalibration` 校准就绪；B05 已有演示校准 seed |
| `lib/data/models.dart` | `CaptureArgs` 已支持 `projectId/drawingKey/drawPointWorldX/drawPointWorldY`（③直接可用）；`Drawing{key,title,src,w,h,cadOcfKey}` |
| `lib/core/storage/local_storage.dart` | `readDoc/writeDoc` JSON 存储（照 `measure_store.dart` 模式） |
| `lib/core/utils/cad_coord.dart` | `CadCoordMapper.screenToWorld`（像素→世界坐标mm，⑤真实里程的算法基础） |

---

## 阶段一：②①③ —— 数据驱动 + 底图换项目 + 标记带真实信息（半天）

### ② PatrolPlan 模型化

**`lib/data/models.dart` 新增三个模型**（放 MeasureArgs 附近）：

```dart
// ==================== 巡场 ====================

/// 巡场路线点（相对坐标 0~100，绑定图纸）。isCheckpoint=true 为检查点。
class PatrolPoint {
  final double dx; // 0~100（对应整图宽度的百分比）
  final double dy; // 0~100
  final bool isCheckpoint;
  const PatrolPoint({required this.dx, required this.dy, this.isCheckpoint = false});

  PatrolPoint copyWith({double? dx, double? dy, bool? isCheckpoint}) =>
      PatrolPoint(
        dx: dx ?? this.dx,
        dy: dy ?? this.dy,
        isCheckpoint: isCheckpoint ?? this.isCheckpoint,
      );

  Map<String, dynamic> toJson() =>
      {'dx': dx, 'dy': dy, 'isCheckpoint': isCheckpoint};

  factory PatrolPoint.fromJson(Map<String, dynamic> m) => PatrolPoint(
        dx: (m['dx'] as num?)?.toDouble() ?? 0,
        dy: (m['dy'] as num?)?.toDouble() ?? 0,
        isCheckpoint: m['isCheckpoint'] == true,
      );
}

/// 巡场路线（一条路线绑定一张图纸、一个项目）。
class PatrolPlan {
  final String id;
  final String projectId;
  final String drawingKey;
  final String name;      // 如 "B1 地下车库巡场路线"
  final String floor;     // 如 "B1"
  final List<PatrolPoint> points;
  final double? totalKm;  // 手动填写的兜底里程（图纸未校准时用）；校准后自动算
  final int updatedAt;
  const PatrolPlan({
    required this.id,
    required this.projectId,
    required this.drawingKey,
    required this.name,
    required this.floor,
    required this.points,
    this.totalKm,
    this.updatedAt = 0,
  });

  List<int> get checkpointIdxs => [
        for (var i = 0; i < points.length; i++)
          if (points[i].isCheckpoint) i
      ];

  PatrolPlan copyWith({
    String? name, String? floor, List<PatrolPoint>? points,
    double? totalKm, int? updatedAt,
  }) =>
      PatrolPlan(
        id: id, projectId: projectId, drawingKey: drawingKey,
        name: name ?? this.name, floor: floor ?? this.floor,
        points: points ?? this.points,
        totalKm: totalKm ?? this.totalKm,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'projectId': projectId, 'drawingKey': drawingKey,
        'name': name, 'floor': floor,
        'points': points.map((p) => p.toJson()).toList(),
        'totalKm': totalKm, 'updatedAt': updatedAt,
      };

  factory PatrolPlan.fromJson(Map<String, dynamic> m) => PatrolPlan(
        id: m['id'] as String? ?? '',
        projectId: m['projectId'] as String? ?? '',
        drawingKey: m['drawingKey'] as String? ?? '',
        name: m['name'] as String? ?? '',
        floor: m['floor'] as String? ?? '',
        points: (m['points'] as List? ?? [])
            .map((e) => PatrolPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalKm: (m['totalKm'] as num?)?.toDouble(),
        updatedAt: (m['updatedAt'] as num? ?? 0).toInt(),
      );
}

/// 一次巡场记录（⑦历史用）。
class PatrolRecord {
  final String id;
  final String planId;
  final String projectId;
  final String drawingKey;
  final String name;
  final int startedAt;   // ms
  final int finishedAt;  // ms
  final double distKm;   // 实际里程（GPS 或按进度估算）
  final int pointCount;  // 采样点数
  final int issueCount;  // 标记问题数
  final List<Map<String, double>> track; // GPS 轨迹 [{lat,lng,ts}]
  const PatrolRecord({
    required this.id, required this.planId, required this.projectId,
    required this.drawingKey, required this.name,
    required this.startedAt, required this.finishedAt,
    required this.distKm, required this.pointCount, required this.issueCount,
    this.track = const [],
  });
  // toJson/fromJson 同上模式（track 直接透传 List<Map>）
}

/// 巡场页路由参数（照 MeasureArgs 模式）。
class PatrolArgs {
  final String? planId;
  const PatrolArgs({this.planId});
}
```

**`lib/core/storage/patrol_plan_store.dart` 新增**（照 `measure_store.dart` 模式）：

```dart
/// 巡场路线持久化。key：patrol_plans_v1_<projectId> → JSON List<PatrolPlan>。
class PatrolPlanStore {
  const PatrolPlanStore._();
  static Future<List<PatrolPlan>> list(String projectId) async { ... }
  static Future<void> save(String projectId, List<PatrolPlan> plans) async { ... }
  // 内部用 LocalStorage.instance.readDoc/writeDoc('patrol_plans_v1_$projectId')
}
```

**`lib/core/di/providers.dart` 新增**：

```dart
final patrolPlansProvider = FutureProvider.family<List<PatrolPlan>, String>(
    (ref, projectId) => PatrolPlanStore.list(projectId));
final patrolRecordsProvider = FutureProvider.family<List<PatrolRecord>, String>(
    (ref, projectId) => PatrolRecordStore.list(projectId));
```

**`lib/data/mock/mock_data.dart` 新增默认路线种子**（两项目各一条，保证首次打开有内容）：

```dart
/// 默认巡场路线种子。南科大 = 原有 34 点路径（迁移自 path_metrics）；
/// 7栋 = B05 地下室夹层平面图上的演示路线（10 点，含 3 个检查点，
/// 具体点位为演示值，上线前用路线编辑器按真实走廊调整）。
const List<PatrolPlan> seedPatrolPlans = [
  PatrolPlan(
    id: 'nkf_default', projectId: 'nkf', drawingKey: 'nkf_west_1f',
    name: '西楼1F 门诊-病房翼巡场', floor: '西楼 1F',
    points: [ /* 把 path_metrics.dart 的 patrolPathPoints 34点搬进来，
               patrolCheckpoints 对应下标 isCheckpoint=true */ ],
  ),
  PatrolPlan(
    id: 'dy7_default', projectId: 'tencent-dy04-7', drawingKey: 'dy04_7_B05',
    name: 'B1 地下室夹层巡场路线', floor: 'B1',
    points: [
      PatrolPoint(dx: 20, dy: 20), PatrolPoint(dx: 20, dy: 50, isCheckpoint: true),
      PatrolPoint(dx: 35, dy: 50), PatrolPoint(dx: 35, dy: 75, isCheckpoint: true),
      PatrolPoint(dx: 55, dy: 75), PatrolPoint(dx: 55, dy: 50),
      PatrolPoint(dx: 70, dy: 50, isCheckpoint: true), PatrolPoint(dx: 70, dy: 20),
      PatrolPoint(dx: 40, dy: 20),
    ],
  ),
];
```

> 首次读取逻辑：`PatrolPlanStore.list(projectId)` 为空时，取 seed 中该项目的计划返回（不强制写库；用户保存编辑后才写库）。

### ① 底图换成当前项目图纸 + 绑定 drawingKey

**`lib/features/patrol/patrol_page.dart` 改造**：
1. 构造改为 `PatrolPage({required this.args})`（`PatrolArgs`，go_router extra 传入；tab 入口处 extra 传 `const PatrolArgs()`）
2. initState 里解析计划：
   ```dart
   // 读当前项目 id（ref.watch(projectProvider)）→ patrolPlansProvider(projectId)
   // → 有 planId 用指定计划，否则取该计划列表第一条；没有则提示"请先创建巡场路线"并给跳编辑页按钮
   ```
3. 底图：`final drawing = drawingsAsync.valueOrNull?[plan.drawingKey];` → `Image.asset(drawing.src)`；删除 `nkf_west_1f.png` 写死
4. 渲染比例：用 `drawing.w / drawing.h` 替代写死的 `1500/944`
5. 顶部"楼层"chip：`plan.floor`（删除"西楼 1F"写死）
6. 检查点下标：`plan.checkpointIdxs` 替代 `patrolCheckpoints`

### ③ _markIssue 传真实项目信息

`patrol_page.dart` 的 `_markIssue()` 改为：

```dart
void _markIssue() {
  final rel = _currentRel(); // 0~1
  final mapper = ref.read(cadCalibrationMapProvider)[plan.drawingKey];
  double? wx, wy;
  if (mapper != null) {
    // 0~1 → 整图像素（drawing.w/h）→ 世界坐标 mm
    final px = rel.dx * drawingW;
    final py = rel.dy * drawingH;
    final w = mapper.screenToWorld(px, py);
    wx = w.dx; wy = w.dy;
  }
  context.push('/capture', extra: CaptureArgs(
    projectId: plan.projectId,
    floor: plan.floor,
    anchorLabel: '巡场中·当前位置',
    x: rel.dx, y: rel.dy,
    drawingKey: plan.drawingKey,
    drawPointWorldX: wx, drawPointWorldY: wy,
  ));
}
```

> `CaptureArgs` 无需改（字段已存在）。唯一改动：`drawingW/H` 从当前 Drawing 取。

**阶段一验收**：
- [ ] 切到"腾讯大铲湾DY04·7栋"打开巡场 → 底图是 B05，楼层 chip 显示 "B1"，路线/检查点按 seed 渲染
- [ ] 切回南科大项目 → 底图/路线还是原西楼1F（旧演示不破坏）
- [ ] 巡场中"标记问题点" → 拍照页收到 projectId/drawingKey/floor，B05 已校准时带 worldX/Y

---

## 阶段二：④⑤ —— 路线编辑器 + 真实里程（1 天）

### ④ 路线编辑模式

**新增 `lib/features/patrol/patrol_editor_page.dart`**（交互规格照量尺页的经验实现）：

| 操作 | 行为 |
|---|---|
| 单击图纸空白处 | 追加一个路点（显示坐标→0~100相对坐标） |
| 拖动已有点 | 移动（GestureDetector onPanUpdate，拖后保存新坐标） |
| 长按点 | 删除该点 |
| 双击点 | 切换检查点标记（蓝色实心=检查点，空心=普通点） |
| 撤销 | 移除最后一个点 |
| 清空 | 清空全部 |
| 保存 | 校验 points≥2 → 写入 PatrolPlanStore（新计划：id=时间戳，projectId/drawingKey/name/floor 从页面表单取） |

技术要点：
- 底图 `Image.asset(drawing.src)` + `LayoutBuilder`；**坐标换算用与 measure_page 相同的 contain 反算**（显示坐标→整图坐标→`/w*100` 相对坐标；绘制时反向映射）
- 覆盖层 `CustomPaint`：折线（照 `roundPolyline` 风格）+ 点（检查点蓝/普通白）+ 序号
- 入口：巡场页 AppBar 右侧"编辑路线"icon（或底部面板加"路线管理"），go_router 加 `/patrol-editor` 路由（extra: `PatrolArgs(planId)`；编辑已有计划则预填）
- 编辑后可改 name/floor 两个文本框

### ⑤ 按图纸校准算真实里程

**`lib/utils/path_metrics.dart` 新增纯函数**：

```dart
/// 按校准后的 CAD 坐标计算路线真实里程（km）。
/// [points] 相对坐标 0~100；[mapper] 图纸校准映射；[imgW]/[imgH] 整图像素尺寸。
/// 图纸未校准返回 null（调用方用 plan.totalKm 兜底）。
double? realRouteKm(List<PatrolPoint> points, CadCoordMapper mapper,
    double imgW, double imgH) {
  if (points.length < 2) return null;
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    final a = mapper.screenToWorld(
        points[i-1].dx / 100 * imgW, points[i-1].dy / 100 * imgH);
    final b = mapper.screenToWorld(
        points[i].dx / 100 * imgW, points[i].dy / 100 * imgH);
    total += (a - b).distance; // mm
  }
  return total / 1e6; // → km
}
```

`patrol_page.dart` 的 `_totalKm` 改为动态：
```dart
// initState/校准加载后计算一次：
_totalKm = realRouteKm(plan.points, mapper, drawing.w, drawing.h)
    ?? plan.totalKm ?? 0.0;
```
里程 chip 显示实算值；统计说明文字改为"里程（按图纸实算）"（未校准则"里程（估算）"）。

> 注意：B05 的 seed 校准是演示值（含系统偏移，见 providers.dart 注释），演示里程有偏差属正常；真实校准后自动变准——这本身就是给院长讲的亮点。

**阶段二验收**：
- [ ] 编辑器：加5个点→拖动1个→长按删1个→双击设2个检查点→保存→巡场页路线更新
- [ ] 保存后重进 App 路线仍在（LocalStorage）
- [ ] B05（已校准）巡场页里程 chip 显示实算 km（≈路线长度），南科大（未校准）走 totalKm 兜底
- [ ] 点数 chip = 按进度 × 路线点数（不再用常量 48）

---

## 阶段三：⑥⑦ —— GPS 真实轨迹 + 历史记录（1 天）

### ⑥ GPS 真实轨迹

1. **依赖**：`pubspec.yaml` 加 `geolocator: ^13.0.1`（pub.dev 标准包，Web 走浏览器定位；添加后需 `flutter pub get`）
2. **权限**：
   - `android/app/src/main/AndroidManifest.xml` 加 `<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>` + `<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>`
   - `ios/Runner/Info.plist` 加 `NSLocationWhenInUseUsageDescription`（"巡场需要定位以记录真实轨迹"）
   - 运行时：`Geolocator.requestPermission()`；拒绝 → 退化为现有计时模式（UI 提示"手动模式"）
3. **新增 `lib/features/patrol/patrol_location_service.dart`**：

```dart
class PatrolLocationService {
  StreamSubscription<Position>? _sub;
  final List<Map<String, double>> track = [];
  double distKm = 0;
  Position? _last;

  Future<bool> start() async {
    final ok = await Geolocator.isLocationServiceEnabled();
    final perm = await Geolocator.checkPermission();
    if (!ok || perm == LocationPermission.deniedForever) return false;
    var p = perm;
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return false;
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 2),
    ).listen((pos) {
      if (_last != null) {
        distKm += Geolocator.distanceBetween(
            _last!.latitude, _last!.longitude, pos.latitude, pos.longitude) / 1000;
      }
      _last = pos;
      track.add({'lat': pos.latitude, 'lng': pos.longitude,
                 'ts': pos.timestamp.millisecondsSinceEpoch.toDouble()});
    });
    return true;
  }
  void stop() { _sub?.cancel(); _sub = null; }
}
```

4. `patrol_page.dart`：`_start()` 时启动 GPS（异步）；运行中里程 chip 显示 `gps.distKm`（GPS 可用）否则沿用进度估算；顶部状态 chip 增加"GPS/手动"标识；`_finish()` 停止 GPS 并生成 PatrolRecord（`track=gps.track`、`issueCount`=本次巡场期间标记问题数——`_markIssue` 成功跳转时计数 +1）
5. **注意**：GPS 不需要网络（卫星信号），"离线 · GPS 仍记录"文案保持正确

### ⑦ 历史记录列表

1. **新增 `lib/core/storage/patrol_record_store.dart`**（key `patrol_records_v1_<projectId>`，保存/追加/列表，照 measure_store 模式）
2. **新增 `lib/features/patrol/patrol_history_page.dart`**：按时间倒序列表，每条显示：名称/日期/时长/里程/点数/问题数；点击进详情（统计 + 轨迹点数 + 起点终点），MVP 不做回放动画
3. `patrol_page.dart` 的 `_showHistory()` 改为 `context.push('/patrol-history')`（删除假 SnackBar）
4. go_router 加 `/patrol-history` 路由

**阶段三验收**：
- [ ] 真机上授权定位 → 巡场记录真实 track、里程随走动增长
- [ ] 拒绝定位 → 正常降级计时模式，不崩溃
- [ ] 完成巡场 → 历史列表出现记录；重进 App 记录仍在
- [ ] 每条记录统计正确（时长/里程/点数/问题数）

---

## 全局约束

1. 只改巡场相关文件 + 通用模型/存储；**不要动量尺（measure_*）、拍照验收、AR 相关文件**
2. 所有存储读取给默认值兜底，旧数据不抛异常
3. 每阶段结束：`flutter analyze` 无新增 error + `flutter build web --release` 通过
4. 不要跑 iOS/Android 构建（Windows 无法验证；geolocator 的原生部分留待 Mac/真机验证，Dart 侧先静态通过）
5. 删除被替代的常量时：`path_metrics.dart` 的 `patrolPathPoints/patrolCheckpoints` 迁移进 mock 种子后**保留原注释说明出处**，`patrolPlanKey` 一并移除（检查全项目无引用后再删）

## 完成后的演示脚本（巡场）

> "巡场不再是写死的demo：打开就是当前项目的图纸和路线——B1地下室的巡场路线是我们自己在图纸上画的，里程按图纸真实坐标算出来；现场走一圈，GPS记录真实轨迹，历史记录随时回看。以后每个项目，设计院5分钟就能配一条自己的巡场路线。"
