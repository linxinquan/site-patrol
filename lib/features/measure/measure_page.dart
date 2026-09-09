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
    final photoMm = photoMeasuredMm(calib, pa.dx, pa.dy, pb.dx, pb.dy);

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
    });
    _persist();
    AppSnack.show(context, '参考物标定完成：${calib.mmPerPx.toStringAsFixed(3)} mm/px');
  }

  /// P1-4：清除照片标定（回到未标定状态，可重新标定）。
  void _clearRefCalib() {
    setState(() {
      _session = _session!.copyWith(clearPhotoCalib: true);
      _refPicks.clear();
      _photoPicks.clear();
    });
    _persist();
    AppSnack.show(context, '已清除标定，请在照片上重新点选参考物两端');
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
        AppSnack.show(context, '已有标定，请先点标定签的 × 清除', kind: AppSnackKind.muted);
      }
      return;
    }
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
                  '标定 ${_session!.photoCalib!.mmPerPx.toStringAsFixed(3)} mm/px',
                  style: const TextStyle(fontSize: 12),
                ),
                backgroundColor: Colors.green.shade50,
                // P1-4：点 × 清除标定，回到未标定状态可重新标定。
                onDeleted: _clearRefCalib,
              ),
          ],
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
                                        ? photoMeasuredMm(
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
          Padding(
            padding: const EdgeInsets.only(top: AppTokens.space2),
            child: Text(
              '照片量得：${fmtMm(photoMeasuredMm(_session!.photoCalib!, _photoPicks[0].dx, _photoPicks[0].dy, _photoPicks[1].dx, _photoPicks[1].dy))} mm',
              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.red),
            ),
          ),
        const SizedBox(height: AppTokens.space1),
        // P2-3：按标定状态给出针对性提示。
        Text(
          _session?.photoCalib == null
              ? '请在照片上点选参考物两端（橙），再点击「标定」'
              : '请在照片上点选被测两点（红）',
          style: const TextStyle(fontSize: 11, color: AppTokens.muted),
        ),
      ],
    );
  }

  void _onPhotoTap(Offset local, Size box) {
    if (_photoSize == null) return;
    final contain = _containSize(box, _photoSize!);
    final offX = (box.width - contain.width) / 2;
    final offY = (box.height - contain.height) / 2;
    final px = (local.dx - offX) / contain.width * _photoSize!.width;
    final py = (local.dy - offY) / contain.height * _photoSize!.height;
    setState(() {
      // 参考物未标定：先收参考物两点
      if (_session?.photoCalib == null) {
        if (_refPicks.length >= 2) _refPicks.clear();
        _refPicks.add(Offset(px, py));
      } else {
        if (_photoPicks.length >= 2) _photoPicks.clear();
        _photoPicks.add(Offset(px, py));
      }
    });
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
