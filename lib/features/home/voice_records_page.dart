import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/design_tokens.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_snack.dart';
import '../../shared/widgets/nav_icon_button.dart';
import '../../shared/widgets/voice_input.dart';

/// 语音记录页：把原来的底部弹窗整理成独立工作页，
/// 让识别状态、结果预览和后续操作都在同一屏内完成。
class VoiceRecordsPage extends ConsumerStatefulWidget {
  const VoiceRecordsPage({super.key});

  @override
  ConsumerState<VoiceRecordsPage> createState() => _VoiceRecordsPageState();
}

class _VoiceRecordsPageState extends ConsumerState<VoiceRecordsPage> {
  String _partial = '';
  String _finalText = '';
  bool _done = false;

  void _commit(String text) {
    if (text.trim().isEmpty) return;
    setState(() {
      _finalText = text.trim();
      _done = true;
    });
  }

  void _reset() {
    setState(() {
      _partial = '';
      _finalText = '';
      _done = false;
    });
  }

  Future<void> _copyResult() async {
    final text = _done ? _finalText : _partial;
    if (text.trim().isEmpty) {
      AppSnack.show(context, '暂无可复制的语音内容', kind: AppSnackKind.muted);
      return;
    }
    await Clipboard.setData(ClipboardData(text: text.trim()));
    if (!mounted) return;
    AppSnack.show(context, '已复制识别内容', kind: AppSnackKind.success);
  }

  @override
  Widget build(BuildContext context) {
    final currentText = _done ? _finalText : _partial;
    final hasText = currentText.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: AppTokens.bg,
      appBar: AppBar(
        backgroundColor: AppTokens.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        leadingWidth: 36,
        leading: const Padding(
          padding: EdgeInsets.only(left: 12),
          child: NavIconButton(icon: MingCuteIcons.leftLine),
        ),
        title: const Text(
          '语音记录',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 24 / 16,
            color: AppTokens.fg,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                children: [
                  // 顶部说明卡：先交代当前页面作用和操作方式。
                  const AppCard(
                    padding: EdgeInsets.all(12),
                    radius: AppTokens.radiusLg,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 32,
                              height: 32,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: AppTokens.brandTint,
                                  borderRadius: BorderRadius.all(
                                      Radius.circular(AppTokens.radiusSm)),
                                ),
                                child: Icon(
                                  MingCuteIcons.voiceLine,
                                  size: 18,
                                  color: AppTokens.brand,
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '现场语音快速记录',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      height: 22 / 14,
                                      color: AppTokens.fg,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    '点击下方麦克风开始录入，识别结果会实时显示在页面中',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      height: 20 / 12,
                                      color: AppTokens.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 结果区：统一用浅灰工作区承载实时文本和最终文本。
                  AppCard(
                    padding: const EdgeInsets.all(12),
                    radius: AppTokens.radiusLg,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              '识别内容',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                height: 22 / 14,
                                color: AppTokens.fg,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              height: 20,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: _done
                                    ? const Color(0x0D00B84A)
                                    : const Color(0x0D0395FF),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                _done ? '已完成' : '录入中',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  height: 20 / 12,
                                  color: _done
                                      ? const Color(0xFF00B84A)
                                      : AppTokens.brand,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(minHeight: 180),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTokens.surface2,
                            borderRadius:
                                BorderRadius.circular(AppTokens.radiusSm),
                          ),
                          child: Text(
                            hasText ? currentText : '点击下方按钮后开始说话，识别内容会实时显示在这里',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              height: 22 / 14,
                              color: hasText ? AppTokens.fg : AppTokens.muted,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _done ? '识别完成后可以直接复制结果' : '再次点击麦克风即可停止识别',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            height: 20 / 12,
                            color: AppTokens.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 底部固定操作区：麦克风居中，左右是重说和复制，保持工作台操作层级。
            Container(
              color: AppTokens.surface,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: _VoiceActionButton(
                        label: '重说',
                        onTap: _reset,
                      ),
                    ),
                    const SizedBox(width: 12),
                    VoiceInputButton(
                      holdToTalk: false,
                      size: 56,
                      iconSize: 24,
                      onInterim: (text) => setState(() {
                        _partial = text;
                        _done = false;
                      }),
                      onResult: _commit,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _VoiceActionButton(
                        label: '复制结果',
                        primary: true,
                        onTap: _copyResult,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 语音记录页底部操作按钮：保持一主一次的固定操作层级。
class _VoiceActionButton extends StatelessWidget {
  final String label;
  final bool primary;
  final VoidCallback onTap;

  const _VoiceActionButton({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary ? AppTokens.accent : AppTokens.surface2,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 24 / 16,
              color: primary ? AppTokens.onAccent : AppTokens.fg2,
            ),
          ),
        ),
      );
}
