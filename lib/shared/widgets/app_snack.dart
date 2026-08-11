import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme/design_tokens.dart';

/// 全局 Snack 提示（HTML demo 内的 `snack()` 系统等价）。
/// 用法：`AppSnack.show(context, '内容', kind: AppSnackKind.success);`
enum AppSnackKind { muted, success, accent, brand, danger }

class AppSnack {
  static void show(BuildContext context, String message,
      {AppSnackKind kind = AppSnackKind.muted}) {
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
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                ),
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
            icon: LucideIcons.circleCheck, fg: AppTokens.success, bg: AppTokens.successSoft);
      case AppSnackKind.accent:
        return const _SnackStyle(
            icon: LucideIcons.fileText, fg: AppTokens.accent, bg: AppTokens.accentSoft);
      case AppSnackKind.brand:
        return const _SnackStyle(
            icon: LucideIcons.info, fg: AppTokens.brand, bg: AppTokens.brandSoft);
      case AppSnackKind.danger:
        return const _SnackStyle(
            icon: LucideIcons.alertTriangle, fg: AppTokens.danger, bg: AppTokens.dangerSoft);
      case AppSnackKind.muted:
        return const _SnackStyle(
            icon: LucideIcons.info, fg: AppTokens.mutedA11y, bg: AppTokens.surface2);
    }
  }
}

class _SnackStyle {
  final IconData icon;
  final Color fg;
  final Color bg;
  const _SnackStyle({required this.icon, required this.fg, required this.bg});
}