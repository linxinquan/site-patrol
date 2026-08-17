import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/theme/app_theme.dart';
import 'core/di/providers.dart';
import 'data/models.dart';
import 'shared/widgets/device_frame.dart';
import 'features/home/home_page.dart';
import 'features/projects/projects_page.dart';
import 'features/projects/drawing_viewer_page.dart';
import 'features/patrol/patrol_page.dart';
import 'features/defects/defects_page.dart';
import 'features/defects/record_detail_page.dart';
import 'features/defects/timeline_compare_page.dart';
import 'features/capture/capture_page.dart';
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
      // 已登录且正在 login：去引导或首页
      if (loggedIn && onLogin) return onboarded ? '/home' : '/onboard';
      // 已登录但未引导，且不在 onboard：强制去 onboard
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
          }
          return Scaffold(
            body: child,
            bottomNavigationBar: AppBottomNav(currentIndex: index),
          );
        },
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomePage()),
          GoRoute(path: '/projects', builder: (_, __) => const ProjectsPage()),
          GoRoute(path: '/patrol', builder: (_, __) => const PatrolPage()),
          GoRoute(path: '/defects', builder: (_, __) => const DefectsPage()),
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
        path: '/capture',
        builder: (_, state) => CapturePage(
          args: state.extra is CaptureArgs ? state.extra as CaptureArgs : const CaptureArgs(),
        ),
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
    ],
  );
});

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phoneMode = ref.watch(devicePhoneModeProvider);
    return MaterialApp.router(
      title: '工地验收',
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
            padding: const EdgeInsets.only(top: 0, bottom: 0),
          ),
          child: child,
        );
      },
    );
  }
}
