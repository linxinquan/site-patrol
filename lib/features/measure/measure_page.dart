import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
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
import '../../data/models.dart';
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
  final TextEditingController _tolMmCtl = TextEditingController(text: '5');
  final TextEditingController _tolPctCtl = TextEditingController(text: '2');
  final TextEditingController _refMmCtl = TextEditingController(text: '1000');

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
              tolMm: 5,
              tolPct: 2,
            );
        _tolMmCtl.text = _session!.tolMm.toString();
        _tolPctCtl.text = _session!.tolPct.toString();
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
        });
      }
    } catch (_) {
      if (mounted) AppSnack.show(context, '无法读取照片', kind: AppSnackKind.danger);
    }
  }

  // ——— ③ 添加校对项 ———
  void _addItem() {
    if (_mapper == null || _imageSize == null) {
      AppSnack.show(context, '图纸未校准，无法量取图纸尺寸', kind: AppSnackKind.danger);
      return;
    }
    if (_drawPicks.length < 2) {
      AppSnack.show(context, '请先在图纸上点选两点', kind: AppSnackKind.danger);
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
    final drawingMm = drawingDistanceMm(
      _mapper!, _imageSize!.width, _imageSize!.height, a.dx, a.dy, b.dx, b.dy);
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
    AppSnack.show(context, '参考物标定完成：${calib.mmPerPx.toStringAsFixed(4)} mm/px');
  }

  @override
  Widget build(BuildContext context) {
    final drawingsAsync = ref.watch(drawingsProvider);
    final drawing = drawingsAsync.valueOrNull?[_drawingKey];
    return Scaffold(
      appBar: AppBar(
        title: const Text('拍照量尺校对'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_outlined),
            tooltip: '保存会话',
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
                '图纸量得：${drawingDistanceMm(_mapper!, _imageSize!.width, _imageSize!.height, _drawPicks[0].dx, _drawPicks[0].dy, _drawPicks[1].dx, _drawPicks[1].dy).toStringAsFixed(1)} mm',
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
          Row(
            children: [
              Expanded(
                child: _textField('量尺项名称', _nameCtl, hint: '如 梁宽'),
              ),
              const SizedBox(width: AppTokens.space3),
              ElevatedButton.icon(
                onPressed: _addItem,
                icon: const Icon(Icons.add),
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
            const Icon(Icons.check_circle, color: Colors.green, size: 16),
            const SizedBox(width: AppTokens.space1),
            Expanded(
              child: Text(
                '图纸已校准（mm/px ≈ ${(_mapper!.a.abs()).toStringAsFixed(4)}），可量取图纸真实尺寸',
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
          Icon(Icons.warning_amber, color: Colors.orange, size: 16),
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
                              child: Image.asset(src, fit: BoxFit.contain),
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
    if (_imageSize == null) {
      setState(() => _drawPicks.add(local));
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
              icon: const Icon(Icons.camera_alt_outlined),
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
                icon: const Icon(Icons.view_in_ar_outlined),
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
                const Text('在下方照片上点选参考物两端（如卷尺 0→1000mm）',
                    style: TextStyle(fontSize: 11, color: AppTokens.muted)),
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
              '照片量得：${photoMeasuredMm(_session!.photoCalib!, _photoPicks[0].dx, _photoPicks[0].dy, _photoPicks[1].dx, _photoPicks[1].dy).toStringAsFixed(1)} mm',
              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.red),
            ),
          ),
        const SizedBox(height: AppTokens.space1),
        const Text('提示：点选照片空白处可先后标定参考物（橙）与量测点（红）',
            style: TextStyle(fontSize: 11, color: AppTokens.muted)),
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
            leading: Icon(ok ? Icons.check_circle : Icons.error,
                color: ok ? Colors.green : Colors.red),
            title: Text(e.name),
            subtitle: Text(
              '图纸 ${e.drawingMm.toStringAsFixed(1)}mm  /  实测 ${e.photoMm.toStringAsFixed(1)}mm\n'
              '偏差 ${dev >= 0 ? "+" : ""}${dev.toStringAsFixed(1)}mm (${devPct >= 0 ? "+" : ""}${devPct.toStringAsFixed(1)}%)',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
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
          _IconBtn(icon: Icons.zoom_out, onTap: onZoomOut, tooltip: '缩小'),
          Container(width: 1, height: 28, color: AppTokens.border),
          _IconBtn(icon: Icons.fullscreen, onTap: onReset, tooltip: '复位'),
          Container(width: 1, height: 28, color: AppTokens.border),
          _IconBtn(icon: Icons.zoom_in, onTap: onZoomIn, tooltip: '放大'),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  const _IconBtn({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 18, color: AppTokens.fg),
        ),
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
