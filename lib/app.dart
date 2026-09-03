import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/theme/app_theme.dart';
import 'core/di/providers.dart';
import 'data/models.dart';
import 'shared/widgets/device_frame.dart';
import 'features/home/home_page.dart';
import 'core/navigation/route_observer.dart';
import 'features/projects/projects_page.dart';
import 'features/projects/drawing_viewer_page.dart';
import 'features/patrol/patrol_page.dart';
import 'features/patrol/patrol_editor_page.dart';
import 'features/defects/defects_page.dart';
import 'features/defects/record_detail_page.dart';
import 'features/defects/timeline_compare_page.dart';
import 'features/capture/capture_page.dart';
import 'features/capture_records/capture_records_page.dart';
import 'features/measure/measure_page.dart';
import 'features/measure/ar_measure_page.dart';
import 'features/projects/blueprint_viewer_page.dart';
import 'shared/widgets/app_bottom_nav.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_page.dart';
import 'features/auth/onboard_page.dart';
import 'features/auth/onboard_project_page.dart';

/// 全局路由（单例，含登录守卫）。登录状态变化时自动刷新并重定向。
final routerProvider = Provider<GoRouter>((ref) {
  // 登录状态变化时触发路由重算。
  final refresh = ValueNotifier<Object?>(null);
  ref.onDispose(() => refresh.dispose());
  ref.listen<Object?>(authStateProvider, (_, __) => refresh.value = Object());

  return GoRouter(
    observers: [routeObserver],
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = ref.read(authStateProvider) != null;
      final onboarded = ref.read(onboardedProvider);
      final loc = state.matchedLocation;
      final onLogin = loc == '/login';
      final onOnboard = loc == "/onboard" || loc.startsWith("/onboard/");
      // 根路径未匹配任何路由：交给守卫决定去向
      if (loc == '/') {
        if (!loggedIn) return '/login';
        return onboarded ? '/home' : '/onboard';
      }
      // 未登录只能去 login
      if (!loggedIn && !onLogin) return '/login';
      // 已登录且正在 login：去引导页或首页
      if (loggedIn && onLogin) return onboarded ? '/home' : '/onboard';
      // 已登录但未引导，且不在 onboard：强制去引导
      if (loggedIn && !onboarded && !onOnboard) return '/onboard';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginPage(),
      ),
      GoRoute(
        path: '/onboard',
        builder: (_, __) => const OnboardPage(),
        routes: [
          GoRoute(
            path: 'project',
            builder: (_, __) => const OnboardProjectPage(),
          ),
        ],
      ),
      ShellRoute(
        builder: (context, state, child) {
          int index = 0;
          final loc = state.matchedLocation;
          if (loc.startsWith('/projects')) {
            index = 1;
          } else if (loc.startsWith('/patrol')) {
            index = 2;
          } else if (loc.startsWith('/defects')) {
            index = 3;
          } else if (loc.startsWith('/capture') ||
              loc.startsWith('/capture-records')) {
            // 拍照验收 / 验收记录是一级页面，但不属于 4 个文字 tab，
            // 故无 tab 选中高亮，仅底部相机按钮保留「active」反馈。
            index = -1;
          }
          final cameraActive = loc.startsWith('/capture') ||
              loc.startsWith('/capture-records');
          return Scaffold(
            body: child,
            bottomNavigationBar: AppBottomNav(
              currentIndex: index,
              cameraActive: cameraActive,
            ),
          );
        },
        routes: [
          // 4 个文字 tab + 拍照验收：切换时瞬间完成（无页面滑动/淡入过渡），
          // 中间相机按钮 icon↔text 也是瞬间切换，无动画。
          GoRoute(
            path: '/home',
            pageBuilder: (_, __) => CustomTransitionPage(
              transitionDuration: Duration.zero,
              transitionsBuilder: (_, __, ___, child) => child,
              child: const HomePage(),
            ),
          ),
          GoRoute(
            path: '/projects',
            pageBuilder: (_, __) => CustomTransitionPage(
              transitionDuration: Duration.zero,
              transitionsBuilder: (_, __, ___, child) => child,
              child: const ProjectsPage(),
            ),
          ),
          GoRoute(
            path: '/patrol',
            pageBuilder: (_, state) => CustomTransitionPage(
              transitionDuration: Duration.zero,
              transitionsBuilder: (_, __, ___, child) => child,
              child: PatrolPage(
                args: state.extra is PatrolArgs
                    ? state.extra as PatrolArgs
                    : const PatrolArgs(),
              ),
            ),
          ),
          GoRoute(
            path: '/defects',
            pageBuilder: (_, __) => CustomTransitionPage(
              transitionDuration: Duration.zero,
              transitionsBuilder: (_, __, ___, child) => child,
              child: const DefectsPage(),
            ),
          ),
          // 中间相机按钮入口：拍照验收属于一级页面（与 4 个 tab 同级，保留底部导航）。
          GoRoute(
            path: '/capture',
            pageBuilder: (_, state) => CustomTransitionPage(
              transitionDuration: Duration.zero,
              transitionsBuilder: (_, __, ___, child) => child,
              child: CapturePage(
                args: state.extra is CaptureArgs ? state.extra as CaptureArgs : const CaptureArgs(),
              ),
            ),
          ),
          // 验收记录（事后工作台）：与拍照验收同级，保留底部导航、无 tab 高亮。
          GoRoute(
            path: '/capture-records',
            pageBuilder: (_, __) => CustomTransitionPage(
              transitionDuration: Duration.zero,
              transitionsBuilder: (_, __, ___, child) => child,
              child: const CaptureRecordsPage(),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/projects/drawing/:key',
        builder: (_, state) =>
            DrawingViewerPage(drawingKey: state.pathParameters['key']!),
      ),
      GoRoute(
        path: '/defects/record/:id',
        builder: (_, state) =>
            RecordDetailPage(defectId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/timeline',
        builder: (_, state) => TimelineComparePage(
          anchor: state.extra is String ? state.extra as String : null,
        ),
      ),
      GoRoute(
        path: '/blueprint',
        builder: (_, __) => const BlueprintViewerPage(),
      ),
      GoRoute(
        path: '/measure',
        builder: (_, state) => MeasurePage(
          args: state.extra is MeasureArgs
              ? state.extra as MeasureArgs
              : const MeasureArgs(projectKey: '', drawingKey: ''),
        ),
      ),
      GoRoute(
        path: '/measure/ar',
        builder: (_, state) => ArMeasurePage(
          args: state.extra is MeasureArgs
              ? state.extra as MeasureArgs
              : const MeasureArgs(projectKey: '', drawingKey: ''),
        ),
      ),
      GoRoute(
        path: '/patrol-editor',
        builder: (_, state) => PatrolEditorPage(
          args: state.extra is PatrolArgs
              ? state.extra as PatrolArgs
              : const PatrolArgs(),
        ),
      ),
    ],
  );
});

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 启动期一次性初始化：校准系数预置 + 校准库灌入（测量模块开箱即用）。
    ref.watch(appInitProvider);
    final phoneMode = ref.watch(devicePhoneModeProvider);
    return MaterialApp.router(
      title: '蓝图落地',
      theme: lightTheme,
      routerConfig: ref.watch(routerProvider),
      debugShowCheckedModeBanner: false,
      // Web 调试：当切到手机尺寸模拟时，显式注入 MediaQuery，避免 FittedBox/SizedBox
      // 在 web release 下推断尺寸导致的边界问题（之前报错：`test inject(injectKey)!`）。
      builder: (context, child) {
        if (!phoneMode || child == null) return child ?? const SizedBox.shrink();
        final base = MediaQuery.of(context);
        return MediaQuery(
          data: base.copyWith(
            size: const Size(DeviceFrame.phoneWidth, DeviceFrame.phoneHeight),
            // 注入真机安全区：顶部状态栏 47pt、底部 home indicator 34pt，
            // 让 AppBar / SafeArea 自动避让，与模拟状态栏/刘海对齐。
            padding: const EdgeInsets.only(
              top: DeviceFrame.statusbarH,
              bottom: DeviceFrame.homeIndicatorH,
            ),
          ),
          child: child,
        );
      },
    );
  }
}
