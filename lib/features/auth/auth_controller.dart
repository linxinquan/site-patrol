import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/session_store.dart';
import '../../core/storage/local_storage.dart';
import '../../core/di/providers.dart';

/// 会话状态：null = 未登录；UserSession = 已登录。
final authStateProvider = StateProvider<UserSession?>((ref) => null);

/// 会话存储封装 Provider。
final sessionStoreProvider = Provider<SessionStore>(
  (ref) => SessionStore(storage: LocalStorage.instance),
);

/// 启动时从本地恢复会话与引导偏好（main 里 await 一次）。
final initAuthProvider = FutureProvider<void>((ref) async {
  final sessionStore = ref.watch(sessionStoreProvider);
  final prefs = ref.watch(userPrefsProvider);

  // 恢复登录态
  final session = await sessionStore.read();
  ref.read(authStateProvider.notifier).state = session;

  // 恢复引导态与当前选择，否则已登录老用户会被路由守卫反复重定向到 /onboard
  ref.read(onboardedProvider.notifier).state = await prefs.readOnboarded();
  final userId = await prefs.readUserId();
  if (userId != null) ref.read(currentUserIdProvider.notifier).state = userId;
  final projectId = await prefs.readProjectId();
  if (projectId != null) {
    ref.read(currentProjectIdProvider.notifier).state = projectId;
  }
});

/// 是否已登录。
final isLoggedInProvider = Provider<bool>(
  (ref) => ref.watch(authStateProvider) != null,
);

/// 是否已完成「选择用户 + 选择项目」引导。
/// 登录后先进入 /onboard 完成引导，才放行到 /home。
final onboardedProvider = StateProvider<bool>((ref) => false);
