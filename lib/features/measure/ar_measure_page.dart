import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:app_settings/app_settings.dart';

import '../../core/ar/ar_measure_service.dart';
import '../../core/storage/measure_store.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/models.dart';
import '../../core/utils/camera_pick.dart';
import '../../shared/widgets/app_snack.dart';

/// AR 量尺（LiDAR，iPhone 12 Pro+）。
///
/// 交互：进入即连续测量 → 单击采点A(蓝) → 再单击采点B(红)+连线 → 自动出距离 →
/// 保留上一组视觉，下次单击开新组；支持多点测量，可删除单条后批量保存到会话。
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
  final List<double> _measurements = [];
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
          _measurements.add(mm);
          _hint = '已测 ${_measurements.length} 组，可继续测或保存';
        });
      }
    } else if (call.method == 'onPointA') {
      if (mounted) setState(() => _hint = '已采点A，请再点一次');
    } else if (call.method == 'onCleared') {
      if (mounted) {
        setState(() {
          _lastMm = null;
          _measurements.clear();
          _hint = '点屏幕采点A';
        });
      }
    } else if (call.method == 'onError') {
      if (mounted) {
        AppSnack.show(context, call.arguments?.toString() ?? '测量失败',
            kind: AppSnackKind.danger);
      }
    } else if (call.method == 'onCameraDenied') {
      if (mounted) _showPermissionGuide();
    }
  }

  /// 相机权限被拒 → 引导去系统设置（与 capture_page 同款）。
  Future<void> _showPermissionGuide() async {
    if (!mounted) return;
    final goSettings = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('相机权限被拒绝'),
        content: const Text('AR量尺需要相机权限。请在系统设置中开启，再回来继续测量。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
    if (goSettings == true) {
      AppSettings.openAppSettings();
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
    // UiKitView 创建后 channel 才注册；先放行渲染，再去查设备支持。
    _supported = true;
    if (mounted) setState(() {});
    final supported = await _svc.isSupported();
    if (!mounted) return;
    if (!supported) {
      // 不支持 LiDAR → 收回渲染权限，show 占位
      _supported = false;
      setState(() {});
      return;
    }
    // 原生默认进入连续模式，无需再 setMode。
    await _svc.startSession();
  }

  /// 批量保存：把 _measurements 全部写入会话。
  Future<void> _saveAll() async {
    if (_measurements.isEmpty) {
      AppSnack.show(context, '暂无测量结果', kind: AppSnackKind.danger);
      return;
    }
    final drawingMm = double.tryParse(_drawingCtl.text);
    var s = await MeasureStore.load(widget.args.projectKey, widget.args.drawingKey);
    s ??= MeasureSession(
      id: '${widget.args.projectKey}_${widget.args.drawingKey}_ar',
      projectKey: widget.args.projectKey,
      drawingKey: widget.args.drawingKey,
      floor: widget.args.floor,
    );
    final items = [
      for (var i = 0; i < _measurements.length; i++)
        MeasureItem(
          name: 'AR-${i + 1}',
          drawingMm: (drawingMm ?? 0),
          photoMm: _measurements[i],
          source: 'ar_lidar',
        ),
    ];
    await MeasureStore.save(s.copyWith(items: [...s.items, ...items]));
    if (mounted) {
      AppSnack.show(context, '已保存 ${items.length} 条测量');
      Navigator.of(context).pop();
    }
  }

  /// 非 iOS / Web：LiDAR 不可用 → 提供「拍照→照片量尺」入口（接入 camera_pick 相机兜底）。
  Widget _buildUnsupported() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AR量尺'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.space4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.phone_iphone, size: 56, color: AppTokens.muted),
              const SizedBox(height: AppTokens.space3),
              const Text(
                'AR量尺（LiDAR）仅支持 iPhone 12 Pro 及以上机型',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppTokens.space2),
              const Text(
                '当前设备不支持 LiDAR，请拍照后到照片量尺完成现场测量。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppTokens.muted),
              ),
              const SizedBox(height: AppTokens.space4),
              FilledButton.icon(
                onPressed: _captureForPhotoMeasure,
                icon: const Icon(Icons.camera_alt),
                label: const Text('拍照并前往照片量尺'),
              ),
              const SizedBox(height: AppTokens.space2),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭并返回'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 调用 camera_pick 拍照，成功后跳转到照片量尺（CapturePage）继续。
  Future<void> _captureForPhotoMeasure() async {
    final file = await pickPhotoRobust(
      context,
      onDenied: _showPermissionGuide,
      maxWidth: 1920.0,
      imageQuality: 88,
    );
    if (file == null || !mounted) return;
    // 跳转到照片量尺：复用拍照记录流程，选点后关联刚拍的照片。
    context.push(
      '/capture',
      extra: CaptureArgs(
        projectId: widget.args.projectKey,
        floor: widget.args.floor,
        anchorLabel: 'AR量尺·现场照片',
        x: 0.5,
        y: 0.5,
        drawingKey: widget.args.drawingKey,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !Platform.isIOS) {
      // Web / 非 iOS：LiDAR 不可用，直接提示，不提供假估算。
      return _buildUnsupported();
    }
    return Scaffold(
      appBar: AppBar(title: const Text('AR量尺（LiDAR）')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                if (_supported)
                  UiKitView(
                    viewType: _viewType,
                    onPlatformViewCreated: _onViewCreated,
                    creationParams: null,
                    creationParamsCodec: const StandardMessageCodec(),
                  )
                else
                  _buildLiDARPlaceholder(),
                Positioned(
                  top: AppTokens.space4,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
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
                        onPressed: _supported
                            ? () async {
                                _paused = !_paused;
                                await _svc.setMode(_paused ? 0 : 1);
                                setState(() {});
                              }
                            : null,
                        icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                        label: Text(_paused ? '继续' : '暂停'),
                      ),
                    ),
                    const SizedBox(width: AppTokens.space2),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _supported
                            ? () async {
                                await _svc.clear();
                                setState(() {
                                  _lastMm = null;
                                  _measurements.clear();
                                  _hint = '点屏幕采点A';
                                });
                              }
                            : null,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('清除'),
                      ),
                    ),
                    const SizedBox(width: AppTokens.space2),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _supported && _measurements.isNotEmpty
                            ? _saveAll
                            : null,
                        child: const Text('保存'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.space2),
                // 测量列表
                Container(
                  height: 180,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ListView.builder(
                    itemCount: _measurements.length,
                    itemBuilder: (ctx, i) {
                      final m = _measurements[i];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Text(
                          '${i + 1}.',
                          style: const TextStyle(color: AppTokens.muted),
                        ),
                        title: Text('实测 ${m.toStringAsFixed(1)} mm'),
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle_outline,
                              size: 20, color: AppTokens.danger),
                          onPressed: () {
                            setState(() {
                              _measurements.removeAt(i);
                              if (_measurements.isEmpty) _lastMm = null;
                            });
                          },
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppTokens.space2),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameCtl,
                        enabled: false,
                        decoration: const InputDecoration(
                            labelText: '量尺项名称（批量保存用 AR-N）',
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
                            labelText: '图纸尺寸(mm，可选)',
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

  Widget _buildLiDARPlaceholder() {
    return Container(
      color: const Color(0xFF0A0A0A),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(AppTokens.space4),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.view_in_ar, size: 56, color: Colors.white54),
          SizedBox(height: AppTokens.space3),
          Text(
            '正在检测 LiDAR 支持…',
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
        ],
      ),
    );
  }
}
