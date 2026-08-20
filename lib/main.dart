import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'shared/widgets/device_frame.dart';
import 'core/storage/local_storage.dart';
import 'core/di/providers.dart';
import 'core/cad/cad_calibration.dart';
import 'core/utils/cad_coord.dart';
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

  // 内置真实校准种子：B05 截图底图已验证 <2mm 的仿射参数，
  // 随包预置，使 Web 预览/新装环境打开即带真实坐标（无需手动粘贴 localStorage）。
  // 用户后续在页面手动校准/清除可正常覆盖。
  try {
    final builtin = CadCoordMapper.fromAffine(
      viewWidth: 4500,
      viewHeight: 2551,
      a: 0.3308888888888889,
      d: -0.3308888888888889,
      c: -359.3091448275862,
      f: 852.4496763746746,
    );
    const builtinRaw =
        '{"v":1,"key":"dy04_7_B05","img":"dy04_7_B05_paper_hybrid.png","imgW":4500,"imgH":2551,"paperW":1489,"paperH":844,"m":{"a":0.3308888888888889,"b":0,"c":-359.3091448275862,"d":-0.3308888888888889,"e":0,"f":852.4496763746746}}';
    final lib = CalibrationLibrary(storage);
    // 仅在清单尚未登记该图纸时写入，避免覆盖用户自己的校准。
    final existing = await lib.readRaw('dy04_7_B05');
    if (existing == null) {
      await lib.upsert('dy04_7_B05', builtin, builtinRaw);
    }
  } catch (_) {
    // 校准种子注入失败不阻塞启动。
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

  /// 校准库只需要在 App 生命周期内套用一次（build 可能被多次调用）。
  static bool _libraryApplied = false;

  void _applyLibraryOnce(WidgetRef ref) {
    if (_libraryApplied) return;
    _libraryApplied = true;
    Future.microtask(() => applyCalibrationLibrary(ref));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final init = ref.watch(initAuthProvider);
    // 启动期把校准库清单一次性灌入内存，使已校准图纸打开即用（无需逐张加载/粘贴）。
    _applyLibraryOnce(ref);
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
