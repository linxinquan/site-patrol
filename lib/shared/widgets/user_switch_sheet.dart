import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/di/providers.dart';
import 'identity_tile.dart';
import 'app_bottom_sheet.dart';

/// 切换身份底部弹窗（也从「个人中心」侧边栏的「切换身份」按钮调起）。
/// 按设计稿「切换用户」帧（Frame 2147228008）还原：遮罩 #000 50%、sheet 背景 #F4F6F7、
/// 顶部圆角 24、头部标题「选择身份」居中 + 关闭按钮、4 张身份卡（无选中边框）。
Future<void> showUserSwitchSheet(BuildContext context, WidgetRef ref) async {
  final users = ref.read(usersProvider);
  final current = ref.read(currentUserProvider);
  await AppBottomSheet.show(
    context: context,
    title: '选择身份',
    body: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < users.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          IdentityTile(
            user: users[i],
            selected: users[i].id == current.id,
            showBorder: false, // 切换用户稿：卡片无选中边框
            onTap: () {
              if (users[i].id != current.id) {
                ref.read(currentUserIdProvider.notifier).state = users[i].id;
                ref.read(userPrefsProvider).saveUserId(users[i].id);
              }
              Navigator.pop(ctx);
            },
          ),
        ],
      ],
    ),
  );
}
