import 'package:speech_to_text/speech_to_text.dart' as stt;

/// 语音识别状态机：与 UI 解耦，供任意功能页复用。
enum SpeechStatus {
  idle, // 未开始
  unavailable, // 设备不支持 / 初始化失败
  noPermission, // 无麦克风/语音权限
  listening, // 录音识别中
  notListening, // 已停止（有结果）
  error, // 识别异常
}

/// 语音识别异常（统一封装，便于 UI 给中文提示）。
class SpeechException implements Exception {
  final String message;
  const SpeechException(this.message);
  @override
  String toString() => message;
}

/// 设备端语音识别服务（封装 speech_to_text）。
///
/// 默认走设备离线 ASR（支持中文），无需后端/Key，契合项目离线优先基调。
/// UI 通过 [status] 与回调 [onFinal]/[onPartial] 消费结果。
class SpeechRecognizer {
  final stt.SpeechToText _speech = stt.SpeechToText();

  SpeechStatus _status = SpeechStatus.idle;
  SpeechStatus get status => _status;

  bool get isAvailable => _status != SpeechStatus.unavailable;
  bool get isListening => _status == SpeechStatus.listening;

  /// 初始化引擎。必须在 [listen] 前调用一次。
  /// 返回是否可用；不可用（无引擎）时 [status] = unavailable。
  Future<bool> init() async {
    try {
      final ok = await _speech.initialize(
        onError: (err) {
          // 权限被拒：speech_to_text 会回调 error(code=permission)
          if (err.permanent) {
            _status = SpeechStatus.noPermission;
          } else {
            _status = SpeechStatus.error;
          }
        },
        onStatus: (s) {
          if (s == 'notListening') _status = SpeechStatus.notListening;
        },
      );
      _status = ok ? SpeechStatus.idle : SpeechStatus.unavailable;
      return ok;
    } catch (_) {
      _status = SpeechStatus.unavailable;
      return false;
    }
  }

  /// 挑选最佳中文 locale（无则回退设备默认）。
  Future<String> _pickLocale() async {
    try {
      final locales = await _speech.locales();
      final zh = locales.where((l) => l.localeId.toLowerCase().startsWith('zh'));
      if (zh.isNotEmpty) {
        // 优先 zh_CN > zh_TW > 其他 zh
        final cn = zh.where((l) => l.localeId.toLowerCase().contains('cn'));
        return (cn.isNotEmpty ? cn.first : zh.first).localeId;
      }
    } catch (_) {}
    return 'zh_CN';
  }

  /// 开始识别。
  /// [onPartial] 实时中间结果；[onFinal] 最终定稿文本。
  /// 权限缺失时抛 [SpeechException]（noPermission）。
  Future<void> listen({
    required void Function(String text) onPartial,
    required void Function(String text) onFinal,
    Duration? listenFor,
  }) async {
    if (_status == SpeechStatus.unavailable) {
      throw const SpeechException('当前设备不支持语音识别');
    }
    if (!_speech.isAvailable) {
      final ok = await init();
      if (!ok) throw const SpeechException('语音识别不可用');
    }
    final localeId = await _pickLocale();
    _status = SpeechStatus.listening;
    await _speech.listen(
      onResult: (result) {
        final text = result.recognizedWords;
        if (text.isEmpty) return;
        if (result.finalResult) {
          _status = SpeechStatus.notListening;
          onFinal(text);
        } else {
          onPartial(text);
        }
      },
      localeId: localeId,
      listenFor: listenFor ?? const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 3),
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.confirmation,
      ),
    );
  }

  /// 主动停止（松手/点停止时调用）。返回最终文本由 onFinal 回调给出。
  Future<void> stop() async {
    if (_speech.isListening) {
      await _speech.stop();
    }
    _status = SpeechStatus.notListening;
  }

  /// 取消本次识别（丢弃结果）。
  Future<void> cancel() async {
    if (_speech.isListening) {
      await _speech.cancel();
    }
    _status = SpeechStatus.idle;
  }

  void dispose() {
    _speech.cancel();
  }
}
