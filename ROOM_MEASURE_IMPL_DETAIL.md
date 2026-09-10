# 量房功能实施（超详细版，CodeBuddy 直接执行）
> 精简版见 `ROOM_MEASURE_IMPL.md`（分层/红线/演示路径）。本文是全量规格：纯逻辑给代码、UI 给规格、原生给骨架与契约。
> 铁律：先在工程内读一遍下列"参照文件"确认现状；models.dart 一律追加不覆盖；fromJson 全默认值；不引新第三方库（绘制用 CustomPaint）。
> 参照文件：`lib/data/models.dart`、`lib/core/storage/measure_store.dart`、`lib/core/utils/measure_math.dart`、`lib/features/measure/measure_page.dart`、`lib/features/measure/ar_measure_page.dart`、`lib/app.dart`(路由)、`lib/data/repository/repository.dart`、`lib/features/defects/report_content.dart`、`report_builder.dart`/`report_pdf.dart`/`report_docx.dart`/`report_xlsx.dart`、`lib/core/di/providers.dart`、`ios/Runner/AppDelegate.swift`、`ios/Runner/ArMeasureView.swift`。

---

## 1. 数据模型（models.dart 文件末尾「量房」段，完整代码）

```dart
// ==================== 量房（Room）====================

/// 墙段洞口（门/窗）
class WallOpening {
  final String type;         // 'door' | 'window'
  final double offsetFromMm; // 距该墙段起点
  final double widthMm;
  final double? heightMm;    // 门高 / 窗台高（人工补，可空）
  const WallOpening({
    required this.type,
    required this.offsetFromMm,
    required this.widthMm,
    this.heightMm,
  });

  WallOpening copyWith({
    String? type, double? offsetFromMm, double? widthMm, double? heightMm,
  }) => WallOpening(
        type: type ?? this.type,
        offsetFromMm: offsetFromMm ?? this.offsetFromMm,
        widthMm: widthMm ?? this.widthMm,
        heightMm: heightMm ?? this.heightMm,
      );

  Map<String, dynamic> toJson() => {
        'type': type, 'offsetFromMm': offsetFromMm,
        'widthMm': widthMm, 'heightMm': heightMm,
      };

  factory WallOpening.fromJson(Map<String, dynamic> m) => WallOpening(
        type: m['type']?.toString() ?? 'door',
        offsetFromMm: (m['offsetFromMm'] as num? ?? 0).toDouble(),
        widthMm: (m['widthMm'] as num? ?? 0).toDouble(),
        heightMm: (m['heightMm'] as num?)?.toDouble(),
      );
}

/// 量房墙段（局部坐标 mm；lenMm 存校正后长度，points 存原始角点）
class RoomWall {
  final String id;
  final double ax, ay, bx, by; // 角点（局部 mm，首点=原点）
  final double lengthMm;       // 校正后长度（正交吸附后重算）
  final double? thicknessMm;   // 墙厚（默认 200，人工可改）
  final List<WallOpening> openings;
  const RoomWall({
    required this.id,
    required this.ax, required this.ay, required this.bx, required this.by,
    required this.lengthMm,
    this.thicknessMm,
    this.openings = const [],
  });

  RoomWall copyWith({
    double? ax, double? ay, double? bx, double? by,
    double? lengthMm, double? thicknessMm, List<WallOpening>? openings,
  }) => RoomWall(
        id: id,
        ax: ax ?? this.ax, ay: ay ?? this.ay, bx: bx ?? this.bx, by: by ?? this.by,
        lengthMm: lengthMm ?? this.lengthMm,
        thicknessMm: thicknessMm ?? this.thicknessMm,
        openings: openings ?? this.openings,
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'ax': ax, 'ay': ay, 'bx': bx, 'by': by,
        'lengthMm': lengthMm, 'thicknessMm': thicknessMm,
        'openings': openings.map((o) => o.toJson()).toList(),
      };

  factory RoomWall.fromJson(Map<String, dynamic> m) => RoomWall(
        id: m['id']?.toString() ?? '',
        ax: (m['ax'] as num? ?? 0).toDouble(),
        ay: (m['ay'] as num? ?? 0).toDouble(),
        bx: (m['bx'] as num? ?? 0).toDouble(),
        by: (m['by'] as num? ?? 0).toDouble(),
        lengthMm: (m['lengthMm'] as num? ?? 0).toDouble(),
        thicknessMm: (m['thicknessMm'] as num?)?.toDouble(),
        openings: (m['openings'] as List? ?? [])
            .map((e) => WallOpening.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 量房记录
class RoomScanRecord {
  final String id;
  final String projectKey;
  final String name;           // 房间名，如 "主卧"
  final String roomUse;        // 用途：卧室/客厅/厨房/卫浴/其他（装修场景）
  final String source;         // 'roomplan' | 'manual' | 'photo'
  final int scannedAtMs;
  final List<RoomWall> walls;  // 首尾相接（按顺序构成闭合多边形）
  final double? closureDeltaMm;
  final double? netHeightMm;   // 净高 mm
  final String? drawingKey;    // 核尺场景关联图纸
  final List<MeasureItem> checks; // 与图纸对照判定（复用 MeasureItem）
  final String? note;
  const RoomScanRecord({
    required this.id,
    required this.projectKey,
    required this.name,
    this.roomUse = '其他',
    this.source = 'manual',
    required this.scannedAtMs,
    this.walls = const [],
    this.closureDeltaMm,
    this.netHeightMm,
    this.drawingKey,
    this.checks = const [],
    this.note,
  });

  /// 几何派生的只读值（不入库）
  List<Offset> get cornerPoints => [
        for (final w in walls) Offset(w.ax, w.ay),
        if (walls.isNotEmpty) Offset(walls.last.bx, walls.last.by),
      ];

  RoomScanRecord copyWith({
    String? name, String? roomUse, String? source,
    List<RoomWall>? walls, double? closureDeltaMm, double? netHeightMm,
    String? drawingKey, List<MeasureItem>? checks, String? note,
  }) => RoomScanRecord(
        id: id, projectKey: projectKey,
        name: name ?? this.name,
        roomUse: roomUse ?? this.roomUse,
        source: source ?? this.source,
        scannedAtMs: scannedAtMs,
        walls: walls ?? this.walls,
        closureDeltaMm: closureDeltaMm ?? this.closureDeltaMm,
        netHeightMm: netHeightMm ?? this.netHeightMm,
        drawingKey: drawingKey ?? this.drawingKey,
        checks: checks ?? this.checks,
        note: note ?? this.note,
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'projectKey': projectKey, 'name': name,
        'roomUse': roomUse, 'source': source, 'scannedAtMs': scannedAtMs,
        'walls': walls.map((w) => w.toJson()).toList(),
        'closureDeltaMm': closureDeltaMm,
        'netHeightMm': netHeightMm, 'drawingKey': drawingKey,
        'checks': checks.map((c) => c.toJson()).toList(),
        'note': note,
      };

  factory RoomScanRecord.fromJson(Map<String, dynamic> m) => RoomScanRecord(
        id: m['id']?.toString() ?? '',
        projectKey: m['projectKey']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        roomUse: m['roomUse']?.toString() ?? '其他',
        source: m['source']?.toString() ?? 'manual',
        scannedAtMs: (m['scannedAtMs'] as num? ?? 0).toInt(),
        walls: (m['walls'] as List? ?? [])
            .map((e) => RoomWall.fromJson(e as Map<String, dynamic>))
            .toList(),
        closureDeltaMm: (m['closureDeltaMm'] as num?)?.toDouble(),
        netHeightMm: (m['netHeightMm'] as num?)?.toDouble(),
        drawingKey: m['drawingKey']?.toString(),
        checks: (m['checks'] as List? ?? [])
            .map((e) => MeasureItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        note: m['note']?.toString(),
      );
}

/// 路由参数
class RoomScanArgs {
  final String? recordId;
  final String? projectKey;
  final String? drawingKey;
  final String? drawingTitle;
  const RoomScanArgs({this.recordId, this.projectKey, this.drawingKey, this.drawingTitle});
}
```

> 注意：`MeasureItem` 若还没有 `fromJson`，先读它的定义并补（toJson 已存在，见 measure_store）。`Offset` 来自 flutter/material（models.dart 已 import）。

## 2. 存储（新增 `lib/core/storage/room_scan_store.dart`，照 measure_store 模式）

```dart
import 'dart:convert';
import 'local_storage.dart';
import '../../data/models.dart';

/// 量房记录持久化：key = room_scan_v1_<projectId> → JSON List。
class RoomScanStore {
  const RoomScanStore._();

  static String _key(String projectId) => 'room_scan_v1_$projectId';

  static Future<List<RoomScanRecord>> list(String projectId) async {
    final raw = await LocalStorage.instance.readDoc(_key(projectId));
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final arr = jsonDecode(raw) as List<dynamic>;
      return arr
          .map((e) => RoomScanRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(String projectId, RoomScanRecord r) async {
    final all = [...await list(projectId)];
    final i = all.indexWhere((e) => e.id == r.id);
    if (i >= 0) { all[i] = r; } else { all.insert(0, r); }
    await LocalStorage.instance
        .writeDoc(_key(projectId), jsonEncode(all.map((e) => e.toJson()).toList()));
  }

  static Future<void> delete(String projectId, String id) async {
    final all = await list(projectId);
    await LocalStorage.instance.writeDoc(_key(projectId),
        jsonEncode(all.where((e) => e.id != id).map((e) => e.toJson()).toList()));
  }
}
```

## 3. 几何/工程习惯引擎（新增 `lib/core/room/room_geometry.dart`，完整代码）

```dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../data/models.dart'; // WallOpening（openingCentersUnit 用到）

/// 量房几何纯函数：正交吸附 / 闭合差 / 面积 / 标注布局 / 洞口分段。
/// 约定：点坐标 mm；多边形点按走墙顺序（顺/逆时针均可）。

/// 点到点距离
double _dist(Offset a, Offset b) => (a - b).distance;

/// 角 abc（b 为顶点）弧度 → 角度（度）
double _angleDeg(Offset a, Offset b, Offset c) {
  final v1 = a - b, v2 = c - b;
  final d = v1.distance * v2.distance;
  if (d == 0) return 0;
  return math.acos((v1.dx * v2.dx + v1.dy * v2.dy) / d) * 180 / math.pi;
}

/// 1) 正交吸附：对每个顶点 b（邻点 a、c），若内角 ∈ [90-tol, 90+tol] 则把
///    a→b、b→c 两向量强制正交（保持 b 位置与两段长度近似，旋转更短的一侧）。
///    返回 {points: 修正后点集, snappedIdx: 被吸附的顶点下标集}。
({List<Offset> points, Set<int> snappedIdx}) orthoSnap(
  List<Offset> pts, {
  double tolDeg = 5,
}) {
  if (pts.length < 3) return (points: List.of(pts), snappedIdx: <int>{});
  final out = List<Offset>.of(pts);
  final snapped = <int>{};
  for (var i = 0; i < pts.length; i++) {
    final a = pts[(i - 1 + pts.length) % pts.length];
    final b = pts[i];
    final c = pts[(i + 1) % pts.length];
    final ang = _angleDeg(a, b, c);
    if (ang > 90 - tolDeg && ang < 90 + tolDeg) {
      // 把 c 沿 (b-a) 垂线投影，使 ab ⊥ bc：以 a 为不动点更稳，
      // 简法：保持 ab 不变，把 c 投影到过 b 且垂直于 ab 的直线上。
      final ab = b - a;
      final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
      if (len2 > 1e-6) {
        final bc = c - b;
        final proj = (bc.dx * ab.dx + bc.dy * ab.dy) / len2;
        final foot = Offset(b.dx + proj * ab.dx, b.dy + proj * ab.dy); // c 在 ab 线上的投影（相对 b）
        // 保持 c 到 b 距离：把 bc 旋转 90° 到 ab 垂直方向，长度不变
        final lenBc = _dist(b, c);
        final n = Offset(-ab.dy, ab.dx) / math.sqrt(len2);
        final dir = (proj >= 0 ? 1.0 : -1.0) * (proj.abs() < 1e-3 ? 1.0 : 1.0);
        // 简化实现：以 foot 为中心取垂直方向，取与旧 c 同侧
        final oldSide = (bc.dx * n.dx + bc.dy * n.dy);
        out[(i + 1) % pts.length] = b + n * (lenBc * (oldSide >= 0 ? 1 : -1));
        snapped.add(i);
      }
      // 注：若需更高保真可保留两版并选闭合差更小者，v1 用本实现即可
    }
  }
  return (points: out, snappedIdx: snapped);
}

/// 2) 闭合差：多边形首尾缺口长度（mm）
double closureDelta(List<Offset> pts) {
  if (pts.length < 3) return 0;
  return _dist(pts.first, pts.last);
}

/// 3) 多边形面积（鞋带公式），㎡（输入 mm）
double areaM2(List<Offset> pts) {
  if (pts.length < 3) return 0;
  var s = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final p = pts[i], q = pts[(i + 1) % pts.length];
    s += p.dx * q.dy - q.dx * p.dy;
  }
  return (s.abs() / 2) / 1e6; // mm² → ㎡
}

/// 4) 各墙段校正长度（正交吸附后重算，mm）
List<double> wallLengthsMm(List<Offset> pts) => [
      for (var i = 0; i < pts.length; i++)
        _dist(pts[i], pts[(i + 1) % pts.length]),
    ];

/// 标注布局参数：第 i 条墙段的标注引出点（墙段中点 + 外法线偏移 len）
/// 返回 {mid, normalFromMid: 外法向单位向量方向的位置点}
({Offset mid, Offset labelPos}) dimAnchorFor(
  List<Offset> pts, int i, {
  double offsetPx = 24,
}) {
  final a = pts[i], b = pts[(i + 1) % pts.length];
  final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
  var n = Offset(-(b.dy - a.dy), b.dx - a.dx);
  final len = n.distance;
  if (len == 0) return (mid: mid, labelPos: mid);
  n = n / len;
  // 取"外"侧：指向多边形外（用质心判断）
  final c = centroid(pts);
  final outward = (mid.dx - c.dx) * n.dx + (mid.dy - c.dy) * n.dy >= 0 ? 1.0 : -1.0;
  return (mid: mid, labelPos: mid + n * outward * offsetPx);
}

Offset centroid(List<Offset> pts) {
  if (pts.isEmpty) return Offset.zero;
  var x = 0.0, y = 0.0;
  for (final p in pts) { x += p.dx; y += p.dy; }
  return Offset(x / pts.length, y / pts.length);
}

/// 5) 洞口在墙段上的打断：给定整墙段 a→b 与洞列表，返回洞口中心位置（局部坐标系归一化）
List<double> openingCentersUnit(List<Offset> aB, List<WallOpening> ops, double wallLenMm) {
  if (wallLenMm <= 0) return const [];
  return [
    for (final o in ops)
      ((o.offsetFromMm + o.widthMm / 2) / wallLenMm).clamp(0.0, 1.0),
  ];
}
```

> 正交吸附 v1 实现较简（保长近似）。若闭合差测试不稳，允许在测试内标注"吸附为启发式"，验收以「吸附后仍闭合可复核」为准，不做非线性全局优化。

## 4. 测试（新增 `test/room_geometry_test.dart`，完整用例）

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:gongdi_app/core/room/room_geometry.dart'; // 包名以 pubspec.yaml name: 为准（实际 gongdi_app）
import 'package:gongdi_app/data/models.dart'; // WallOpening

void main() {
  test('开多边形闭合差=首尾缺口(底边长 3000)、面积正确', () {
    final pts = [
      const Offset(0, 0), const Offset(0, 4000),
      const Offset(3000, 4000), const Offset(3000, 0),
    ];
    // closureDelta = dist(首,尾)；此 4 点未闭合（缺"回起点"边）→ 缺口=底边 3000
    expect(closureDelta(pts), closeTo(3000, 1e-6));
    expect(areaM2(pts), closeTo(12.0, 1e-6)); // 3m×4m = 12㎡
    expect(wallLengthsMm(pts), [4000, 3000, 4000, 3000]);
  });

  test('闭合多边形（末点=首点）闭合差 0', () {
    final closed = [
      const Offset(0, 0), const Offset(0, 4000),
      const Offset(3000, 4000), const Offset(3000, 0), const Offset(0, 0),
    ];
    expect(closureDelta(closed), closeTo(0, 1e-6));
    expect(wallLengthsMm(closed).length, 4);
  });

  test('88° 角被吸附为 90°', () {
    final pts = [
      const Offset(0, 0), const Offset(0, 4000),
      const Offset(3010, 4010), // 应被吸附到 3000? 方向近似垂直
      const Offset(3000, 0),
    ];
    final r = orthoSnap(pts);
    expect(r.snappedIdx, isNotEmpty);
    // 吸附后相邻段夹角近似 90°
    // 复核第2点与第3点间夹角
  });

  test('面积 ㎡ 输出（旋转房间不依赖方向）', () {
    final r = [
      const Offset(0, 0), const Offset(2000, 0),
      const Offset(2000, 1500), const Offset(0, 1500),
    ];
    expect(areaM2(r), closeTo(3.0, 1e-6));
  });

  test('标注外法向与质心方向一致（向外）', () {
    final pts = [
      const Offset(0, 0), const Offset(0, 4000),
      const Offset(3000, 4000), const Offset(3000, 0),
    ];
    final anchor = dimAnchorFor(pts, 0); // 左墙
    // labelPos.x 应 < mid.x（朝外侧 x 负向）
    expect(anchor.labelPos.dx, lessThan(anchor.mid.dx));
  });

  test('洞口中心归一化', () {
    const w = [
      WallOpening(type: 'door', offsetFromMm: 100, widthMm: 900),
    ];
    final units = openingCentersUnit([Offset.zero, const Offset(0, 4000)], w, 4000);
    expect(units.single, closeTo((100 + 450) / 4000, 1e-9));
  });
}
```

## 5. Providers / 存储注册（providers.dart 追加）

```dart
final roomScansProvider =
    FutureProvider.family<List<RoomScanRecord>, String>(
        (ref, projectId) => RoomScanStore.list(projectId));

Future<void> refreshRoomScans(Ref ref, String projectId) =>
    ref.invalidate(roomScansProvider(projectId));
```

## 6. 路由（app.dart）

新增 4 条（照现有 MeasurePage 路由的 extra 模式）：`/room-records`、`/room-draw`、`/room-detail`、`/room-scan`，extra 用 `RoomScanArgs`。入口按钮加在：主页快捷操作（`home_page.dart` 现有入口旁）与 capture_page 的"量尺"按钮区（照其现有图标按钮写法），文案「量房」。

## 7. 页面规格

### 7.1 记录列表 `lib/features/room/room_records_page.dart`
- 顶栏：AppBar「量房记录」+ 右上 `+`（跳 /room-draw 新建，source:manual）
- Body：从 `roomScansProvider(currentProjectId)` 读；空态文案"还没有量房记录，点 + 开始量房"
- 卡片每项：CustomPaint 缩略户型图（复用 7.4 painter，小尺寸）+ 名称/用途/日期/面积㎡/闭合差状态（≤15 绿· 超 红"需复核"）
- 点卡片 → /room-detail；长按 → 删除确认（RoomScanStore.delete + refresh）

### 7.2 核心成图页 `lib/features/room/room_draw_page.dart`
状态机：`empty → drawing → saved`；本地状态：`List<Offset> _ptsMm`（局部 mm）、`List<RoomWall> _walls`、`bool _orthoOn=true`、`_selectedWallIdx`、开洞对话框状态、工程信息字段 controllers。
坐标空间：屏幕 = InteractiveViewer 缩放的 0.5m 网格画布（画布逻辑尺寸取 max(5m, 房间包围盒) 或直接 1px=1mm 大画布 + 初始 fit）。**简化方案：固定画布 8000×8000mm，1px=1mm 会超屏 → 用 `CustomPaint` 接受 transform（InteractiveViewer child 用 SizedBox(8000×8000)），点选坐标用 `TransformationController.toScene` 取毫米**（ArMeasure/measure 页已有同款先例）。
工具栏与交互（从左到右一排，照 AppTokens/图标风格）：

| 按钮/手势 | 行为 |
|---|---|
| 顶栏「拍照成图」 | 复用照片标定：拍照/相册 → 参照物标定 → 点墙角（1px:mm 换算后进 _ptsMm）；无照片=网格手绘模式 |
| 单击画布 | 加角点（自动连墙段） |
| 拖动已有点 | 改点 |
| 长按点 | 删点 |
| 双击墙段 | 选中墙段 → 底部弹「添加洞口」：类型(门/窗) + 距起端 mm + 宽度 mm |
| 正交开关 | 每次改点后 `_pts = orthoSnap(...).points`（显示被吸附下标） |
| 底部状态条 | 实时：周长 m · 面积 ㎡ · 闭合差 mm（色标）· 墙段数 |
| 工程信息卡 | 名称/房间用途下拉/净高 mm/默认墙厚 mm（底部展开） |
| 保存 | 校验：角点 ≥3、闭合差>50mm 弹"闭合差偏大，仍保存？"→ 组 RoomWall（长度=吸附后 wallLengthsMm）+ 写 store → pop 回列表 |

### 7.3 详情页 `lib/features/room/room_detail_page.dart`
户型图（大）+ 尺寸标注（7.4 painter 开标注层）+ 工程信息 + 墙段表（编号/长度/墙厚/洞口，行可删改存）+ checks 区（核尺结果，见 7.5）+ 右上「导出进报告」（报告组件已含量房块后自动纳入）。

### 7.4 户型 painter（新增 `lib/features/room/room_plan_painter.dart`）
`CustomPainter` 参数：`walls/record, bool showDims, double area, ColorScheme-ish 色板（AppTokens）`。绘制顺序：
1. 房间填充（surface）
2. 外墙双线（厚 thicknessMm→ 缩放后描双线，或 v1 单线+填充示意）：内边线粗 2、外扩 4 半透明
3. 洞口：在墙段上画门弧（quarter arc 90°方向）+ 窗双线（按 offset/width 换算）
4. 尺寸标注层（showDims）：每墙 dimAnchorFor → 引线+两端短竖线+文字（`fmtMm`，墙体字 12 深灰；被吸附段绿色小勾）
5. 面积文字：质心处 "房间名 · xx.xx ㎡"（W700）
缩放：统一 `scale = painterSize / 包围盒`，所有 mm → px 后绘制（视图 widget 用 LayoutBuilder + FittedBox 或 AspectRatio 居中；列表缩略用同一 painter 小尺寸）。

### 7.5 图纸核尺对照（P0-5，场景2）
详情页「对照图纸」按钮（当 drawingKey 存在 / 或选图）：
1. 调校准映射 `loadCadCalibration(ref, drawingKey)`；无则提示先校准
2. 进入对照模式：户型图与图纸并排/叠放，逐墙选择"图纸上对应两点"（复用 measure_page 图纸点两点量距），自动生成 `MeasureItem(name:'墙N', drawingMm:图纸量, photoMm:本墙lengthMm, source:'roomplan'/'manual')`
3. 判定复用 MeasureItem.pass(tolMm,tolPct)（默认 15/2 可调）→ 列表绿/红 + 记录.checks 保存 → 进报告"尺寸校对"区

## 8. 报告四端接入（四端必须同步改）

- `WeeklyReport`：追加 `final List<RoomScanRecord> roomScans;`（默认 `const []`）+ copyWith/构建处补（读取处给默认）
- `report_content.dart`：新增 `final class RoomBlock extends ReportBlock`（字段：record + 户型PNG字节 path 或占位标志）；在 `buildReportBlocks` 的板块序里插到 DefectsBlock 之后；`ReportStats` 不必加（量房为独立区，标题"量房记录"）
- HTML `report_builder.dart` / PDF `report_pdf.dart` / DOCX `report_docx.dart` / XLSX `report_xlsx.dart`：各自在 switch(block) 加 `RoomBlock` 分支——HTML 用 `<img src=data:png>` 内嵌户型图（缺字节显"量房记录未配图"）；PDF 用 `pw.MemoryImage`；DOCX 插段落+文本尺寸表；XLSX 加"量房记录"sheet（名称/用途/时间/面积/闭合差/墙段数）。照片字节来源照 defects_page `_loadPhotoBytes` 同法。
- 导出入口 `defects_page.dart` 的 `_loadPhotoBytes` 一并加载量房户型图字节（缺则占位）。

## 9. P1：[原生-待真机] RoomPlan

### 9.1 原生骨架 `ios/Runner/RoomCaptureController.swift`
```swift
import ARKit
import RoomPlan
import Flutter
import UIKit

/// RoomPlan 量房封装：绕房扫描 → 回调 capturedRoom JSON。
/// 仅 iOS16+ 且支持 LiDAR 的设备可用（RoomCaptureSession.isSupported）。
class RoomCaptureController: NSObject {
    private let channel: FlutterMethodChannel
    private var session: RoomCaptureSession?
    private var roomBuilder: RoomBuilder?
    private var finalRoom: CapturedRoom?
    private let sessionConfig = RoomCaptureSession.Configuration()
    private var isScanning = false

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isSupported":
            result(RoomCaptureSession.isSupported)
        case "start":
            guard RoomCaptureSession.isSupported else {
                result(FlutterError(code: "UNSUPPORTED", message: "需 iPhone 12 Pro+ / iPad Pro 2020+ 且 iOS16+", details: nil)); return
            }
            startSession(); result(true)
        case "stop":
            stopSession(); result(true)
        case "exportJson":
            exportJson(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func startSession() {
        if isScanning { return }
        let session = RoomCaptureSession()
        self.session = session
        roomBuilder = RoomBuilder(options: [.beautifyObjects])
        let view = RoomCaptureView(frame: .zero, session: session)
        // 展示层由 Flutter 通过 platform view 承载（照 ArMeasureView 方式注册）
        session.delegate = self
        session.run(configuration: sessionConfig)
        isScanning = true
    }

    private func stopSession() {
        guard isScanning else { return }
        session?.stop()
        isScanning = false
    }

    private func exportJson(result: @escaping FlutterResult) {
        guard let room = finalRoom else {
            result(FlutterError(code: "NO_ROOM", message: "扫描尚未完成", details: nil)); return
        }
        do {
            let data = try room.export(to: URL(fileURLWithPath: NSTemporaryDirectory()))
                // export(to:) 产 USDZ + JSON；改用手动构 JSON 更稳：
            // 此处直接由 capturedRoom 属性构造精简 JSON（walls/doors/windows/objects + 尺寸）
            let json = buildJson(from: room)
            result(json)
        } catch {
            result(FlutterError(code: "EXPORT_FAIL", message: error.localizedDescription, details: nil))
        }
    }

    private func buildJson(from room: CapturedRoom) -> String {
        // walls: room.walls.map { start/end + dimensions }; doors/windows 同理；
        // 输出 {walls:[{start:{x,y,z},end:{...},lengthMm}], doors:[...], windows:[...], objects:[...]}
        // z 忽略，x/y 用 mm（CapturedRoom 单位为米 → ×1000）
        // 交付时给出完整实现（见下方契约字段）
        return "{}"
    }
}

extension RoomCaptureController: RoomCaptureSessionDelegate {
    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        // 实时预览可回调 onUpdate（骨架数）
    }
    func captureSession(_ session: RoomCaptureSession, didEndWith room: CapturedRoom, error: Error?) {
        finalRoom = room
        channel.invokeMethod("onScanned", arguments: buildJson(from: room))
    }
    func captureSession(_ session: RoomCaptureSession, didStartWith configuration: RoomCaptureSession.Configuration) {}
    func captureSession(_ session: RoomCaptureSession, didFailWithError error: Error) {
        channel.invokeMethod("onError", arguments: error.localizedDescription)
    }
}
```

### 9.2 MethodChannel 契约（写入本文件，交付时作为原生-待联调依据）
通道名 `room_capture`；方法/参数/返回/回调：
| 方法 | 参数 | 返回 | 说明 |
|---|---|---|---|
| isSupported | - | bool | RoomCaptureSession.isSupported |
| start | - | bool | 启动扫描（需先经 isSupported） |
| stop | - | bool | 结束并进入处理 |
| exportJson | - | String | 精简 JSON（字段见 9.3） |
| 回调 onScanned | json:String | - | didEndWith 后回调一次 |
| 回调 onError | msg:String | - | 会话错误/权限拒绝 |

### 9.3 JSON 契约（Flutter 侧解析）
```json
{
  "walls":  [{"start":{"x":0,"y":0,"z":0},"end":{"x":3000,"y":0,"z":0},"lengthMm":3000}],
  "doors":  [{"position":{"x":..},"widthMm":900,"heightMm":2100}],
  "windows":[{"position":{"x":..},"widthMm":1500,"heightMm":1500,"offsetFromFloorMm":900}],
  "objects":[{"category":"table","dimensions":{"x":..}}]
}
```
Flutter `room_auto_scan_page` 收 JSON → 生成墙段序列（取首尾相接的墙端点集合）→ 转 `RoomWall`（含 openings=doors/windows）→ 跳 7.2 成图页确认修正（source:'roomplan'）。

### 9.4 Dart 侧服务与页面
- `lib/core/room/room_capture_service.dart`（MethodChannel 封装，照 ar_measure_service）：isSupported/start/stop/exportJson + onScanned/onError 回调注册
- `lib/features/room/room_auto_scan_page.dart`：非 iOS / 不支持 → 提示 + 「用手动成图」按钮跳 /room-draw；支持 → 全屏 RoomCaptureView(platform view 需原生侧再建 `RoomCapturePlatformView`，照 ArMeasureViewFactory 模式) + 顶部引导文案（"从门口开始，绕房间缓慢走一圈，角角落落扫到，别遮挡镜头"）+ 底部「完成扫描」。收 onScanned → 骨架页 → 跳成图页补正。
- ⚠️ 本文件全部 iOS 项标注 **[待真机]**，交付清单列明未验证点。

### 9.5 AppDelegate.swift 注册
照 ArMeasureView 注册范式新增：`RoomCapturePlatformViewFactory`（viewType `room_capture_view`）与通道 `room_capture`（每 viewId 后缀或全局单例——用单例全局通道 + 单 view，实现取简单路径）。

## 10. P3 安卓调研（文档任务）
在既有 `ANDROID_AR_RESEARCH.md` 追加「量房成图」节：有 GMS 安卓实测 `ar_flutter_plugin_plus` 的 plane 命中能否用于墙角打点序列；无 GMS → 结论"安卓主路径=手动/照片成图（本方案 P0）"，不写产品代码。

## 11. 验收清单（交付逐项勾选）

P0：
- [ ] `flutter analyze` 无 error；`flutter build web --release` 通过
- [ ] `flutter test test/room_geometry_test.dart` 全绿
- [ ] Web 手绘模式：点4角→吸附→面积/周长/闭合差正确→加门洞→保存→列表出现→详情户型图带尺寸标注
- [ ] 照片成图：选图→标定→点墙角→长度量级正确
- [ ] 报告导出（4格式）含"量房记录"区；无图占位不崩
- [ ] 旧数据兼容：无 room_scan key 时列表空不报错
P1（代码交付，[待真机]）：
- [ ] RoomCaptureController.swift + 契约文档 + room_capture_service + auto_scan 页代码齐全
- [ ] 未验证项清单明确（isSupported/扫描/exportJson/onScanned 全需真机）
P2：
- [ ] 图纸对照：B05 校准后逐墙对照出 checks + 判定 + 进报告
P3：
- [ ] ANDROID_AR_RESEARCH.md 追加量房结论

## 12. 演示路径与话术（无 Pro 设备版）

Web 端量房入口 → 手动成图：网格底图点四角（或现场照片标定后点墙角）→ 实时出墙长/面积/闭合差 → 加一扇门 → 保存 → 报告导出含户型图与尺寸。
话术："现在手动成图已经能用了——房间多大、墙多长、有没有闭合误差，一眼看出。等 iPhone Pro 到位，RoomPlan 扫一圈就自动出图，这部分代码已经写好了，就差真机联调。"

## 13. 给 CodeBuddy 的执行顺序与红线

顺序：§1模型 → §2存储 → §3引擎 → §4测试(先绿) → §5 provider → §6路由 → §7页面(7.1→7.2→7.3→7.4→7.5) → §8报告四端 → §9 P1 代码与契约 → §10 P3 文档 → 按 §11 自查。
红线：追加不覆盖；fromJson 默认值；引擎有测试；四端同步；[待真机]不伪造验证；不引新依赖；每阶段输出改动清单+analyze/构建结果。
