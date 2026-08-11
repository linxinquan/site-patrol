import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme/design_tokens.dart';

class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  const AppBottomNav({super.key, required this.currentIndex});

  static const List<String> _routes = [
    '/home',
    '/projects',
    '/patrol',
    '/defects',
  ];

  @override
  Widget build(BuildContext context) => BottomNavigationBar(
        currentIndex: currentIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppTokens.accent,
        unselectedItemColor: AppTokens.muted,
        backgroundColor: AppTokens.surface,
        elevation: 0,
        onTap: (i) => context.go(_routes[i]),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(LucideIcons.layoutDashboard), label: '工作台'),
          BottomNavigationBarItem(
              icon: Icon(LucideIcons.folder), label: '项目图纸'),
          BottomNavigationBarItem(icon: Icon(LucideIcons.map), label: '巡场'),
          BottomNavigationBarItem(
              icon: Icon(LucideIcons.listChecks), label: '缺陷'),
        ],
      );
}
