import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// 移动端拍照：权限预检 → 后置 → 失败自动重试 → 失败弹"改用相册"兜底。
///
/// 规则：
/// - 权限类错误 → 回调 [onDenied]（页面弹权限引导）。
/// - 相机不可用 → 弹兜底对话框：取消 / 重试 / 改用相册。
/// - 重试最多一次（递归调用一次后仅提供相册选项），避免无限递归。
/// - 返回 null 表示用户取消。
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
    if (!context.mounted) return null;
    final msg = e.message ?? e.code;
    // 权限类错误 → 引导
    if (msg.toLowerCase().contains('permission') ||
        e.code.toLowerCase().contains('denied')) {
      onDenied();
      return null;
    }
    // 相机不可用（后置失败/模拟器等）→ 弹兜底对话框：重试 / 改用相册
    final useGallery = await _showCameraFallbackDialog(context, msg);
    if (useGallery == null) return null;
    if (useGallery) {
      return picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: maxWidth,
          imageQuality: imageQuality);
    }
    // 用户选择重试：仅重试一次（第二次直接走相册）
    try {
      final retry = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: maxWidth,
        imageQuality: imageQuality,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (retry != null) return retry;
      // 重试返回 null（用户取消）→ 再弹一次兜底，此时不再给"重试"
      if (!context.mounted) return null;
      final useGallery2 = await _showCameraFallbackDialog(
          context, '相机重试未返回图像', allowRetry: false);
      if (useGallery2 == true) {
        return picker.pickImage(
            source: ImageSource.gallery,
            maxWidth: maxWidth,
            imageQuality: imageQuality);
      }
      return null;
    } catch (_) {
      if (!context.mounted) return null;
      final useGallery2 =
          await _showCameraFallbackDialog(context, '相机不可用', allowRetry: false);
      if (useGallery2 == true) {
        return picker.pickImage(
            source: ImageSource.gallery,
            maxWidth: maxWidth,
            imageQuality: imageQuality);
      }
      return null;
    }
  } catch (_) {
    if (!context.mounted) return null;
    final useGallery =
        await _showCameraFallbackDialog(context, '相机不可用');
    if (useGallery == true) {
      return picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: maxWidth,
          imageQuality: imageQuality);
    }
    return null;
  }
}

/// 相机兜底对话框。
/// [allowRetry] 为 false 时只提供"取消/改用相册"，不再给"重试"。
Future<bool?> _showCameraFallbackDialog(
  BuildContext context,
  String reason, {
  bool allowRetry = true,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('相机不可用'),
      content: Text('原因：$reason\n是否改用相册选图？'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, null), child: const Text('取消')),
        if (allowRetry)
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('重试')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('改用相册')),
      ],
    ),
  );
}
