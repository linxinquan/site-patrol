import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';

import '../../core/theme/design_tokens.dart';

/// 统一自绘普通弹窗。
///
/// 约定：
/// - 遮罩：#000 50%
/// - 卡片：白底、圆角 16、左右最小留白 24
/// - 标题：16 / W600 / #202224
/// - 描述：14 / 22 / W400，默认次级文字色
/// - 按钮：高 48、圆角 8，主按钮蓝底白字，次按钮白底描边/纯白底
class AppDialog {
  static const TextStyle titleStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 24 / 16,
    color: AppTokens.fg,
  );

  static const TextStyle descriptionStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 22 / 14,
    color: AppTokens.fg2,
  );

  static Future<T?> show<T>({
    required BuildContext context,
    String? title,
    String? description,
    Widget? content,
    Widget? actions,
    bool barrierDismissible = true,
    bool useRootNavigator = true,
    bool showClose = true,
    bool canPop = true,
    double width = 326,
    EdgeInsetsGeometry? contentPadding,
    EdgeInsetsGeometry? actionsPadding,
  }) {
    return showGeneralDialog<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      barrierDismissible: barrierDismissible,
      barrierLabel: 'dialog',
      barrierColor: const Color(0x80000000),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => PopScope(
        canPop: canPop,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Material(
                type: MaterialType.transparency,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: width),
                  child: _AppDialogCard(
                    title: title,
                    description: description,
                    content: content,
                    actions: actions,
                    showClose: showClose,
                    contentPadding: contentPadding,
                    actionsPadding: actionsPadding,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      transitionBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

class _AppDialogCard extends StatelessWidget {
  final String? title;
  final String? description;
  final Widget? content;
  final Widget? actions;
  final bool showClose;
  final EdgeInsetsGeometry? contentPadding;
  final EdgeInsetsGeometry? actionsPadding;

  const _AppDialogCard({
    this.title,
    this.description,
    this.content,
    this.actions,
    required this.showClose,
    this.contentPadding,
    this.actionsPadding,
  });

  @override
  Widget build(BuildContext context) {
    final hasHeader = (title?.isNotEmpty ?? false) || showClose;
    return Container(
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasHeader)
            SizedBox(
              height: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (title?.isNotEmpty ?? false)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 48),
                      child: Text(
                        title!,
                        textAlign: TextAlign.center,
                        style: AppDialog.titleStyle,
                      ),
                    ),
                  if (showClose)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: _DialogIconButton(
                        icon: MingCuteIcons.closeMediumLine,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                ],
              ),
            ),
          if (description?.isNotEmpty ?? false)
            Padding(
              padding: EdgeInsets.fromLTRB(24, hasHeader ? 12 : 24, 24, 0),
              child: Text(description!, style: AppDialog.descriptionStyle),
            ),
          if (content != null)
            Padding(
              padding: contentPadding ??
                  EdgeInsets.fromLTRB(
                    24,
                    (description?.isNotEmpty ?? false)
                        ? 12
                        : (hasHeader ? 12 : 24),
                    24,
                    0,
                  ),
              child: content,
            ),
          if (actions != null)
            Padding(
              padding:
                  actionsPadding ?? const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: actions,
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// 自绘弹窗右上角图标按钮。
class _DialogIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _DialogIconButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 24,
        height: 24,
        child: Icon(icon, size: 24, color: const Color(0xFF09244B)),
      ),
    );
  }
}

/// 弹窗按钮组：
/// - 2 个以内横向排布
/// - 3 个及以上改为纵向排布，避免文字被压缩
class AppDialogActions extends StatelessWidget {
  final List<Widget> children;

  const AppDialogActions({
    super.key,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    if (children.length <= 2) {
      return Row(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            Expanded(child: children[i]),
            if (i < children.length - 1) const SizedBox(width: 12),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < children.length; i++) ...[
          children[i],
          if (i < children.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// 自绘弹窗按钮。
class AppDialogButton extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final Color? borderColor;
  final VoidCallback? onTap;

  const AppDialogButton({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.borderColor,
    this.onTap,
  });

  factory AppDialogButton.primary({
    Key? key,
    required String label,
    required VoidCallback? onTap,
  }) {
    return AppDialogButton(
      key: key,
      label: label,
      background: AppTokens.brand,
      foreground: AppTokens.onAccent,
      onTap: onTap,
    );
  }

  factory AppDialogButton.secondary({
    Key? key,
    required String label,
    required VoidCallback? onTap,
  }) {
    return AppDialogButton(
      key: key,
      label: label,
      background: AppTokens.surface,
      foreground: AppTokens.fg2,
      borderColor: AppTokens.border,
      onTap: onTap,
    );
  }

  factory AppDialogButton.danger({
    Key? key,
    required String label,
    required VoidCallback? onTap,
  }) {
    return AppDialogButton(
      key: key,
      label: label,
      background: const Color(0x0DFF4444),
      foreground: const Color(0xFFFF4444),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border:
                  borderColor == null ? null : Border.all(color: borderColor!),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 24 / 16,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 自绘输入框容器。
class AppDialogInput extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool autofocus;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const AppDialogInput({
    super.key,
    required this.controller,
    required this.hintText,
    this.autofocus = false,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTokens.border),
      ),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        maxLines: maxLines,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: 22 / 14,
          color: AppTokens.fg,
        ),
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: hintText,
          hintStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            height: 22 / 14,
            color: AppTokens.muted,
          ),
        ),
      ),
    );
  }
}
