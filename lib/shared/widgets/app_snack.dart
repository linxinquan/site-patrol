import 'package:flutter/material.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../core/theme/design_tokens.dart';

/// 全局 Snack 提示（HTML demo 内的 `snack()` 系统等价）。
/// 用法：`AppSnack.show(context, '内容', kind: AppSnackKind.success);`
enum AppSnackKind { muted, success, accent, brand, danger }

class AppSnack {
  static void show(BuildContext context, String message,
      {AppSnackKind kind = AppSnackKind.muted,
      String? actionLabel,
      VoidCallback? onAction}) {
    final style = _resolve(kind);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          ),
          backgroundColor: style.bg,
          content: Row(
            children: [
              Icon(style.icon, color: style.fg, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                      color: style.fg,
                      fontSize: 14,
                      fontWeight: FontWeight.w400),
                ),
              ),
              if (actionLabel != null && onAction != null)
                TextButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    onAction();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: style.fg,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                  ),
                  child: Text(actionLabel,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ),
      );
  }

  static _SnackStyle _resolve(AppSnackKind k) {
    switch (k) {
      case AppSnackKind.success:
        return const _SnackStyle(
            icon: MingCuteIcons.checkCircleLine, fg: AppTokens.success, bg: AppTokens.successSoft);
      case AppSnackKind.accent:
        return const _SnackStyle(
            icon: MingCuteIcons.documentLine, fg: AppTokens.fg, bg: AppTokens.surface2);
      case AppSnackKind.brand:
        return const _SnackStyle(
            icon: MingCuteIcons.informationLine, fg: AppTokens.brand, bg: AppTokens.brandSoft);
      case AppSnackKind.danger:
        return const _SnackStyle(
            icon: MingCuteIcons.warningLine, fg: AppTokens.danger, bg: AppTokens.dangerSoft);
      case AppSnackKind.muted:
        return const _SnackStyle(
            icon: MingCuteIcons.informationLine, fg: AppTokens.muted, bg: AppTokens.surface2);
    }
  }
}

class _SnackStyle {
  final IconData icon;
  final Color fg;
  final Color bg;
  const _SnackStyle({required this.icon, required this.fg, required this.bg});
}