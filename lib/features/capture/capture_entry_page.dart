import 'package:flutter/material.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/design_tokens.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/user_switcher.dart';

/// 验收一级入口页：只保留流程说明和入口，不在这里直接做拍照操作。
class CaptureEntryPage extends StatelessWidget {
  const CaptureEntryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.bg,
      appBar: AppBar(
        backgroundColor: AppTokens.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 48,
        scrolledUnderElevation: 0,
        titleSpacing: 12,
        title: const Text(
          '验收',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            height: 32 / 24,
            color: AppTokens.fg,
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: UserSwitcher(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.space3,
          AppTokens.space2,
          AppTokens.space3,
          AppTokens.space4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeroCard(),
            const SizedBox(height: AppTokens.space3),
            _buildStepCard(),
            const SizedBox(height: AppTokens.space3),
            SizedBox(
              width: double.infinity,
              child: AppButton(
                label: '开始验收',
                radius: AppTokens.radiusMd,
                onPressed: () => context.push('/capture/select'),
              ),
            ),
            const SizedBox(height: AppTokens.space2),
            SizedBox(
              width: double.infinity,
              child: AppButton(
                outlined: true,
                label: '查看验收记录',
                radius: AppTokens.radiusMd,
                onPressed: () => context.push('/capture-records'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部说明卡：告诉用户验收主页只负责承接入口。
  Widget _buildHeroCard() {
    return Container(
      padding: const EdgeInsets.all(AppTokens.space3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '按步骤完成验收',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              height: 26 / 18,
              color: AppTokens.fg,
            ),
          ),
          SizedBox(height: AppTokens.space2),
          Text(
            '验收主页只保留入口说明，不再把选图纸、选点、拍照、保存全部堆在同一页里。',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              height: 22 / 14,
              color: AppTokens.fg2,
            ),
          ),
        ],
      ),
    );
  }

  /// 步骤卡：把新流程讲清楚，减少用户第一次进入时的理解成本。
  Widget _buildStepCard() {
    const steps = [
      ('1', '选择图纸和部位', MingCuteIcons.layersLine),
      ('2', '现场拍照', MingCuteIcons.cameraLine),
      ('3', '识别并保存', MingCuteIcons.scanLine),
    ];
    return Container(
      padding: const EdgeInsets.all(AppTokens.space3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      ),
      child: Column(
        children: [
          for (int i = 0; i < steps.length; i++) ...[
            if (i > 0) const Divider(height: AppTokens.space4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppTokens.brandTint,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Center(
                    child: Icon(
                      steps[i].$3,
                      size: 18,
                      color: AppTokens.brand,
                    ),
                  ),
                ),
                const SizedBox(width: AppTokens.space3),
                Expanded(
                  child: Text(
                    '${steps[i].$1}. ${steps[i].$2}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 22 / 14,
                      color: AppTokens.fg,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
