import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'core/theme/app_theme.dart';
import 'features/home/home_page.dart';
import 'features/projects/projects_page.dart';
import 'features/projects/drawing_viewer_page.dart';
import 'features/patrol/patrol_page.dart';
import 'features/defects/defects_page.dart';
import 'features/defects/record_detail_page.dart';
import 'features/capture/capture_page.dart';
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
        anchorLabel: state.extra as String?,
      ),
    ),
  ],
);

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: '工地验收',
        theme: lightTheme,
        routerConfig: router,
        debugShowCheckedModeBanner: false,
      );
}
