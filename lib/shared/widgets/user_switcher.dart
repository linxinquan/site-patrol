import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../core/theme/design_tokens.dart';
import 'profile_drawer.dart';

/// 顶部菜单按钮（menuLine 图标）。点击打开「个人中心」侧边栏（不再直接弹切换身份）。
/// 切换身份改由侧边栏内的「切换身份」按钮调起（见 [showUserSwitchSheet]）。
class UserSwitcher extends ConsumerWidget {
  const UserSwitcher({super.key, this.size = 24});

  /// 图标尺寸（直径）。
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openProfileDrawer(context),
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(MingCuteIcons.menuLine, size: size, color: AppTokens.fg),
      ),
    );
  }
}
