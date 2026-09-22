import ARKit
import AVFoundation
import Flutter
import UIKit

/// 采集模式：0=暂停 1=连续测量
enum CaptureMode: Int { case paused = 0, continuous = 1 }

/// 命中类型（吸附来源）：决定 Dart 侧的"已吸附：…"提示与后续吸附策略。
///
/// - plane：命中平面（地面/墙面）
/// - edge：命中**平面边界线**（墙根/墙角线、物体边界）——施工量尺最常用的锚点
/// - corner：命中**平面角点**（两面墙交角、柱角）——比边线更稳，优先吸附
/// - feature：命中**特征点**（无平面几何时的物体边界点云）
/// - depth：深度图兜底（无 raycast 命中）
enum SnapKind: String {
    case plane, edge, corner, feature, depth
}

/// 吸附阈值（mm）：命中点离平面边界/角点超过它就"不吸附"，
/// 避免把用户本意落在面中间的点强行拉到边缘上。
private let kSnapDistanceMm = 30.0
private let kCornerRatio = 0.12

class ArMeasureView: NSObject, FlutterPlatformView {
    private let sceneView: ARSCNView
    private let channel: FlutterMethodChannel
    private var mode: CaptureMode = .paused
    private var pointA: simd_float3?
    private var pointB: simd_float3?
    private var nodeA: SCNNode?
    private var nodeB: SCNNode?
    private var lineNode: SCNNode?
    private var labelNode: SCNNode?
    /// 已画出的面/体（半透明几何 + 边缘线），clearAreaVolume 或下次绘制时替换。
    private var faceNode: SCNNode?

    init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
        sceneView = ARSCNView(frame: frame)
        // channel 用固定名，与 Dart 端 ArMeasureService 保持一致；
        // 不拼接 viewId，避免两端 id 不一致导致通道对不上。
        channel = FlutterMethodChannel(name: "ar_measure_channel",
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
        case "showArea":
            // 画一个面域（半透明填充 + 边缘线 + 中央文字），corners 为 4 角世界坐标（米）
            guard
                let args = call.arguments as? [String: Any],
                let raw = args["corners"] as? [[Double]],
                raw.count == 4,
                raw.allSatisfy({ $0.count >= 3 })
            else { result(false); return }
            let c = raw.map { simd_float3(Float($0[0]), Float($0[1]), Float($0[2])) }
            showArea(corners: c, label: (args["label"] as? String) ?? "")
            result(true)
        case "showVolume":
            // 画一个体积（半透明体 + 边缘线 + 中央文字）：origin + 三条边向量（米）
            guard
                let args = call.arguments as? [String: Any],
                let o = args["origin"] as? [Double], o.count >= 3,
                let w = args["w"] as? [Double], w.count >= 3,
                let d = args["d"] as? [Double], d.count >= 3,
                let h = args["h"] as? [Double], h.count >= 3
            else { result(false); return }
            showVolume(
                origin: simd_float3(Float(o[0]), Float(o[1]), Float(o[2])),
                w: simd_float3(Float(w[0]), Float(w[1]), Float(w[2])),
                d: simd_float3(Float(d[0]), Float(d[1]), Float(d[2])),
                h: simd_float3(Float(h[0]), Float(h[1]), Float(h[2])),
                label: (args["label"] as? String) ?? "")
            result(true)
        case "clearAreaVolume":
            clearAreaVolume(); result(true)
        case "snapPicture":
            // 相机画面 + 当前 AR 标注层合成一张 PNG（base64 回传，Dart 负责存相册）
            if let png = sceneView.snapshot().pngData() {
                result(png.base64EncodedString())
            } else {
                result(FlutterMethodNotImplemented)
            }
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
        labelNode?.removeFromParentNode(); labelNode = nil
    }

    // MARK: - 命中与吸附
    /// 命中并**吸附**：raycast 已对齐平面 → 平面边界/角点 → 特征点 → 深度图兜底。
    ///
    /// 施工量尺里用户要的是"墙根线/墙角点"这类**边界**，而 libre 命中点往往落在
    /// 面中间；这里在命中后把点投影到最近的平面边界（阈值 [kSnapDistanceMm]），
    /// 靠近顶点则吸附为角点。这样连续量墙长/开间不会因为手抖而每次差几厘米。
    private func hitSnapped(at point: CGPoint) -> (pos: simd_float3, kind: SnapKind, snapMm: Double)? {
        // ① 已有平面几何：精确命中该平面
        if let q = sceneView.raycastQuery(from: point,
                                          allowing: .existingPlaneGeometry,
                                          alignment: .any),
           let r = sceneView.session.raycast(q).first {
            let p = simd_make_float3(r.worldTransform.columns.3)
            if let s = snapToPlaneBoundary(p) { return s }
            return (p, .plane, 0)
        }
        // ② 估计平面（扫描初期，平面还没成型）
        if let q = sceneView.raycastQuery(from: point,
                                          allowing: .estimatedPlane,
                                          alignment: .any),
           let r = sceneView.session.raycast(q).first {
            let p = simd_make_float3(r.worldTransform.columns.3)
            if let s = snapToPlaneBoundary(p) { return s }
            return (p, .plane, 0)
        }
        // ③ 特征点（物体边界点云）：无平面时的"吸附物体边界"来源
        let hits = sceneView.hitTest(point, types: [.featurePoint,
                                                    .estimatedVerticalPlane,
                                                    .existingPlaneUsingExtent])
        if let f = hits.first {
            return (simd_make_float3(f.worldTransform.columns.3), .feature, 0)
        }
        // ④ 深度图兜底
        if let p = worldPositionFromDepth(at: point) { return (p, .depth, 0) }
        return nil
    }

    /// 把命中点吸附到最近的**平面边界线/角点**；不满足阈值返回 nil（保持原命中点）。
    private func snapToPlaneBoundary(_ p: simd_float3)
        -> (pos: simd_float3, kind: SnapKind, snapMm: Double)? {
        guard let frame = sceneView.session.currentFrame else { return nil }
        var best: (simd_float3, SnapKind, Double)?
        for anchor in frame.anchors {
            guard let plane = anchor as? ARPlaneAnchor else { continue }
            let local = plane.geometry.boundaryVertices
            guard local.count >= 2 else { continue }
            let verts: [simd_float3] = local.map { v in
                let w = anchor.transform * simd_float4(v, 1)
                return simd_make_float3(w.x, w.y, w.z)
            }
            for i in 0..<verts.count {
                let a = verts[i]
                let b = verts[(i + 1) % verts.count]
                let (proj, t) = Self.closestPointOnSegment(p, a, b)
                let d = Double(simd_distance(p, proj) * 1000.0)
                if d > kSnapDistanceMm { continue }
                // 靠近线段端点（t→0/1）视为角点：两侧墙的交角，最稳的量尺基准
                let isCorner = t < kCornerRatio || t > 1 - kCornerRatio
                let kind: SnapKind = isCorner ? .corner : .edge
                if best == nil || d < best!.2 {
                    best = (proj, kind, d)
                }
            }
        }
        guard let b = best else { return nil }
        return (b.0, b.1, b.2)
    }

    /// 点到线段的最近点与参数 t（0=起点，1=终点）。
    private static func closestPointOnSegment(_ p: simd_float3, _ a: simd_float3, _ b: simd_float3)
        -> (simd_float3, Double) {
        let ab = b - a
        let len2 = simd_length_squared(ab)
        if len2 < 1e-9 { return (a, 0) }
        let t = Double(simd_dot(p - a, ab) / len2)
        let tc = max(0.0, min(1.0, t))
        return (a + ab * Float(tc), t)
    }

    // MARK: - 点击处理（连续测量：A/B 循环）
    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        guard mode != .paused else { return }
        let p = g.location(in: sceneView)
        guard let hit = hitSnapped(at: p) else {
            channel.invokeMethod("onError", arguments: "未能命中有效深度，请靠近目标/调整角度后重试")
            return
        }
        let world = hit.pos
        if pointA == nil {
            // 新一轮：先清掉上一组的 B 标记与连线（A 标记会被新 A 覆盖）
            nodeB?.removeFromParentNode(); nodeB = nil
            lineNode?.removeFromParentNode(); lineNode = nil
            labelNode?.removeFromParentNode(); labelNode = nil
            pointA = world
            placeMarker(world, slot: 0, snapped: hit.kind != .depth)
            channel.invokeMethod("onPointA", arguments: [
                "snap": hit.kind.rawValue,
                "edgeMm": hit.snapMm,
            ])
        } else {
            let a = pointA!
            placeMarker(world, slot: 1, snapped: hit.kind != .depth)
            drawLine(a, world)
            let mm = simd_distance(a, world) * 1000.0
            // 线与标注样式：与 Dart 侧 measure_style 同一口径（m + 3 位小数）。
            drawLabel(Self.lengthText(mm), at: (a + world) / 2)
            // 距相机的深度（mm）：LiDAR 有效区间约 0.3~5m，超过则误差迅速放大，
            // 由 Dart 侧做最佳区间提示与超量程拒绝（见 ar_measure_page 的门控）。
            let cam = sceneView.session.currentFrame?.camera.transform.columns.3
            var depthA = 0.0, depthB = 0.0
            if let c = cam {
                let camPos = simd_make_float3(c.x, c.y, c.z)
                depthA = Double(simd_distance(camPos, a) * 1000.0)
                depthB = Double(simd_distance(camPos, world) * 1000.0)
            }
            channel.invokeMethod("onMeasure", arguments: [
                "mm": mm,
                "ax": a.x, "ay": a.y, "az": a.z,
                "bx": world.x, "by": world.y, "bz": world.z,
                "depthA": depthA, "depthB": depthB,
                "depthMm": (depthA + depthB) / 2.0,
                "snapB": hit.kind.rawValue,
                "edgeMmB": hit.snapMm,
            ])
            pointA = nil; pointB = nil // 本组结束，等待下一次单击开新组（视觉保留）
        }
    }

    /// 长度文案：≥1m 用 m + 3 位小数，否则 mm 取整（与 Dart `fmtLengthText` 一致）。
    private static func lengthText(_ mm: Double) -> String {
        if abs(mm) >= 1000.0 {
            return String(format: "%.3fm", mm / 1000.0)
        }
        return String(format: "%.0fmm", mm)
    }

    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        clearPicks()
        channel.invokeMethod("onCleared", arguments: true)
    }

    // MARK: - 深度图兜底（raycast 全部落空时使用）
    // 数学部分对照 Apple 官方 ARFrame.displayTransform + 内参反投影
    // （WWDC20-10611 / 论坛 thread/709872）：视图点 → displayTransform(逆) →
    // 图像归一化坐标 → ×imageResolution 得像素坐标 → 内参反投影到相机系 →
    // 乘 frame.camera.transform 到世界系。
    private func worldPositionFromDepth(at point: CGPoint) -> simd_float3? {
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

    // MARK: - 场景可视化（样式对齐参考样张：明黄线 + 方块端点 + 文字标注）
    /// 端点标记：**方形**薄片（空心观感由白底+黄边构成），恒面向相机。
    ///
    /// 参考样张的端点是"空心方块"而非圆点；吸附命中时用实心黄块区分
    /// （用户能一眼看出这个点是吸到边界上的）。
    private func placeMarker(_ world: simd_float3, slot: Int, snapped: Bool) {
        if slot == 0 { nodeA?.removeFromParentNode() } else { nodeB?.removeFromParentNode() }
        let side: CGFloat = 0.016
        let plane = SCNPlane(width: side, height: side)
        let mat = SCNMaterial()
        mat.diffuse.contents = snapped ? UIColor(red: 1.0, green: 0.77, blue: 0.0, alpha: 1.0)
                                       : UIColor.white
        mat.emission.contents = mat.diffuse.contents
        mat.isDoubleSided = true
        // 空心方块：白底 + 黄描边（用 image 不方便，这里用两层薄片近似）
        plane.firstMaterial = mat
        let node = SCNNode(geometry: plane)
        node.position = SCNVector3(world)
        // 恒面向相机（billboard），避免侧看变成一条线
        node.constraints = [SCNBillboardConstraint()]
        sceneView.scene.rootNode.addChildNode(node)
        if !snapped {
            let border = SCNPlane(width: side * 1.35, height: side * 1.35)
            let bm = SCNMaterial()
            bm.diffuse.contents = UIColor(red: 1.0, green: 0.77, blue: 0.0, alpha: 1.0)
            bm.emission.contents = bm.diffuse.contents
            bm.isDoubleSided = true
            border.firstMaterial = bm
            let bn = SCNNode(geometry: border)
            bn.position = SCNVector3(0, 0, -0.002)
            bn.constraints = [SCNBillboardConstraint()]
            node.addChildNode(bn)
        }
        if slot == 0 { nodeA = node } else { nodeB = node }
    }

    /// 尺寸线：明黄细圆柱（与 Dart 侧 [kMeasureYellow] 同色）。
    private func drawLine(_ a: simd_float3, _ b: simd_float3) {
        lineNode?.removeFromParentNode()
        let v = b - a
        let len = simd_length(v)
        guard len > 1e-4 else { return }
        let mid = (a + b) / 2
        let cyl = SCNCylinder(radius: 0.0018, height: CGFloat(len))
        cyl.firstMaterial?.diffuse.contents = UIColor(red: 1.0, green: 0.77, blue: 0.0, alpha: 1.0)
        cyl.firstMaterial?.emission.contents = cyl.firstMaterial?.diffuse.contents
        let node = SCNNode(geometry: cyl)
        node.position = SCNVector3(mid)
        // 圆柱默认沿 Y 轴 → 旋转到 AB 方向
        node.simdOrientation = simd_quatf(from: simd_float3(0, 1, 0),
                                          to: simd_normalize(v))
        sceneView.scene.rootNode.addChildNode(node)
        lineNode = node
    }

    /// 统一黄色（与 Dart `kMeasureYellow` 同口径）。
    private func measureYellow() -> UIColor {
        UIColor(red: 1.0, green: 0.77, blue: 0.0, alpha: 1.0)
    }

    /// 给某个父节点添加一条黄色边缘圆柱（不影响测量线）。
    private func addEdge(_ a: simd_float3, _ b: simd_float3, to parent: SCNNode) {
        let v = b - a
        let len = simd_length(v)
        guard len > 1e-4 else { return }
        let cyl = SCNCylinder(radius: 0.0018, height: CGFloat(len))
        cyl.firstMaterial?.diffuse.contents = measureYellow()
        cyl.firstMaterial?.emission.contents = measureYellow()
        let node = SCNNode(geometry: cyl)
        node.position = SCNVector3((a + b) / 2)
        node.simdOrientation = simd_quatf(from: simd_float3(0, 1, 0),
                                          to: simd_normalize(v))
        parent.addChildNode(node)
    }

    /// 画一个面域：半透明黄填充 + 4 条边缘线 + 中央文字。
    private func showArea(corners c: [simd_float3], label: String) {
        clearAreaVolume()
        let parent = SCNNode()
        // 半透明填充（两个三角形）
        let source = SCNGeometrySource(vertices: c.map { SCNVector3($0) })
        let element = SCNGeometryElement(indices: [UInt32(0), 1, 2, 0, 2, 3],
                                         primitiveType: .triangles)
        let geo = SCNGeometry(sources: [source], elements: [element])
        let mat = SCNMaterial()
        mat.diffuse.contents = measureYellow().withAlphaComponent(0.22)
        mat.isDoubleSided = true
        geo.materials = [mat]
        parent.addChildNode(SCNNode(geometry: geo))
        // 边缘线
        for i in 0..<4 { addEdge(c[i], c[(i + 1) % 4], to: parent) }
        sceneView.scene.rootNode.addChildNode(parent)
        faceNode = parent
        drawLabel(label, at: (c[0] + c[2]) / 2)
    }

    /// 画一个体积：半透明黄体 + 12 条边缘线 + 中央文字。
    private func showVolume(origin: simd_float3, w: simd_float3, d: simd_float3,
                            h: simd_float3, label: String) {
        clearAreaVolume()
        let parent = SCNNode()
        // 八个角点
        let o = origin
        let p = [
            o, o + w, o + w + d, o + d,                   // 底面
            o + h, o + h + w, o + h + w + d, o + h + d,     // 顶面
        ]
        // 半透明体：SCNBox 轴对齐 → 按基向量定向（w→x, h→y, d→z，保证右手系）
        let wl = simd_length(w), hl = simd_length(h), dl = simd_length(d)
        if wl > 1e-4 && hl > 1e-4 && dl > 1e-4 {
            let x = simd_normalize(w)
            let y = simd_normalize(h)
            var z = simd_normalize(d)
            if simd_dot(simd_cross(x, y), z) < 0 { z = -z }
            let box = SCNBox(width: CGFloat(wl), height: CGFloat(hl),
                             length: CGFloat(dl), chamferRadius: 0)
            let mat = SCNMaterial()
            mat.diffuse.contents = measureYellow().withAlphaComponent(0.18)
            mat.isDoubleSided = true
            box.materials = [mat]
            let node = SCNNode(geometry: box)
            node.simdOrientation = simd_quatf(simd_float3x3(columns: (x, y, z)))
            node.position = SCNVector3(o + (w + h + d) / 2)
            parent.addChildNode(node)
        }
        // 12 条边缘线
        let edges: [(Int, Int)] = [
            (0, 1), (1, 2), (2, 3), (3, 0),
            (4, 5), (5, 6), (6, 7), (7, 4),
            (0, 4), (1, 5), (2, 6), (3, 7),
        ]
        for (i, j) in edges { addEdge(p[i], p[j], to: parent) }
        sceneView.scene.rootNode.addChildNode(parent)
        faceNode = parent
        drawLabel(label, at: o + (w + h + d) / 2)
    }

    /// 清除已画的面/体。
    private func clearAreaVolume() {
        faceNode?.removeFromParentNode()
        faceNode = nil
    }

    /// 尺寸文字标注（挂在线中点上方，恒面向相机）。
    private func drawLabel(_ text: String, at world: simd_float3) {
        labelNode?.removeFromParentNode(); labelNode = nil
        let t = SCNText(string: text, extrusionDepth: 0.0)
        t.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        t.flatness = 0.2
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor.white
        mat.emission.contents = UIColor.white
        t.firstMaterial = mat
        let node = SCNNode(geometry: t)
        // SCNText 以左下角为原点 → 居中并按毫米尺度缩小
        let scale: Float = 0.0016
        node.scale = SCNVector3(scale, scale, scale)
        let (minB, maxB) = node.boundingBox
        node.pivot = SCNMatrix4MakeTranslation((minB.x + maxB.x) / 2,
                                               (minB.y + maxB.y) / 2, 0)
        node.position = SCNVector3(world.x, world.y + 0.012, world.z)
        node.constraints = [SCNBillboardConstraint()]
        sceneView.scene.rootNode.addChildNode(node)
        labelNode = node
    }
}

extension ArMeasureView: ARSessionDelegate {
    // 预留：如需多帧平均抑制抖动，可在此按锚点累积采样（MVP 可先不做）
}
