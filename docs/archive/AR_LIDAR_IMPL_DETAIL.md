# AR量尺（LiDAR + ARKit sceneDepth）完整实现指南 — CodeBuddy 执行版

> 任务：为 site-patrol（Flutter iOS/Android/Web）实现 iPhone Pro 高精度 AR 量尺：
> 相机取景 → 点两点 → 实时显示距离(mm) → 结果汇入现有量尺会话（MeasureSession）。
> 精度目标：1m 误差 ≤2cm，3m 误差 ≤5cm（与卷尺对比）。仅 iOS，LiDAR 机型（iPhone 12 Pro 及以上）。
> 本指南给出**可直接落地**的文件清单与代码；实现时先读现有代码，保持风格一致。

---

## ⚠️ 0. 前置条件（动手前先确认）

1. **iOS 无法在 Windows 上编译**：需要一台 Mac（macOS 13+，Xcode 15+）+ 一根数据线 + **实体 iPhone 12 Pro 或更新 Pro 机型**。Apple 免费开发者账号即可真机调试（7 天签名）。
2. **模拟器不支持 ARKit/LiDAR**：`ARSession` 在模拟器上不可用，必须真机测试。
3. 如果暂时没有 Mac/iPhone Pro：本指南的代码照写（iOS 代码在 Mac 上编译验证），测试排在拿到设备后。
4. 相关公开资料（CodeBuddy 可查）：[WWDC20 ARKit4 深度](https://developer.apple.com/jp/videos/play/wwdc2020/10611/?time=418#2)、[Apple 论坛 LiDAR 距离](https://developer.apple.com/forums/thread/709872#1)、[LiDAR 深度感知开发指南](https://blog.csdn.net/outlejackson/article/details/159500499#1)、[arkit_plugin（参考但不用）](https://pub.dev/packages/arkit_plugin/versions/1.1.2/changelog#1)。

---

## 1. 架构总览

```
[Flutter: ArMeasurePage]                         [Flutter 侧]
  ├─ UiKitView(viewType:'ar_measure_view')        全屏 AR 相机预览（原生 ARSCNView）
  ├─ 按钮：点A / 点B / 清除 / 加入校对
  ├─ 结果卡：AR实测 mm + 名称 + 图纸尺寸(手填) → 加入 MeasureSession
  └─ MethodChannel('ar_measure_<viewId>')
        ▲ invokeMethod: isSupported / startSession / setMode(0|1|2) / clear / stopSession
        ▼ callback: onMeasure({mm,x,y,z...}) / onError(msg)
[IOS: ArMeasureView (FlutterPlatformView)]        [原生侧]
  ├─ ARSCNView + ARWorldTrackingConfiguration + frameSemantics=[.sceneDepth,.smoothedSceneDepth]
  ├─ UITapGestureRecognizer（原生捕获点击：UiKitView 会拦截 Flutter 手势）
  ├─ 命中策略：raycast(.estimatedPlane) 优先 → 深度图 5×5 中位数兜底
  └─ 两点确定 → 3D 距离×1000 = mm → 回调 Flutter；场景中画球+连线
```

---

## 2. iOS 原生实现（完整代码）

### 2.1 `ios/Runner/AppDelegate.swift` — 注册平台视图

在现有 AppDelegate 的 `application(_:didFinishLaunchingWithOptions:)` 中、`GeneratedPluginRegistrant.register` 之后加：

```swift
let registrar = self.registrar(forPlugin: "ArMeasureViewPlugin")
if let registrar = registrar {
    registrar.register(ArMeasureViewFactory(messenger: registrar.messenger()),
                       withId: "ar_measure_view")
}
```

### 2.2 新增 `ios/Runner/ArMeasureViewFactory.swift`

```swift
import Flutter
import UIKit

class ArMeasureViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger
    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(withFrame frame: CGRect,
                viewIdentifier viewId: Int64,
                arguments args: Any?) -> FlutterPlatformView {
        return ArMeasureView(frame: frame, viewId: viewId, messenger: messenger)
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}
```

### 2.3 新增 `ios/Runner/ArMeasureView.swift`（核心，约 260 行，完整实现）

```swift
import ARKit
import Flutter
import UIKit

/// 采集模式：0=空闲 1=采集点A 2=采集点B
enum CaptureMode: Int { case idle = 0, captureA = 1, captureB = 2 }

class ArMeasureView: NSObject, FlutterPlatformView {
    private let sceneView: ARSCNView
    private let channel: FlutterMethodChannel
    private var mode: CaptureMode = .idle
    private var pointA: simd_float3?
    private var pointB: simd_float3?
    private var nodeA: SCNNode?
    private var nodeB: SCNNode?
    private var lineNode: SCNNode?

    init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
        sceneView = ARSCNView(frame: frame)
        channel = FlutterMethodChannel(name: "ar_measure_\(viewId)",
                                       binaryMessenger: messenger)
        super.init()
        setup()
    }

    func view() -> UIView { sceneView }

    // MARK: - 初始化
    private func setup() {
        sceneView.session.delegate = self
        sceneView.automaticallyUpdatesLighting = true

        // 原生捕获点击（UiKitView 会拦截 Flutter 手势，Flutter 侧只放按钮）
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        sceneView.addGestureRecognizer(tap)

        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
    }

    // MARK: - Flutter 方法通道
    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isSupported":
            // 仅 LiDAR 机型支持 sceneDepth
            result(ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth))
        case "startSession":
            startSession(); result(true)
        case "setMode":
            mode = CaptureMode(rawValue: (call.arguments as? Int) ?? 0) ?? .idle
            if mode == .idle { clearPicks() }
            result(true)
        case "clear":
            clearPicks(); result(true)
        case "stopSession":
            sceneView.session.pause(); result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func startSession() {
        let cfg = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsFrameSemantics([.sceneDepth, .smoothedSceneDepth]) {
            cfg.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        }
        cfg.planeDetection = [.horizontal, .vertical]
        sceneView.session.run(cfg, options: [.resetTracking, .removeExistingAnchors])
    }

    private func clearPicks() {
        pointA = nil; pointB = nil
        nodeA?.removeFromParentNode(); nodeA = nil
        nodeB?.removeFromParentNode(); nodeB = nil
        lineNode?.removeFromParentNode(); lineNode = nil
    }

    // MARK: - 点击处理
    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        guard mode != .idle else { return }
        let p = g.location(in: sceneView)
        guard let world = worldPosition(at: p) else {
            channel.invokeMethod("onError", arguments: "未能命中有效深度，请靠近目标/调整角度后重试")
            return
        }
        if mode == .captureA {
            pointA = world
            placeSphere(world, color: UIColor.systemBlue, slot: 0)
        } else {
            pointB = world
            placeSphere(world, color: UIColor.systemRed, slot: 1)
        }
        if let a = pointA, let b = pointB {
            drawLine(a, b)
            let mm = simd_distance(a, b) * 1000.0
            channel.invokeMethod("onMeasure", arguments: [
                "mm": mm,
                "ax": a.x, "ay": a.y, "az": a.z,
                "bx": b.x, "by": b.y, "bz": b.z,
            ])
        }
        mode = .idle
    }

    // MARK: - 命中：raycast 优先，深度图兜底
    private func worldPosition(at point: CGPoint) -> simd_float3? {
        // ① raycast（LiDAR 增强下纯色墙面也可命中）
        if let q = sceneView.raycastQuery(from: point,
                                          allowing: .estimatedPlane,
                                          alignment: .any),
           let r = sceneView.session.raycast(q).first {
            return simd_make_float3(r.worldTransform.columns.3)
        }
        // ② 深度图采样兜底
        guard let frame = sceneView.session.currentFrame else { return nil }
        guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth else { return nil }
        let viewport = sceneView.bounds.size
        let orientation: UIInterfaceOrientation = .portrait

        // 视图坐标 → 相机图像坐标（Apple 官方 displayTransform 做法）
        let display = frame.displayTransform(for: orientation, viewportSize: viewport)
        let ip = CGPoint(x: point.x, y: point.y).applying(display.inverted())
        let imgRes = frame.camera.imageResolution
        let ix = ip.x * imgRes.width
        let iy = ip.y * imgRes.height
        guard ix >= 0, iy >= 0, ix < imgRes.width, iy < imgRes.height else { return nil }

        let depthMap = depthData.depthMap
        let confMap = depthData.confidenceMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        CVPixelBufferLockBaseAddress(confMap, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            CVPixelBufferUnlockBaseAddress(confMap, .readOnly)
        }

        let dW = CVPixelBufferGetWidth(depthMap)
        let dH = CVPixelBufferGetHeight(depthMap)
        let sx = CGFloat(dW) / imgRes.width
        let sy = CGFloat(dH) / imgRes.height
        let baseD = CVPixelBufferGetBaseAddress(depthMap)!
            .assumingMemoryBound(to: Float32.self)
        let baseC = CVPixelBufferGetBaseAddress(confMap)!
            .assumingMemoryBound(to: UInt8.self)
        let cx = Int(ix * sx), cy = Int(iy * sy)

        // 5×5 邻域中位数；仅保留高置信度(high=2)像素
        var vals: [Float] = []
        for dy in -2...2 {
            for dx in -2...2 {
                let xx = cx + dx, yy = cy + dy
                guard xx >= 0, yy >= 0, xx < dW, yy < dH else { continue }
                guard baseC[yy * dW + xx] == ARConfidenceLevel.high.rawValue else { continue }
                let d = baseD[yy * dW + xx]
                if d.isFinite && d > 0 { vals.append(d) }
            }
        }
        guard !vals.isEmpty else { return nil }
        vals.sort()
        let depth = vals[vals.count / 2]

        // 内参反投影：像素 → 相机系（ARSCNView 渲染即相机系，无需再用 viewMatrix）
        let intr = frame.camera.intrinsics // 3x3，基于 imageResolution（横版）
        let fx = intr.columns.0.x
        let fy = intr.columns.1.y
        let cx0 = intr.columns.2.x
        let cy0 = intr.columns.2.y
        let local = simd_float3((Float(ix) - cx0) / fx * depth,
                                (Float(iy) - cy0) / fy * depth,
                                depth)
        let world = frame.camera.transform * simd_float4(local, 1)
        return simd_float3(world.x, world.y, world.z)
    }

    // MARK: - 场景可视化
    private func placeSphere(_ world: simd_float3, color: UIColor, slot: Int) {
        if slot == 0 { nodeA?.removeFromParentNode() }
        else { nodeB?.removeFromParentNode() }
        let sphere = SCNSphere(radius: 0.008)
        sphere.firstMaterial?.diffuse.contents = color
        let node = SCNNode(geometry: sphere)
        node.position = SCNVector3(world)
        sceneView.scene.rootNode.addChildNode(node)
        if slot == 0 { nodeA = node } else { nodeB = node }
    }

    private func drawLine(_ a: simd_float3, _ b: simd_float3) {
        lineNode?.removeFromParentNode()
        let v = b - a
        let len = simd_length(v)
        guard len > 1e-4 else { return }
        let mid = (a + b) / 2
        let cyl = SCNCylinder(radius: 0.003, height: CGFloat(len))
        cyl.firstMaterial?.diffuse.contents = UIColor.systemGreen
        let node = SCNNode(geometry: cyl)
        node.position = SCNVector3(mid)
        // 圆柱默认沿 Y 轴 → 旋转到 AB 方向
        node.simdOrientation = simd_quatf(from: simd_float3(0, 1, 0),
                                          to: simd_normalize(v))
        sceneView.scene.rootNode.addChildNode(node)
        lineNode = node
    }
}

extension ArMeasureView: ARSessionDelegate {
    // 预留：如需多帧平均抑制抖动，可在此按锚点累积采样（MVP 可先不做）
}
```

### 2.4 `ios/Runner/Info.plist` — 相机权限（必须）

在 `<dict>` 内加：

```xml
<key>NSCameraUsageDescription</key>
<string>需要使用相机进行AR量尺测量</string>
```

### 2.5 无需新增 Pod 依赖

ARKit 是系统框架，不用改 Podfile。

---

## 3. Flutter 侧实现

### 3.1 `lib/data/models.dart` — MeasureItem 增加 source 字段（无破坏性）

找到 `class MeasureItem`（约 537~561 行），替换为：

```dart
/// 校对清单中的一项：图纸侧量得值 vs 照片侧量得值。
class MeasureItem {
  final String name; // 量尺项，如「梁宽」「墙厚」
  final double drawingMm; // 图纸侧量得（CAD 校准后，mm）
  final double photoMm; // 照片侧量得（参考物标定后，mm）
  final String source; // 来源：'photo' 默认 | 'ar_lidar' AR量尺 | 'manual'
  const MeasureItem({
    required this.name,
    required this.drawingMm,
    required this.photoMm,
    this.source = 'photo',
  });

  double get deviation => photoMm - drawingMm;
  double get deviationPct => drawingMm == 0 ? 0 : deviation / drawingMm * 100;
  bool pass(double tolMm, double tolPct) =>
      deviation.abs() <= tolMm && deviationPct.abs() <= tolPct;

  MeasureItem copyWith({String? name, double? drawingMm, double? photoMm, String? source}) =>
      MeasureItem(
        name: name ?? this.name,
        drawingMm: drawingMm ?? this.drawingMm,
        photoMm: photoMm ?? this.photoMm,
        source: source ?? this.source,
      );
}
```

同文件 `MeasureSession.toJson`（约 627~633 行）items 段加字段：

```dart
        'items': items
            .map((e) => {
                  'name': e.name,
                  'drawingMm': e.drawingMm,
                  'photoMm': e.photoMm,
                  'source': e.source,
                })
            .toList(),
```

`MeasureSession.fromJson`（约 654~661 行）items 段：

```dart
      items: (m['items'] as List? ?? [])
          .map((e) => (e as Map<String, dynamic>))
          .map((e) => MeasureItem(
                name: e['name'] as String? ?? '',
                drawingMm: (e['drawingMm'] as num? ?? 0).toDouble(),
                photoMm: (e['photoMm'] as num? ?? 0).toDouble(),
                source: e['source'] as String? ?? 'photo', // 旧数据兼容
              ))
          .toList(),
```

### 3.2 `lib/core/storage/measure_store.dart` — 序列化同步

`_toJson`（约 51~57 行）items 段加 `'source': e.source,`；
`_fromJson`（约 78~85 行）`MeasureItem(...)` 加 `source: e['source'] as String? ?? 'photo',`。

### 3.3 新增 `lib/core/ar/ar_measure_service.dart`

```dart
import 'package:flutter/services.dart';

/// AR 量尺 MethodChannel 封装（照 vision_service.dart 模式）。
/// viewId 对应原生 ArMeasureView 的 channel 后缀。
class ArMeasureService {
  final MethodChannel channel;

  ArMeasureService({required int viewId})
      : channel = MethodChannel('ar_measure_$viewId');

  Future<bool> isSupported() async =>
      (await channel.invokeMethod<bool>('isSupported')) ?? false;

  Future<void> startSession() async => channel.invokeMethod('startSession');

  Future<void> setMode(int mode) async => channel.invokeMethod('setMode', mode);

  Future<void> clear() async => channel.invokeMethod('clear');

  Future<void> stopSession() async => channel.invokeMethod('stopSession');
}
```

### 3.4 新增 `lib/features/measure/ar_measure_page.dart`（页面，照 measure_page 风格）

结构代码（UI 细节照 AppTokens/AppCard/AppSnack 现有规范补齐）：

```dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ar/ar_measure_service.dart';
import '../../core/storage/measure_store.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/models.dart';
import '../../shared/widgets/app_snack.dart';

/// AR 量尺（LiDAR，iPhone 12 Pro+）。
/// 流程：进入 → 校验支持 → 开始会话 → [点A][点B]（原生侧出距离）→ 加入校对（写入 MeasureSession）。
class ArMeasurePage extends StatefulWidget {
  final MeasureArgs args;
  const ArMeasurePage({super.key, required this.args});

  @override
  State<ArMeasurePage> createState() => _ArMeasurePageState();
}

class _ArMeasurePageState extends State<ArMeasurePage> {
  static const _viewType = 'ar_measure_view';
  static const _viewId = 0;

  late final ArMeasureService _svc;
  double? _lastMm;
  bool _supported = false;
  final _nameCtl = TextEditingController(text: 'AR实测');
  final _drawingCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _svc = ArMeasureService(viewId: _viewId);
    _svc.channel.setMethodCallHandler(_onNative);
  }

  Future<dynamic> _onNative(MethodCall call) async {
    if (call.method == 'onMeasure') {
      final mm = ((call.arguments as Map)['mm'] as num).toDouble();
      if (mounted) setState(() => _lastMm = mm);
    } else if (call.method == 'onError') {
      if (mounted) {
        AppSnack.show(context, call.arguments?.toString() ?? '测量失败',
            kind: AppSnackKind.danger);
      }
    }
  }

  @override
  void dispose() {
    _svc.stopSession();
    _nameCtl.dispose();
    _drawingCtl.dispose();
    super.dispose();
  }

  Future<void> _onViewCreated(int id) async {
    _supported = await _svc.isSupported();
    if (!mounted) return;
    if (!_supported) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('需要 LiDAR 设备'),
          content: const Text('AR量尺需 iPhone 12 Pro 及以上机型，请改用照片量尺。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    await _svc.startSession();
  }

  Future<void> _addToSession() async {
    final drawingMm = double.tryParse(_drawingCtl.text);
    if (_lastMm == null || drawingMm == null || drawingMm <= 0) {
      AppSnack.show(context, '请先完成AR测量并填写图纸尺寸', kind: AppSnackKind.danger);
      return;
    }
    var s = await MeasureStore.load(widget.args.projectKey, widget.args.drawingKey);
    s ??= MeasureSession(
      id: '${widget.args.projectKey}_${widget.args.drawingKey}_ar',
      projectKey: widget.args.projectKey,
      drawingKey: widget.args.drawingKey,
      floor: widget.args.floor,
    );
    final item = MeasureItem(
      name: _nameCtl.text.trim().isEmpty ? 'AR实测' : _nameCtl.text.trim(),
      drawingMm: drawingMm,
      photoMm: _lastMm!,
      source: 'ar_lidar',
    );
    await MeasureStore.save(s.copyWith(items: [...s.items, item]));
    if (mounted) {
      AppSnack.show(context, '已加入校对清单');
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 非 iOS：直接提示（Android/Web 无此能力）
    if (kIsWeb || !Platform.isIOS) {
      return Scaffold(
        appBar: AppBar(title: const Text('AR量尺')),
        body: const Center(child: Text('AR量尺仅支持 iPhone Pro 机型（iOS）')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('AR量尺（LiDAR）')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                UiKitView(
                  viewType: _viewType,
                  onPlatformViewCreated: _onViewCreated,
                  creationParams: null,
                  creationParamsCodec: const StandardMessageCodec(),
                ),
                if (_lastMm != null)
                  Positioned(
                    top: AppTokens.space4,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Card(
                        color: Colors.black.withValues(alpha: 0.65),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          child: Text(
                            '实测 ${_lastMm!.toStringAsFixed(1)} mm',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 控制条
          Padding(
            padding: const EdgeInsets.all(AppTokens.space3),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _btn('点A', () => _svc.setMode(1))),
                    const SizedBox(width: AppTokens.space2),
                    Expanded(child: _btn('点B', () => _svc.setMode(2))),
                    const SizedBox(width: AppTokens.space2),
                    Expanded(child: _btn('清除', () async {
                      await _svc.clear();
                      setState(() => _lastMm = null);
                    })),
                  ],
                ),
                const SizedBox(height: AppTokens.space2),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameCtl,
                        decoration: const InputDecoration(
                            labelText: '量尺项名称', isDense: true,
                            border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: AppTokens.space2),
                    Expanded(
                      child: TextField(
                        controller: _drawingCtl,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                            labelText: '图纸尺寸(mm)', isDense: true,
                            border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: AppTokens.space2),
                    ElevatedButton.icon(
                      onPressed: _addToSession,
                      icon: const Icon(Icons.add),
                      label: const Text('加入校对'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _btn(String label, VoidCallback onTap) => ElevatedButton(
        onPressed: _supported ? onTap : null,
        child: Text(label),
      );
}
```

> 注意：页面里 "点A/点B" 按钮只是设置原生采集模式；**实际的屏幕点击由原生 ARSCNView 的手势处理**，Flutter 侧不做点击采集。

### 3.5 路由与入口

1. `lib/app.dart`：参照现有 MeasurePage 路由（约 124~127 行）加 `ArMeasurePage` 路由
2. `lib/features/measure/measure_page.dart` 照片面板（约 439~455 行按钮行）：加一个 `OutlinedButton.icon('AR量尺（iPhone Pro）')` → `Navigator` 推入 ArMeasurePage（传同一个 `widget.args`）；`kIsWeb`/Android 时隐藏或置灰

---

## 4. 构建与运行

**Mac 上**：
```bash
cd ios && pod install && cd ..
flutter run -d <iPhonePro的udid>   # 真机调试
```
- Xcode 15+；首次需在 Xcode 里选择 Signing Team（免费个人账号即可）
- 真机运行前在 iPhone 上信任开发者证书（设置→通用→VPN与设备管理）

**Windows 现状**：本机只能跑 `flutter analyze` 检查 Dart 侧；iOS 编译必须上 Mac。
- 备选：Codemagic（免费额度 500 分钟/月）配置 macOS 构建；无 Mac 时先把 Swift 代码过一遍语法（可用在线 Swift 编译器粗验），拿到 Mac 后再真机联调。

---

## 5. 联调测试计划（拿到 iPhone Pro 后逐项执行）

| # | 测试项 | 方法 | 通过标准 |
|---|---|---|---|
| 1 | 设备校验 | 进页面 | 非 Pro 机型弹"需要LiDAR"提示；Pro 机型正常进相机 |
| 2 | 1m 精度 | 墙面贴卷尺，点 0→100cm | 实测 1000±20mm |
| 3 | 3m 精度 | 地面/墙面 3m 两点 | 实测 3000±50mm |
| 4 | 纯白墙点选 | 无纹理白墙点两点 | 能命中（LiDAR 特性，普通 ARKit 会失败） |
| 5 | 玻璃/镜面 | 点玻璃 | 允许失败并出现 onError 提示（记录，不判错） |
| 6 | 汇入会话 | 测量→加入校对 | measure_page 清单出现 `AR实测` 项，source=ar_lidar，判定/保存/重进恢复正常 |
| 7 | 旧数据兼容 | 打开旧会话 | 旧 items（无 source）正常显示，默认 photo |
| 8 | 抖动观察 | 手持静止观察距离值 | 数值稳定（若抖动大，后续加多帧平均） |

## 6. 常见坑排查表

| 现象 | 原因 | 处理 |
|---|---|---|
| UiKitView 黑屏 | 会话未启动/相机权限被拒 | 检查 Info.plist 文案与系统权限；确认 onPlatformViewCreated 里调了 startSession |
| 白屏/Flutter 报 "platform view not found" | 工厂未注册 | 检查 AppDelegate 的 registrar(forPlugin:) 注册与 viewType 字符串一致（`ar_measure_view`） |
| 点击无反应 | 未先点"点A/点B"设置模式 | 流程：点A按钮 → 点屏幕 → 点B按钮 → 点屏幕 |
| onError 频繁 | 距离太近(<20cm)/太远(>5m)/暗光/玻璃 | 提示文案引导；5m 内、明亮环境测量 |
| 模拟器一运行就崩 | ARKit 不支持模拟器 | 必须真机 |
| 发热掉帧 | LiDAR 持续开 | 会话按需启停；演示控制在10分钟内 |

## 7. 验收标准

- [ ] 1m/3m 精度达标（≤2cm / ≤5cm）
- [ ] 纯白墙可测
- [ ] 结果入会话、判定、持久化全链路 OK
- [ ] 非 Pro 机型有降级提示
- [ ] `flutter analyze` 无新增 error
- [ ] 录 90 秒演示视频

## 8. 演示脚本

> "这是 iPhone Pro 的激光雷达：手机对着墙，点一下、再点一下——梁高 1 米 8，误差 2 厘米内。以后现场核尺寸，不用带尺子，举起手机就行。"
