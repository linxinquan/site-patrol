import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'shared/widgets/device_frame.dart';
import 'core/storage/local_storage.dart';
import 'features/auth/auth_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化 Hive 本地 DB（移动端写入 Documents，Web 用 IndexedDB 后端）。
  await Hive.initFlutter();

  final storage = LocalStorage.instance;
  // 首次启动：把随包预置图纸拷贝到本地。
  try {
    await storage.seedDrawingsIfNeeded();
  } catch (_) {
    // 图纸拷贝失败不阻塞启动，业务上仍可从 assets 读取。
  }

  runApp(
    const ProviderScope(
      child: AuthBootstrap(
        child: DeviceFrame(child: App()),
      ),
    ),
  );
}

/// 启动期先恢复本地会话再挂载 App，避免登录守卫误跳。
class AuthBootstrap extends ConsumerWidget {
  const AuthBootstrap({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final init = ref.watch(initAuthProvider);
    return init.when(
      loading: () => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: SizedBox.shrink()),
      ),
      error: (_, __) => child,
      data: (_) => child,
    );
  }
}
