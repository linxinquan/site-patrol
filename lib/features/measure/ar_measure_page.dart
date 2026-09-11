import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../shared/widgets/nav_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:app_settings/app_settings.dart';

import '../../core/ar/ar_measure_service.dart';
import '../../core/storage/ar_scale_calibration.dart';
import '../../core/storage/measure_store.dart';
import '../../core/storage/measure_threshold_store.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/models.dart';
import '../../core/utils/camera_pick.dart';
import '../../core/utils/measure_math.dart';
import '../../core/utils/mm_format.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_dialog.dart';
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

  /// 项目级判定门槛（可配置容差与误差带门槛）。
  MeasureThresholds _thresholds = const MeasureThresholds();

  // —— 系统偏差校正（把「重复性」与「准确度」分开）——
  /// 本机尺度校正：读数 × k。null = 未校正（此时 ±误差带只代表重复性）。
  ArScaleCalibration? _scaleCalib;

  /// 校正模式：对本机已知长度重复采样，完成后再写回 [_scaleCalib]。
  bool _calibMode = false;
  final TextEditingController _calibRefCtl = TextEditingController(text: '297');

  /// 最近一次测量的距相机深度（mm，取两端均值；原生未上报时为 null）。
  double? _lastDepthMm;

  /// LiDAR 有效区间（mm）：超出则误差迅速放大，只提示不禁止。
  static const double _bestMinMm = 300;
  static const double _bestMaxMm = 3000;

  /// 超量程拒绝采样（mm）：超出 LiDAR 量程，读数不可信。
  static const double _rejectMm = 5000;

  /// 尺度系数（未校正为 1.0）。
  double get _k => _scaleCalib?.k ?? 1.0;

  /// 把原生原始读数换算为修正读数。
  double _corrected(double rawMm) => rawMm * _k;

  /// 距离门控文案：null = 原生未报深度（无法判断）。
  String? get _depthHint {
    final d = _lastDepthMm;
    if (d == null || d <= 0) return null;
    if (d > _rejectMm) {
      return '距相机 ${(d / 1000).toStringAsFixed(1)}m 超出 LiDAR 量程，读数不可信';
    }
    if (d > _bestMaxMm || d < _bestMinMm) {
      return '距相机 ${(d / 1000).toStringAsFixed(2)}m，超出最佳区间 '
          '0.3~3m，误差会明显放大';
    }
    return null;
  }

  /// 校正模式下按钮上的实时 k 预览（真值 / 当前采样中位）。
  String get _calibKPreview {
    final ref = double.tryParse(_calibRefCtl.text.trim()) ?? 0;
    final m = medianOf(_samples);
    if (ref <= 0 || m <= 0) return '—';
    return (ref / m).toStringAsFixed(4);
  }

  /// 是否处于最佳测量区间（深度未知时按"不阻断"处理）。
  bool get _depthOk {
    final d = _lastDepthMm;
    if (d == null || d <= 0) return true;
    return d >= _bestMinMm && d <= _bestMaxMm;
  }

  @override
  void initState() {
    super.initState();
    _svc = ArMeasureService(viewId: _viewId);
    _svc.channel.setMethodCallHandler(_onNative);
    _loadSession();
    _loadScaleCalib();
    _loadThresholds();
  }

  /// 读取本机已有的尺度校正（有则读数自动修正）。
  Future<void> _loadScaleCalib() async {
    final c = await ArScaleCalibrationStore.load();
    if (mounted && c != null) setState(() => _scaleCalib = c);
  }

  /// 读取已有会话取容差（判定门控用），无则用项目门槛。
  Future<void> _loadSession() async {
    final s =
        await MeasureStore.load(widget.args.projectKey, widget.args.drawingKey);
    if (mounted && s != null) setState(() => _session = s);
  }

  /// 项目级判定门槛（与照片量尺、报告口径同源）。
  Future<void> _loadThresholds() async {
    final t = await MeasureThresholdStore.load(widget.args.projectKey);
    if (mounted) setState(() => _thresholds = t);
  }

  double get _tolMm => _session?.tolMm ?? _thresholds.tolMm;
  double get _tolPct => _session?.tolPct ?? _thresholds.tolPct;

  /// 误差带门槛：项目配置优先，未配置回退容差/3。
  double get _judgeMaxErrorMm => _thresholds.judgeMaxErrorMm ?? _tolMm / 3;

  Future<dynamic> _onNative(MethodCall call) async {
    if (call.method == 'onMeasure') {
      final args = call.arguments as Map;
      final raw = (args['mm'] as num?)?.toDouble() ?? 0;
      final depth = (args['depthMm'] as num?)?.toDouble();
      if (!mounted) return;
      // 距离门控：超出 LiDAR 量程的读数直接丢弃（不污染中位数）。
      if (depth != null && depth > _rejectMm) {
        setState(() => _lastDepthMm = depth);
        AppSnack.show(
          context,
          '距相机 ${(depth / 1000).toStringAsFixed(1)}m 超出 LiDAR 量程（约 5m），'
          '该读数已丢弃，请靠近目标重测',
          kind: AppSnackKind.danger,
        );
        return;
      }
      setState(() {
        // 采样保存**原始读数**（校正模式要用原始值算 k），显示时才乘 k。
        _samples.add(raw);
        _lastDepthMm = depth;
        _hint = _calibMode
            ? '校正采样第 ${_samples.length} 次：对已知长度重复测，≥2 次后点「完成校正」'
            : '第 ${_samples.length} 次读数'
                '${_depthOk ? '' : '（当前超出最佳区间，误差偏大）'}，满意后点「采纳本组」';
      });
    } else if (call.method == 'onPointA') {
      if (mounted) setState(() => _hint = '已采点A，请再点一次');
    } else if (call.method == 'onCleared') {
      if (mounted) {
        setState(() {
          _samples.clear();
          _lastDepthMm = null;
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
    final goSettings = await AppDialog.show<bool>(
      context: context,
      title: '相机权限被拒绝',
      description: 'AR量尺需要相机权限。请在系统设置中开启，再回来继续测量。',
      actions: AppDialogActions(
        children: [
          AppDialogButton.secondary(
            label: '取消',
            onTap: () => Navigator.of(context, rootNavigator: true).pop(false),
          ),
          AppDialogButton.primary(
            label: '去设置',
            onTap: () => Navigator.of(context, rootNavigator: true).pop(true),
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
    _calibRefCtl.dispose();
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
  ///
  /// 读数与误差带都会乘上尺度系数 k（若有校正）——k 修正的是**系统偏差**，
  /// 而 ±误差带仍是**重复性**，两者含义不同，UI 文案分开表述。
  void _adoptSamples() {
    if (_samples.length < 2) {
      AppSnack.show(context, '请对同一条边至少测 2 次再采纳', kind: AppSnackKind.muted);
      return;
    }
    setState(() {
      _readings.add((
        mm: _corrected(medianOf(_samples)),
        errMm: spreadHalfRange(_samples) * _k,
      ));
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
    if (!(errMm > 0 && errMm <= _judgeMaxErrorMm)) {
      return '重复性 ±${fmtMm(errMm)}mm 超过门槛 '
          '±${fmtMm(_judgeMaxErrorMm)}mm，需卷尺复核';
    }
    final ok = dev.abs() <= _tolMm && devPct.abs() <= _tolPct;
    return ok
        ? '偏差 ${fmtMmSigned(dev)}mm · 合格'
        : '偏差 ${fmtMmSigned(dev)}mm · 超差';
  }

  // ——— 系统偏差校正（已知长度）———

  /// 进入校正模式：清空采样，让用户对一个已知长度重复测量。
  Future<void> _startCalib() async {
    final ctl = TextEditingController(text: _calibRefCtl.text);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('系统偏差校正'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AR 的 ±误差带只代表「重复性」，不含系统偏差（读数可能整体偏大/偏小）。\n'
              '请填一个**已知真实长度**（如 A4 长边 297、瓷砖 600、卷尺 1000），'
              '然后对它重复测 ≥2 次。',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '已知长度真值 (mm)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('开始校正')),
        ],
      ),
    );
    final ref = double.tryParse(ctl.text.trim());
    ctl.dispose();
    if (ok != true || ref == null || ref <= 0) return;
    setState(() {
      _calibMode = true;
      _calibRefCtl.text = fmtMm(ref);
      _samples.clear();
      _hint = '校正中：对 ${fmtMm(ref)}mm 的已知长度重复测 ≥2 次，然后点「完成校正」';
    });
  }

  /// 完成校正：用本组原始采样中位数求尺度系数并落库。
  Future<void> _finishCalib() async {
    final ref = double.tryParse(_calibRefCtl.text.trim()) ?? 0;
    if (ref <= 0) {
      AppSnack.show(context, '已知长度无效', kind: AppSnackKind.danger);
      return;
    }
    if (_samples.length < 2) {
      AppSnack.show(context, '请至少测 2 次再完成校正', kind: AppSnackKind.muted);
      return;
    }
    final c = ArScaleCalibration(
      refMm: ref,
      measuredMm: medianOf(_samples),
      samples: _samples.length,
      ts: DateTime.now().millisecondsSinceEpoch,
    );
    if (!c.isUsable) {
      AppSnack.show(
        context,
        '校正偏差 ${c.deltaPct.toStringAsFixed(1)}% 超出合理范围（>15%），'
        '多半是测错目标，请重测',
        kind: AppSnackKind.danger,
      );
      return;
    }
    await ArScaleCalibrationStore.save(c);
    if (!mounted) return;
    setState(() {
      _scaleCalib = c;
      _calibMode = false;
      _samples.clear();
      _hint = '校正完成：k=${c.k.toStringAsFixed(4)}，后续读数自动修正';
    });
    AppSnack.show(
      context,
      '已校正系统偏差：实测 ${fmtMm(c.measuredMm)}mm / 真值 ${fmtMm(c.refMm)}mm，'
      'k=${c.k.toStringAsFixed(4)}（${c.deltaPct >= 0 ? '+' : ''}${c.deltaPct.toStringAsFixed(2)}%）',
      kind: AppSnackKind.success,
    );
  }

  Future<void> _clearCalib() async {
    await ArScaleCalibrationStore.clear();
    if (!mounted) return;
    setState(() {
      _scaleCalib = null;
      _calibMode = false;
      _hint = '已清除尺度校正，读数将不做系统偏差修正';
    });
  }

  /// 批量保存：把已采纳的读数组全部写入会话（带误差带）。
  Future<void> _saveAll() async {
    if (_readings.isEmpty) {
      AppSnack.show(context, '暂无已采纳的测量结果', kind: AppSnackKind.danger);
      return;
    }
    final drawingMm = double.tryParse(_drawingCtl.text);
    var s =
        await MeasureStore.load(widget.args.projectKey, widget.args.drawingKey);
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

  /// AR 不可用时的占位页。
  ///
  /// 必须区分两种原因（此前混为一谈，导致 iPhone 14 Pro Max 被误报"机型不支持"）：
  /// - **Web**：浏览器拿不到 ARKit/LiDAR（是平台能力缺失，与机型无关）；
  /// - **原生但无 LiDAR**：才是真正的机型不支持。
  Widget _buildUnsupported() {
    const isWeb = kIsWeb;
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
          'AR量尺',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
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
              const Icon(MingCuteIcons.phoneLine,
                  size: 56, color: AppTokens.muted),
              const SizedBox(height: AppTokens.space3),
              Text(
                isWeb
                    ? '网页版不支持 AR 量尺（需装 App）'
                    : 'AR量尺（LiDAR）仅支持 iPhone 12 Pro 及以上机型',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppTokens.space2),
              Text(
                isWeb
                    ? 'AR 量尺依赖 iOS 原生 ARKit + LiDAR，浏览器无法调用——'
                        '这跟机型无关：iPhone 14 Pro Max 本身有 LiDAR，但网页里用不了。\n\n'
                        '网页版请继续用「拍照量尺」：AI 识别模数网格 → 透视校正 → 量取尺寸，'
                        '门窗洞口还能自动给出 M0921 这类编号。'
                    : '当前设备没有 LiDAR，请拍照后到照片量尺完成现场测量。',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppTokens.muted),
              ),
              const SizedBox(height: AppTokens.space4),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(MingCuteIcons.leftLine),
                label: const Text('返回拍照量尺继续'),
              ),
              const SizedBox(height: AppTokens.space2),
              TextButton.icon(
                onPressed: _captureForPhotoMeasure,
                icon: const Icon(MingCuteIcons.cameraLine),
                label: const Text('拍照并前往拍照记录'),
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
        centerTitle: true,
        leadingWidth: 36,
        leading: const Padding(
          padding: EdgeInsets.only(left: 12),
          child: NavIconButton(icon: MingCuteIcons.leftLine),
        ),
        title: const Text(
          'AR量尺（LiDAR）',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: AppCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppTokens.brandTint,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      MingCuteIcons.pencilRulerLine,
                      size: 18,
                      color: AppTokens.brand,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.args.floor.isNotEmpty
                              ? '${widget.args.floor} · AR量尺'
                              : 'AR实时量尺工作台',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            height: 22 / 14,
                            color: AppTokens.fg,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          '先在现场完成采点，再采纳本组结果，最后统一保存到当前图纸量尺记录',
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
            ),
          ),
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
                                  '本次 ${fmtMm(_corrected(_samples.last))} mm',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700),
                                ),
                                if (_samples.length >= 2)
                                  Text(
                                    '本组中位 ${fmtMm(_corrected(medianOf(_samples)))} mm'
                                    '（重复性 ±${fmtMm(spreadHalfRange(_samples) * _k)} mm，'
                                    'n=${_samples.length}）',
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 12),
                                  ),
                                if (_scaleCalib != null)
                                  Text(
                                    '已做系统偏差校正 k=${_scaleCalib!.k.toStringAsFixed(4)}'
                                    '（真值 ${fmtMm(_scaleCalib!.refMm)}mm / '
                                    '实测 ${fmtMm(_scaleCalib!.measuredMm)}mm）',
                                    style: const TextStyle(
                                        color: Colors.lightGreenAccent,
                                        fontSize: 11),
                                  ),
                                if (_depthHint != null)
                                  Text(
                                    _depthHint!,
                                    style: const TextStyle(
                                        color: Colors.orangeAccent,
                                        fontSize: 11),
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
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              children: [
                // 主按钮：校正模式 → 完成校正；常态 → 采纳本组
                SizedBox(
                  width: double.infinity,
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTokens.surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide.none,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _calibMode
                          ? (_supported && _samples.length >= 2
                              ? _finishCalib
                              : null)
                          : (_supported && _samples.length >= 2
                              ? _adoptSamples
                              : null),
                      icon: const Icon(MingCuteIcons.checkCircleLine, size: 18),
                      label: Text(
                        _calibMode
                            ? (_samples.length < 2
                                ? '完成校正（再测 ${2 - _samples.length} 次可启用）'
                                : '完成校正 → k=$_calibKPreview')
                            : (_samples.length < 2
                                ? '采纳本组（同边再测 ${2 - _samples.length} 次可启用）'
                                : '采纳本组 → ${fmtMm(_corrected(medianOf(_samples)))} mm'
                                    '（重复性 ±${fmtMm(spreadHalfRange(_samples) * _k)}）'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 22 / 14,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppTokens.space1),
                // 系统偏差校正：把「重复性」与「准确度」分开（±误差带只代表前者）
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _calibMode
                            ? '校正中：对 ${_calibRefCtl.text}mm 已知长度重复测 ≥2 次'
                            : (_scaleCalib == null
                                ? '未做系统偏差校正：± 仅为重复性，不代表准确度'
                                : '已校正 k=${_scaleCalib!.k.toStringAsFixed(4)}'
                                    '（${_scaleCalib!.deltaPct >= 0 ? '+' : ''}'
                                    '${_scaleCalib!.deltaPct.toStringAsFixed(2)}%）'),
                        style: TextStyle(
                          fontSize: 11,
                          color: _calibMode
                              ? Colors.blue
                              : (_scaleCalib == null
                                  ? AppTokens.muted
                                  : Colors.green),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _supported
                          ? (_calibMode ? _finishCalib : _startCalib)
                          : null,
                      child: Text(_calibMode ? '完成' : '系统偏差校正'),
                    ),
                    if (_scaleCalib != null && !_calibMode)
                      TextButton(
                        onPressed: _clearCalib,
                        child: const Text('清除'),
                      ),
                  ],
                ),
                const SizedBox(height: AppTokens.space2),
                Row(
                  children: [
                    Expanded(
                      child: _MeasureActionButton(
                        primary: true,
                        label: _paused ? '继续' : '暂停',
                        icon: _paused
                            ? MingCuteIcons.playLine
                            : MingCuteIcons.pauseLine,
                        onTap: _supported
                            ? () async {
                                _paused = !_paused;
                                await _svc.setMode(_paused ? 0 : 1);
                                setState(() {});
                              }
                            : null,
                      ),
                    ),
                    const SizedBox(width: AppTokens.space2),
                    Expanded(
                      child: _MeasureActionButton(
                        label: '清除',
                        icon: MingCuteIcons.deleteLine,
                        onTap: _supported
                            ? () async {
                                await _svc.clear();
                                setState(() {
                                  _samples.clear();
                                  _readings.clear();
                                  _hint = '对目标边采点：点一次=A，再点=B 出距离';
                                });
                              }
                            : null,
                      ),
                    ),
                    const SizedBox(width: AppTokens.space2),
                    Expanded(
                      child: _MeasureActionButton(
                        label: '保存',
                        icon: MingCuteIcons.saveLine,
                        onTap: _supported && _readings.isNotEmpty
                            ? _saveAll
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.space2),
                // 测量列表
                Container(
                  height: 180,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: AppTokens.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
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
                        title: Text('${fmtMm(r.mm)} mm（重复性 ±${fmtMm(r.errMm)}）',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
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

/// AR量尺页底部操作按钮：统一为 48 高度，一主两次，和当前 App 操作风格保持一致。
class _MeasureActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool primary;

  const _MeasureActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.5 : 1,
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: primary ? AppTokens.accent : AppTokens.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: primary ? AppTokens.onAccent : AppTokens.fg2,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 22 / 14,
                    color: primary ? AppTokens.onAccent : AppTokens.fg2,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
