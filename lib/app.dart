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

final router = GoRouter(
  initialLocation: '/home',
  routes: [
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

class App extends ConsumerWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phoneMode = ref.watch(devicePhoneModeProvider);
    return MaterialApp.router(
      title: '工地验收',
      theme: lightTheme,
      routerConfig: router,
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
