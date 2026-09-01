import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/design_tokens.dart';

/// iOS/抖音 风格底部导航（tab bar）：
/// 纯白底（无顶部描边/分割线）+ 纯文字 Tab，扁平化。中间常驻主色「拍照/新增」按钮。
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

  @override
  Widget build(BuildContext context) => Container(
        color: AppTokens.surface, // 纯白底，无顶部描边
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: AppTokens.tabbarH,
            child: Stack(
              children: [
                // —— 4 个纯文字 Tab（铺满）——
                Row(
                  children: [
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
                    // 中间留白，供常驻按钮居中
                    const Expanded(child: SizedBox()),
                    _TabItem(
                      label: '巡场',
                      selected: currentIndex == 2,
                      onTap: () => context.go(_routes[2]),
                    ),
                    _TabItem(
                      label: '问题清单',
                      selected: currentIndex == 3,
                      onTap: () => context.go(_routes[3]),
                    ),
                  ],
                ),
                // —— 中间常驻按钮（与 tab 栏水平 + 垂直居中）——
                // 拍照验收是一级页面（与 4 个 tab 同级），用 go 而非 push，避免成为带返回的二级页。
                Align(
                  alignment: Alignment.center,
                  child: _CenterCaptureButton(
                    active: cameraActive,
                    onTap: () => context.go('/capture'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// 单个 Tab 项（抖音风：纯文字，选中 W700 主题蓝 #0395FF，未选中灰色）。
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
                fontWeight: FontWeight.w700,
                color: selected ? AppTokens.brand : AppTokens.muted,
              ),
            ),
          ),
        ),
      );
}

/// 中间常驻「拍照 / 新增」按钮（验收）。
/// - 未激活：42×30 圆角 8 的【主色 #428BF7 底】，中央白色加号。
/// - 激活（处于拍照验收一级页）：主色「验收」文字（16·W700·#428BF7）。
/// 图标 ↔ 文字 切换瞬间完成（无动画），与 4 个 tab 的切换保持一致。
class _CenterCaptureButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool active;
  const _CenterCaptureButton({
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: active ? _buildLabel() : _buildIcon(),
        ),
      );

  /// 未激活：42×30 圆角 8 的【主色 #428BF7 底】，中央白色加号（圆头端点，长度 12）。
  Widget _buildIcon() => Container(
        width: 42,
        height: 30,
        decoration: BoxDecoration(
          color: AppTokens.brand,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 2,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            Container(
              width: 12,
              height: 2,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      );

  /// 激活态：金色图标 → 文字「验收」（主色 #428BF7），标示当前正处于拍照验收页。
  Widget _buildLabel() => const SizedBox(
        width: 42,
        height: 30,
        child: Center(
          child: Text(
            '验收',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTokens.brand,
            ),
          ),
        ),
      );
}
