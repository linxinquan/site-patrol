import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/design_tokens.dart';

/// iOS/抖音 风格底部导航（tab bar）：
/// 浅灰底（#F4F6F7，无顶部描边/分割线）+ 纯文字 Tab，扁平化。5 个等宽文字 Tab。
class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final bool cameraActive;
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    this.cameraActive = false,
  });

  static const List<String> _routes = [
    '/home',
    '/projects',
    '/patrol',
    '/defects',
  ];

  // 纯文字 tab 比图标+文字 tab 更轻，内容区用 44 会比 49 更紧凑，
  // 同时保留外层安全区背景，iOS / Android 看起来都会更自然。
  static const double _contentHeight = 44;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      color: AppTokens.bg, // 背景继续铺到底部安全区
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: _contentHeight,
        child: Row(
          children: [
            // 5 个纯文字 Tab（等宽）
            _TabItem(
              label: '项目',
              selected: currentIndex == 0,
              onTap: () => context.go(_routes[0]),
            ),
            _TabItem(
              label: '图纸',
              selected: currentIndex == 1,
              onTap: () => context.go(_routes[1]),
            ),
            _TabItem(
              label: '验收',
              selected: cameraActive,
              onTap: () => context.go('/capture'),
            ),
            _TabItem(
              label: '巡场',
              selected: currentIndex == 2,
              onTap: () => context.go(_routes[2]),
            ),
            _TabItem(
              label: '工单',
              selected: currentIndex == 3,
              onTap: () => context.go(_routes[3]),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个 Tab 项（抖音风：纯文字，选中 W600 主题蓝 #0395FF，未选中灰色）。
class _TabItem extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TabItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: selected ? AppTokens.brand : AppTokens.muted,
              ),
            ),
          ),
        ),
      );
}
