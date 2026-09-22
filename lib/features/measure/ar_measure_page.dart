import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../shared/widgets/nav_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app_settings/app_settings.dart';

import '../../core/ar/ar_measure_service.dart';
import '../../core/di/providers.dart';
import '../../core/storage/ar_scale_calibration.dart';
import '../../core/storage/measure_store.dart';
import '../../core/storage/measure_threshold_store.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/models.dart';
import '../../core/utils/camera_pick.dart';
import '../../core/utils/ids.dart';
import '../../core/utils/measure_math.dart';
import '../../core/utils/measure_modes.dart';
import '../../core/utils/measure_style.dart';
import '../../core/utils/mm_format.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/app_snack.dart';
import 'widgets/area_volume_sheet.dart';

/// AR 量尺（LiDAR，iPhone 12 Pro+）。
///
/// 交互：进入即连续测量 → 单击采点A(蓝) → 再单击采点B(红)+连线 → 自动出距离 →
/// 保留上一组视觉，下次单击开新组；支持多点测量，可删除单条后批量保存到会话。
class ArMeasurePage extends ConsumerStatefulWidget {
  final MeasureArgs args;
  const ArMeasurePage({super.key, required this.args});

  @override
  ConsumerState<ArMeasurePage> createState() => _ArMeasurePageState();
}

class _ArMeasurePageState extends ConsumerState<ArMeasurePage> {
  static const _viewType = 'ar_measure_view';
  static const _viewId = 0;

  late final ArMeasureService _svc;

  /// 同一被测边的重复采样（三值）：采纳时按当前模式取稳健中位为读数、
  /// 离散半宽为 ±误差带，并**剔除离群读数**（实拍常见：点到了后面的墙/柜子）。
  final List<({double slope, double horizontal, double vertical})> _samples = [];

  /// 读数模式：斜边（默认）/ 水平 / 高差。
  ArMeasureMode _mode = ArMeasureMode.slope;

  /// 采纳一致性门槛（±mm）：稳健误差带超过它就拒绝采纳，提示重测。
  /// 30mm 是经验值——超过基本可判定"这几次点到的不是同一条边"。
  static const double _adoptMaxSpreadMm = 30;

  /// 当前模式下各样本的读数值。
  List<double> get _sampleValues => [for (final s in _samples) _valueOf(s)];

  double _valueOf(({double slope, double horizontal, double vertical}) s) {
    switch (_mode) {
      case ArMeasureMode.slope:
        return s.slope;
      case ArMeasureMode.horizontal:
        return s.horizontal;
      case ArMeasureMode.vertical:
        return s.vertical;
    }
  }

  /// 当前组的稳健统计（含离群剔除）。
  RobustStat get _stat => robustStats(_sampleValues);

  /// 已采纳的读数组（每组 = 中位值 + 误差带半宽），逐组写为一条 MeasureItem。
  final List<({double mm, double errMm})> _readings = [];

  /// 由已采纳读数组合出的**面积/体积**记录（unit = m2 / m3）。
  ///
  /// 单列一份：它们不是"一条边长"，混进 [_readings] 会让"读数 N"的序号与
  /// 中位数统计口径错乱；保存时与线性读数一起写入会话。
  final List<MeasureItem> _calcItems = [];

  /// Web 预览专用：点击窗口后记录 A/B 点与待采纳结果，方便浏览器里验收交互。
  Offset? _previewPointA;
  Offset? _previewPointB;
  ({double mm, double errMm})? _previewPendingReading;
  final List<({double mm, double errMm})> _previewReadings = [];
  bool _previewPaused = false;

  /// 最近一次**吸附**结果（原生真机 / Web 预览共用同一条提示口径）。
  ///
  /// 真机：ARKit raycast 命中平面/平面边界/特征点后由原生上报；
  /// Web：由 [snapToPreviewGuides] 对取景辅助线吸附。null = 未吸附。
  String? _snapHint;
  Offset? _previewSnapPoint;

  /// 最近一次面积/体积组合的因子（Web 预览按参考样式画出尺寸胶囊与面域）。
  List<MeasureItem> _lastCalcFactors = const [];

  // —— 几何模式（直线 / 面积 / 体积）：连续测量 + 自动成面/成体 ——
  /// 当前几何模式：直线模式每采纳一条边就是一条记录；
  /// 面积/体积模式**连续量 2/3 条边后自动生成**面积/体积（参考样张的做法）。
  ArGeometryMode _geoMode = ArGeometryMode.line;

  /// 面积模式的边累加器（长 → 宽）。
  final FaceBuilder _areaBuilder = FaceBuilder(isVolume: false);

  /// 体积模式的边累加器（长 → 宽 → 高）。
  final FaceBuilder _volumeBuilder = FaceBuilder(isVolume: true);

  FaceBuilder get _activeBuilder =>
      _geoMode.isVolume ? _volumeBuilder : _areaBuilder;

  /// 当前模式下"已量了几条边 / 共几条"。
  String get _geoProgress {
    if (!_geoMode.isFace) return '';
    return '${_geoMode.label}模式 ${_activeBuilder.got}/${_activeBuilder.need}：'
        '${_activeBuilder.progressText()}';
  }

  /// 最近一次产出的面积/体积项（决定图上画面域还是立方体）。
  ///
  /// 只认**最后一个**：否则先量面积再量体积时，面域与立方体会同时叠在图上
  /// （两者各自独立判空就会这样），观感与读数都会互相干扰。
  MeasureItem? get _lastCalcItem =>
      _calcItems.isEmpty ? null : _calcItems.last;

  /// 最近一次面积结果（m²）：仅当最后产出的是面积才返回，否则 null。
  double? get _lastCalcAreaM2 =>
      _lastCalcItem?.unit == 'm2' ? _lastCalcItem!.photoMm : null;

  /// 最近一次体积结果（m³）：仅当最后产出的是体积才返回，否则 null。
  double? get _lastCalcVolumeM3 =>
      _lastCalcItem?.unit == 'm3' ? _lastCalcItem!.photoMm : null;

  /// 最后一个产出项需要的因子条数（面积 2 / 体积 3 / 无 0）。
  int get _lastCalcNeeds {
    final last = _lastCalcItem;
    if (last == null) return 0;
    return last.unit == 'm3' ? 3 : 2;
  }

  bool _supported = false;
  bool _paused = false;
  String _hint = '对目标边采点：点一次=A，再点=B 出距离';
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

  /// 校正模式下按钮上的实时 k 预览（真值 / 当前采样**斜边**中位）。
  ///
  /// 校正用的是原始斜边长（系统偏差与显示模式无关），故这里不跟随 [_mode]。
  String get _calibKPreview {
    final ref = double.tryParse(_calibRefCtl.text.trim()) ?? 0;
    final m = medianOf([for (final s in _samples) s.slope]);
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
      // 三值拆分：原生同时上报两端世界坐标，可直接算水平投影与高度差。
      final ax = (args['ax'] as num?)?.toDouble();
      final ay = (args['ay'] as num?)?.toDouble();
      final az = (args['az'] as num?)?.toDouble();
      final bx = (args['bx'] as num?)?.toDouble();
      final by = (args['by'] as num?)?.toDouble();
      final bz = (args['bz'] as num?)?.toDouble();
      final parts = (ax != null &&
              ay != null &&
              az != null &&
              bx != null &&
              by != null &&
              bz != null)
          ? pythagorasParts(
              ax: ax, ay: ay, az: az, bx: bx, by: by, bz: bz)
          // 无坐标（旧原生）→ 退化为只有斜边可用
          : (slope: raw, horizontal: raw, vertical: 0.0);
      setState(() {
        // 采样保存**原始值**（校正模式要用原始斜边算 k），显示时才乘 k。
        _samples.add(parts);
        _lastDepthMm = depth;
        // B 点吸附结果（原生上报时）：命中物体边界/角点 → 提示已吸附。
        final snapB = args['snapB']?.toString();
        if (snapB != null) {
          _snapHint = snapLabel(
            snapB,
            edgeMm: (args['edgeMmB'] as num?)?.toDouble(),
          );
        }
        _hint = _calibMode
            ? '校正采样第 ${_samples.length} 次：对已知长度重复测，≥2 次后点「完成校正」'
            : '第 ${_samples.length} 次读数（${_mode.label} '
                '${fmtMm(_valueOf(parts))} mm）'
                '${_depthOk ? '' : '（当前超出最佳区间，误差偏大）'}，满意后点「采纳本组」';
      });
    } else if (call.method == 'onPointA') {
      // 原生可带上吸附结果（{snap, edgeMm}）：命中平面边界/角点时提示已吸附。
      final args = call.arguments;
      final snap = args is Map ? args['snap']?.toString() : null;
      if (mounted) {
        setState(() {
          _hint = '已采点A，请再点一次';
          _snapHint = snap == null
              ? null
              : snapLabel(
                  snap,
                  edgeMm: (args is Map ? args['edgeMm'] as num? : null)
                      ?.toDouble(),
                );
        });
      }
    } else if (call.method == 'onCleared') {
      if (mounted) {
        setState(() {
          _samples.clear();
          _lastDepthMm = null;
          _snapHint = null;
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
  /// 把一条已采纳的边喂给面积/体积累加器；满则生成面积/体积并提示。
  ///
  /// 返回 true 表示已生成面/体（调用方据此更新提示语）。
  bool _feedGeometry(MeasureItem edge) {
    if (!_geoMode.isFace) return false;
    final builder = _activeBuilder;
    final labels = edgeLabels(isVolume: _geoMode.isVolume);
    final produced = builder.add(edge);
    if (produced == null) {
      // 未满（或量级异常被丢弃）：给出"下一条量什么"的明确指引
      final idx = builder.got - 1;
      final gotLabel = idx >= 0 && idx < labels.length ? labels[idx] : '';
      AppSnack.show(
        context,
        builder.got == 0
            ? '${_geoMode.label}：这一段读数异常已丢弃，请重新量「${labels[0]}」'
            : '已采纳「$gotLabel」'
                '${(edge.photoMm / 1000).toStringAsFixed(3)}m'
                '（${builder.got}/${builder.need}）：'
                '继续量「${builder.currentLabel}」',
        kind: AppSnackKind.success,
      );
      return false;
    }
    setState(() {
      _calcItems.add(produced.item);
      _lastCalcFactors = produced.factors;
    });
    AppSnack.show(
      context,
      '已生成 ${produced.item.name}（可继续量下一个${_geoMode.label}）',
      kind: AppSnackKind.success,
    );
    return true;
  }

  void _adoptSamples() {
    if (_samples.length < 2) {
      AppSnack.show(context, '请对同一条边至少测 2 次再采纳', kind: AppSnackKind.muted);
      return;
    }
    final st = _stat;
    // 一致性门控：误差带超过门槛 = 这几次点到的不是同一条边 → 拒绝采纳。
    // 直接给一个"带 ±误差带"的错数，比不给数更危险（会被当判定依据）。
    if (!consistentEnough(st.spread, _adoptMaxSpreadMm)) {
      AppSnack.show(
        context,
        '读数不一致（稳健 ±${fmtMm(st.spread)}mm > ±${fmtMm(_adoptMaxSpreadMm)}mm）：'
        '多半是几次点到了不同的面（后墙/柜子/地脚线）。请对准同一条边重测，'
        '必要时放大后再点',
        kind: AppSnackKind.danger,
      );
      return;
    }
    final mm = _corrected(st.median);
    final errMm = st.spread * _k;
    final dropped = st.rejected;
    setState(() {
      _readings.add((mm: mm, errMm: errMm));
      _samples.clear();
      _hint = dropped > 0
          ? '已采纳一组（${_mode.label}，剔除 $dropped 个离群读数）；继续测下一条边'
          : '已采纳一组（${_mode.label}）；继续测下一条边，全部测完点「保存」';
    });
    // 面积/体积模式：连续量够边数就自动出面/成体（不打断连续测量）
    if (_geoMode.isFace) {
      _feedGeometry(MeasureItem(
        name: 'AR-${_readings.length}',
        drawingMm: double.tryParse(_drawingCtl.text) ?? 0,
        photoMm: mm,
        source: 'ar_lidar',
        errorMm: errMm,
      ));
    }
  }

  /// Web 预览采纳：只写入预览列表，不落真实存储，便于继续调 UI。
  void _adoptPreviewMeasurement() {
    final pending = _previewPendingReading;
    if (pending == null) return;
    setState(() {
      _previewReadings.insert(0, pending);
      _previewPointA = null;
      _previewPointB = null;
      _previewPendingReading = null;
    });
    if (_geoMode.isFace) {
      // 面/体模式：连续采纳即自动累加，够数出面/成体
      _feedGeometry(MeasureItem(
        name: 'AR-${_previewReadings.length}',
        drawingMm: 0,
        photoMm: pending.mm,
        source: 'ar_lidar',
        errorMm: pending.errMm,
      ));
      return;
    }
    AppSnack.show(
      context,
      '已采纳并自动保存到预览结果',
      kind: AppSnackKind.success,
    );
  }

  /// Web 预览清空：重置当前点位和已采纳的演示结果。
  void _clearPreviewSession() {
    setState(() {
      _previewPaused = false;
      _previewPointA = null;
      _previewPointB = null;
      _previewPendingReading = null;
      _previewReadings.clear();
      _previewSnapPoint = null;
      _snapHint = null;
      _calcItems.clear();
      _lastCalcFactors = const [];
    });
  }

  /// Web 预览点击窗口：第一次落 A 点，第二次落 B 点并生成模拟距离，第三次开始新一组。
  void _handlePreviewTap(TapUpDetails details, BoxConstraints constraints) {
    if (_previewPaused) return;
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    if (width <= 0 || height <= 0) return;
    final local = details.localPosition;
    // 吸附：靠近取景辅助线（井字格/中心）即被吸走——与真机"吸附物体边界"
    // 的交互与提示口径一致（真机由 ARKit raycast + 平面边界求最近点实现）。
    final snapped =
        snapToPreviewGuides(local, Size(width, height));
    final point = Offset(
      (snapped.point.dx / width).clamp(0.0, 1.0),
      (snapped.point.dy / height).clamp(0.0, 1.0),
    );
    setState(() {
      _previewSnapPoint = snapped.point;
      _snapHint = snapped.kind == null ? null : '已吸附：${snapped.kind}';
      if (_previewPointA == null || _previewPointB != null) {
        _previewPointA = point;
        _previewPointB = null;
        _previewPendingReading = null;
        return;
      }
      _previewPointB = point;
      final distance = (_previewPointA! - point).distance;
      // 用窗口相对距离生成稳定的演示值，让 Web 预览可以完整跑通 UI。
      final mm = (distance * 4200).clamp(180.0, 4200.0);
      final errMm = (8 + distance * 18).clamp(6.0, 28.0);
      _previewPendingReading = (mm: mm, errMm: errMm);
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
      measuredMm: medianOf([for (final s in _samples) s.slope]),
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

  /// 打开面积/体积弹层：用已采纳的读数作为候选边长（量尺宝式测量模式）。
  ///
  /// Web 预览模式用 [_previewReadings] 作候选，保证浏览器里也能完整走通并核对样式。
  Future<void> _openAreaVolume({bool isPreview = false}) async {
    final src = isPreview ? _previewReadings : _readings;
    final cands = [
      for (var i = 0; i < src.length; i++)
        MeasureItem(
          name: 'AR-${i + 1}',
          drawingMm: 0,
          photoMm: src[i].mm,
          source: 'ar_lidar',
          errorMm: src[i].errMm,
        ),
    ];
    final r = await showAreaVolumeSheet(context, candidates: cands);
    if (r == null || !mounted) return;
    setState(() {
      _calcItems.add(r.item);
      _lastCalcFactors = r.factors;
    });
    showCalcAddedSnack(context, r.item);
  }

  /// 吸附类型 → 用户可读文案（真机与 Web 预览共用）。
  static String snapLabel(String kind, {double? edgeMm}) {
    switch (kind) {
      case 'corner':
        return '已吸附：墙角/角点';
      case 'edge':
        return '已吸附：物体边界'
            '${edgeMm != null && edgeMm > 0 ? '（±${fmtMm(edgeMm)}mm）' : ''}';
      case 'plane':
        return '已吸附：平面';
      case 'feature':
        return '已吸附：特征点';
      default:
        return '已吸附：$kind';
    }
  }

  /// 批量保存：把已采纳的读数组 + 面积/体积项全部写入会话（带误差带）。
  Future<void> _saveAll() async {
    if (_readings.isEmpty && _calcItems.isEmpty) {
      AppSnack.show(context, '暂无已采纳的测量结果', kind: AppSnackKind.danger);
      return;
    }
    final drawingMm = double.tryParse(_drawingCtl.text);
    var s =
        await MeasureStore.load(widget.args.projectKey, widget.args.drawingKey);
    s ??= MeasureSession(
      id: newId(),
      projectKey: widget.args.projectKey,
      drawingKey: widget.args.drawingKey,
      // 绑定当前发布版本；若已存在会话，copyWith 会保留原版本。
      drawingVersionId: publishedVersionIdOf(ref, widget.args.drawingKey),
      floor: widget.args.floor,
      sync: SyncMeta.create(),
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
      // 面积/体积项一并落库（不带图纸对照，报告里显示为"未判定"）
      ..._calcItems,
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
        toolbarHeight: 48,
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
              const Text(
                isWeb
                    ? '网页版不支持 AR 量尺（需装 App）'
                    : 'AR量尺（LiDAR）仅支持 iPhone 12 Pro 及以上机型',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppTokens.space2),
              const Text(
                isWeb
                    ? 'AR 量尺依赖 iOS 原生 ARKit + LiDAR，浏览器无法调用——'
                        '这跟机型无关：iPhone 14 Pro Max 本身有 LiDAR，但网页里用不了。\n\n'
                        '网页版请继续用「拍照量尺」：AI 识别模数网格 → 透视校正 → 量取尺寸，'
                        '门窗洞口还能自动给出 M0921 这类编号。'
                    : '当前设备没有 LiDAR，请拍照后到照片量尺完成现场测量。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppTokens.muted),
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

  /// Web 端不执行真实 AR，但保留完整工作台结构，方便预览界面和交互布局。
  Widget _buildWebPreview() {
    return _buildWorkbenchScaffold(isPreview: true);
  }

  /// 统一的 AR 量尺外层工作台：Web 预览与真机共用同一套排版，只替换中间取景层和交互数据。
  Widget _buildWorkbenchScaffold({required bool isPreview}) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF000000),
        surfaceTintColor: const Color(0xFF000000),
        shadowColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        automaticallyImplyLeading: false,
        toolbarHeight: 48,
        centerTitle: true,
        leadingWidth: 36,
        leading: const Padding(
          padding: EdgeInsets.only(left: 12),
          child: NavIconButton(
            icon: MingCuteIcons.leftLine,
            color: Colors.white,
          ),
        ),
        title: Text(
          isPreview ? 'AR量尺（Web预览）' : 'AR量尺（LiDAR）',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: NavIconButton(
              icon: MingCuteIcons.settings3Line,
              color: Colors.white,
              onPressed: () => _openSettingsSheet(isPreview: isPreview),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Stack(
              children: [
                _buildViewportStack(isPreview: isPreview),
                Positioned(
                  top: AppTokens.space3,
                  left: AppTokens.space3,
                  right: AppTokens.space3,
                  child: _buildViewportOverlay(isPreview: isPreview),
                ),
              ],
            ),
            Expanded(
              child: _buildBottomWorkspace(isPreview: isPreview),
            ),
          ],
        ),
      ),
    );
  }

  /// 中间取景区：保留同一层级结构，Web 用预览画面替换原生相机层。
  Widget _buildViewportStack({required bool isPreview}) {
    return Container(
      color: const Color(0xFF0A0A0A),
      child: Align(
        alignment: Alignment.topCenter,
        child: AspectRatio(
          // 相机常用 4:3 画幅；竖屏下按 3:4 呈现，避免取景区被拉成长条。
          aspectRatio: 3 / 4,
          child: isPreview ? _buildPreviewViewport() : _buildNativeViewport(),
        ),
      ),
    );
  }

  /// Web 预览版取景层：用固定导视和暗色背景模拟真实 AR 取景窗，方便核对 UI。
  Widget _buildPreviewViewport() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => _handlePreviewTap(details, constraints),
          child: Container(
            color: const Color(0xFFD9D9D9),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ArPreviewGuidePainter(
                      pointA: _previewPointA,
                      pointB: _previewPointB,
                      pendingReading: _previewPendingReading,
                      snapPoint: _previewSnapPoint,
                      snapLabelText: _snapHint,
                      areaM2: _lastCalcAreaM2,
                      volumeM3: _lastCalcVolumeM3,
                      // 因子必须与"最后一个产出项"匹配：条数不符就不画
                      // （例如用户删掉了清单里的项，避免用旧因子画出错几何）
                      calcFactorsMm: _lastCalcFactors.length == _lastCalcNeeds
                          ? [for (final f in _lastCalcFactors) f.photoMm]
                          : const <double>[],
                      // 面/体模式：把已量到的边长与进度画出来（连续测量的关键反馈）
                      pendingEdgeMm: _geoMode.isFace &&
                              _activeBuilder.edges.isNotEmpty
                          ? _activeBuilder.edges.last.photoMm
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 真机取景层：保留原生 LiDAR 视图和设备检测占位。
  Widget _buildNativeViewport() {
    return Stack(
      children: [
        const Positioned.fill(
          child: ColoredBox(color: Color(0xFF0A0A0A)),
        ),
        UiKitView(
          viewType: _viewType,
          onPlatformViewCreated: _onViewCreated,
          creationParams: null,
          creationParamsCodec: const StandardMessageCodec(),
        ),
        if (!_supported) _buildLiDARPlaceholder(),
      ],
    );
  }

  /// 顶部浮层：提示条和测量摘要卡统一由这一处输出，保证两端位置与间距一致。
  Widget _buildViewportOverlay({required bool isPreview}) {
    if (isPreview) {
      return const SizedBox.shrink();
    }
    final showSummary = _samples.isNotEmpty;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            isPreview ? 'Web 预览模式：展示 AR量尺工作台布局' : _hint,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
        if (showSummary) ...[
          const SizedBox(height: AppTokens.space2),
          _buildViewportSummaryCard(isPreview: isPreview),
        ],
      ],
    );
  }

  /// 测量摘要卡：保持同一位置和样式，Web 仅替换展示数据。
  Widget _buildViewportSummaryCard({required bool isPreview}) {
    final st = _stat;
    final currentText = isPreview
        ? '本次 2980 mm'
        : '本次 ${fmtMm(_corrected(_valueOf(_samples.last)))} mm';
    final groupText = isPreview
        ? '本组中位 2980 mm（重复性 ±8 mm，n=3）'
        : (_samples.length >= 2
            ? '本组中位 ${fmtMm(_corrected(st.median))} mm'
                '（重复性 ±${fmtMm(st.spread * _k)} mm，'
                'n=${st.used}${st.rejected > 0 ? '，已剔除 ${st.rejected} 个离群' : ''}）'
            : null);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xCC111111),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              currentText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (groupText != null)
              Text(
                groupText,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            if (!isPreview && _scaleCalib != null)
              Text(
                '已做系统偏差校正 k=${_scaleCalib!.k.toStringAsFixed(4)}'
                '（真值 ${fmtMm(_scaleCalib!.refMm)}mm / '
                '实测 ${fmtMm(_scaleCalib!.measuredMm)}mm）',
                style: const TextStyle(
                  color: Colors.lightGreenAccent,
                  fontSize: 11,
                ),
              ),
            if (!isPreview && _depthHint != null)
              Text(
                _depthHint!,
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 11,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 底部工作区：直接承接窗口下方空白，不再做悬浮卡片。
  Widget _buildBottomWorkspace({required bool isPreview}) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      width: double.infinity,
      color: const Color(0xFF000000),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + safeBottom),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: _buildBottomPanel(isPreview: isPreview),
      ),
    );
  }

  /// 底部操作区：主按钮、状态说明、辅助按钮、列表和字段区统一复用。
  Widget _buildBottomPanel({required bool isPreview}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 几何模式：直线 / 面积 / 体积（面积体积模式为**连续测量**，够边数自动出面/成体）
        _buildGeometryModeSelector(),
        // 勾股三值模式：决定采纳哪一个读数（斜边/水平/高差）
        if (!isPreview) _buildModeSelector(),
        if (!isPreview && _samples.isNotEmpty) _buildSampleList(),
        // 面积/体积：**直线模式**下提供手动组合入口；
        // 面积/体积模式下改为连续测量自动生成（见 _feedGeometry），不再需要手动选边。
        if (_geoMode == ArGeometryMode.line &&
            (isPreview ? _previewReadings.isNotEmpty : _readings.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _openAreaVolume(isPreview: isPreview),
                icon: const Icon(MingCuteIcons.cubeLine, size: 18),
                label: const Text('手动组合面积 / 体积（选已测边长）'),
              ),
            ),
          ),
        if (!isPreview && _calcItems.isNotEmpty) _buildCalcList(),
        SizedBox(
          width: double.infinity,
          child: _buildPrimaryActionButton(isPreview: isPreview),
        ),
        const SizedBox(height: 8),
        _buildActionButtonsRow(isPreview: isPreview),
      ],
    );
  }

  /// 读数模式选择（勾股三值）：斜边 / 水平 / 高差。
  ///
  /// 现场对应关系：量层高或洞口高 → 高差；量开间/进深 → 水平；量对角线 → 斜边。
  /// 几何模式选择：直线 / 面积 / 体积（+ 当前进度）。
  ///
  /// 面/体模式下"采纳本组"会把读数作为 长/宽[/高] 累加，够数即自动生成，
  /// 中途不需要再进弹层挑边——这是参考样张的连续测量做法。
  Widget _buildGeometryModeSelector() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < ArGeometryMode.values.length; i++) ...[
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _geoMode = ArGeometryMode.values[i];
                      // 切模式清空半成品，避免把"长"当"宽"用
                      _areaBuilder.reset();
                      _volumeBuilder.reset();
                    }),
                    child: Container(
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _geoMode == ArGeometryMode.values[i]
                            ? kMeasureYellow
                            : Colors.white12,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        ArGeometryMode.values[i].label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: _geoMode == ArGeometryMode.values[i]
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: _geoMode == ArGeometryMode.values[i]
                              ? kMeasureInk
                              : Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ),
                if (i != ArGeometryMode.values.length - 1)
                  const SizedBox(width: 8),
              ],
            ],
          ),
          if (_geoMode.isFace) ...[
            const SizedBox(height: 6),
            Text(
              '$_geoProgress（量够 ${_geoMode.edgeCount} 条边自动生成'
              '${_geoMode.label}）',
              style: const TextStyle(fontSize: 11, color: Colors.white60),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          for (var i = 0; i < ArMeasureMode.values.length; i++) ...[
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _mode = ArMeasureMode.values[i]),
                child: Container(
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _mode == ArMeasureMode.values[i]
                        ? AppTokens.accent
                        : Colors.white12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    ArMeasureMode.values[i].label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: _mode == ArMeasureMode.values[i]
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: _mode == ArMeasureMode.values[i]
                          ? AppTokens.onAccent
                          : Colors.white70,
                    ),
                  ),
                ),
              ),
            ),
            if (i != ArMeasureMode.values.length - 1)
              const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  /// 面积/体积结果列表（明确标注"不参与合格判定"，避免被当尺寸看）。
  Widget _buildCalcList() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('面积/体积（不参与合格判定）',
              style: TextStyle(color: Colors.white70, fontSize: 11)),
          for (var i = 0; i < _calcItems.length; i++)
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_calcItems[i].name}'
                    '${_calcItems[i].errorMm != null ? '  ±${_calcItems[i].errorMm!.toStringAsFixed(2)}' : ''}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                InkWell(
                  onTap: () => setState(() {
                    _calcItems.removeAt(i);
                    // 因子与已删项不再对应 → 清掉，避免图上用过时因子画出错几何
                    _lastCalcFactors = const [];
                  }),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text('删',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// 样本明细：逐条列出（离群点标黄提示"将被剔除"），并支持单条删除。
  ///
  /// 实测痛点：一次点到后面的墙/柜子会让整组"误差带"爆到几百毫米。
  /// 让用户看见每次读数并手动删掉明显错误的那次，比只给一个中位数有用。
  Widget _buildSampleList() {
    final values = _sampleValues;
    final dropped = outlierIndexes(values);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '本组 ${_samples.length} 次读数（${_mode.label}）'
            '${dropped.isEmpty ? '' : ' · 标记 ${dropped.length} 个离群（采纳时自动剔除）'}',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          for (var i = 0; i < _samples.length; i++)
            Row(
              children: [
                Expanded(
                  child: Text(
                    '第 ${i + 1} 次：'
                    '${fmtMm(_corrected(values[i]))} mm'
                    '${dropped.contains(i) ? '   ← 离群' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: dropped.contains(i)
                          ? Colors.orangeAccent
                          : Colors.white,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => _samples.removeAt(i)),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text('删',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// 主按钮文案统一走一处，避免 Web 和真机的按钮高度、字重、图标错位。
  Widget _buildPrimaryActionButton({required bool isPreview}) {
    final enabled = isPreview
        ? _previewPendingReading != null
        : (_calibMode
            ? (_supported && _samples.length >= 2)
            : (_supported && _samples.length >= 2));
    // 面/体模式：按钮带上"这是第几条边"，让连续测量有明确节奏
    final faceTag = _geoMode.isFace
        ? '［${_activeBuilder.currentLabel} ${_activeBuilder.got + 1}/'
            '${_activeBuilder.need}］'
        : '';
    final label = isPreview
        ? (_previewPendingReading == null
            ? (_geoMode.isFace
                ? '点两点量「${_activeBuilder.currentLabel}」'
                : '点击窗口选择 A 点和 B 点')
            : '采纳本组$faceTag → ${fmtMm(_previewPendingReading!.mm)} mm'
                '（重复性 ±${fmtMm(_previewPendingReading!.errMm)}）')
        : (_calibMode
            ? (_samples.length < 2
                ? '完成校正（再测 ${2 - _samples.length} 次可启用）'
                : '完成校正 → k=$_calibKPreview')
            : (_samples.length < 2
                ? '采纳本组（同边再测 ${2 - _samples.length} 次可启用）'
                : '采纳本组$faceTag → ${fmtMm(_corrected(_stat.median))} mm'
                    '（${_mode.label}，重复性 ±${fmtMm(_stat.spread * _k)}）'));
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: AppTokens.accent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTokens.onAccent,
            side: BorderSide.none,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: isPreview
              ? (_previewPendingReading != null
                  ? _adoptPreviewMeasurement
                  : null)
              : (_calibMode
                  ? (_supported && _samples.length >= 2 ? _finishCalib : null)
                  : (_supported && _samples.length >= 2
                      ? _adoptSamples
                      : null)),
          icon: const Icon(
            MingCuteIcons.checkCircleLine,
            size: 18,
            color: AppTokens.onAccent,
          ),
          label: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 22 / 14,
              color: AppTokens.onAccent,
            ),
          ),
        ),
      ),
    );
  }

  /// 底部辅助按钮区：暂停、清除、查看数据共用同一行结构。
  Widget _buildActionButtonsRow({required bool isPreview}) {
    if (isPreview) {
      return Row(
        children: [
          Expanded(
            child: _MeasureActionButton(
              label: _previewPaused ? '继续' : '暂停',
              icon: _previewPaused
                  ? MingCuteIcons.playLine
                  : MingCuteIcons.pauseLine,
              onTap: () {
                setState(() => _previewPaused = !_previewPaused);
              },
            ),
          ),
          const SizedBox(width: AppTokens.space2),
          Expanded(
            child: _MeasureActionButton(
              label: '清除',
              icon: MingCuteIcons.deleteLine,
              onTap: _clearPreviewSession,
            ),
          ),
          const SizedBox(width: AppTokens.space2),
          Expanded(
            child: _MeasureActionButton(
              label: '查看数据',
              icon: MingCuteIcons.eyeLine,
              onTap: () => _openDataSheet(isPreview: true),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: _MeasureActionButton(
            label: _paused ? '继续' : '暂停',
            icon: _paused ? MingCuteIcons.playLine : MingCuteIcons.pauseLine,
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
            label: '查看数据',
            icon: MingCuteIcons.eyeLine,
            onTap: () => _openDataSheet(isPreview: false),
          ),
        ),
      ],
    );
  }

  /// 测量列表容器统一复用，Web 用示例数据灌入，真机继续用实时读数。
  Widget _buildReadingListPanel({required bool isPreview}) {
    return Container(
      height: 180,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(8),
      ),
      child: () {
        final previewReadings = _previewReadings;
        final realReadings = _readings;
        final itemCount =
            isPreview ? previewReadings.length : realReadings.length;
        if (itemCount == 0) {
          return Center(
            child: Text(
              isPreview ? '先在窗口里点 A 点和 B 点，再点“采纳本组”' : '采纳后的量尺结果会显示在这里',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                height: 20 / 13,
                color: Color(0xFF8F9399),
              ),
            ),
          );
        }
        return ListView.builder(
          itemCount: itemCount,
          itemBuilder: (ctx, i) {
            final mm = isPreview ? previewReadings[i].mm : realReadings[i].mm;
            final errMm =
                isPreview ? previewReadings[i].errMm : realReadings[i].errMm;
            final titleText = '${fmtMm(mm)} mm（重复性 ±${fmtMm(errMm)}）';
            final verdictText = isPreview ? null : _verdictOf(mm, errMm);
            final verdictColor = verdictText == null
                ? null
                : verdictText.contains('合格')
                    ? Colors.green
                    : verdictText.contains('超差')
                        ? AppTokens.danger
                        : Colors.orange;
            return ListTile(
              dense: true,
              tileColor: Colors.transparent,
              contentPadding: EdgeInsets.zero,
              leading: Text(
                'AR-${i + 1}.',
                style: const TextStyle(color: Color(0xFF8F9399)),
              ),
              title: Text(
                titleText,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              subtitle: verdictText == null
                  ? null
                  : Text(
                      verdictText,
                      style: TextStyle(fontSize: 12, color: verdictColor),
                    ),
              trailing: IconButton(
                icon: const Icon(
                  MingCuteIcons.minusCircleLine,
                  size: 20,
                  color: AppTokens.danger,
                ),
                onPressed: () {
                  setState(() {
                    if (isPreview) {
                      _previewReadings.removeAt(i);
                    } else {
                      _readings.removeAt(i);
                    }
                  });
                },
              ),
            );
          },
        );
      }(),
    );
  }

  /// 偏差校正和图纸尺寸统一放进深色底部弹窗，主界面只保留核心量尺操作。
  Future<void> _openSettingsSheet({required bool isPreview}) {
    return _showDarkBottomSheet<void>(
      title: '量尺设置',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isPreview
                ? '这里集中放偏差校正和图纸尺寸，主界面不再展示这些设置项。'
                : (_calibMode
                    ? '当前正在做系统偏差校正，请对已知长度重复测量至少 2 次，再完成校正。'
                    : (_scaleCalib == null
                        ? '当前未做系统偏差校正，测量结果的 ± 只代表重复性。'
                        : '当前已校正 k=${_scaleCalib!.k.toStringAsFixed(4)}'
                            '（${_scaleCalib!.deltaPct >= 0 ? '+' : ''}'
                            '${_scaleCalib!.deltaPct.toStringAsFixed(2)}%）')),
            style: _darkSheetHelperStyle(),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '系统偏差校正',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 22 / 14,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isPreview
                      ? 'Web 端只展示设置结构，不会触发真实校正。'
                      : '用已知长度做重复测量，校正系统偏差后，后续读数会自动修正。',
                  style: _darkSheetHelperStyle(const Color(0xFF9EA3AA)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _DarkSheetActionButton(
                        label: _calibMode ? '完成校正' : '开始校正',
                        onPressed: isPreview
                            ? null
                            : () {
                                Navigator.of(context, rootNavigator: true)
                                    .pop();
                                if (_calibMode) {
                                  _finishCalib();
                                } else {
                                  _startCalib();
                                }
                              },
                      ),
                    ),
                    if (!isPreview && _scaleCalib != null && !_calibMode) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DarkSheetActionButton(
                          label: '清除校正',
                          foregroundColor: const Color(0xFFFF7A7A),
                          backgroundColor: const Color(0xFF262629),
                          onPressed: () {
                            Navigator.of(context, rootNavigator: true).pop();
                            _clearCalib();
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '图纸尺寸',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 22 / 14,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '选填。填写后会在保存量尺记录时一并带上，方便后续对比。',
                  style: _darkSheetHelperStyle(const Color(0xFF9EA3AA)),
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: _darkSheetInputBoxDecoration(),
                  child: TextField(
                    controller: _drawingCtl,
                    enabled: !isPreview,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: _darkSheetInputTextStyle,
                    decoration:
                        _darkSheetInputDecoration(hintText: '输入图纸尺寸(mm，可选)'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 量尺数据走独立深色底部弹窗，主界面只保留操作按钮。
  Future<void> _openDataSheet({required bool isPreview}) {
    final count = isPreview ? _previewReadings.length : _readings.length;
    return _showDarkBottomSheet<void>(
      title: '量尺数据',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isPreview
                ? '当前共有 $count 组预览数据，采纳后会直接写入下面的列表。'
                : (count == 0
                    ? '当前还没有采纳的量尺数据。'
                    : '当前共有 $count 组已采纳数据，可在这里查看后再保存。'),
            style: _darkSheetHelperStyle(),
          ),
          const SizedBox(height: 12),
          _buildReadingListPanel(isPreview: isPreview),
          if (!isPreview) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: _DarkSheetActionButton(
                label: '保存量尺数据',
                onPressed: count > 0
                    ? () {
                        Navigator.of(context, rootNavigator: true).pop();
                        _saveAll();
                      }
                    : null,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 深色底部弹窗：保持黑色工作台风格统一，避免白色弹窗跳出来。
  Future<T?> _showDarkBottomSheet<T>({
    required String title,
    required Widget child,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x99000000),
      builder: (sheetContext) {
        final media = MediaQuery.of(sheetContext);
        final bottomSafeInset = media.padding.bottom;
        final keyboardInset = media.viewInsets.bottom;
        final maxSheetHeight = media.size.height - media.padding.top - 24;
        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: keyboardInset),
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottomSafeInset),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxSheetHeight),
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF121214),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DarkSheetHeader(title: title),
                    Flexible(
                      fit: FlexFit.loose,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        child: child,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
      '/capture/photo',
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
    if (kIsWeb) {
      // Web 端提供界面预览，方便验收 UI；真实 AR 仍需在 App 内运行。
      return _buildWebPreview();
    }
    if (!Platform.isIOS) {
      // 非 iOS：LiDAR 不可用，直接提示，不提供假估算。
      return _buildUnsupported();
    }
    return _buildWorkbenchScaffold(isPreview: false);
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

/// Web 预览的叠加层：**按参考样式绘制**（明黄尺寸线 + 空心方块端点 + 胶囊标注），
/// 并复现吸附提示、面积面域与体积线框三种标注形态，方便浏览器里核对观感。
///
/// 说明：这里的几何是"示意"（取景辅助线 + 点击点），数值来自真实读数/组合结果；
/// 真机上的线、端点、标注由原生 `ArMeasureView.swift` 按同一套样式绘制。
class _ArPreviewGuidePainter extends CustomPainter {
  final Offset? pointA;
  final Offset? pointB;
  final ({double mm, double errMm})? pendingReading;
  final Offset? snapPoint;
  final String? snapLabelText;
  /// 最近一次面积（m²）/体积（m³）结果；null = 无。
  final double? areaM2;
  final double? volumeM3;
  /// 面积/体积的因子边长（mm），用于画边缘尺寸胶囊。
  final List<double> calcFactorsMm;
  /// 面/体模式**已量到的最后一条边**（mm）：画成一条已确认的尺寸线。
  final double? pendingEdgeMm;

  _ArPreviewGuidePainter({
    this.pointA,
    this.pointB,
    this.pendingReading,
    this.snapPoint,
    this.snapLabelText,
    this.areaM2,
    this.volumeM3,
    this.calcFactorsMm = const [],
    this.pendingEdgeMm,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 取景辅助线（浅灰）——吸附的"素材"，靠近即被吸走。
    final gridPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    final thirdWidth = size.width / 3;
    final thirdHeight = size.height / 3;
    for (var i = 1; i <= 2; i++) {
      canvas.drawLine(Offset(thirdWidth * i, 0),
          Offset(thirdWidth * i, size.height), gridPaint);
      canvas.drawLine(Offset(0, thirdHeight * i),
          Offset(size.width, thirdHeight * i), gridPaint);
    }
    // 准星（中心十字，暗色）——不抢黄线的视觉焦点。
    final center = size.center(Offset.zero);
    final cross = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..strokeWidth = 1.4;
    canvas.drawLine(Offset(center.dx - 22, center.dy),
        Offset(center.dx + 22, center.dy), cross);
    canvas.drawLine(Offset(center.dx, center.dy - 22),
        Offset(center.dx, center.dy + 22), cross);

    final a = pointA == null
        ? null
        : Offset(pointA!.dx * size.width, pointA!.dy * size.height);
    final b = pointB == null
        ? null
        : Offset(pointB!.dx * size.width, pointB!.dy * size.height);

    // —— 面积：半透明黄面域 + 对角线虚线 + 边尺寸胶囊 + 中央大字 ——
    // 几何按**真实长宽比例**合成（预览无 AR 空间坐标，比例仍来自实测读数）
    if (areaM2 != null && calcFactorsMm.length >= 2) {
      final r = synthFaceRect(size, calcFactorsMm[0], calcFactorsMm[1]);
      final poly = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
      paintAreaFace(canvas, poly, fmtAreaText(areaM2!));
      // 长在下边、宽在左边（竖排），与参考样张一致
      paintCapsuleLabel(
        canvas,
        Offset(r.center.dx, r.bottom + 4),
        fmtLengthText(calcFactorsMm[0]),
      );
      paintCapsuleLabel(
        canvas,
        Offset(r.left - 4, r.center.dy),
        fmtLengthText(calcFactorsMm[1]),
        vertical: true,
      );
    }

    // —— 体积：黄立方体线框（可见边实线/隐藏边虚线）+ 三边胶囊 + 中央大字 ——
    if (volumeM3 != null && calcFactorsMm.length >= 3) {
      final g = synthVolumeGeometry(
        size,
        calcFactorsMm[0],
        calcFactorsMm[1],
        calcFactorsMm[2],
      );
      if (g.base.length == 4) {
        paintVolumeWire(
          canvas,
          g.base,
          g.rise,
          hLabel: fmtLengthText(calcFactorsMm[2]),
          centerText: fmtVolumeText(volumeM3!),
        );
        // 长（近底边）、宽（右侧边）标注
        paintCapsuleLabel(
          canvas,
          Offset((g.base[0].dx + g.base[1].dx) / 2, g.base[0].dy + 16),
          fmtLengthText(calcFactorsMm[0]),
        );
        paintCapsuleLabel(
          canvas,
          Offset((g.base[1].dx + g.base[2].dx) / 2, (g.base[1].dy + g.base[2].dy) / 2),
          fmtLengthText(calcFactorsMm[1]),
          fontSize: 11,
        );
      }
    }

    // —— 尺寸线（参考样式：黄线 + 空心方块端点 + 胶囊）——
    if (areaM2 == null && volumeM3 == null) {
      // 面/体模式：已量到的边长画成一条尺寸线（表示"这一段已确认"）
      if (pendingEdgeMm != null) {
        final y = size.height * 0.62;
        paintDimLine(
          canvas,
          Offset(size.width * 0.16, y),
          Offset(size.width * 0.84, y),
          fmtLengthText(pendingEdgeMm!),
        );
      } else if (a != null && b != null) {
        final vertical = (b.dy - a.dy).abs() > (b.dx - a.dx).abs() * 2;
        paintDimLine(
          canvas,
          a,
          b,
          pendingReading == null ? '' : fmtLengthText(pendingReading!.mm),
          vertical: vertical,
        );
      } else if (a != null) {
        // 只有 A 点：画一个空心方块标记起点（不带 A/B 字母，与参考一致）
        paintDimLine(canvas, a, a, '', lineWidth: 1);
      }
    }
    // 面/体进度只留在底部面板文案里，图上不再叠加进度胶囊——
    // 否则与尺寸胶囊互相遮挡（参考样张的画布上也只有几何与尺寸标注）。

    // —— 吸附提示：吸附点画实心黄方块 + 下方胶囊文案 ——
    if (snapPoint != null) {
      canvas.drawRect(
        Rect.fromCenter(center: snapPoint!, width: 9, height: 9),
        Paint()..color = kMeasureYellow,
      );
      if (snapLabelText != null) {
        paintCapsuleLabel(
          canvas,
          Offset(snapPoint!.dx + 60, snapPoint!.dy + 22),
          snapLabelText!,
          fontSize: 11,
          accent: kMeasureYellow,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ArPreviewGuidePainter oldDelegate) =>
      oldDelegate.pointA != pointA ||
      oldDelegate.pointB != pointB ||
      oldDelegate.pendingReading != pendingReading ||
      oldDelegate.snapPoint != snapPoint ||
      oldDelegate.snapLabelText != snapLabelText ||
      oldDelegate.areaM2 != areaM2 ||
      oldDelegate.volumeM3 != volumeM3 ||
      oldDelegate.calcFactorsMm != calcFactorsMm ||
      oldDelegate.pendingEdgeMm != pendingEdgeMm;
}

/// AR量尺页底部操作按钮：统一为 48 高度，一主两次，和当前 App 操作风格保持一致。
class _MeasureActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const _MeasureActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.5 : 1,
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF151515),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: AppTokens.heightCalibrated,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// 深色底部弹窗的辅助说明文字样式。
TextStyle _darkSheetHelperStyle([Color color = const Color(0xFFB8BBC0)]) =>
    TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 22 / 14,
      color: color,
    );

/// 深色底部弹窗输入框正文样式。
const TextStyle _darkSheetInputTextStyle = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w400,
  height: 22 / 14,
  color: Colors.white,
);

/// 深色底部弹窗输入框外层：只保留输入框描边，符合当前页面规范。
BoxDecoration _darkSheetInputBoxDecoration() => BoxDecoration(
      color: const Color(0xFF1C1C1E),
      border: Border.all(color: const Color(0xFF3A3A3C)),
      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
    );

/// 深色底部弹窗输入框内部占位样式。
InputDecoration _darkSheetInputDecoration({required String hintText}) =>
    InputDecoration(
      isCollapsed: true,
      border: InputBorder.none,
      hintText: hintText,
      hintStyle: _darkSheetHelperStyle(const Color(0xFF6E737A)),
    );

/// 深色底部弹窗头部：标题居中，关闭按钮放在右侧。
class _DarkSheetHeader extends StatelessWidget {
  final String title;

  const _DarkSheetHeader({required this.title});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 24 / 16,
                color: Colors.white,
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: NavIconButton(
                icon: MingCuteIcons.closeMediumLine,
                color: Colors.white70,
                onPressed: () =>
                    Navigator.of(context, rootNavigator: true).pop(),
              ),
            ),
          ],
        ),
      );
}

/// 深色底部弹窗按钮：统一用 8 圆角，避免弹窗里出现浅色按钮样式。
class _DarkSheetActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color foregroundColor;

  const _DarkSheetActionButton({
    required this.label,
    required this.onPressed,
    this.backgroundColor = AppTokens.accent,
    this.foregroundColor = AppTokens.onAccent,
  });

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onPressed == null ? 0.5 : 1,
        child: SizedBox(
          height: 44,
          child: FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: backgroundColor,
              foregroundColor: foregroundColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 22 / 14,
              ),
            ),
          ),
        ),
      );
}
