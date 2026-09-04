import 'package:flutter/material.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../core/theme/design_tokens.dart';

/// 统一底部弹窗壳（设计稿 Frame 2147228008）。
///
/// - 遮罩 #000 50%；sheet 背景 #F4F6F7、顶部圆角 24；
/// - 头部标题居中（W600/16/#202224）+ 关闭按钮（右上 24×24 `closeMediumLine`）；
/// - 内容区水平内缩 12、底部 24（LTRB(12,0,12,24)），头部与内容间距 12。
///
/// 用法：
/// ```dart
/// AppBottomSheet.show(
///   context: context,
///   title: '修改路线名称',
///   body: (ctx) => Column(children: [ /* 内容 + 可选 AppSheetFooter.cancelSave */ ]),
/// );
/// ```
class AppBottomSheet {
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required WidgetBuilder body,
    bool useRootNavigator = true,
    bool isScrollControlled = false,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      isScrollControlled: isScrollControlled,
      backgroundColor: AppTokens.bg,
      barrierColor: const Color(0x80000000), // 遮罩 #000 50%
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SheetHeader(title: title, onClose: () => Navigator.pop(ctx)),
              const SizedBox(height: 12),
              body(ctx),
            ],
          ),
        ),
      ),
    );
  }
}

/// 弹窗头部：高 48，标题水平居中；右侧 24×24 关闭按钮。
class _SheetHeader extends StatelessWidget {
  final String title;
  final VoidCallback onClose;
  const _SheetHeader({required this.title, required this.onClose});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 24 / 16,
                color: AppTokens.fg,
              ),
            ),
            Positioned(
              top: 12,
              right: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClose,
                child: const SizedBox(
                  width: 24,
                  height: 24,
                  child: Icon(MingCuteIcons.closeMediumLine,
                      size: 24, color: Color(0xFF09244B)),
                ),
              ),
            ),
          ],
        ),
      );
}

/// 底部「取消 / 保存」双按钮行（Frame 2147228056）：两按钮等宽、高 48、圆角 8、间距 12。
/// 取消：白底红字（#FF4444）；保存：蓝底白字。
class AppSheetFooter {
  static Widget cancelSave({
    required VoidCallback onCancel,
    required VoidCallback onSave,
    String cancelLabel = '取消',
    String saveLabel = '保存',
  }) =>
      Row(
        children: [
          Expanded(
            child: _SheetButton(
              label: cancelLabel,
              background: AppTokens.surface,
              foreground: const Color(0xFFFF4444),
              onTap: onCancel,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _SheetButton(
              label: saveLabel,
              background: AppTokens.brand,
              foreground: AppTokens.onAccent,
              onTap: onSave,
            ),
          ),
        ],
      );
}

class _SheetButton extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;
  const _SheetButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  height: 24 / 16,
                  color: foreground,
                ),
              ),
            ),
          ),
        ),
      );
}
