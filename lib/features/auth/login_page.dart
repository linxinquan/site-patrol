import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/session_store.dart';
import '../auth/auth_controller.dart';

/// 登录页（Ins 风扁平化）：白底 + 大留白 + 单一主色 + 极简。
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
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 上方留白
                  const Spacer(flex: 3),
                  // Logo（扁平圆形橙底）
                  Container(
                    width: 84,
                    height: 84,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0E6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.engineering,
                      size: 42,
                      color: Color(0xFFEA580C),
                    ),
                  ),
                  const SizedBox(height: 28),
                  // APP 名称（大字号细字重）
                  const Text(
                    '蓝图落地',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '设计院视角的现场数据闭环',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.3,
                      color: Color(0xFF8E8E93),
                    ),
                  ),
                  // 中部留白
                  const Spacer(flex: 4),
                  // 进入应用按钮（纯橙胶囊）
                  FilledButton(
                    onPressed: () => _login(ref),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFEA580C),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: const Text(
                      '进入应用',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '蓝图落地 · 现场数据闭环与缺陷知识库',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFFC7C7CC),
                    ),
                  ),
                  const Spacer(flex: 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
