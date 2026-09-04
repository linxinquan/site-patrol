import 'package:flutter/material.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../core/theme/design_tokens.dart';

/// 全局自定义 Toast 提示（替代 Material SnackBar，使用自有卡片样式，非 Google UI）。
/// 用法：`AppSnack.show(context, '内容', kind: AppSnackKind.success);`
enum AppSnackKind { muted, success, accent, brand, danger }

class AppSnack {
  static void show(BuildContext context, String message,
      {AppSnackKind kind = AppSnackKind.muted,
      String? actionLabel,
      VoidCallback? onAction,
      EdgeInsetsGeometry? margin,
      Duration? duration}) {
    final style = _resolve(kind);
    final overlay = Overlay.of(context);
    if (overlay == null) return;
    final key = GlobalKey<_ToastWidgetState>();
    late final OverlayEntry entry;
    void dismiss() => entry.remove();
    entry = OverlayEntry(
      builder: (_) => _ToastWidget(
        key: key,
        message: message,
        style: style,
        margin: margin,
        onDismiss: dismiss,
        actionLabel: actionLabel,
        onAction: onAction,
        onActionDismiss: dismiss,
      ),
    );
    overlay.insert(entry);
    // 带操作按钮时不自动消失（点击按钮后由 onActionDismiss 关闭）。
    if (actionLabel == null || onAction == null) {
      Future.delayed(duration ?? const Duration(seconds: 2), () {
        key.currentState?.hide();
      });
    }
  }

  static _SnackStyle _resolve(AppSnackKind k) {
    switch (k) {
      case AppSnackKind.success:
        return const _SnackStyle(
            icon: MingCuteIcons.checkCircleLine, fg: AppTokens.success);
      case AppSnackKind.accent:
        return const _SnackStyle(
            icon: MingCuteIcons.documentLine, fg: AppTokens.fg);
      case AppSnackKind.brand:
        return const _SnackStyle(
            icon: MingCuteIcons.informationLine, fg: AppTokens.brand);
      case AppSnackKind.danger:
        return const _SnackStyle(
            icon: MingCuteIcons.warningLine, fg: AppTokens.danger);
      case AppSnackKind.muted:
        return const _SnackStyle(
            icon: MingCuteIcons.informationLine, fg: AppTokens.muted);
    }
  }
}

class _SnackStyle {
  final IconData icon;
  final Color fg;
  const _SnackStyle({required this.icon, required this.fg});
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final _SnackStyle style;
  final EdgeInsetsGeometry? margin;
  final VoidCallback onDismiss;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onActionDismiss;
  const _ToastWidget({
    super.key,
    required this.message,
    required this.style,
    this.margin,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
    this.onActionDismiss,
  });
  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 200));
  late final Animation<double> _fade =
      CurvedAnimation(parent: _ac, curve: Curves.easeOut);
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    _ac.forward();
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  /// 淡出动画结束后移除。
  void hide() {
    if (_hidden) return;
    _hidden = true;
    _ac.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    final raw = widget.margin?.resolve(Directionality.of(context)) ??
        const EdgeInsets.symmetric(horizontal: 12);
    final horizontal = EdgeInsets.only(left: raw.left, right: raw.right);
    return Positioned.fill(
      child: SafeArea(
        top: true,
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: FadeTransition(
              opacity: _fade,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: horizontal,
                  constraints: const BoxConstraints(maxWidth: 360),
                  decoration: BoxDecoration(
                    color: AppTokens.surface,
                    borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.style.icon, color: widget.style.fg, size: 16),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(widget.message,
                        style: TextStyle(
                            color: widget.style.fg,
                            fontSize: 14,
                            fontWeight: FontWeight.w400)),
                  ),
                  if (widget.actionLabel != null && widget.onAction != null)
                    TextButton(
                      onPressed: () {
                        widget.onAction!();
                        widget.onActionDismiss?.call();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: widget.style.fg,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                      ),
                      child: Text(widget.actionLabel!,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  ),
    );
  }
}
