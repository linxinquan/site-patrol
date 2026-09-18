# AR量尺补全 + 三处BUG修复（交付 CodeBuddy）

> 背景：读代码后诊断确认——AR页每次测量覆盖上次（无多点/无批量保存）、非iOS走"假估算"页面（永远合格，必须删）、AR无权限/无错误处理导致黑屏、拍照记录选点无视觉反馈且label恒为"待选点"（旧构建可能还有拦截）、拍照量尺无权限引导与相册兜底。另：P0-2标记错位修复尚未合入，本次一并做。
> 工作目录：`F:\建筑验收工具\site-patrol`。先读相关文件再改，只动本文涉及的三个功能。

---

## 任务1：AR 多点测量 + 批量保存（lib/features/measure/ar_measure_page.dart）

原生侧不用改（连续测量已就绪）。Flutter 侧：

1. 新增状态 `final List<double> _measurements = [];`（单位mm，按测量顺序）
2. `_onNative` 的 `onMeasure` 分支改为**追加**：
   ```dart
   setState(() {
     _lastMm = mm;
     _measurements.add(mm);
     _hint = '已测 ${_measurements.length} 组，可继续测或保存';
   });
   ```
3. `onCleared` 时清空 `_measurements`
4. 结果区改为列表：距离卡片下方加 `SizedBox(height:180)` 的 ListView，每行 `实测 ${m.toStringAsFixed(1)} mm` + 序号 + 删除按钮（删除单条）
5. **"保存"按钮（替换原"加入校对"）**：把 `_measurements` **全部**写入 MeasureSession：
   ```dart
   Future<void> _saveAll() async {
     if (_measurements.isEmpty) {
       AppSnack.show(context, '暂无测量结果', kind: AppSnackKind.danger);
       return;
     }
     final drawingMm = double.tryParse(_drawingCtl.text);
     var s = await MeasureStore.load(widget.args.projectKey, widget.args.drawingKey);
     s ??= MeasureSession(id: '${widget.args.projectKey}_${widget.args.drawingKey}_ar',
         projectKey: widget.args.projectKey, drawingKey: widget.args.drawingKey,
         floor: widget.args.floor);
     final items = [
       for (var i = 0; i < _measurements.length; i++)
         MeasureItem(
           name: 'AR-${i + 1}',
           drawingMm: (drawingMm ?? 0),
           photoMm: _measurements[i],
           source: 'ar_lidar',
         ),
     ];
     await MeasureStore.save(s.copyWith(items: [...s.items, ...items]));
     if (mounted) {
       AppSnack.show(context, '已保存 ${items.length} 条测量');
       Navigator.of(context).pop();
     }
   }
   ```
6. 若 `_drawingCtl` 为空：允许保存（drawingMm=0），清单页后续手填——保存按钮校验改为"仅要求有测量结果"

## 任务2：AR 黑屏修复（ios/Runner/ArMeasureView.swift + ar_measure_page.dart）

### 2.1 原生（ArMeasureView.swift）

`startSession()` 改为带权限检查与错误捕获：

```swift
import AVFoundation // 文件顶部

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
```

### 2.2 Flutter（ar_measure_page.dart）

1. `_onNative` 加 `onCameraDenied` 处理：弹权限引导对话框（照 capture_page 的 `_showPermissionGuide`：提示 + `AppSettings.openAppSettings()`）
2. `_onViewCreated`：`isSupported==false` 时**不渲染 UiKitView**（`_supported=false` 状态下 build 里用占位视图替换 UiKitView：居中提示"需 iPhone 12 Pro+，请使用照片量尺"+"去照片量尺"按钮 `Navigator.pop` 后由调用方处理或直接 push MeasurePage）
3. 暂停/继续/清除/保存按钮在 `_supported==false` 时禁用
4. **删除 `_buildWebFallback()` 的假估算逻辑**：非iOS/Web 平台 build 直接返回提示页（"AR量尺仅支持iPhone Pro，请使用照片量尺" + 关闭按钮），不要再提供"计算并加入校对"假结果（当前 `estMm=drw` 会导致永远判定合格，是错误功能）

## 任务3：拍照记录"选点无反馈/显示待选点"（lib/features/capture/capture_page.dart）

1. **选点图钉反馈**：`_onTapDrawing` 的 setState 里除 `_x/_y` 外，加 `_pinX/_pinY`（或直接复用 `_x/_y`）→ 图纸 Stack 里 `_step != selectFloor` 时在 `(_x, _y)` 处渲染固定图钉（照 `_buildPin` 风格，但位置用 `_x*width, _y*height`，颜色用 accent）
2. **label 不再出现"待选点"**：`_snapToNearestAnchor` 吸附失败时（当前直接不更新，label 停在'待选点'）改为：
   ```dart
   if (bestDist < 0.12 || force) {
     _anchorLabel = best.label;
   } else {
     _anchorLabel = '已选点 (${(_x * 100).toStringAsFixed(0)}%, ${(_y * 100).toStringAsFixed(0)}%)';
   }
   ```
   注：`_onTapDrawing` 里 `_anchorLabel = '待选点'` 改为 `_anchorLabel = '已选点'` 占位（随后 _snapToNearestAnchor 覆盖为具体值）
3. **确认无拦截**：全文件 grep `待选点`——除注释与显示文案外，不得存在"拦截拍照/保存"的校验（当前源码已无；如果用户仍遇到"未选点"提示，是**旧构建**，`flutter clean` 后重建即可）
4. `_confirmPointAndCapture` 保持现状（不做锚点校验）

## 任务4：拍照量尺 + 拍照记录相机稳定性

### 4.1 通用相机兜底工具（新增 lib/core/utils/camera_pick.dart，两处复用）

```dart
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// 移动端拍照：权限预检 → 后置 → 失败自动重试 → 失败弹"改用相册"兜底。
/// [onDenied] 权限拒绝回调（页面弹权限引导）。
Future<XFile?> pickPhotoRobust(
  BuildContext context, {
  required VoidCallback onDenied,
  double maxWidth = 1920,
  int imageQuality = 85,
}) async {
  final picker = ImagePicker();
  try {
    // 先尝试后置相机
    return await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: maxWidth,
      imageQuality: imageQuality,
      preferredCameraDevice: CameraDevice.rear,
    );
  } on PlatformException catch (e) {
    final msg = e.message ?? e.code;
    // 权限类错误 → 引导
    if (msg.toLowerCase().contains('permission') || e.code.contains('denied')) {
      onDenied();
      return null;
    }
    // 相机不可用（后置失败/模拟器等）→ 弹兜底对话框：重试 / 改用相册
    final useGallery = await _showCameraFallbackDialog(context, msg);
    if (useGallery == null) return null;
    if (useGallery) {
      return picker.pickImage(
          source: ImageSource.gallery, maxWidth: maxWidth, imageQuality: imageQuality);
    }
    return pickPhotoRobust(context, onDenied: onDenied,
        maxWidth: maxWidth, imageQuality: imageQuality);
  } catch (_) {
    final useGallery = await _showCameraFallbackDialog(context, '相机不可用');
    if (useGallery == true) {
      return picker.pickImage(
          source: ImageSource.gallery, maxWidth: maxWidth, imageQuality: imageQuality);
    }
    return null;
  }
}

Future<bool?> _showCameraFallbackDialog(BuildContext context, String reason) async {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('相机不可用'),
      content: Text('原因：$reason\n是否改用相册选图？'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('取消')),
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('重试')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('改用相册')),
      ],
    ),
  );
}
```

### 4.2 接入两处

- **measure_page.dart `_pickPhoto`**：移动端调用 `pickPhotoRobust(context, onDenied: _showPermissionGuide 同款弹窗)`；Web 保持 gallery
- **capture_page.dart `_pickImage`**：替换为 `pickPhotoRobust`（保留其现有 `_showPermissionGuide` 作为 onDenied 回调）

### 4.3 顺手合入 P0-2（标记错位，MEASURE_FIX_PLAN.md §P0-2）

`measure_page.dart` 新增 `imageToDisplay`（BoxFit.contain 逆变换），三处标记（图纸蓝点/照片橙点/红点）渲染前换算——此修复此前未合入，本次一并完成。

---

## 验收清单

- [ ] AR（真机iPhone Pro）：连续测3组 → 列表显示3条 → 删除1条 → 保存 → 清单页出现2条 `AR-1/AR-2`
- [ ] AR：拒绝相机权限 → 弹权限引导；isSupported=false → 无黑屏（占位提示+引导照片量尺）
- [ ] 非iOS/Web：无"假估算"页面，直接提示使用照片量尺
- [ ] 拍照记录：点图纸 → 出现图钉 + label 显示"已选点(x%, y%)"（无锚点时）→ 开始拍照正常调相机
- [ ] 拍照量尺：后置相机失败 → 弹"重试/改用相册"；相册兜底可用；权限拒绝 → 引导设置
- [ ] 标记错位修复：点击处与标记重合
- [ ] `flutter analyze` 无新增 error + Web 构建通过；真机验证需 Mac/iOS 设备

## 红线

1. 删除假估算页面后，确保没有任何路径再把 `estMm=drw` 式"永远合格"的数据写入会话
2. 相机兜底对话框不能无限递归重试（重试最多一次后只给相册选项）
