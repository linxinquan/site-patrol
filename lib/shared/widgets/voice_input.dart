import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/utils/speech_recognizer.dart';
import '../../core/di/providers.dart';
import 'app_button.dart';
import 'app_snack.dart';

/// 可复用的语音录入组件集合。
///
/// - [VoiceInputButton]：通用触发按钮（按住说话 / 点击开关），可嵌入任意功能页。
/// - [VoiceInputSheet]：底部弹层形态（含实时文本 + 状态提示），适合首页等临时入口或独立录入场景。
///
/// 组件只负责「采集语音 → 产出文字」，通过回调 [onResult] 抛给宿主；
/// 文字用途（填输入框 / 跳转 / 存草稿）完全由宿主决定，组件保持无副作用、可复用。

const Duration _autoStop = Duration(seconds: 60);

/// ==================== 通用语音录入按钮 ====================
///
/// 用法：
/// ```dart
/// VoiceInputButton(
///   onResult: (text) => _noteController.text = text,
///   onInterim: (text) => setState(() => _live = text),
/// )
/// ```
class VoiceInputButton extends ConsumerStatefulWidget {
  /// 识别完成（最终文本）回调。
  final void Function(String text) onResult;

  /// 实时中间结果回调（可选）。
  final void Function(String text)? onInterim;

  /// true = 按住说话（默认）；false = 点击切换开始/停止。
  final bool holdToTalk;

  /// 图标尺寸（默认 22）。
  final double iconSize;

  /// 按钮直径（默认 56）。
  final double size;

  const VoiceInputButton({
    super.key,
    required this.onResult,
    this.onInterim,
    this.holdToTalk = true,
    this.iconSize = 22,
    this.size = 56,
  });

  @override
  ConsumerState<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends ConsumerState<VoiceInputButton> {
  bool _busy = false; // 初始化/请求权限中，防连点

  SpeechRecognizer get _rec => ref.read(speechRecognizerProvider);

  Future<void> _start() async {
    if (_busy || _rec.isListening) return;
    _busy = true;
    try {
      await _rec.listen(
        onPartial: (t) => widget.onInterim?.call(t),
        onFinal: (t) {
          widget.onResult(t);
          _busy = false;
        },
        listenFor: _autoStop,
      );
    } on SpeechException catch (e) {
      _busy = false;
      _notifyError(e.message);
    } catch (e) {
      _busy = false;
      _notifyError('语音识别启动失败');
    }
    if (mounted) setState(() {});
  }

  Future<void> _stop() async {
    await _rec.stop();
    _busy = false;
    if (mounted) setState(() {});
  }

  void _notifyError(String msg) {
    if (mounted) AppSnack.show(context, msg, kind: AppSnackKind.danger);
  }

  void _onPressDown() {
    if (widget.holdToTalk) _start();
  }

  void _onPressUp() {
    if (widget.holdToTalk && _rec.isListening) _stop();
  }

  void _onTap() {
    if (widget.holdToTalk) return; // 按住模式不响应点击
    if (_rec.isListening) {
      _stop();
    } else {
      _start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final listening = _rec.isListening;
    final active = listening || _busy;
    final color = active ? AppTokens.danger : AppTokens.accent;
    final child = Icon(
      listening ? LucideIcons.audioLines : LucideIcons.mic,
      color: active ? AppTokens.onAccent : AppTokens.accent,
      size: widget.iconSize,
    );

    Widget btn = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: active ? color : AppTokens.accentSoft,
        shape: BoxShape.circle,
        boxShadow: active
            ? [BoxShadow(color: AppTokens.danger.withValues(alpha: 0.3), blurRadius: 12, spreadRadius: 2)]
            : null,
      ),
      child: child,
    );

    if (widget.holdToTalk) {
      return GestureDetector(
        onTapDown: (_) => _onPressDown(),
        onTapUp: (_) => _onPressUp(),
        onTapCancel: _onPressUp,
        child: btn,
      );
    }
    return InkWell(onTap: _onTap, borderRadius: BorderRadius.circular(widget.size), child: btn);
  }
}

/// ==================== 底部语音录入弹层 ====================
///
/// 通过 `showModalBottomSheet` 打开；结束通过 [onResult] 回传识别文本。
/// 内部复用 [VoiceInputButton]（点击开关形态），并展示实时文本与状态提示。
class VoiceInputSheet extends ConsumerStatefulWidget {
  final void Function(String text) onResult;
  const VoiceInputSheet({super.key, required this.onResult});

  @override
  ConsumerState<VoiceInputSheet> createState() => _VoiceInputSheetState();
}

class _VoiceInputSheetState extends ConsumerState<VoiceInputSheet> {
  String _partial = '';
  String _final = '';
  bool _done = false;

  void _commit(String text) {
    if (text.trim().isEmpty) return;
    setState(() {
      _final = text;
      _done = true;
    });
  }

  void _useResult() {
    if (_final.trim().isNotEmpty) {
      widget.onResult(_final.trim());
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _final.isNotEmpty || _partial.isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题
            Row(
              children: [
                const Icon(LucideIcons.mic, color: AppTokens.accent, size: 18),
                const SizedBox(width: 8),
                const Text('语音记录',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700, color: AppTokens.fg)),
                const Spacer(),
                IconButton(
                  icon: const Icon(LucideIcons.x, color: AppTokens.muted, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                  splashRadius: 16,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 实时/最终文本区
            Container(
              constraints: const BoxConstraints(minHeight: 96, maxHeight: 200),
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTokens.surface2,
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                border: Border.all(color: AppTokens.border),
              ),
              child: SingleChildScrollView(
                child: _done
                    ? Text(_final,
                        style: const TextStyle(
                            fontSize: 16, color: AppTokens.fg, height: 1.5))
                    : Text(
                        _partial.isEmpty ? '点击麦克风开始说话…' : _partial,
                        style: TextStyle(
                          fontSize: 16,
                          color: _partial.isEmpty ? AppTokens.muted : AppTokens.fg2,
                          height: 1.5,
                          fontStyle: _partial.isEmpty ? FontStyle.italic : FontStyle.normal,
                        )),
              ),
            ),
            const SizedBox(height: 20),

            // 麦克风按钮（点击开关）
            Center(
              child: VoiceInputButton(
                holdToTalk: false,
                size: 64,
                iconSize: 26,
                onInterim: (t) => setState(() => _partial = t),
                onResult: _commit,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                _done ? '识别完成' : '点击开始 / 再次点击停止',
                style: const TextStyle(fontSize: 12, color: AppTokens.muted),
              ),
            ),

            if (hasText) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: '重说',
                      text: true,
                      onPressed: () => setState(() {
                        _partial = '';
                        _final = '';
                        _done = false;
                      }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: AppButton(
                      label: _done ? '使用此文本' : '停止并采用',
                      onPressed: () async {
                        if (!_done) {
                          await ref.read(speechRecognizerProvider).stop();
                        }
                        _useResult();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
