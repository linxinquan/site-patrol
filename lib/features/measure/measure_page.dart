import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../shared/widgets/nav_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_settings/app_settings.dart';

import '../../core/cad/cad_calibration.dart';
import '../../core/di/providers.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/storage/local_storage.dart';
import '../../core/storage/measure_store.dart';
import '../../core/utils/cad_coord.dart';
import '../../core/utils/camera_pick.dart';
import '../../core/utils/homography.dart';
import '../../core/utils/measure_math.dart';
import '../../core/utils/mm_format.dart';
import '../../core/utils/anchor_objects.dart';
import '../../data/models.dart';
import '../../data/vision_service.dart';
import '../../shared/widgets/drawing_image.dart';
import '../../shared/widgets/app_snack.dart';
import 'ar_measure_page.dart';

/// 拍照量尺校对页（半自动标定测量，MEASURE_FEATURE_PLAN.md）。
///
/// 流程：
///  ① 图纸侧量距：在 CAD 校准后的图纸上点两点 → 世界坐标(mm) 距离 = 图纸尺寸。
///  ② 照片侧量距：拍/选照片 → 用已知尺寸参考物（卷尺/标准块）标定比例 →
///     在照片上点两点 → 像素距离 × 比例 = 实测尺寸。
///  ③ 校对清单：逐项对比 图纸 mm vs 照片实测 mm，双容差判定合格/超差。
///  ④ 持久化：按 项目+图纸 唯一会话存入 LocalStorage。
class MeasurePage extends ConsumerStatefulWidget {
  final MeasureArgs args;
  const MeasurePage({super.key, required this.args});

  @override
  ConsumerState<MeasurePage> createState() => _MeasurePageState();
}

class _MeasurePageState extends ConsumerState<MeasurePage> {
  // —— 图纸侧 ——
  CadCoordMapper? _mapper;
  Size? _imageSize; // 整图渲染像素尺寸（w,h）
  bool _calibLoading = true;
  final List<Offset> _drawPicks = []; // 图纸侧两点（整图像素坐标）

  // —— 照片侧 ——
  Uint8List? _photoBytes;
  Size? _photoSize;
  final List<Offset> _photoPicks = []; // 照片侧像素坐标
  final List<Offset> _refPicks = []; // 参考物两点（照片像素）

  // —— 模数网格单应标定（透视校正，替代两点比例法）——
  /// 是否处于「网格标定」点选状态。
  bool _gridMode = false;
  /// 已点选的网格交点（照片像素，行优先：从左到右、从上到下）。
  final List<Offset> _gridPicks = [];
  final TextEditingController _gridMmCtl = TextEditingController(text: '600');
  final TextEditingController _gridColsCtl = TextEditingController(text: '3');
  final TextEditingController _gridRowsCtl = TextEditingController(text: '3');

  // —— AI 网格识别（自动标定主路径：零输入，人工只做确认）——
  /// AI 识别到的网格（待确认 / 已确认都用它画绿色叠加层）。
  GridDetection? _aiGrid;
  /// 是否已人工确认并写入标定（true 后叠加层转为浅绿、可开始量尺）。
  bool _aiGridConfirmed = false;
  bool _aiGridBusy = false;
  String? _aiGridMsg;

  // —— 会话 ——
  MeasureSession? _session;
  final TextEditingController _nameCtl = TextEditingController(text: '梁宽');
  final TextEditingController _tolMmCtl = TextEditingController(text: '15');
  final TextEditingController _tolPctCtl = TextEditingController(text: '2');
  final TextEditingController _refMmCtl = TextEditingController(text: '1000');
  /// P1-1：图纸尺寸手填（图纸未校准时降级使用；已校准时可覆盖量得值）。
  final TextEditingController _drawingMmCtl = TextEditingController();

  // —— 自动标定（锚物识别，零输入主路径）——
  bool _autoCalibBusy = false;
  String? _autoCalibMsg; // 最近一次自动标定结果说明（null=无）
  bool _autoTried = false; // 当前照片是否已自动尝试过（避免重复调远端）
  bool _netOffline = false; // 联网预检失败（地下室/无信号）→ 引导手动标定

  // —— 缩放 ——
  final _drawingTransform = TransformationController();
  final _photoTransform = TransformationController();

  String get _drawingKey => widget.args.drawingKey;
  String get _projectKey => widget.args.projectKey;

  @override
  void initState() {
    super.initState();
    _loadCalibration();
    _loadSession();
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _tolMmCtl.dispose();
    _tolPctCtl.dispose();
    _refMmCtl.dispose();
    _drawingMmCtl.dispose();
    _gridMmCtl.dispose();
    _gridColsCtl.dispose();
    _gridRowsCtl.dispose();
    _drawingTransform.dispose();
    _photoTransform.dispose();
    super.dispose();
  }

  void _zoom(TransformationController controller, double factor) {
    final current = controller.value.getMaxScaleOnAxis();
    final target = (current * factor).clamp(0.8, 8.0);
    if (target == current) return;
    controller.value = Matrix4.identity()..scale(target);
  }

  void _resetZoom(TransformationController controller) =>
      controller.value = Matrix4.identity();

  // ——— ① 加载 CAD 校准 ———
  Future<void> _loadCalibration() async {
    setState(() => _calibLoading = true);
    final store = CadCalibrationStore(LocalStorage.instance);
    final m = await store.readCalibration(_drawingKey);
    if (m != null && m.useAffine) {
      _mapper = m;
      _imageSize = Size(m.viewWidth, m.viewHeight);
    } else {
      _mapper = null;
      _imageSize = null;
    }
    if (mounted) setState(() => _calibLoading = false);
  }

  // ——— ④ 加载已存会话 ———
  Future<void> _loadSession() async {
    final s = await MeasureStore.load(_projectKey, _drawingKey);
    if (mounted) {
      setState(() {
        _session = s ??
            MeasureSession(
              id: '${_projectKey}_${_drawingKey}_${DateTime.now().millisecondsSinceEpoch}',
              projectKey: _projectKey,
              drawingKey: _drawingKey,
              floor: widget.args.floor,
              tolMm: 15,
              tolPct: 2,
            );
        _tolMmCtl.text = fmtNumTrim(_session!.tolMm);
        _tolPctCtl.text = fmtNumTrim(_session!.tolPct);
      });
    }
  }

  Future<void> _persist() async {
    if (_session == null) return;
    final s = _session!.copyWith(
      tolMm: double.tryParse(_tolMmCtl.text) ?? _session!.tolMm,
      tolPct: double.tryParse(_tolPctCtl.text) ?? _session!.tolPct,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _session = s;
    // ① 离线优先：本地持久化。
    await MeasureStore.save(s);
    // ② 云端同步（prod 下 RemoteRepository 落库；失败不影响本地）。
    try {
      await ref.read(repositoryProvider).saveMeasurement(s);
    } catch (_) {
      // 云端不可用：仅本地保存，下次联网可再同步。
    }
  }

  /// 相机权限被拒 → 弹窗引导前往系统设置。
  void _showPermissionGuide() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('相机权限被拒绝'),
        content: const Text('拍照量尺需要相机权限。请在系统设置中开启，再回来继续测量。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              AppSettings.openAppSettings();
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  // ——— ② 照片取图 ———
  Future<void> _pickPhoto() async {
    XFile? x;
    if (kIsWeb) {
      // Web：相册选图。
      x = await ImagePicker()
          .pickImage(source: ImageSource.gallery, maxWidth: 1920, imageQuality: 85);
    } else {
      // 移动端：通用相机兜底（权限引导 + 相机失败改用相册）。
      x = await pickPhotoRobust(
        context,
        onDenied: _showPermissionGuide,
        maxWidth: 1920,
        imageQuality: 85,
      );
    }
    if (x == null) return;
    try {
      final bytes = await x.readAsBytes();
      // 解析尺寸（轻量：用 decodeImageFromList 拿宽高）。
      final ui.Image? img = await decodeImageFromListSafe(bytes);
      Size? size;
      if (img != null) size = Size(img.width.toDouble(), img.height.toDouble());
      if (mounted) {
        setState(() {
          _photoBytes = bytes;
          _photoSize = size;
          _photoPicks.clear();
          _refPicks.clear();
          _gridPicks.clear();
          _gridMode = false;
          _aiGrid = null;
          _aiGridConfirmed = false;
          _aiGridMsg = null;
          _autoCalibMsg = null;
          _autoTried = false;
        });
        // 零输入目标：照片就绪即自动尝试锚物识别（失败静默，可手动重试）。
        _tryAutoCalibOnce();
      }
    } catch (_) {
      if (mounted) AppSnack.show(context, '无法读取照片', kind: AppSnackKind.danger);
    }
  }

  // ——— ③ 添加校对项 ———
  void _addItem() {
    // P1-1 降级：图纸尺寸优先取手填值（可覆盖量得值）；未手填时才要求图纸已校准。
    final manualMm = double.tryParse(_drawingMmCtl.text.trim());
    final hasManual = manualMm != null && manualMm > 0;
    final canMeasure = _mapper != null && _imageSize != null;

    if (!hasManual && !canMeasure) {
      AppSnack.show(context, '图纸未校准：请在「图纸尺寸」处手填图纸尺寸（mm）',
          kind: AppSnackKind.danger);
      return;
    }
    if (!hasManual && _drawPicks.length < 2) {
      AppSnack.show(context, '请先在图纸上点选两点，或手填图纸尺寸', kind: AppSnackKind.danger);
      return;
    }
    if (_photoBytes == null) {
      AppSnack.show(context, '请先拍摄/选择现场照片', kind: AppSnackKind.danger);
      return;
    }
    final calib = _session?.photoCalib;
    if (calib == null) {
      AppSnack.show(context, '请先在照片上标定参考物', kind: AppSnackKind.danger);
      return;
    }
    if (_photoPicks.length < 2) {
      AppSnack.show(context, '请在照片上点选两点', kind: AppSnackKind.danger);
      return;
    }
    final a = _drawPicks[0], b = _drawPicks[1];
    final drawingMm = hasManual
        ? manualMm
        : drawingDistanceMm(
            _mapper!, _imageSize!.width, _imageSize!.height,
            a.dx, a.dy, b.dx, b.dy);
    final pa = _photoPicks[0], pb = _photoPicks[1];
    // 实测值：有单应标定走透视校正，否则回退两点比例法。
    final photoMm = photoMeasuredMmAuto(calib, pa.dx, pa.dy, pb.dx, pb.dy);

    final item = MeasureItem(
      name: _nameCtl.text.trim().isEmpty ? '未命名' : _nameCtl.text.trim(),
      drawingMm: drawingMm,
      photoMm: photoMm,
    );
    setState(() {
      _session = _session!.copyWith(items: [..._session!.items, item]);
      _drawPicks.clear();
      _photoPicks.clear();
      _drawingMmCtl.clear();
    });
    _persist();
  }

  // ——— 照片标定参考物 ———
  void _applyRefCalib() {
    if (_refPicks.length < 2 || _photoSize == null) {
      AppSnack.show(context, '请在照片上点选参考物两端', kind: AppSnackKind.danger);
      return;
    }
    final refMm = double.tryParse(_refMmCtl.text);
    if (refMm == null || refMm <= 0) {
      AppSnack.show(context, '参考物尺寸无效', kind: AppSnackKind.danger);
      return;
    }
    final calib = PhotoCalib(
      refMm: refMm,
      ax: _refPicks[0].dx,
      ay: _refPicks[0].dy,
      bx: _refPicks[1].dx,
      by: _refPicks[1].dy,
      imgW: _photoSize!.width,
      imgH: _photoSize!.height,
    );
    if (calib.spanPx <= 1e-3) {
      AppSnack.show(context, '参考物两点过近，请重新点选', kind: AppSnackKind.danger);
      return;
    }
    setState(() {
      _session = _session!.copyWith(photoCalib: calib);
      _refPicks.clear();
      _gridPicks.clear();
      _gridMode = false;
      _aiGrid = null;
      _aiGridConfirmed = false;
      _aiGridMsg = null;
      _autoCalibMsg = null;
    });
    _persist();
    AppSnack.show(context,
        '参考物标定完成：${calib.mmPerPx.toStringAsFixed(3)} mm/px（两点比例法，未做透视校正）');
  }

  /// P1-4：清除照片标定（回到未标定状态，可重新标定）。
  void _clearRefCalib() {
    setState(() {
      _session = _session!.copyWith(clearPhotoCalib: true);
      _refPicks.clear();
      _photoPicks.clear();
      _gridPicks.clear();
      _gridMode = false;
      _aiGrid = null;
      _aiGridConfirmed = false;
      _aiGridMsg = null;
      _autoCalibMsg = null;
    });
    _persist();
    AppSnack.show(context, '已清除标定，请重新标定（AI 识别网格 / 手动点选网格 / 参考物两点）');
  }

  // ——— 模数网格单应标定（透视校正主路径）———

  /// 切换网格标定模式：进入后按**行优先**依次点选网格交点。
  void _toggleGridMode() {
    if (_photoBytes == null) {
      AppSnack.show(context, '请先拍/选照片', kind: AppSnackKind.muted);
      return;
    }
    setState(() {
      _gridMode = !_gridMode;
      if (_gridMode) {
        _gridPicks.clear();
        _refPicks.clear();
        _photoPicks.clear();
      }
    });
  }

  /// 按目标点数（列×行，至少 4）能否开始标定。
  int get _gridTarget {
    final cols = int.tryParse(_gridColsCtl.text.trim()) ?? 3;
    final rows = int.tryParse(_gridRowsCtl.text.trim()) ?? 3;
    return (cols < 2 ? 2 : cols) * (rows < 2 ? 2 : rows);
  }

  /// 用已点选的网格交点求解单应并写入标定。
  ///
  /// 网格必须是**同一平面**上的等距交点（瓷砖缝、吊顶扣板、幕墙分格等），
  /// 用户按行优先点选，格距与列/行数由输入框给定；点数 ≥4 即可解，
  /// ≥5 时残差才有判别意义（4 点为精确解，残差恒 0）。
  void _applyGridCalib() {
    if (_photoSize == null) return;
    final gridMm = double.tryParse(_gridMmCtl.text.trim());
    final cols = int.tryParse(_gridColsCtl.text.trim()) ?? 0;
    final rows = int.tryParse(_gridRowsCtl.text.trim()) ?? 0;
    if (gridMm == null || gridMm <= 0) {
      AppSnack.show(context, '请填写网格间距（mm）', kind: AppSnackKind.danger);
      return;
    }
    if (cols < 2 || rows < 2) {
      AppSnack.show(context, '网格列数/行数至少为 2', kind: AppSnackKind.danger);
      return;
    }
    if (_gridPicks.length < 4) {
      AppSnack.show(context, '至少点选 4 个网格交点（当前 ${_gridPicks.length} 个）',
          kind: AppSnackKind.danger);
      return;
    }
    final pairs = buildGridCorrespondences(
      picks: _gridPicks,
      cols: cols,
      rows: rows,
      gridMm: gridMm,
    );
    if (pairs.src.length < 4) {
      AppSnack.show(context, '控制点不足，无法标定', kind: AppSnackKind.danger);
      return;
    }
    final hom = Homography.solve(pairs.src, pairs.dst);
    if (hom == null) {
      AppSnack.show(context, '点位近共线或重合，无法求解；请重选更分散的网格交点',
          kind: AppSnackKind.danger);
      return;
    }
    final res = Homography.residualMm(hom, pairs.src, pairs.dst);
    // 兼容字段：用网格对角两点合成旧两点比例（不影响单应主路径）。
    final w = (cols - 1) * gridMm;
    final hgt = (rows - 1) * gridMm;
    final calib = PhotoCalib(
      refMm: math.sqrt(w * w + hgt * hgt),
      ax: _gridPicks.first.dx,
      ay: _gridPicks.first.dy,
      bx: _gridPicks[_gridPicks.length - 1].dx,
      by: _gridPicks[_gridPicks.length - 1].dy,
      imgW: _photoSize!.width,
      imgH: _photoSize!.height,
      homography: hom.toList(),
      homographyResidualMm: res,
      calibWidthMm: w,
      calibHeightMm: hgt,
      calibPoints: pairs.src.length,
    );
    setState(() {
      _session = _session!.copyWith(photoCalib: calib);
      _gridPicks.clear();
      _gridMode = false;
      _photoPicks.clear();
      _aiGrid = null; // 手动点选覆盖 AI 结果，避免两套控制点混淆
      _aiGridConfirmed = false;
      _aiGridMsg = null;
      _autoCalibMsg = '已网格单应标定：${pairs.src.length} 点 · 格距 ${fmtMm(gridMm)}mm'
          '${pairs.src.length > 4 ? ' · 残差 ${fmtMm(res)}mm' : '（4 点为精确解，残差恒 0）'}';
    });
    _persist();
    AppSnack.show(
      context,
      '透视校正标定完成：${pairs.src.length} 个控制点'
      '${pairs.src.length > 4 ? '，残差 ${fmtMm(res)} mm' : ''}',
      kind: AppSnackKind.success,
    );
  }

  // ——— AI 网格识别 + 人工确认（自动标注主路径）———

  /// 调视觉服务识别画面中的等距模数网格；结果先进入**待确认**态。
  Future<void> _aiDetectGrid() async {
    if (_aiGridBusy) return;
    if (_photoBytes == null || _photoSize == null) {
      AppSnack.show(context, '请先拍/选照片', kind: AppSnackKind.muted);
      return;
    }
    if (_session?.photoCalib != null && !_aiGridConfirmed) {
      AppSnack.show(context, '已有标定，请先点标定签的 × 清除', kind: AppSnackKind.muted);
      return;
    }
    final online = await VisionService.isReachable();
    if (!mounted) return;
    if (!online) {
      setState(() {
        _netOffline = true;
        _aiGridMsg = '当前无网络：AI 识别不可用，请用下方手动点选网格（离线可用）';
      });
      return;
    }
    setState(() {
      _netOffline = false;
      _aiGridBusy = true;
      _aiGridMsg = '正在识别画面中的模数网格…';
    });
    try {
      final g = await VisionService().detectGrid(_photoBytes!);
      if (!mounted) return;
      if (g == null) {
        setState(() => _aiGridMsg =
            '未识别到可用网格：请让瓷砖缝/扣板缝完整入画、避免强反光，或改用下方手动点选');
        return;
      }
      setState(() {
        _aiGrid = g;
        _aiGridConfirmed = false;
        _gridMode = false;
        _gridPicks.clear();
        _photoPicks.clear();
        _refPicks.clear();
        _aiGridMsg = '识别到「${g.name}」格距 ${fmtMm(g.gridMm)}mm · '
            '${g.cols}×${g.rows} 交点（置信度 ${(g.conf * 100).round()}%）；'
            '请核对图中绿点后确认';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _aiGridMsg = 'AI 识别不可用，请手动点选网格（$e）');
    } finally {
      if (mounted) setState(() => _aiGridBusy = false);
    }
  }

  /// 人工确认 AI 识别结果 → 用其交点求解单应并写入标定。
  void _confirmAiGrid() {
    final g = _aiGrid;
    final size = _photoSize;
    if (g == null || size == null) return;
    final src = g.points
        .map((p) => Offset(p.dx * size.width, p.dy * size.height))
        .toList();
    final pairs = buildGridCorrespondences(
      picks: src,
      cols: g.cols,
      rows: g.rows,
      gridMm: g.gridMm,
    );
    if (pairs.src.length < 4) {
      AppSnack.show(context, '识别到的交点不足 4 个，无法标定，请手动点选',
          kind: AppSnackKind.danger);
      return;
    }
    final hom = Homography.solve(pairs.src, pairs.dst);
    if (hom == null) {
      AppSnack.show(
          context, '识别点过于集中或共线，无法求解；请手动点选更分散的网格交点',
          kind: AppSnackKind.danger);
      return;
    }
    final res = Homography.residualMm(hom, pairs.src, pairs.dst);
    final w = (g.cols - 1) * g.gridMm;
    final hgt = (g.rows - 1) * g.gridMm;
    final calib = PhotoCalib(
      refMm: math.sqrt(w * w + hgt * hgt),
      ax: pairs.src.first.dx,
      ay: pairs.src.first.dy,
      bx: pairs.src.last.dx,
      by: pairs.src.last.dy,
      imgW: size.width,
      imgH: size.height,
      homography: hom.toList(),
      homographyResidualMm: res,
      calibWidthMm: w,
      calibHeightMm: hgt,
      calibPoints: pairs.src.length,
    );
    setState(() {
      _session = _session!.copyWith(photoCalib: calib);
      _aiGridConfirmed = true;
      _gridMode = false;
      _gridPicks.clear();
      _photoPicks.clear();
      _refPicks.clear();
      _aiGridMsg = '已确认 AI 网格标定：${pairs.src.length} 个控制点 · '
          '残差 ${fmtMm(res)} mm（残差越小标定越可信）';
    });
    _persist();
    AppSnack.show(
      context,
      '已按 AI 网格完成透视校正标定（${pairs.src.length} 点，残差 ${fmtMm(res)} mm）',
      kind: AppSnackKind.success,
    );
  }

  /// 放弃 AI 识别结果（回到未标定状态，可重新识别或手动点选）。
  void _discardAiGrid() {
    setState(() {
      _aiGrid = null;
      _aiGridConfirmed = false;
      _aiGridMsg = null;
    });
  }

  // —— 自动标定（锚物识别）：用户零输入的主路径 ——

  /// 识别画面里的已知尺寸标准件并自动完成标定；失败静默/提示后仍可手动兜底。
  Future<void> _autoCalib({bool manual = false}) async {
    if (_autoCalibBusy) return;
    if (_photoBytes == null || _photoSize == null) {
      if (manual) {
        AppSnack.show(context, '请先拍/选照片', kind: AppSnackKind.muted);
      }
      return;
    }
    if (_session?.photoCalib != null) {
      if (manual) {
        AppSnack.show(context, '已有标定，请先点标定签的 × 清除',
            kind: AppSnackKind.muted);
      }
      return;
    }
    // 网格单应标定优先：网格是同一平面上的多点约束，
    // 比单点锚物更稳（AI 只用于"辅助识别锚物"，不改变精度来源）。
    if (_gridMode) return;
    // 联网预检：地下室/无信号时不白等超时，直接引导手动标定。
    final online = await VisionService.isReachable();
    if (!mounted) return;
    if (!online) {
      setState(() {
        _netOffline = true;
        _autoCalibMsg = null;
      });
      if (manual) {
        AppSnack.show(context, '当前无网络，自动标定不可用；手动标定离线可用',
            kind: AppSnackKind.muted);
      }
      return;
    }
    setState(() {
      _netOffline = false;
      _autoCalibBusy = true;
      _autoCalibMsg = '正在识别画面中的标准件…';
    });
    try {
      final d = await VisionService().detectAnchor(_photoBytes!);
      if (!mounted) return;
      if (d == null) {
        setState(() => _autoCalibMsg = null);
        if (manual) {
          AppSnack.show(context, '未识别到标准件，请把标准件完整拍进画面，或手动标定',
              kind: AppSnackKind.muted);
        }
        return;
      }
      _applyAnchorCalib(d);
    } catch (e) {
      if (!mounted) return;
      setState(() => _autoCalibMsg = null);
      // 远端不可用 / Web 跨域等：不打断量尺流程，回退手动。
      AppSnack.show(context, '自动标定不可用，请手动标定（$e）', kind: AppSnackKind.muted);
    } finally {
      if (mounted) setState(() => _autoCalibBusy = false);
    }
  }

  /// 照片就绪后自动尝试一次（失败静默，不重复调远端）。
  Future<void> _tryAutoCalibOnce() async {
    if (_autoTried) return;
    _autoTried = true;
    await _autoCalib();
  }

  /// 用识别到的锚物合成 `PhotoCalib`（不改 models.dart，零改动复用现有模型）。
  ///
  /// 框横/纵各自有真实长度时，取两方向比例尺的**几何平均**作为各向同性比例尺：
  /// 物体正对画面时精确，斜置 45° 时误差最小，且避免旧版"只看横向"的缺陷。
  /// ax..by 为**合成**标定点（非画面真实点）：令 spanPx = boxWpx、
  /// refMm = scale × boxWpx，使 `mmPerPx` 恰等于 scale。
  void _applyAnchorCalib(AnchorDetection d) {
    final img = _photoSize!;
    final boxWpx = (d.right - d.left) * img.width;
    final boxHpx = (d.bottom - d.top) * img.height;
    if (boxWpx <= 1 || boxHpx <= 1) {
      AppSnack.show(context, '识别框过小，请靠近标准件重拍', kind: AppSnackKind.danger);
      return;
    }
    final scale = math.sqrt((d.realWmm / boxWpx) * (d.realHmm / boxHpx));
    final calib = PhotoCalib(
      refMm: scale * boxWpx,
      ax: 0,
      ay: 0,
      bx: boxWpx,
      by: 0,
      imgW: img.width,
      imgH: img.height,
    );
    setState(() {
      _session = _session!.copyWith(photoCalib: calib);
      _autoCalibMsg =
          '已用「${d.name}」自动标定（置信度 ${(d.conf * 100).round()}%）';
      _refPicks.clear();
      _photoPicks.clear();
      _aiGrid = null;
      _aiGridConfirmed = false;
      _aiGridMsg = null;
    });
    _persist();
    AppSnack.show(context,
        '自动标定完成（${d.name}）：${scale.toStringAsFixed(3)} mm/px');
  }

  @override
  Widget build(BuildContext context) {
    final drawingsAsync = ref.watch(drawingsProvider);
    final drawing = drawingsAsync.valueOrNull?[_drawingKey];
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: NavIconButton(icon: MingCuteIcons.leftLine),
        title: const Text('拍照量尺校对'),
        actions: [
          NavIconButton(
            icon: MingCuteIcons.saveLine,
            onPressed: () async {
              await _persist();
              if (mounted) AppSnack.show(context, '已保存');
            },
          ),
        ],
      ),
      body: _session == null || _calibLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(drawing),
    );
  }

  Widget _buildBody(Drawing? drawing) {
    final tolMm = double.tryParse(_tolMmCtl.text) ?? _session!.tolMm;
    final tolPct = double.tryParse(_tolPctCtl.text) ?? _session!.tolPct;
    final pass = _session!.passCount;
    final total = _session!.items.length;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部信息卡
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(drawing?.title ?? _drawingKey,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppTokens.space1),
                  Text('楼层：${_session!.floor.isEmpty ? "—" : _session!.floor}',
                      style: TextStyle(color: AppTokens.muted, fontSize: 12)),
                  const SizedBox(height: AppTokens.space2),
                  Row(
                    children: [
                      Expanded(
                        child: _numberField('容差 ±mm', _tolMmCtl, suffix: 'mm'),
                      ),
                      const SizedBox(width: AppTokens.space3),
                      Expanded(
                        child: _numberField('容差 ±%', _tolPctCtl, suffix: '%'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.space2),
                  _calibBanner(),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTokens.space4),

          // ① 图纸侧量距
          _sectionTitle('① 图纸侧量距', '在 CAD 校准图纸上点选两点，量得图纸标注尺寸'),
          const SizedBox(height: AppTokens.space2),
          _drawingPicker(drawing),
          if (_drawPicks.length == 2 && _mapper != null && _imageSize != null)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.space2),
              child: Text(
                '图纸量得：${fmtMm(drawingDistanceMm(_mapper!, _imageSize!.width, _imageSize!.height, _drawPicks[0].dx, _drawPicks[0].dy, _drawPicks[1].dx, _drawPicks[1].dy))} mm',
                style: const TextStyle(fontWeight: FontWeight.w600, color: AppTokens.accent),
              ),
            ),
          const SizedBox(height: AppTokens.space4),

          // ② 照片侧量距
          _sectionTitle('② 现场照片量距', '拍/选照片 → 标定参考物 → 点两点量实测尺寸'),
          const SizedBox(height: AppTokens.space2),
          _photoPanel(),
          const SizedBox(height: AppTokens.space4),

          // ③ 添加项
          _textField('量尺项名称', _nameCtl, hint: '如 梁宽'),
          const SizedBox(height: AppTokens.space2),
          Row(
            children: [
              // P1-1：图纸尺寸手填——图纸未校准时降级使用，已校准时可覆盖量得值。
              Expanded(
                child: _numberField('图纸尺寸(mm)', _drawingMmCtl, suffix: 'mm'),
              ),
              const SizedBox(width: AppTokens.space3),
              ElevatedButton.icon(
                onPressed: _addItem,
                icon: const Icon(MingCuteIcons.addLine),
                label: const Text('加入校对'),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.space4),

          // ④ 校对清单
          _sectionTitle('③ 校对清单', total == 0 ? '暂无' : '合格 $pass / $total'),
          const SizedBox(height: AppTokens.space2),
          _itemList(tolMm, tolPct),
        ],
      ),
    );
  }

  Widget _calibBanner() {
    if (_mapper != null) {
      return Container(
        padding: const EdgeInsets.all(AppTokens.space2),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(MingCuteIcons.checkCircleLine, color: Colors.green, size: 16),
            const SizedBox(width: AppTokens.space1),
            Expanded(
              child: Text(
                '图纸已校准（mm/px ≈ ${(_mapper!.a.abs()).toStringAsFixed(3)}），可量取图纸真实尺寸',
                style: const TextStyle(fontSize: 12, color: Colors.green),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(AppTokens.space2),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          Icon(MingCuteIcons.warningLine, color: Colors.orange, size: 16),
          SizedBox(width: AppTokens.space1),
          Expanded(
            child: Text('图纸未校准：请在图纸查看页完成坐标校准后再来量尺',
                style: TextStyle(fontSize: 12, color: Colors.orange)),
          ),
        ],
      ),
    );
  }

  Widget _drawingPicker(Drawing? drawing) {
    final src = drawing?.src;
    return Container(
      height: 260,
      decoration: BoxDecoration(
        border: Border.all(color: AppTokens.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            InteractiveViewer(
              transformationController: _drawingTransform,
              minScale: 0.8,
              maxScale: 8.0,
              boundaryMargin: const EdgeInsets.all(40),
              child: SizedBox.expand(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (src != null)
                      Positioned.fill(
                        child: LayoutBuilder(
                          builder: (ctx, c) {
                            final box = c.biggest;
                            return GestureDetector(
                              onTapDown: (e) => _onDrawTap(e.localPosition, box),
                              child: DrawingImage(src, fit: BoxFit.contain),
                            );
                          },
                        ),
                      )
                    else
                      const Center(child: Text('无图纸底图')),
                    // 选点标记（P0-2：整图坐标→显示坐标，避免错位）
                    LayoutBuilder(
                      builder: (ctx, c) => Stack(
                        children: [
                          ..._drawPicks.map((p) => _pickDot(
                              imageToDisplay(p, c.biggest, _imageSize!), Colors.blue)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: _ZoomToolbar(
                onZoomIn: () => _zoom(_drawingTransform, 1.2),
                onZoomOut: () => _zoom(_drawingTransform, 1 / 1.2),
                onReset: () => _resetZoom(_drawingTransform),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onDrawTap(Offset local, Size box) {
    // 估算整图像素坐标：以 BoxFit.contain 反推（简化：按比例映射到 _imageSize）。
    // P2-2：图纸未加载时不存点（避免显示坐标与整图像素两套坐标系混用）。
    if (_imageSize == null) {
      AppSnack.show(context, '图纸未加载，暂不能选点', kind: AppSnackKind.muted);
      return;
    }
    final contain = _containSize(box, _imageSize!);
    final offX = (box.width - contain.width) / 2;
    final offY = (box.height - contain.height) / 2;
    final px = (local.dx - offX) / contain.width * _imageSize!.width;
    final py = (local.dy - offY) / contain.height * _imageSize!.height;
    setState(() {
      if (_drawPicks.length >= 2) _drawPicks.clear();
      _drawPicks.add(Offset(px, py));
      // P1-1：量满两点后预填图纸尺寸（用户可手改覆盖）。
      if (_drawPicks.length == 2 && _mapper != null) {
        final a = _drawPicks[0], b = _drawPicks[1];
        final mm = drawingDistanceMm(
            _mapper!, _imageSize!.width, _imageSize!.height,
            a.dx, a.dy, b.dx, b.dy);
        if (mm > 0) _drawingMmCtl.text = fmtMm(mm);
      }
    });
  }

  Size _containSize(Size box, Size img) {
    final r = img.width / img.height;
    double w = box.width, h = box.width / r;
    if (h > box.height) {
      h = box.height;
      w = box.height * r;
    }
    return Size(w, h);
  }

  /// P0-2 标记错位修复：把整图像素坐标换算成显示坐标（BoxFit.contain 逆变换）。
  /// 供图纸蓝点/照片橙点/红点渲染前使用，保证点击处与标记重合。
  Offset imageToDisplay(Offset p, Size box, Size imageSize) {
    final contain = _containSize(box, imageSize);
    final offX = (box.width - contain.width) / 2;
    final offY = (box.height - contain.height) / 2;
    return Offset(
      p.dx / imageSize.width * contain.width + offX,
      p.dy / imageSize.height * contain.height + offY,
    );
  }

  Widget _photoPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _pickPhoto,
              icon: const Icon(MingCuteIcons.cameraLine),
              label: const Text('拍/选照片'),
            ),
            const SizedBox(width: AppTokens.space3),
            if (kIsWeb || Platform.isIOS)
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ArMeasurePage(args: widget.args),
                  ),
                ),
                icon: const Icon(MingCuteIcons.cubeLine),
                label: const Text('AR量尺（iPhone Pro）'),
              ),
            if (kIsWeb || Platform.isIOS) const SizedBox(width: AppTokens.space3),
            if (_session?.photoCalib != null)
              Chip(
                label: Text(
                  _session!.photoCalib!.hasHomography
                      ? '透视校正 ${_session!.photoCalib!.calibPoints} 点'
                          '${(_session!.photoCalib!.calibPoints > 4 && _session!.photoCalib!.homographyResidualMm != null) ? ' · 残差 ${fmtMm(_session!.photoCalib!.homographyResidualMm!)}mm' : ''}'
                      : '标定 ${_session!.photoCalib!.mmPerPx.toStringAsFixed(3)} mm/px',
                  style: const TextStyle(fontSize: 12),
                ),
                backgroundColor: Colors.green.shade50,
                // P1-4：点 × 清除标定，回到未标定状态可重新标定。
                onDeleted: _clearRefCalib,
              ),
          ],
        ),
        const SizedBox(height: AppTokens.space2),
        // 模数网格标定（透视校正主路径）：同平面多点约束，比单点锚物更稳
        Card(
          color: AppTokens.surface2,
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.space3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('模数网格标定（透视校正·推荐）',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                    TextButton(
                      onPressed: _toggleGridMode,
                      child: Text(_gridMode ? '取消手选' : '手动点选'),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.space1),
                // AI 自动识别网格（零输入：识别 → 图上标注 → 人工确认）
                OutlinedButton(
                  onPressed: _aiGridBusy ? null : _aiDetectGrid,
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(40)),
                  child: _aiGridBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('AI 自动识别网格（推荐·零输入）'),
                ),
                if (_aiGridMsg != null) ...[
                  const SizedBox(height: AppTokens.space1),
                  Text(_aiGridMsg!,
                      style: TextStyle(
                        fontSize: 11,
                        color: _aiGrid == null ? Colors.orange : Colors.green,
                      )),
                ],
                // 人工确认条：AI 结果不直接生效，必须点确认
                if (_aiGrid != null && !_aiGridConfirmed) ...[
                  const SizedBox(height: AppTokens.space2),
                  Container(
                    padding: const EdgeInsets.all(AppTokens.space2),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('AI 已在图上标出网格（绿点/绿线），请核对：',
                            style: TextStyle(fontSize: 12)),
                        const SizedBox(height: AppTokens.space1),
                        Row(
                          children: [
                            ElevatedButton(
                                onPressed: _confirmAiGrid,
                                child: const Text('确认并标定')),
                            const SizedBox(width: AppTokens.space2),
                            TextButton(
                                onPressed: _discardAiGrid,
                                child: const Text('放弃')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppTokens.space2),
                Row(
                  children: [
                    Expanded(child: _numberField('格距(mm)', _gridMmCtl, suffix: 'mm')),
                    const SizedBox(width: AppTokens.space2),
                    SizedBox(width: 70, child: _numberField('列', _gridColsCtl)),
                    const SizedBox(width: AppTokens.space2),
                    SizedBox(width: 70, child: _numberField('行', _gridRowsCtl)),
                  ],
                ),
                const SizedBox(height: AppTokens.space2),
                if (_gridMode)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppTokens.space2),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '按「行优先」从左到右、从上到下依次点选网格交点：'
                      '已点 ${_gridPicks.length}/$_gridTarget。\n'
                      '用现场等距模数网格（瓷砖缝 600 / 吊顶扣板 300 / 石膏板 1200…），'
                      '斜拍也能换算出真实尺寸。',
                      style: const TextStyle(fontSize: 11, color: Colors.blue),
                    ),
                  )
                else
                  const Text(
                    '提示：瓷砖 600×600 用「格距 600 / 3 列 / 3 行」点 9 个缝交点；'
                    '4 点为精确解（残差恒 0），≥5 点才有标定质量参考。',
                    style: TextStyle(fontSize: 11, color: AppTokens.muted),
                  ),
                if (_gridMode && _gridPicks.isNotEmpty) ...[
                  const SizedBox(height: AppTokens.space1),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => setState(_gridPicks.clear),
                        child: const Text('清空已点'),
                      ),
                      const SizedBox(width: AppTokens.space2),
                      TextButton(
                        onPressed: _applyGridCalib,
                        child: const Text('立即标定'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppTokens.space2),
        // 参考物标定行
        Card(
          color: AppTokens.surface2,
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.space3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('参考物标定', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: AppTokens.space1),
                // 自动标定（零输入主路径）：识别画面中的已知尺寸标准件
                OutlinedButton(
                  onPressed:
                      _autoCalibBusy ? null : () => _autoCalib(manual: true),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(40)),
                  child: _autoCalibBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('自动标定（识别画面中的标准件）'),
                ),
                if (_netOffline) ...[
                  const SizedBox(height: AppTokens.space1),
                  const Text('当前无网络（如地下室）：自动标定不可用，请用手动标定（离线可用）。',
                      style: TextStyle(fontSize: 11, color: Colors.orange)),
                ],
                if (_autoCalibMsg != null) ...[
                  const SizedBox(height: AppTokens.space1),
                  Text(_autoCalibMsg!,
                      style: const TextStyle(fontSize: 11, color: Colors.green)),
                ],
                const SizedBox(height: AppTokens.space2),
                // 手动兜底（远端不可用 / 画面无标准件时）
                Row(
                  children: [
                    Expanded(child: _numberField('参考物真实尺寸(mm)', _refMmCtl)),
                    const SizedBox(width: AppTokens.space3),
                    ElevatedButton(
                      onPressed: _applyRefCalib,
                      child: const Text('标定'),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.space1),
                Text(
                    '支持自动识别：$anchorHintText。\n'
                    '或手动：在下方照片上点选参考物两端（如卷尺 0→1000mm）。',
                    style: const TextStyle(fontSize: 11, color: AppTokens.muted)),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppTokens.space2),
        if (_photoBytes != null)
          Container(
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(color: AppTokens.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  InteractiveViewer(
                    transformationController: _photoTransform,
                    minScale: 0.8,
                    maxScale: 8.0,
                    boundaryMargin: const EdgeInsets.all(40),
                    child: SizedBox.expand(
                      child: LayoutBuilder(
                        builder: (ctx, c) => GestureDetector(
                          onTapDown: (e) => _onPhotoTap(e.localPosition, c.biggest),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Positioned.fill(
                                child: Image.memory(_photoBytes!, fit: BoxFit.contain),
                              ),
                              ..._refPicks.map((p) => _pickDot(
                                  imageToDisplay(p, c.biggest, _photoSize!), Colors.orange)),
                              ..._photoPicks.map((p) => _pickDot(
                                  imageToDisplay(p, c.biggest, _photoSize!), Colors.red)),
                              // 网格标定控制点（青）：点满即自动求单应
                              ..._gridPicks.map((p) => _pickDot(
                                  imageToDisplay(p, c.biggest, _photoSize!),
                                  Colors.teal)),
                              // AI 识别网格叠加（绿）：待确认=亮绿加粗，已确认=浅绿
                              if (_aiGrid != null)
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _AiGridPainter(
                                      pts: [
                                        for (final p in _aiGrid!.points)
                                          imageToDisplay(
                                            Offset(
                                              p.dx * _photoSize!.width,
                                              p.dy * _photoSize!.height,
                                            ),
                                            c.biggest,
                                            _photoSize!,
                                          ),
                                      ],
                                      cols: _aiGrid!.cols,
                                      rows: _aiGrid!.rows,
                                      pending: !_aiGridConfirmed,
                                    ),
                                  ),
                                ),
                              // P1-3：参考线覆盖层（橙=参考物，红=被测）
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _MeasureLinePainter(
                                    refPts: [
                                      for (final p in _refPicks)
                                        imageToDisplay(p, c.biggest, _photoSize!),
                                    ],
                                    pickPts: [
                                      for (final p in _photoPicks)
                                        imageToDisplay(p, c.biggest, _photoSize!),
                                    ],
                                    measuredMm: _session?.photoCalib != null &&
                                            _photoPicks.length == 2
                                        ? photoMeasuredMmAuto(
                                            _session!.photoCalib!,
                                            _photoPicks[0].dx,
                                            _photoPicks[0].dy,
                                            _photoPicks[1].dx,
                                            _photoPicks[1].dy)
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _ZoomToolbar(
                      onZoomIn: () => _zoom(_photoTransform, 1.2),
                      onZoomOut: () => _zoom(_photoTransform, 1 / 1.2),
                      onReset: () => _resetZoom(_photoTransform),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Container(
            height: 120,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: AppTokens.border, style: BorderStyle.solid),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text('尚未选择照片', style: TextStyle(color: AppTokens.muted)),
          ),
        if (_photoPicks.length == 2 && _session?.photoCalib != null)
          Builder(builder: (_) {
            final c = _session!.photoCalib!;
            final p0 = _photoPicks[0], p1 = _photoPicks[1];
            final corrected = photoMeasuredMmAuto(c, p0.dx, p0.dy, p1.dx, p1.dy);
            final legacy = photoMeasuredMm(c, p0.dx, p0.dy, p1.dx, p1.dy);
            return Padding(
              padding: const EdgeInsets.only(top: AppTokens.space2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '照片量得：${fmtMm(corrected)} mm'
                    '${c.hasHomography ? '（透视校正）' : ''}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, color: Colors.red),
                  ),
                  // 效果对比（实时）：同两点，两点比例法 vs 单应校正
                  if (c.hasHomography)
                    Text(
                      '校正前（两点比例）${fmtMm(legacy)} mm → '
                      '校正后（单应）${fmtMm(corrected)} mm，'
                      '差 ${fmtMmSigned(corrected - legacy)} mm',
                      style: const TextStyle(fontSize: 11, color: Colors.green),
                    ),
                ],
              ),
            );
          }),
        const SizedBox(height: AppTokens.space1),
        // P2-3：按标定状态给出针对性提示。
        Text(
          _gridMode
              ? '网格标定中：请依次点选网格交点（青），点满 $_gridTarget 个自动求解'
              : (_session?.photoCalib == null
                  ? '先做网格标定（推荐）或在照片上点选参考物两端（橙）后点「标定」'
                  : '请在照片上点选被测两点（红）'),
          style: const TextStyle(fontSize: 11, color: AppTokens.muted),
        ),
      ],
    );
  }

  void _onPhotoTap(Offset local, Size box) {
    if (_photoSize == null) return;
    // AI 结果待确认时不接受打点，避免误点落进参考物/量测点。
    if (_aiGrid != null && !_aiGridConfirmed) {
      AppSnack.show(context, '请先「确认」或「放弃」AI 识别结果', kind: AppSnackKind.muted);
      return;
    }
    final contain = _containSize(box, _photoSize!);
    final offX = (box.width - contain.width) / 2;
    final offY = (box.height - contain.height) / 2;
    final px = (local.dx - offX) / contain.width * _photoSize!.width;
    final py = (local.dy - offY) / contain.height * _photoSize!.height;
    setState(() {
      // 网格标定模式：行优先依次收控制点（点满即自动求解单应）
      if (_gridMode) {
        if (_gridPicks.length >= _gridTarget) _gridPicks.clear();
        _gridPicks.add(Offset(px, py));
        return;
      }
      // 参考物未标定：先收参考物两点
      if (_session?.photoCalib == null) {
        if (_refPicks.length >= 2) _refPicks.clear();
        _refPicks.add(Offset(px, py));
      } else {
        if (_photoPicks.length >= 2) _photoPicks.clear();
        _photoPicks.add(Offset(px, py));
      }
    });
    // 点满目标点数 → 立即求解单应（省一次点击；不满意可重新进入网格标定）
    if (_gridMode && _gridPicks.length >= _gridTarget) {
      _applyGridCalib();
    }
  }

  Widget _itemList(double tolMm, double tolPct) {
    if (_session!.items.isEmpty) {
      return const Text('  —  暂无校对项', style: TextStyle(color: AppTokens.muted));
    }
    return Column(
      children: _session!.items.asMap().entries.map((entry) {
        final i = entry.key;
        final e = entry.value;
        final ok = e.pass(tolMm, tolPct);
        final dev = e.deviation;
        final devPct = e.deviationPct;
        return Card(
          margin: const EdgeInsets.only(bottom: AppTokens.space2),
          child: ListTile(
            leading: Icon(ok ? MingCuteIcons.checkCircleLine : MingCuteIcons.closeCircleLine,
                color: ok ? Colors.green : Colors.red),
            title: Text(e.name),
            subtitle: Text(
              '图纸 ${fmtMm(e.drawingMm)} mm  /  实测 ${fmtMm(e.photoMm)} mm\n'
              '偏差 ${fmtMmSigned(dev)} mm (${fmtPctSigned(devPct)}%)'
              '${e.errorMm != null ? '  ±${fmtMm(e.errorMm!)}' : ''}'
              '${e.errorMm != null && !e.canJudge(tolMm) ? '\n⚠ 测量误差过大，判定需卷尺复核' : ''}',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: IconButton(
              icon: const Icon(MingCuteIcons.deleteLine, size: 18),
              onPressed: () {
                setState(() {
                  final items = [..._session!.items]..removeAt(i);
                  _session = _session!.copyWith(items: items);
                });
                _persist();
              },
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _sectionTitle(String t, String sub) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          Text(sub, style: TextStyle(fontSize: 12, color: AppTokens.muted)),
        ],
      );

  Widget _pickDot(Offset p, Color c) => Positioned(
        left: p.dx,
        top: p.dy,
        child: Transform.translate(
          offset: const Offset(-6, -6),
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      );

  Widget _numberField(String label, TextEditingController c, {String? suffix}) =>
      TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );

  Widget _textField(String label, TextEditingController c, {String? hint}) =>
      TextField(
        controller: c,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );
}

/// 悬浮缩放工具条（量尺页 / 拍照验收页复用）。
/// P1-3：照片上的参考线覆盖层。
///
/// 橙线 = 参考物两端（中点标注像素跨度），红线 = 被测两点（中点标注实测 mm）。
class _MeasureLinePainter extends CustomPainter {
  const _MeasureLinePainter({
    required this.refPts,
    required this.pickPts,
    this.measuredMm,
  });

  final List<Offset> refPts;
  final List<Offset> pickPts;
  final double? measuredMm;

  void _line(Canvas canvas, List<Offset> pts, Color color, String? label) {
    if (pts.length < 2) return;
    canvas.drawLine(
      pts[0],
      pts[1],
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    if (label == null) return;
    final mid =
        Offset((pts[0].dx + pts[1].dx) / 2, (pts[0].dy + pts[1].dy) / 2);
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          shadows: const [Shadow(color: Colors.white, blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(mid.dx - tp.width / 2, mid.dy - tp.height - 6));
  }

  @override
  void paint(Canvas canvas, Size size) {
    _line(
      canvas,
      refPts,
      Colors.orange,
      refPts.length == 2
          ? '跨度 ${(refPts[1] - refPts[0]).distance.toStringAsFixed(0)} px'
          : null,
    );
    _line(
      canvas,
      pickPts,
      Colors.red,
      measuredMm != null ? '${fmtMm(measuredMm!)} mm' : null,
    );
  }

  @override
  bool shouldRepaint(covariant _MeasureLinePainter old) =>
      old.refPts != refPts ||
      old.pickPts != pickPts ||
      old.measuredMm != measuredMm;
}

/// AI 识别网格的叠加层：按行列连线 + 交点圆点。
///
/// [pending] 为「待人工确认」态——亮绿加粗，提示用户核对；
/// 确认后转为浅绿细线，仅作标定依据展示，不再抢视觉焦点。
class _AiGridPainter extends CustomPainter {
  const _AiGridPainter({
    required this.pts,
    required this.cols,
    required this.rows,
    required this.pending,
  });

  final List<Offset> pts; // 显示坐标，行优先
  final int cols;
  final int rows;
  final bool pending;

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.length < 4 || cols < 2 || rows < 2) return;
    final color = pending ? const Color(0xFF1DB954) : const Color(0x881DB954);
    final line = Paint()
      ..color = color
      ..strokeWidth = pending ? 1.6 : 1.0
      ..style = PaintingStyle.stroke;
    final dot = Paint()..color = color;

    bool has(int r, int c) => r >= 0 && r < rows && c >= 0 && c < cols;
    Offset at(int r, int c) => pts[r * cols + c];

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (has(r, c + 1)) canvas.drawLine(at(r, c), at(r, c + 1), line);
        if (has(r + 1, c)) canvas.drawLine(at(r, c), at(r + 1, c), line);
      }
    }
    for (final p in pts) {
      canvas.drawCircle(p, pending ? 3.0 : 2.2, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _AiGridPainter old) =>
      old.pts != pts ||
      old.cols != cols ||
      old.rows != rows ||
      old.pending != pending;
}

class _ZoomToolbar extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  const _ZoomToolbar({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTokens.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: AppTokens.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _IconBtn(icon: MingCuteIcons.zoomOutLine, onTap: onZoomOut),
          Container(width: 1, height: 28, color: AppTokens.border),
          _IconBtn(icon: MingCuteIcons.fullscreenLine, onTap: onReset),
          Container(width: 1, height: 28, color: AppTokens.border),
          _IconBtn(icon: MingCuteIcons.zoomInLine, onTap: onZoomIn),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _IconBtn({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(icon, size: 18, color: AppTokens.fg),
      ),
    );
  }
}

/// 安全解码图片尺寸（避免直接依赖 package:image，仅取宽高）。
Future<ui.Image?> decodeImageFromListSafe(Uint8List bytes) async {
  try {
    final img = await decodeImageFromList(bytes);
    return img;
  } catch (_) {
    return null;
  }
}
