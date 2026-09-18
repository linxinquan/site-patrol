# AR量尺 — 交互优化补丁（连续测量模式，覆盖 AR_LIDAR_IMPL_DETAIL.md 的交互设计）

> 适用：在按 AR_LIDAR_IMPL_DETAIL.md 实现的基础上，替换交互方案。
> 目标：去掉"点A/点B"两个按钮，改为**手势驱动连续测量**：点一下=采A → 再点一下=采B → 自动出距离 → 可继续下一组；长按=清除；保留一个"暂停/继续"开关。
> 本补丁只改交互相关代码，深度采样/反投影等核心算法不动。

---

## 1. 新交互规格

| 操作 | 行为 |
|---|---|
| 进入页面 | 自动开始连续测量模式（无需按按钮） |
| 单击屏幕 | 第一下=点A（蓝球）；第二下=点B（红球+绿线）→ 自动算距离 → 顶部卡片更新 → 上一组球/线保留，等下一次单击自动清理并开新组 |
| 长按屏幕(0.6s) | 清除当前组与全部视觉残留，距离卡片清空 |
| 「暂停/继续」按钮 | 暂停=不再采集（可旋转查看场景）；继续=恢复连续测量 |
| 「加入校对」按钮 | 用最近一次测量值 + 手填图纸尺寸 → 写入 MeasureSession（逻辑不变） |
| 顶部提示条 | 动态提示："点屏幕采点A" → "已采点A，请再点一次" → "实测 XXX mm" |

---

## 2. 原生侧改动（`ios/Runner/ArMeasureView.swift`）

### 2.1 枚举语义变更

```swift
/// 采集模式：0=暂停 1=连续测量
enum CaptureMode: Int { case paused = 0, continuous = 1 }
```

### 2.2 setup() 增加长按手势（替换原 setup）

```swift
private func setup() {
    sceneView.session.delegate = self
    sceneView.automaticallyUpdatesLighting = true

    let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
    sceneView.addGestureRecognizer(tap)

    // 长按清除
    let long = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
    long.minimumPressDuration = 0.6
    sceneView.addGestureRecognizer(long)

    channel.setMethodCallHandler { [weak self] call, result in
        self?.handle(call, result: result)
    }
}
```

### 2.3 handleTap 改为 A/B 循环（替换原 handleTap）

```swift
@objc private func handleTap(_ g: UITapGestureRecognizer) {
    guard mode != .paused else { return }
    let p = g.location(in: sceneView)
    guard let world = worldPosition(at: p) else {
        channel.invokeMethod("onError", arguments: "未能命中有效深度，请靠近目标/调整角度后重试")
        return
    }
    if pointA == nil {
        // 新一轮：先清掉上一组的 B 球与连线（A 球会被新 A 覆盖）
        nodeB?.removeFromParentNode(); nodeB = nil
        lineNode?.removeFromParentNode(); lineNode = nil
        pointA = world
        placeSphere(world, color: UIColor.systemBlue, slot: 0)
        channel.invokeMethod("onPointA", arguments: true)
    } else {
        let a = pointA!
        placeSphere(world, color: UIColor.systemRed, slot: 1)
        drawLine(a, world)
        let mm = simd_distance(a, world) * 1000.0
        channel.invokeMethod("onMeasure", arguments: [
            "mm": mm,
            "ax": a.x, "ay": a.y, "az": a.z,
            "bx": world.x, "by": world.y, "bz": world.z,
        ])
        pointA = nil; pointB = nil // 本组结束，等待下一次单击开新组（视觉保留）
    }
}
```

### 2.4 新增长按处理 + setMode 语义更新（替换原 handle 中 setMode 分支）

```swift
@objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
    guard g.state == .began else { return }
    clearPicks()
    channel.invokeMethod("onCleared", arguments: true)
}
```

`handle(_:result:)` 中 setMode 分支改为（暂停**不清除**已有结果）：

```swift
case "setMode":
    mode = CaptureMode(rawValue: (call.arguments as? Int) ?? 0) ?? .paused
    result(true)
```

### 2.5 startSession 后默认进入连续模式

`startSession()` 末尾加：`mode = .continuous`（方法返回前设置）。

---

## 3. Flutter 侧改动（`lib/features/measure/ar_measure_page.dart`）

### 3.1 状态与回调

```dart
bool _paused = false;
String _hint = '点屏幕采点A';

Future<dynamic> _onNative(MethodCall call) async {
  if (call.method == 'onMeasure') {
    final mm = ((call.arguments as Map)['mm'] as num).toDouble();
    if (mounted) setState(() {
      _lastMm = mm;
      _hint = '测量完成，可继续测下一组，或加入校对';
    });
  } else if (call.method == 'onPointA') {
    if (mounted) setState(() => _hint = '已采点A，请再点一次');
  } else if (call.method == 'onCleared') {
    if (mounted) setState(() {
      _lastMm = null;
      _hint = '点屏幕采点A';
    });
  } else if (call.method == 'onError') {
    if (mounted) {
      AppSnack.show(context, call.arguments?.toString() ?? '测量失败',
          kind: AppSnackKind.danger);
    }
  }
}
```

### 3.2 控制条改为单行三按钮（替换原"点A/点B/清除"行）

```dart
Row(
  children: [
    Expanded(
      child: ElevatedButton.icon(
        onPressed: () async {
          _paused = !_paused;
          await _svc.setMode(_paused ? 0 : 1);
          setState(() {});
        },
        icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
        label: Text(_paused ? '继续' : '暂停'),
      ),
    ),
    const SizedBox(width: AppTokens.space2),
    Expanded(
      child: OutlinedButton.icon(
        onPressed: () async {
          await _svc.clear();
          setState(() { _lastMm = null; _hint = '点屏幕采点A'; });
        },
        icon: const Icon(Icons.delete_outline),
        label: const Text('清除'),
      ),
    ),
    const SizedBox(width: AppTokens.space2),
    Expanded(
      child: OutlinedButton(
        onPressed: _lastMm == null ? null : _addToSession,
        child: const Text('加入校对'),
      ),
    ),
  ],
),
```

### 3.3 顶部卡片区加动态提示条（卡片上方）

```dart
Positioned(
  top: AppTokens.space4, left: 0, right: 0,
  child: Column(
    children: [
      // 提示条
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(_hint, style: const TextStyle(color: Colors.white, fontSize: 13)),
      ),
      // 距离卡片（_lastMm != null 时显示，原逻辑保留）
      ...
    ],
  ),
),
```

### 3.4 其余不变

- `_onViewCreated`：`startSession` 后**无需**再调 setMode（原生默认连续模式）
- `_addToSession`、`_svc` 定义、非iOS提示页、路由：均不变

---

## 4. 测试计划追加（在 AR_LIDAR_IMPL_DETAIL.md §5 基础上补 4 条）

| # | 测试项 | 方法 | 通过标准 |
|---|---|---|---|
| 9 | 连续测量 | 连续测 3 组（点A→点B×3） | 每组自动出距离，卡片更新；上一组视觉在下一组首次单击时清理 |
| 10 | 长按清除 | 测完一组后长按屏幕 | 球/线全部消失，卡片清空，提示回"点屏幕采点A" |
| 11 | 暂停/继续 | 暂停后点屏幕 | 暂停时点击无反应；继续后恢复采集 |
| 12 | 加入校对取最近值 | 测两组后点"加入校对" | 写入的是最近一次测量值 |

## 5. 演示话术更新

> "打开就是测量状态：手机对着墙，点一下、再点一下，距离就出来了——测完一组接着测，不用碰任何按钮；长按就能清掉重来。"
