import 'package:flutter/material.dart';

/// 导航栏图标按钮：去除了 Material 默认在 web/桌面端的 hover 圆形背景
/// （hoverColor/splashColor/highlightColor/focusColor 全部透明），用于
/// 二级页返回、搜索、复位、编辑等导航栏图标。
///
/// 图标水平方向完全贴边（无内边距）：
/// - 视觉边距 = 调用处 Padding，写 12 就是 12（此前内 padding all(8)
///   会导致外层 12 实际渲染 20，且 leading: 页面被 AppBar 强制 56 宽居中成 16）；
/// - 纵向保留 10×2 padding 撑出 44 高点击区，不影响水平位置。
class NavIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final Color? color;

  const NavIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 24,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed ?? () => Navigator.of(context).maybePop(),
        // 直接固定成 24 宽、44 高的点击区，避开不同平台对 IconButton 最小热区的差异，
        // 让导航图标的实际视觉间距和代码里的数值保持一致。
        child: SizedBox(
          width: size,
          height: 44,
          child: Center(
            child: Icon(icon, size: size, color: color),
          ),
        ),
      ),
    );
  }
}
