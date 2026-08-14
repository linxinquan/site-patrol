import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/session_store.dart';
import '../../core/storage/local_storage.dart';

/// 会话状态：null = 未登录；UserSession = 已登录。
final authStateProvider = StateProvider<UserSession?>((ref) => null);

/// 会话存储封装 Provider。
final sessionStoreProvider = Provider<SessionStore>(
  (ref) => SessionStore(storage: LocalStorage.instance),
);

/// 启动时从本地恢复会话（main 里 await 一次）。
final initAuthProvider = FutureProvider<void>((ref) async {
  final session = await ref.watch(sessionStoreProvider).read();
  ref.read(authStateProvider.notifier).state = session;
});

/// 是否已登录。
final isLoggedInProvider = Provider<bool>(
  (ref) => ref.watch(authStateProvider) != null,
);
