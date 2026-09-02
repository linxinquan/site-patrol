import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../core/di/providers.dart';
import 'identity_tile.dart';

/// 切换身份底部弹窗（也从「个人中心」侧边栏的「切换身份」按钮调起）。
/// 按设计稿「切换用户」帧（Frame 2147228008）还原：遮罩 #000 50%、sheet 背景 #F4F6F7、
/// 顶部圆角 24、头部标题「选择身份」居中 + 关闭按钮、4 张身份卡（无选中边框）。
Future<void> showUserSwitchSheet(BuildContext context, WidgetRef ref) async {
  final users = ref.read(usersProvider);
  final current = ref.read(currentUserProvider);
  await showModalBottomSheet(
    context: context,
    useRootNavigator: true, // 推到根导航，遮罩覆盖 ShellRoute 的底部 Tab 栏
    backgroundColor: const Color(0xFFF4F6F7),
    barrierColor: const Color(0x80000000), // 遮罩 #000 50%
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // —— 头部：标题居中 + 关闭按钮（右上）——
            // 注意：外层 padding.top 为 0（稿 Frame 2147228008 = 0 12 24），
            // 头部高 48 自带 12 上下内边距，故此处不再额外加顶部间距。
            SizedBox(
              width: double.infinity,
              height: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Text(
                    '选择身份',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 24 / 16,
                      color: Color(0xFF202224),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.pop(sheetCtx),
                      child: const SizedBox(
                        width: 24,
                        height: 24,
                        child: Icon(MingCuteIcons.closeMediumLine,
                            size: 24, color: Color(0xFF09244B)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // —— 身份卡列表（gap 12）——
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
                  Navigator.pop(sheetCtx);
                },
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
