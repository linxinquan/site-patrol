import ARKit
import AVFoundation
import Flutter
import UIKit

/// 采集模式：0=暂停 1=连续测量
enum CaptureMode: Int { case paused = 0, continuous = 1 }

class ArMeasureView: NSObject, FlutterPlatformView {
    private let sceneView: ARSCNView
    private let channel: FlutterMethodChannel
    private var mode: CaptureMode = .paused
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

        // 长按清除（AR_UX_SMOOTH.md）
        let long = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        long.minimumPressDuration = 0.6
        sceneView.addGestureRecognizer(long)

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
            // 暂停不再清除已有结果（AR_UX_SMOOTH.md）
            mode = CaptureMode(rawValue: (call.arguments as? Int) ?? 0) ?? .paused
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
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    granted ? self?.runSession() : self?.denyCamera()
                }
            }
        case .denied, .restricted:
            denyCamera()
        case .authorized:
            runSession()
        @unknown default:
            runSession()
        }
    }

    private func denyCamera() {
        channel.invokeMethod("onCameraDenied", arguments: "相机权限被拒绝，请在系统设置中开启")
    }

    private func runSession() {
        let cfg = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsFrameSemantics([.sceneDepth, .smoothedSceneDepth]) {
            cfg.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        }
        cfg.planeDetection = [.horizontal, .vertical]
        do {
            sceneView.session.run(cfg, options: [.resetTracking, .removeExistingAnchors])
            mode = .continuous
        } catch {
            channel.invokeMethod("onError", arguments: "AR会话启动失败：\(error.localizedDescription)")
        }
    }

    private func clearPicks() {
        pointA = nil; pointB = nil
        nodeA?.removeFromParentNode(); nodeA = nil
        nodeB?.removeFromParentNode(); nodeB = nil
        lineNode?.removeFromParentNode(); lineNode = nil
    }

    // MARK: - 点击处理（连续测量：A/B 循环）
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

    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        clearPicks()
        channel.invokeMethod("onCleared", arguments: true)
    }

    // MARK: - 命中：raycast 优先，深度图兜底
    // 数学部分对照 Apple 官方 ARFrame.displayTransform + 内参反投影
    // （WWDC20-10611 / 论坛 thread/709872）：视图点 → displayTransform(逆) →
    // 图像归一化坐标 → ×imageResolution 得像素坐标 → 内参反投影到相机系 →
    // 乘 frame.camera.transform 到世界系。
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
        guard let confMap = depthData.confidenceMap else { return nil }
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
