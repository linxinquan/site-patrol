import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/design_tokens.dart';

/// 引导第 0 页：产品价值主张「四步数据闭环」。
/// 登录后、选身份前展示，讲清设计院视角的数据闭环，弱化「巡检」定位。
/// inside / iOS 扁平化：白底、大留白、单一主色、横向四步流程。
class ValuePage extends ConsumerWidget {
  const ValuePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(flex: 2),
                  // —— 顶部：品牌 + 一句话定位 ——
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF0E6),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(LucideIcons.ruler,
                            size: 17, color: AppTokens.accent),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '蓝图落地',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: AppTokens.fg,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '设计院视角的现场数据闭环',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppTokens.muted,
                    ),
                  ),
                  const Spacer(flex: 2),
                  // —— 中部：四步闭环横向流程 ——
                  const _StepFlow(),
                  const Spacer(flex: 3),
                  // —— 底部：价值总结 + 进入按钮 ——
                  const Text(
                    '现场反馈反哺设计，缺陷沉淀成知识库',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      height: 1.5,
                      color: AppTokens.mutedA11y,
                    ),
                  ),
                  const SizedBox(height: AppTokens.space5),
                  FilledButton(
                    onPressed: () => context.push('/onboard'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTokens.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: const Text(
                      '开始使用',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Spacer(flex: 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 四步闭环横向流程：拍照 → AI 分类关联 → 责任判定 → 知识库。
/// 弱化信息、突出流转关系，扁平圆形图标 + 连接线。
class _StepFlow extends StatelessWidget {
  const _StepFlow();

  static const _steps = [
    _StepData(
        icon: LucideIcons.camera,
        tint: AppTokens.accent,
        title: '现场拍照',
        desc: '随手记录'),
    _StepData(
        icon: LucideIcons.brainCircuit,
        tint: AppTokens.brand,
        title: 'AI 分类关联',
        desc: '图纸 + 规范'),
    _StepData(
        icon: LucideIcons.scale,
        tint: AppTokens.warning,
        title: '责任判定',
        desc: '设计 / 施工'),
    _StepData(
        icon: LucideIcons.database,
        tint: AppTokens.success,
        title: '知识库',
        desc: '反哺设计'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          '四步数据闭环',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: AppTokens.fg,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '不只看「整改销项」，更沉淀设计经验',
          style: TextStyle(fontSize: 11.5, color: AppTokens.muted),
        ),
        const SizedBox(height: AppTokens.space6),
        // 横向四步
        Row(
          children: [
            for (var i = 0; i < _steps.length; i++) ...[
              _StepNode(step: _steps[i], isLast: i == _steps.length - 1),
              if (i < _steps.length - 1) const _StepConnector(),
            ],
          ],
        ),
      ],
    );
  }
}

class _StepData {
  final IconData icon;
  final Color tint;
  final String title;
  final String desc;
  const _StepData({
    required this.icon,
    required this.tint,
    required this.title,
    required this.desc,
  });
}

class _StepNode extends StatelessWidget {
  final _StepData step;
  final bool isLast;
  const _StepNode({required this.step, required this.isLast});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: step.tint.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(step.icon, color: step.tint, size: 23),
            ),
            const SizedBox(height: 10),
            Text(step.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: AppTokens.fg)),
            const SizedBox(height: 3),
            Text(step.desc,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 10.5,
                    color: AppTokens.muted,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      );
}

/// 步骤之间的连接线 + 箭头。
class _StepConnector extends StatelessWidget {
  const _StepConnector();

  @override
  Widget build(BuildContext context) => Container(
        width: 22,
        height: 2,
        margin: const EdgeInsets.only(top: 26),
        color: AppTokens.border,
      );
}
