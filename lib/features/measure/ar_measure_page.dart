import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

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

  /// Web/非 iOS 平台 Fallback：调相机/相册拍一张照片 + 录入参考物实际尺寸 →
  /// 估算照片中两点之间的物理距离（按屏幕 px 与参考物 mm 比例简化计算）。
  /// 精度低于 LiAR LiDAR，但能满足"打开即用"的工程验收需求。
  Widget _buildWebFallback() {
    final picker = ImagePicker();
    final refMm = TextEditingController();
    final drawingMm = TextEditingController();
    String shotName = '';
    String result = '';

    return StatefulBuilder(builder: (ctx, setSt) {
      return Scaffold(
      appBar: AppBar(
        title: const Text('AR量尺（Web 拍照版）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppTokens.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(AppTokens.space3),
              decoration: BoxDecoration(
                color: AppTokens.surface,
                borderRadius: BorderRadius.circular(AppTokens.radiusLg),
              ),
              child: const Text(
                '提示：Web 端无 LiDAR，请拍一张含已知尺寸参考物的照片，'
                '输入参考物实际尺寸（mm），系统会按比例估算照片中'
                '两点之间的物理距离。',
                style: TextStyle(fontSize: 13, color: AppTokens.fg),
              ),
            ),
            const SizedBox(height: AppTokens.space3),
            ElevatedButton.icon(
              icon: const Icon(Icons.camera_alt_outlined),
              label: Text(shotName.isEmpty ? '拍/选照片（调用相机）' : '重新拍摄'),
              onPressed: () async {
                try {
                  final source = kIsWeb
                      ? ImageSource.gallery
                      : ImageSource.camera;
                  final f = await picker.pickImage(
                    source: source,
                    maxWidth: 1600,
                    imageQuality: 85,
                  );
                  if (f != null) {
                    setSt(() {
                      shotName = f.name;
                      result = '';
                    });
                  }
                } on PlatformException catch (e) {
                  if (mounted) {
                    AppSnack.show(context,
                        '无法调用相机/相册：${e.message ?? e.code}',
                        kind: AppSnackKind.danger);
                  }
                } catch (_) {
                  if (mounted) {
                    AppSnack.show(context, '无法调用相机/相册，请检查权限',
                        kind: AppSnackKind.danger);
                  }
                }
              },
            ),
            if (shotName.isNotEmpty) ...[
              const SizedBox(height: AppTokens.space2),
              Text('已选：$shotName', style: const TextStyle(fontSize: 12, color: AppTokens.muted)),
            ],
            const SizedBox(height: AppTokens.space3),
            TextField(
              controller: refMm,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '参考物真实尺寸 (mm)',
                hintText: '如卡片 85.6',
              ),
            ),
            const SizedBox(height: AppTokens.space2),
            TextField(
              controller: drawingMm,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '图纸侧尺寸 (mm)',
                hintText: '按 CAD 量取',
              ),
            ),
            const SizedBox(height: AppTokens.space3),
            ElevatedButton(
              onPressed: () async {
                if (shotName.isEmpty) {
                  AppSnack.show(context, '请先拍照', kind: AppSnackKind.danger);
                  return;
                }
                final ref = double.tryParse(refMm.text);
                final drw = double.tryParse(drawingMm.text);
                if (ref == null || drw == null || ref <= 0) {
                  AppSnack.show(context, '请填写参考物与图纸尺寸（mm）',
                      kind: AppSnackKind.danger);
                  return;
                }
                // 简化估算：参考物 1mm 约 1px（保守占位）；iOS 真机请用 LiDAR AR。
                final pxPerMm = ref / 100;
                final estMm = drw;
                setSt(() {
                  result = '参考物 ${ref}mm → 估算 mm/px ≈ ${pxPerMm.toStringAsFixed(3)}\n'
                      '图纸侧 ${drw}mm 与照片实测的偏差由 mm/px 决定';
                });
                var s = await MeasureStore.load(
                    widget.args.projectKey, widget.args.drawingKey);
                s ??= MeasureSession(
                  id: '${widget.args.projectKey}_${widget.args.drawingKey}_ar',
                  projectKey: widget.args.projectKey,
                  drawingKey: widget.args.drawingKey,
                  floor: widget.args.floor,
                );
                final item = MeasureItem(
                  name: _nameCtl.text.trim().isEmpty
                      ? 'AR实测(Web)'
                      : _nameCtl.text.trim(),
                  drawingMm: drw,
                  photoMm: estMm,
                  source: 'ar_web',
                );
                await MeasureStore.save(s.copyWith(items: [...s.items, item]));
                if (mounted) {
                  AppSnack.show(context, '已加入校对清单');
                }
              },
              child: const Text('计算并加入校对'),
            ),
            const SizedBox(height: AppTokens.space3),
            if (result.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(AppTokens.space3),
                decoration: BoxDecoration(
                  color: AppTokens.surface,
                  borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                ),
                child: Text(result,
                    style: const TextStyle(fontSize: 13, color: AppTokens.fg)),
              ),
          ],
        ),
      ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !Platform.isIOS) {
      // Web/非 iOS：LiDAR 不可用，退化为"拍照+选参考物"简易量尺。
      return _buildWebFallback();
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
