# AR量尺（LiDAR + ARKit sceneDepth）— 实现文档（交付 CodeBuddy）

> 目标：在 site-patrol（Flutter）中实现 **iPhone Pro 高精度 AR 量尺**：相机取景 → 点两点 → 显示实测距离(mm)，结果汇入现有量尺会话。
> 精度定位：±1~2cm（5m内，LiDAR），**快速核对/科技感演示**，不替代验收测量。
> 平台：仅 iOS（iPhone 12 Pro 及更新 Pro 机型）；非 Pro 机型显示提示并引导用照片量尺。

---

## 1. 技术原理

1. ARKit 会话开启 **sceneDepth**（`ARWorldTrackingConfiguration.frameSemantics = [.sceneDepth, .smoothedSceneDepth]`）→ LiDAR 为画面生成逐像素深度图（Apple 官方测距仪同款方案，[WWDC20](https://developer.apple.com/jp/videos/play/wwdc2020/10611/?time=418#2)）
2. 用户点屏幕 → **raycast**（`raycastQuery(from:allowing:.estimatedPlane, alignment:.any)`）→ 命中真实物体的 3D 世界坐标（[Apple 论坛：LiDAR 真实距离](https://developer.apple.com/forums/thread/709872#1)）
3. 两个世界坐标的欧氏距离 = 实测尺寸(mm)
4. 增强：点击处用深度图做 **k×k 邻域中位数采样 + 置信度过滤 + 多帧平均**，抑制抖动

## 2. 架构

```
[Flutter: ArMeasurePage]
   │ MethodChannel('ar_measure')
   ▼
[Native iOS 插件 ArMeasurePlugin.swift]（新增，约 300 行）
   ├─ startSession(): ARWorldTrackingConfiguration + sceneDepth
   ├─ tapAt(x, y): raycast + 深度采样 → 返回 {x,y,z, depth, confidence}
   ├─ measureBetween(a, b): 3D 距离 mm
   └─ stopSession()
   ▼
[复用现有] MeasureSession / MeasureItem(source:'ar_lidar') / MeasureStore / 判定逻辑
```

## 3. 新增/修改文件清单

### 新增 A：iOS 原生插件（关键，先写这个）

**文件：`ios/Classes/ArMeasurePlugin.swift`**（Flutter 插件工程模式）

核心代码骨架：

```swift
import ARKit
import Flutter
import UIKit

public class ArMeasurePlugin: NSObject, FlutterPlugin {
    private var session: ARSession?
    private var sceneView: ARSCNView?
    private var lastAnchors: [Int: simd_float3] = [:] // 点位缓存（多帧平均用）
    private var anchorFrameCount: [Int: Int] = [:]

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "ar_measure", binaryMessenger: registrar.messenger())
        let instance = ArMeasurePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isSupported":
            // 仅 LiDAR 机型：sceneDepth 支持判断
            let cfg = ARWorldTrackingConfiguration()
            result(ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth))
        case "startSession":
            start()
            result(true)
        case "tapAt":
            guard let args = call.arguments as? [String: Any],
                  let x = args["x"] as? CGFloat, let y = args["y"] as? CGFloat else {
                result(FlutterError(code: "BAD_ARGS", message: nil, details: nil)); return
            }
            result(tapAt(x: x, y: y))
        case "measure":
            result(measure())
        case "stopSession":
            session?.pause(); result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func start() {
        let cfg = ARWorldTrackingConfiguration()
        cfg.frameSemantics = [.sceneDepth, .smoothedSceneDepth] // LiDAR 深度图
        let view = ARSCNView(frame: .zero)
        view.session.delegate = self
        sceneView = view
        session = view.session
        session?.run(cfg)
    }

    /// 点击 → 世界坐标（raycast 优先，深度采样兜底）
    private func tapAt(x: CGFloat, y: CGFloat) -> [String: Any] {
        guard let sceneView = sceneView else { return [:] }
        let point = CGPoint(x: x, y: y)
        // ① raycast（LiDAR 下对纯色墙也能命中）
        let query = sceneView.raycastQuery(from: point,
                                           allowing: .estimatedPlane, alignment: .any)
        if let query = query, let hit = sceneView.session.raycast(query).first {
            let p = hit.worldTransform.columns.3
            let p3 = simd_float3(p.x, p.y, p.z)
            return ["x": p3.x, "y": p3.y, "z": p3.z,
                    "depth": hit.distance, "confidence": 1.0]
        }
        // ② 兜底：从深度图采样（点周围 5×5 中位数，置信度过滤）
        if let depth = sceneView.session.currentFrame?.smoothedSceneDepth?.depthMap {
            return sampleDepth(depth, at: point)
        }
        return [:]
    }

    /// 深度图采样：5×5 邻域取中位数，confidence<1 的像素剔除
    private func sampleDepth(_ depthMap: CVPixelBuffer, at point: CGPoint) -> [String: Any] {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferLockBaseAddress(depthMap, .readOnly) }
        // … 用 CVPixelBufferGetBaseAddress 读取深度值，收集 5×5 有效值取中位数，
        // 结合 confidenceMap 过滤，再通过 viewport→camera 反投影得到 3D 坐标 …
        return [:]
    }

    /// 两个缓存点位距离（mm）
    private func measure() -> [String: Any] {
        guard let a = lastAnchors[0], let b = lastAnchors[1] else { return [:] }
        let d = simd_distance(a, b) * 1000 // 米 → 毫米
        return ["mm": d]
    }
}

extension ArMeasurePlugin: ARSessionDelegate {
    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // 多帧平均：同一锚点位置连续采样，抑制抖动（可选增强）
    }
}
```

> 说明：`sampleDepth` 的深度反投影（pixel → camera space → world space）是精度核心，用 `frame.camera` 的 `projectionMatrix`/`viewMatrix` 反算；CodeBuddy 实现时参照 [激光雷达深度感知开发指南](https://blog.csdn.net/outlejackson/article/details/159500499#1)。

**iOS 配置**：`ios/Podfile` 无新增依赖（ARKit 系统框架）；`Info.plist` 加相机权限文案 `NSCameraUsageDescription`；Xcode 最低版本需支持 sceneDepth API（iOS 14+）。

### 新增 B：Flutter 页面

**文件：`lib/features/measure/ar_measure_page.dart`**（照 measure_page 的样式与流程）

```dart
class ArMeasurePage extends StatefulWidget {
  final MeasureArgs args; // 复用路由参数
  ...
}
```

- `MethodChannel('ar_measure')` 封装 `ArMeasureService`（照 `vision_service.dart` 的模式）
- 页面流程：`startSession` → 全屏相机预览（用 `PlatformView` 承载 ARSCNView，或原生全屏+手势）→ 点A → 点B → 显示 mm → "加入校对"（填进 MeasureItem，`source: 'ar_lidar'`）
- 进页面先调 `isSupported`：false → 提示"需要 iPhone 12 Pro 及以上机型"，提供"使用照片量尺"跳转

### 修改 C：数据模型（无破坏性）

- `lib/data/models.dart` — `MeasureItem` 加可选字段 `final String source;`（默认 `'photo'`；AR 量尺传 `'ar_lidar'`），`copyWith`/序列化同步；旧数据默认 'photo'，兼容

### 修改 D：入口

- `capture_page.dart` 或 measure 相关入口加"AR量尺"按钮（iOS 显示，Android/Web 隐藏或提示）

## 4. 精度增强清单（LiDAR 也要做）

1. **smoothedSceneDepth**（时域平滑）优先于 raw
2. 点击采样用 **5×5 邻域中位数**，剔除 confidence < 1 的像素
3. 同一锚点**多帧平均**（3~5 帧）后再确认
4. UI 提示：**建议 5 米内测量**；玻璃、镜面、水面测不准
5. 可选：提供"已知 1m 参照自校准"修正系数（同照片标定思路）

## 5. 验收标准

- [ ] iPhone Pro 上：对已知距离（1m / 3m）测量，误差 ≤ 2cm / ≤ 5cm（与卷尺对比）
- [ ] 纯色白墙可正常点选（LiDAR 特性，非 Pro 机型此场景会失败）
- [ ] 结果能"加入校对"，复用现有会话保存/判定/清单
- [ ] 非 Pro 机型：`isSupported=false` 正确提示并引导照片量尺
- [ ] 录 90 秒演示：取景 → 点A点B → 显示距离 → 加入校对

## 6. 演示脚本（给院长/设计师）

> "这是iPhone Pro的激光雷达：手机对着墙，点一下、再点一下——**1米8的梁高，误差在2厘米内**。以后现场核尺寸，不用带尺子，举起手机就行。"

## 7. 红线

1. 定位"快速核对 + 科技感"，**不替代验收测量**（全站仪/激光测距仪）
2. 仅 iPhone 12 Pro+（含 iPad Pro 2020+）支持；演示前确认设备
3. ARSession 耗电/发热明显，演示控制在 10 分钟内
