import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ar/ar_measure_service.dart';
import '../../core/storage/measure_store.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/models.dart';
import '../../shared/widgets/app_snack.dart';

/// AR 量尺（LiDAR，iPhone 12 Pro+）。
///
/// 交互（AR_UX_SMOOTH.md 覆盖版，手势驱动连续测量）：
/// 进入即连续测量 → 单击采点A(蓝) → 再单击采点B(红)+连线 → 自动出距离 →
/// 保留上一组视觉，下次单击开新组；长按清除；暂停/继续开关；加入校对写入会话。
class ArMeasurePage extends StatefulWidget {
  final MeasureArgs args;
  const ArMeasurePage({super.key, required this.args});

  @override
  State<ArMeasurePage> createState() => _ArMeasurePageState();
}

class _ArMeasurePageState extends State<ArMeasurePage> {
  static const _viewType = 'ar_measure_view';
  static const _viewId = 0;

  late final ArMeasureService _svc;
  double? _lastMm;
  bool _supported = false;
  bool _paused = false;
  String _hint = '点屏幕采点A';
  final _nameCtl = TextEditingController(text: 'AR实测');
  final _drawingCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _svc = ArMeasureService(viewId: _viewId);
    _svc.channel.setMethodCallHandler(_onNative);
  }

  Future<dynamic> _onNative(MethodCall call) async {
    if (call.method == 'onMeasure') {
      final mm = ((call.arguments as Map)['mm'] as num).toDouble();
      if (mounted) {
        setState(() {
          _lastMm = mm;
          _hint = '测量完成，可继续测下一组，或加入校对';
        });
      }
    } else if (call.method == 'onPointA') {
      if (mounted) setState(() => _hint = '已采点A，请再点一次');
    } else if (call.method == 'onCleared') {
      if (mounted) {
        setState(() {
          _lastMm = null;
          _hint = '点屏幕采点A';
        });
      }
    } else if (call.method == 'onError') {
      if (mounted) {
        AppSnack.show(context, call.arguments?.toString() ?? '测量失败',
            kind: AppSnackKind.danger);
      }
    }
  }

  @override
  void dispose() {
    _svc.stopSession();
    _nameCtl.dispose();
    _drawingCtl.dispose();
    super.dispose();
  }

  Future<void> _onViewCreated(int id) async {
    _supported = await _svc.isSupported();
    if (!mounted) return;
    if (!_supported) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('需要 LiDAR 设备'),
          content: const Text('AR量尺需 iPhone 12 Pro 及以上机型，请改用照片量尺。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    // 原生默认进入连续模式，无需再 setMode。
    await _svc.startSession();
  }

  Future<void> _addToSession() async {
    final drawingMm = double.tryParse(_drawingCtl.text);
    if (_lastMm == null || drawingMm == null || drawingMm <= 0) {
      AppSnack.show(context, '请先完成AR测量并填写图纸尺寸',
          kind: AppSnackKind.danger);
      return;
    }
    var s = await MeasureStore.load(widget.args.projectKey, widget.args.drawingKey);
    s ??= MeasureSession(
      id: '${widget.args.projectKey}_${widget.args.drawingKey}_ar',
      projectKey: widget.args.projectKey,
      drawingKey: widget.args.drawingKey,
      floor: widget.args.floor,
    );
    final item = MeasureItem(
      name: _nameCtl.text.trim().isEmpty ? 'AR实测' : _nameCtl.text.trim(),
      drawingMm: drawingMm,
      photoMm: _lastMm!,
      source: 'ar_lidar',
    );
    await MeasureStore.save(s.copyWith(items: [...s.items, item]));
    if (mounted) {
      AppSnack.show(context, '已加入校对清单');
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !Platform.isIOS) {
      return Scaffold(
        appBar: AppBar(title: const Text('AR量尺')),
        body: const Center(child: Text('AR量尺仅支持 iPhone Pro 机型（iOS）')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('AR量尺（LiDAR）')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                UiKitView(
                  viewType: _viewType,
                  onPlatformViewCreated: _onViewCreated,
                  creationParams: null,
                  creationParamsCodec: const StandardMessageCodec(),
                ),
                Positioned(
                  top: AppTokens.space4,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
                      // 动态提示条
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 32),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(_hint,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13)),
                      ),
                      if (_lastMm != null)
                        Card(
                          color: Colors.black.withValues(alpha: 0.65),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            child: Text(
                              '实测 ${_lastMm!.toStringAsFixed(1)} mm',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppTokens.space3),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          _paused = !_paused;
                          await _svc.setMode(_paused ? 0 : 1);
                          setState(() {});
                        },
                        icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                        label: Text(_paused ? '继续' : '暂停'),
                      ),
                    ),
                    const SizedBox(width: AppTokens.space2),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await _svc.clear();
                          setState(() {
                            _lastMm = null;
                            _hint = '点屏幕采点A';
                          });
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('清除'),
                      ),
                    ),
                    const SizedBox(width: AppTokens.space2),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _lastMm == null ? null : _addToSession,
                        child: const Text('加入校对'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.space2),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameCtl,
                        decoration: const InputDecoration(
                            labelText: '量尺项名称',
                            isDense: true,
                            border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: AppTokens.space2),
                    Expanded(
                      child: TextField(
                        controller: _drawingCtl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            labelText: '图纸尺寸(mm)',
                            isDense: true,
                            border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
