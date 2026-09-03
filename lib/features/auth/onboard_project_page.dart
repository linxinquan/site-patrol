import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';

import '../../core/di/providers.dart';
import '../../data/models.dart';
import '../../shared/widgets/project_tile.dart';
import 'auth_controller.dart';

/// 引导第 2 页：选择项目。
/// 按设计稿「选择你的项目」帧还原（画布 390×844，背景 #F8F8F8）：
/// - 状态栏 47 + 导航栏 44；返回图标 24×24 在 left 12 / top 57（相对安全区 top 10），色 #09244B
/// - 主内容区 left 12 / top 139：标题组（238 宽，24/W600 + 14/W400，gap 8）+ gap 24 + 项目卡列表（gap 12）
/// - 项目卡 366 宽白底圆角 8（见 ProjectTile），地址两行时高度自适应
/// - 底部双按钮（均 240×48 圆角 8）：蓝底白字「开始使用」top 613 + 白底蓝字「上一步」top 673（间距 12）
/// 选完点「开始使用」→ 完成引导 → 首页。
class OnboardProjectPage extends ConsumerStatefulWidget {
  const OnboardProjectPage({super.key});

  // —— 设计稿「选择你的项目」帧专用色 ——
  static const Color bg = Color(0xFFF8F8F8); // 页面背景
  static const Color fg = Color(0xFF202224); // 标题-正文
  static const Color muted = Color(0xFF919499); // 辅助说明
  static const Color brand = Color(0xFF0395FF); // 品牌色
  static const Color backIcon = Color(0xFF09244B); // 返回图标（本帧为深蓝）

  @override
  ConsumerState<OnboardProjectPage> createState() =>
      _OnboardProjectPageState();
}

class _OnboardProjectPageState extends ConsumerState<OnboardProjectPage> {
  late String? _projectId;

  @override
  void initState() {
    super.initState();
    // 不默认选中任何项目，进入后再由用户点选；未选中时「开始使用」按钮禁用。
    _projectId = null;
  }

  void _confirm() {
    if (_projectId == null) return;
    ref.read(currentProjectIdProvider.notifier).state = _projectId;
    ref.read(onboardedProvider.notifier).state = true;
    ref.read(userPrefsProvider).saveProjectId(_projectId);
    ref.read(userPrefsProvider).saveOnboarded(true);
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsProvider).maybeWhen(
          data: (p) => p,
          orElse: () => const <Project>[],
        );
    return Scaffold(
      backgroundColor: OnboardProjectPage.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // —— 返回（left 12 / top 10，图标 24×24）——
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => context.pop(),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 24, height: 24),
                  icon: const Icon(MingCuteIcons.leftLine,
                      size: 24, color: OnboardProjectPage.backIcon),
                ),
              ),
            ),

            // 返回区底 34 → 主内容 top 92，间距 58
            const SizedBox(height: 58),

            // —— 主内容（标题组 + 项目卡，可滚动）——
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // 标题组（Frame 2131330649：238 宽居中，gap 8）
                    Center(
                      child: SizedBox(
                        width: 238,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Text(
                              '选择你的项目',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                                height: 32 / 24,
                                color: OnboardProjectPage.fg,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              '选择要巡检的工地，可在首页切换项目',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                height: 22 / 14,
                                color: OnboardProjectPage.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // 项目卡列表（Frame 2131330655：gap 12，左右留 12）
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        children: [
                          for (int i = 0; i < projects.length; i++) ...[
                            if (i > 0) const SizedBox(height: 12),
                            ProjectTile(
                              project: projects[i],
                              selected: projects[i].id == _projectId,
                              onTap: () =>
                                  setState(() => _projectId = projects[i].id),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // —— 开始使用：240×48 圆角 8 品牌蓝 ——
            Center(
              child: _OnboardButton(
                label: '开始使用',
                onPressed: _projectId == null ? null : _confirm,
              ),
            ),
            const SizedBox(height: 12),
            // —— 上一步：240×48 圆角 8 白底蓝字 ——
            Center(
              child: _OnboardButton(
                label: '上一步',
                secondary: true,
                onPressed: () => context.pop(),
              ),
            ),
            // 稿：次按钮底 721 → home indicator 顶 810，留白 89
            const SizedBox(height: 89),
          ],
        ),
      ),
    );
  }
}

/// 引导按钮：240×48 圆角 8，主按钮蓝底白字 / 次按钮白底蓝字，文字 16/W600 行高 24。
/// 未复用 AppButton 是因为本帧按稿为圆角 8 / 字重 600，与全局 token（圆角 12 / W700）不同。
class _OnboardButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool secondary;
  const _OnboardButton({
    required this.label,
    required this.onPressed,
    this.secondary = false,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 240,
        height: 48,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor:
                secondary ? Colors.white : OnboardProjectPage.brand,
            disabledBackgroundColor: const Color(0xFFE9EAEB),
            foregroundColor:
                secondary ? OnboardProjectPage.brand : Colors.white,
            disabledForegroundColor: const Color(0xFF919499),
            // 关闭 Material 默认 48 点击区扩张，避免高度被撑开
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 24 / 16,
              letterSpacing: 0,
            ),
          ),
          child: Text(label, textAlign: TextAlign.center),
        ),
      );
}
