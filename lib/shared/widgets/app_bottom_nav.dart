import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme/design_tokens.dart';

/// iOS 风格底部导航（tab bar）：
/// 白底 + 顶部细分割线 + 图标/选中高亮，扁平化。
class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  const AppBottomNav({super.key, required this.currentIndex});

  static const List<String> _routes = [
    '/home',
    '/projects',
    '/patrol',
    '/defects',
  ];

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: AppTokens.surface,
          border: Border(
            top: BorderSide(color: AppTokens.border, width: 0.5),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: AppTokens.tabbarH,
            child: Row(
              children: [
                _TabItem(
                  icon: LucideIcons.layoutDashboard,
                  label: '工作台',
                  selected: currentIndex == 0,
                  onTap: () => context.go(_routes[0]),
                ),
                _TabItem(
                  icon: LucideIcons.folder,
                  label: '图纸',
                  selected: currentIndex == 1,
                  onTap: () => context.go(_routes[1]),
                ),
                _TabItem(
                  icon: LucideIcons.map,
                  label: '巡场',
                  selected: currentIndex == 2,
                  onTap: () => context.go(_routes[2]),
                ),
                _TabItem(
                  icon: LucideIcons.listChecks,
                  label: '缺陷',
                  selected: currentIndex == 3,
                  onTap: () => context.go(_routes[3]),
                ),
              ],
            ),
          ),
        ),
      );
}

/// 单个 Tab 项（iOS 风格：图标 + 文字，选中高亮 + 轻缩放）。
class _TabItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TabItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: selected ? 1.0 : 0.45,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                  decoration: selected
                      ? BoxDecoration(
                          color: AppTokens.accent.withValues(alpha: 0.14),
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusPill),
                        )
                      : null,
                  child: Icon(
                    icon,
                    size: 22,
                    color: selected ? AppTokens.accent : AppTokens.mutedA11y,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? AppTokens.accent : AppTokens.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
