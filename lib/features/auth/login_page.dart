import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/storage/session_store.dart';
import 'auth_controller.dart';

/// 登录页（S2 占位实现）。
///
/// 当前仅提供「直接进入」以便登录守卫闭环可测；S3 将替换为
/// 预置 3 用户（yang/liu/zhao）表单校验 → 生成本地会话 → 跳转 /home。
class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  Future<void> _login(WidgetRef ref) async {
    final store = ref.read(sessionStoreProvider);
    await store.save(UserSession(
      userId: 'demo',
      username: 'demo',
      displayName: '演示用户',
      loginAt: DateTime.now(),
    ));
    ref.read(authStateProvider.notifier).state = await store.read();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppTokens.bg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.engineering,
                  size: 64,
                  color: AppTokens.accent,
                ),
                const SizedBox(height: 16),
                const Text(
                  '工地验收',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppTokens.fg,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '南方科技大学附属医院（校本部）',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: () => _login(ref),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('进入应用'),
                ),
                const SizedBox(height: 12),
                Text(
                  '登录校验功能将在后续版本加入',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
