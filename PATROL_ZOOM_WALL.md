# 巡场地图优化 — 缩放平移 + 防穿墙（交付 CodeBuddy）

> 背景：巡场地图存在两个体验问题：
> ① 图纸比例大（B05 为 4500×2551），手机上缩成一团看不清，无法放大
> ② 模拟轨迹沿点间直线走，会穿墙——人应沿走廊/通道走
> 本文件是 `PATROL_OPTIMIZE.md` 的**增强补丁**：在已实现的巡场改造基础上叠加。
> 分 P0（缩放，今天可交付）/ P1（穿墙检测与警告）/ P2（自动寻路，二期简述，暂不实现）。

---

## P0：地图缩放与平移（巡场页 + 路线编辑器都要）

**方案**：Flutter 内置 `InteractiveViewer`，不用第三方包。

**`lib/features/patrol/patrol_page.dart`** 地图区（现在约 245~292 行的 LayoutBuilder 部分）改为：

```dart
final _transformController = TransformationController(); // State 字段

// 地图区：
Expanded(
  child: LayoutBuilder(
    builder: (context, constraints) {
      // …原有 contain-fit 计算 pw/ph 不变…
      return InteractiveViewer(
        transformationController: _transformController,
        minScale: 1.0,
        maxScale: 12.0,
        boundaryMargin: const EdgeInsets.all(160),
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: pw,
          height: ph,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(drawing.src, fit: BoxFit.fill),
              CustomPaint(painter: PatrolOverlayPainter(...)),
            ],
          ),
        ),
      );
    },
  ),
)
```

**要点**：
1. `InteractiveViewer` 放在 `Expanded` 内、包住 `SizedBox(pw,ph)`——初始 scale=1 即现在的适配全图状态；双指捏合 / 触控板 / 鼠标滚轮放大到 12×，拖动平移
2. 移动端默认支持双指捏合与单指平移（InteractiveViewer 内置）
3. 加"复位"按钮（AppBar 或地图角落悬浮）：`_transformController.value = Matrix4.identity()`
4. **注意**：放大时路径、检查点、当前位置标记随图一起缩放（MVP 可接受；标记反缩放为固定像素是后续优化，不做）
5. 路线编辑器 `patrol_editor_page.dart` 同样包一层 InteractiveViewer（编辑器里用户需要放大到房间级别布点，这是"沿走廊画点"的前提）

**P0 验收**：
- [ ] 巡场页：双指捏合/滚轮可放大到看清房间与走廊（≥5×），可平移，复位按钮回全图
- [ ] 编辑器：同样可缩放平移，放大状态下加点/拖点坐标正确（缩放矩阵换算用 `localToViewPixel` 思路：显示坐标→child坐标，注意 InteractiveViewer 的变换由 `TransformationController.toScene(localPosition)` 直接给出 child 坐标，用它替代手算）

---

## P1：穿墙检测与警告（编辑器红色高亮 + 巡场页红色渲染）

### P1-1 数据管线：导出墙线段（Python，ezdxf 现成）

**`server/cad_meta_server.py`** 的 `parse_dwg_to_meta()` 增加墙线段提取，输出字段：

```python
# 在返回 meta 的 dict 里追加：
"wall_lines": [
    {"layer": "AD-WALL-B1M$0$WALL", "pts": [[x1,y1],[x2,y2], ...]},
    ...
]
```

实现要点：
1. 遍历 `msp.query('LINE LWPOLYLINE')`
2. 图层过滤：`layer_name.upper()` 含 `'WALL'` 或 含 `'墙'`；**排除**含 `'COL'` 的图层（柱，不是墙线）——`'COL' not in name.upper()`
3. LINE → pts=[[start.x,start.y],[end.x,end.y]]（世界坐标 mm）；LWPOLYLINE → 取各顶点（闭合多段线去掉最后一个重复点）
4. 数量可能数千段，JSON 直接存；体积大也没关系（本地资产）

**`server/cad_meta_build.py`**：
- `OCF_KEYS` 加入 `'dy04_7_B05'`（B05 目前在列表外，必须加，否则生成不了墙线数据；find_dwg 从 `大铲湾DY04_资料` 根递归找，能找到第一轮测试CAD里的B05）
- 生成后**额外拷贝**一份到 Flutter 资产目录：`site-patrol/assets/walls/<key>_walls.json`（新建 assets/walls 目录），并同步 `pubspec.yaml` 注册该 assets 目录：

```yaml
flutter:
  assets:
    - assets/walls/
```

> 说明：App 端用 rootBundle 读本地资产（演示最稳）；后续接网络时再从 cad_meta_server 拉取。

### P1-2 Flutter 侧：墙线加载与相交检测

**新增 `lib/utils/geo.dart`**（纯函数，可单测）：

```dart
/// 线段相交检测（不含端点相接）。返回 true = 两线段严格相交。
bool segmentsIntersect(
    double ax, double ay, double bx, double by,
    double cx, double cy, double dx, double dy) {
  // 标准叉积法：
  double cross(ox, oy, px, py, qx, qy) =>
      (px - ox) * (qy - oy) - (py - oy) * (qx - ox);
  final d1 = cross(cx, cy, dx, dy, ax, ay);
  final d2 = cross(cx, cy, dx, dy, bx, by);
  final d3 = cross(ax, ay, bx, by, cx, cy);
  final d4 = cross(ax, ay, bx, by, dx, dy);
  return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
         ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
}

/// 一段路线折线（相对坐标0-100）是否穿墙。
/// [walls] 为同一相对坐标系下的墙线段 [[ax,ay,bx,by], ...]。
bool routeSegmentHitsWall(double ax, double ay, double bx, double by,
    List<List<double>> walls) {
  for (final w in walls) {
    if (segmentsIntersect(ax, ay, bx, by, w[0], w[1], w[2], w[3])) return true;
  }
  return false;
}
```

**新增 `lib/core/cad/wall_lines.dart`**：

```dart
/// 从本地资产加载某图纸的墙线段，并把世界坐标(mm) 转为相对坐标(0-100)。
/// [mapper] 该图纸校准映射（worldToScreen 逆变换）；未校准返回 null。
Future<List<List<double>>?> loadWallLinesRel(
    String drawingKey, CadCoordMapper mapper) async {
  final raw = await rootBundle.loadString('assets/walls/${drawingKey}_walls.json');
  final j = jsonDecode(raw) as Map<String, dynamic>;
  final rel = <List<double>>[];
  for (final wl in (j['wall_lines'] as List)) {
    final pts = (wl['pts'] as List);
    for (var i = 1; i < pts.length; i++) {
      final a = mapper.worldToScreen(
          (pts[i-1][0] as num).toDouble(), (pts[i-1][1] as num).toDouble());
      final b = mapper.worldToScreen(
          (pts[i][0] as num).toDouble(), (pts[i][1] as num).toDouble());
      rel.add([a.dx / mapper.viewWidth * 100, a.dy / mapper.viewHeight * 100,
               b.dx / mapper.viewWidth * 100, b.dy / mapper.viewHeight * 100]);
    }
  }
  return rel;
}
```

> 注意：`CadCoordMapper.worldToScreen` 在仿射模式下已实现（b=e=0 假设，B05 满足）。图纸未校准时墙线检测不可用——编辑器提示"该图纸未校准，无法检测穿墙"。

### P1-3 编辑器集成（穿墙警告）

`patrol_editor_page.dart`：
1. initState 加载墙线（校准存在时）；维护 `crossingSegs = <int>[]`（穿墙的路线段下标）
2. **每次加点/拖点后**重算：对每段路线调用 `routeSegmentHitsWall` → 穿墙段下标集合
3. 绘制：穿墙段画**红色粗线**，正常段绿色/蓝色；顶部横幅："⚠ 有 N 段路线穿墙，请沿走廊补点"（红色）/ "路线无穿墙"（绿色）
4. 保存时：存在穿墙段 → 弹确认对话框"路线存在穿墙段，仍要保存吗？"（允许保存，因为墙线数据可能有门窗洞口等误差）

### P1-4 巡场页渲染

`PatrolOverlayPainter` 加可选参数 `crossingSegs: Set<int>`：穿墙段画红色；正常段维持现状。巡场页加载墙线后计算传入（路线不变时只算一次）。

### P1 验收

- [ ] 运行 `python cad_meta_build.py` → B05 生成 `dy04_7_B05.json` 含 `wall_lines`，并拷贝出 `assets/walls/dy04_7_B05_walls.json`
- [ ] 编辑器放大到房间级，在房间内点两点（直线横穿墙）→ 该段红色 + 顶部"N 段穿墙"警告
- [ ] 沿走廊在拐角补点 → 警告消除
- [ ] 保存时弹确认框
- [ ] 巡场页穿墙段红色渲染
- [ ] `flutter analyze` + `flutter build web --release` 通过

---

## P2（二期，本次不实现，只记录方案）：A* 自动寻路

目标：用户只点起点/终点/检查点，系统沿可走区域自动生成折线（彻底不穿墙）。

方案：
1. 用 P1 的墙线段在世界坐标下**网格化**（如 500mm 格网）：与墙相交的格子标为障碍，墙体两侧各膨胀一格
2. 检查点吸附到最近可走格 → **A\*** 求最短路径 → 折线简化（Douglas-Peucker）→ 存入 PatrolPlan
3. 依赖 P1 数据；工作量约 1~2 天，等 P1 验证稳定后再排

## 全局约束（与 PATROL_OPTIMIZE.md 一致）

1. 只改巡场相关 + `geo.dart`/墙线加载/Python 管线；不碰量尺、拍照验收、AR
2. 未校准图纸要优雅降级（提示，不崩溃）
3. 每阶段 `flutter analyze` 无新增 error + Web 构建通过；Python 侧在本机跑通 `cad_meta_build.py`
4. 不跑 iOS/Android 构建
