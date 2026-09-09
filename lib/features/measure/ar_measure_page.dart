import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../shared/widgets/nav_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:app_settings/app_settings.dart';

import '../../core/ar/ar_measure_service.dart';
import '../../core/storage/measure_store.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/models.dart';
import '../../core/utils/camera_pick.dart';
import '../../core/utils/measure_math.dart';
import '../../core/utils/mm_format.dart';
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
  /// 同一被测边的重复采样读数（mm）：对同一条边多测几次，
  /// 采纳时取稳健中位为读数、离散半宽为 ±误差带，提高判定可信度。
  final List<double> _samples = [];
  /// 已采纳的读数组（每组 = 中位值 + 误差带半宽），逐组写为一条 MeasureItem。
  final List<({double mm, double errMm})> _readings = [];
  bool _supported = false;
  bool _paused = false;
  String _hint = '对目标边采点：点一次=A，再点=B 出距离';
  final _nameCtl = TextEditingController(text: 'AR实测');
  final _drawingCtl = TextEditingController();
  MeasureSession? _session;

  @override
  void initState() {
    super.initState();
    _svc = ArMeasureService(viewId: _viewId);
    _svc.channel.setMethodCallHandler(_onNative);
    _loadSession();
  }

  /// 读取已有会话取容差（判定门控用），无则保持默认。
  Future<void> _loadSession() async {
    final s =
        await MeasureStore.load(widget.args.projectKey, widget.args.drawingKey);
    if (mounted && s != null) setState(() => _session = s);
  }

  double get _tolMm => _session?.tolMm ?? 15;
  double get _tolPct => _session?.tolPct ?? 2;

  Future<dynamic> _onNative(MethodCall call) async {
    if (call.method == 'onMeasure') {
      final mm = ((call.arguments as Map)['mm'] as num).toDouble();
      if (mounted) {
        setState(() {
          _samples.add(mm);
          _hint = '第 ${_samples.length} 次读数（同边重复测更稳），满意后点「采纳本组」';
        });
      }
    } else if (call.method == 'onPointA') {
      if (mounted) setState(() => _hint = '已采点A，请再点一次');
    } else if (call.method == 'onCleared') {
      if (mounted) {
        setState(() {
          _samples.clear();
          _hint = '已清除本组采样，重新对目标边采点（A→B）';
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
    // view 已创建、channel 已注册，此时查询设备支持才可靠。
    final supported = await _svc.isSupported();
    if (!mounted) return;
    setState(() => _supported = supported);
    if (!supported) return;
    // 原生默认进入连续模式，无需再 setMode。
    await _svc.startSession();
  }

  /// 采纳当前采样组：中位数为读数，离散半宽为 ±误差带。
  void _adoptSamples() {
    if (_samples.length < 2) {
      AppSnack.show(context, '请对同一条边至少测 2 次再采纳', kind: AppSnackKind.muted);
      return;
    }
    setState(() {
      _readings.add(
          (mm: medianOf(_samples), errMm: spreadHalfRange(_samples)));
      _samples.clear();
      _hint = '已采纳一组，可继续测下一条边；全部测完点「保存」';
    });
  }

  /// 一组读数的判定说明：误差带 > 容差/3 → 不可判定需复核；否则按偏差给结论。
  /// 未填图纸尺寸返回 null（仅记录，不判定）。
  String? _verdictOf(double mm, double errMm) {
    final drawingMm = double.tryParse(_drawingCtl.text);
    if (drawingMm == null || drawingMm <= 0) return null;
    final dev = mm - drawingMm;
    final devPct = dev / drawingMm * 100;
    if (!canJudgeByError(errMm, _tolMm)) {
      return '误差 ±${fmtMm(errMm)}mm 大于容差 1/3，需卷尺复核';
    }
    final ok = dev.abs() <= _tolMm && devPct.abs() <= _tolPct;
    return ok ? '偏差 ${fmtMmSigned(dev)}mm · 合格' : '偏差 ${fmtMmSigned(dev)}mm · 超差';
  }

  /// 批量保存：把已采纳的读数组全部写入会话（带误差带）。
  Future<void> _saveAll() async {
    if (_readings.isEmpty) {
      AppSnack.show(context, '暂无已采纳的测量结果', kind: AppSnackKind.danger);
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
      for (var i = 0; i < _readings.length; i++)
        MeasureItem(
          name: 'AR-${i + 1}',
          drawingMm: (drawingMm ?? 0),
          photoMm: _readings[i].mm,
          source: 'ar_lidar',
          errorMm: _readings[i].errMm,
        ),
    ];
    await MeasureStore.save(s.copyWith(items: [...s.items, ...items]));
    if (mounted) {
      AppSnack.show(context, '已保存 ${items.length} 条测量（含误差带）');
      Navigator.of(context).pop();
    }
  }

  /// 非 iOS / Web：LiDAR 不可用 → 提供「拍照→照片量尺」入口（接入 camera_pick 相机兜底）。
  Widget _buildUnsupported() {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: NavIconButton(icon: MingCuteIcons.leftLine),
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
              const Icon(MingCuteIcons.phoneLine, size: 56, color: AppTokens.muted),
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
                icon: const Icon(MingCuteIcons.cameraLine),
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
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: NavIconButton(icon: MingCuteIcons.leftLine),
        title: const Text('AR量尺（LiDAR）'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                // UiKitView 必须无条件渲染：只有 view 先创建，原生 ArMeasureView
                // 才会注册 channel，随后 _onViewCreated 才能查到 LiDAR 支持。
                UiKitView(
                  viewType: _viewType,
                  onPlatformViewCreated: _onViewCreated,
                  creationParams: null,
                  creationParamsCodec: const StandardMessageCodec(),
                ),
                if (!_supported) _buildLiDARPlaceholder(),
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
                      if (_samples.isNotEmpty)
                        Card(
                          color: Colors.black.withValues(alpha: 0.65),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '本次 ${fmtMm(_samples.last)} mm',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700),
                                ),
                                if (_samples.length >= 2)
                                  Text(
                                    '本组中位 ${fmtMm(medianOf(_samples))} '
                                    '±${fmtMm(spreadHalfRange(_samples))} mm'
                                    '（n=${_samples.length}）',
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 12),
                                  ),
                              ],
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
                // 采纳本组：同边重复采样 ≥2 次后，取中位 ± 误差带进入清单
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _supported && _samples.length >= 2
                        ? _adoptSamples
                        : null,
                    icon: const Icon(MingCuteIcons.checkCircleLine, size: 18),
                    label: Text(
                      _samples.length < 2
                          ? '采纳本组（同边再测 ${2 - _samples.length} 次可启用）'
                          : '采纳本组 → ${fmtMm(medianOf(_samples))} '
                              '±${fmtMm(spreadHalfRange(_samples))} mm',
                    ),
                  ),
                ),
                const SizedBox(height: AppTokens.space2),
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
                        icon: Icon(_paused ? MingCuteIcons.playLine : MingCuteIcons.pauseLine),
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
                                  _samples.clear();
                                  _readings.clear();
                                  _hint = '对目标边采点：点一次=A，再点=B 出距离';
                                });
                              }
                            : null,
                        icon: const Icon(MingCuteIcons.deleteLine),
                        label: const Text('清除'),
                      ),
                    ),
                    const SizedBox(width: AppTokens.space2),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _supported && _readings.isNotEmpty
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
                    itemCount: _readings.length,
                    itemBuilder: (ctx, i) {
                      final r = _readings[i];
                      final verdict = _verdictOf(r.mm, r.errMm);
                      final Color? vColor = verdict == null
                          ? null
                          : verdict.contains('合格')
                              ? Colors.green
                              : verdict.contains('超差')
                                  ? AppTokens.danger
                                  : Colors.orange;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Text('AR-${i + 1}.',
                            style: const TextStyle(color: AppTokens.muted)),
                        title: Text('${fmtMm(r.mm)} ±${fmtMm(r.errMm)} mm',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: verdict == null
                            ? null
                            : Text(verdict,
                                style: TextStyle(fontSize: 12, color: vColor)),
                        trailing: IconButton(
                          icon: const Icon(MingCuteIcons.minusCircleLine,
                              size: 20, color: AppTokens.danger),
                          onPressed: () {
                            setState(() => _readings.removeAt(i));
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
          Icon(MingCuteIcons.cubeLine, size: 56, color: Colors.white54),
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
