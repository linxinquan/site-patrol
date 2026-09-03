import 'package:flutter/material.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';

/// 导航栏图标按钮：去除了 Material 默认在 web/桌面端的 hover 圆形背景
/// （hoverColor/splashColor/highlightColor/focusColor 全部透明），用于
/// 二级页返回、搜索、复位、编辑等导航栏图标。
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
    return IconButton(
      onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
      hoverColor: Colors.transparent,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      focusColor: Colors.transparent,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      icon: Icon(icon, size: size, color: color),
    );
  }
}
