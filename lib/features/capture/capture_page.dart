import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/design_tokens.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models.dart';
import '../../shared/widgets/app_snack.dart';

/// 拍照验收页（P3）：图纸 + 图钉选点 → 模拟快门（对齐原型 mockPhotoSVG 选历史照片）
/// → 1.5s 扫描 → VL 识别 → 保存记录。
/// 注：真实相机（image_picker）代码已注释，改走"关联历史照片"的模拟拍照。
class CapturePage extends StatefulWidget {
  final CaptureArgs args;
  const CapturePage({super.key, this.args = const CaptureArgs()});

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  late String _floor;
  late String _anchorLabel;
  late double _x;
  late double _y;

  /// 模拟照片：从最近锚点的历史照片里随机取一张（对齐原型 capState.shotPhoto）。
  AnchorPhoto? _shotPhoto;
  bool _scanning = false;
  List<VlDefect> _defects = const [];
  Timer? _scanTimer;
  bool _saved = false;

  List<PhotoAnchor> get _anchors => photoAnchors[_floor] ?? const [];

  @override
  void initState() {
    super.initState();
    _floor = widget.args.floor;
    _anchorLabel = widget.args.anchorLabel;
    _x = widget.args.x;
    _y = widget.args.y;
    // 初始坐标下尝试关联最近锚点（兼容"待选点"默认值）。
    _snapToNearestAnchor(force: true);
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    super.dispose();
  }

  // —— 图纸坐标换算 ——
  String get _drawingKey => floorToDrawingKey(_floor);
  Drawing get _drawing => drawings[_drawingKey] ?? drawings['nkf_west_1f']!;

  double get _ratio => (_drawing.h / _drawing.w).clamp(0.6, 1.0);

  void _onTapDrawing(Offset local, Size size) {
    final nx = (local.dx / size.width).clamp(0.02, 0.98).toDouble();
    final ny = (local.dy / size.height).clamp(0.02, 0.98).toDouble();
    setState(() {
      _x = nx;
      _y = ny;
      _anchorLabel = '待选点';
      _snapToNearestAnchor();
    });
  }

  /// 关联最近锚点（HTML nearestAnchor）。
  void _snapToNearestAnchor({bool force = false}) {
    if (_anchors.isEmpty) return;
    PhotoAnchor? best;
    var bestDist = double.infinity;
    for (final a in _anchors) {
      final d = math.sqrt(math.pow(a.x - _x, 2) + math.pow(a.y - _y, 2));
      if (d < bestDist) {
        bestDist = d;
        best = a;
      }
    }
    if (best == null) return;
    if (bestDist < 0.12 || force) {
      _anchorLabel = best.label;
    }
  }

  // —— 快门 / 扫描 / 识别 ——
  // 模拟拍照：从最近锚点的历史照片里取一张（对齐原型 openCapture → doCapture）。
  // 真实相机代码已注释（见文件底部），当前用模拟照片替代。
  Future<void> _doCapture() async {
    if (_scanning) return;

    // 找最近锚点，取它的历史照片；无锚点或锚点无照片时，取本楼层任意一张。
    final near = _nearestAnchor();
    AnchorPhoto? photo;
    if (near != null && near.photos.isNotEmpty) {
      photo = near.photos[_rand(near.photos.length)];
    } else {
      final any = _anchors.where((a) => a.photos.isNotEmpty).toList();
      if (any.isNotEmpty) {
        photo = any[_rand(any.length)].photos.first;
      }
    }
    if (photo == null) {
      if (mounted) {
        AppSnack.show(context, '该部位暂无历史照片，请换一个锚点',
            kind: AppSnackKind.danger);
      }
      return;
    }

    // 关联最近锚点（若尚未吸附，拍下时锁定）
    if (near != null) _anchorLabel = near.label;

    setState(() {
      _shotPhoto = photo;
      _defects = const [];
    });
    if (mounted) {
      AppSnack.show(context, '已拍摄：${photo.caption}（${photo.date}）',
          kind: AppSnackKind.accent);
    }
    await _runScan();
  }

  /// 当前准星最近的照片锚点（用于模拟拍照取图 + 吸附标签）。
  PhotoAnchor? _nearestAnchor() {
    if (_anchors.isEmpty) return null;
    PhotoAnchor? best;
    var bestDist = double.infinity;
    for (final a in _anchors) {
      final d = math.sqrt(math.pow(a.x - _x, 2) + math.pow(a.y - _y, 2));
      if (d < bestDist) {
        bestDist = d;
        best = a;
      }
    }
    return best;
  }

  int _rand(int max) => max <= 0 ? 0 : math.Random().nextInt(max);

  // /// 真实相机快门（保留参考，Web 阶段不可用）：
  // /// 用 image_picker 打开相机拍摄后走 1.5s 扫描。接真机时恢复。
  // final ImagePicker _picker = ImagePicker();
  // Future<void> _doCaptureReal() async {
  //   if (_scanning) return;
  //   final XFile? shot;
  //   try {
  //     shot = await _picker.pickImage(
  //       source: ImageSource.camera,
  //       maxWidth: 1280,
  //       imageQuality: 82,
  //     );
  //   } catch (_) {
  //     if (mounted) {
  //       AppSnack.show(context, '无法调用相机，请检查相机权限',
  //           kind: AppSnackKind.danger);
  //     }
  //     return;
  //   }
  //   if (shot == null) {
  //     if (mounted) AppSnack.show(context, '已取消拍摄');
  //     return;
  //   }
  //   final path = shot.path;
  //   setState(() {
  //     _shotPhoto = null;
  //     _defects = const [];
  //   });
  //   await _runScan();
  // }

  Future<void> _runScan() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    _scanTimer?.cancel();
    // 1.5s 扫描动画后出 VL 识别结果（对齐 HTML doCapture → runVL）。
    _scanTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _defects = vlPreset(_anchorLabel);
      });
    });
  }

  void _retake() {
    _scanTimer?.cancel();
    setState(() {
      _shotPhoto = null;
      _defects = const [];
      _scanning = false;
    });
    AppSnack.show(context, '已重拍，请再次按下快门');
  }

  void _addPoint() {
    AppSnack.show(context, '加点：已在该位置临时标记部位（可拖拽准星微调）',
        kind: AppSnackKind.brand);
  }

  void _annotate() {
    AppSnack.show(context, '标注功能预留：后续支持圈选/语音备注',
        kind: AppSnackKind.brand);
  }

  void _saveRecord() {
    if (_scanning) return;
    if (_shotPhoto == null) {
      AppSnack.show(context, '请先按下快门拍摄现场照片',
          kind: AppSnackKind.danger);
      return;
    }
    if (_saved) return;
    _saved = true;
    final part =
        _defects.isEmpty ? '未识别缺陷' : _defects.map((d) => d.name).join('、');
    AppSnack.show(
        context,
        '验收记录已保存：$_anchorLabel（$part）已关联历史照片',
        kind: AppSnackKind.success);
    Navigator.of(context).pop();
  }

  // —— 渲染 ——
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppTokens.bg,
        appBar: AppBar(
          title: const Text('拍照验收',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTokens.fg)),
          centerTitle: false,
          backgroundColor: AppTokens.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        body: Column(
          children: [
            _buildAnchorBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    AppTokens.space4, AppTokens.space2, AppTokens.space4, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildDrawingStage(),
                    const SizedBox(height: AppTokens.space4),
                    _buildWatermark(),
                    const SizedBox(height: AppTokens.space4),
                    _buildResultPanel(),
                    const SizedBox(height: AppTokens.space4),
                    _buildControls(),
                    const SizedBox(height: AppTokens.space6),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  /// 顶部锚定部位信息条。
  Widget _buildAnchorBar() => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(
            AppTokens.space4, AppTokens.space2, AppTokens.space4, 0),
        padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.space4, vertical: AppTokens.space3),
        decoration: BoxDecoration(
          color: AppTokens.surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          border: Border.all(color: AppTokens.border),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.mapPin, size: 16, color: AppTokens.accent),
            const SizedBox(width: AppTokens.space2),
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: '锚定部位：',
                  style: const TextStyle(
                      fontSize: 13, color: AppTokens.muted),
                  children: [
                    TextSpan(
                      text: _anchorLabel,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTokens.fg),
                    ),
                    TextSpan(
                      text: ' · $_floor',
                      style: const TextStyle(
                          fontSize: 12, color: AppTokens.muted),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );

  /// 图纸 + 图钉 + 准星交互区。
  Widget _buildDrawingStage() {
    return AspectRatio(
      aspectRatio: 1 / _ratio,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            onTapUp: (d) => _onTapDrawing(d.localPosition, constraints.biggest),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                  child: Image.asset(
                    _drawing.src,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                // 半透明遮罩，突出蓝图观感
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.10),
                        Colors.black.withValues(alpha: 0.28),
                      ],
                    ),
                  ),
                ),
                // 预置照片锚点图钉
                ..._anchors.map((a) => _buildPin(a)),
                // 准星选点
                _buildCrosshair(),
                // 顶部提示条
                Positioned(
                  top: AppTokens.space3,
                  left: AppTokens.space3,
                  right: AppTokens.space3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.space3, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.mousePointerClick,
                            size: 12, color: Colors.white),
                        SizedBox(width: 6),
                        Text('点击图纸选点，将自动吸附最近锚点',
                            style: TextStyle(
                                fontSize: 11, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
                // 扫描动画
                if (_scanning) _buildScanOverlay(),
                // 识别结果（浮于图纸上，与 HTML runVL 一致）
                if (_defects.isNotEmpty) _buildDefectOverlay(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPin(PhotoAnchor a) {
    // 把 0~1 的相对坐标映射到 -1~1 的 Alignment（Positioned + Align 实现百分比定位）。
    return Positioned.fill(
      child: Align(
        alignment: Alignment(a.x * 2 - 1, a.y * 2 - 1),
        child: GestureDetector(
          onTap: () => _showAnchorPhotos(a),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                ),
                child: Text(
                  a.label,
                  style: const TextStyle(
                      fontSize: 10, color: Colors.white, height: 1.2),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppTokens.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppTokens.accent.withValues(alpha: 0.5),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 点击图钉查看该锚点历史照片（对齐原型 cap__pin 点开照片）。
  void _showAnchorPhotos(PhotoAnchor a) {
    if (a.photos.isEmpty) {
      AppSnack.show(context, '「${a.label}」暂无历史照片',
          kind: AppSnackKind.muted);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: AppTokens.space3),
          padding: const EdgeInsets.all(AppTokens.space4),
          decoration: BoxDecoration(
            color: AppTokens.surface,
            borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.mapPin,
                      size: 14, color: AppTokens.accent),
                  const SizedBox(width: 6),
                  Text('${a.label} · 历史照片',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTokens.fg)),
                ],
              ),
              const SizedBox(height: AppTokens.space3),
              SizedBox(
                height: 150,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: a.photos.map((p) {
                    return Padding(
                      padding: const EdgeInsets.only(right: AppTokens.space3),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                        child: Image.asset(
                          'assets/photos/${p.file}',
                          width: 180,
                          height: 150,
                          fit: BoxFit.cover,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: AppTokens.space2),
              Text(
                a.photos.map((p) => '${p.date} ${p.caption}').join('\n'),
                style: const TextStyle(
                    fontSize: 11, color: AppTokens.muted, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 准星十字 + 外圈。
  Widget _buildCrosshair() {
    return Positioned.fill(
      child: Align(
        alignment: Alignment(_x * 2 - 1, _y * 2 - 1),
        child: IgnorePointer(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppTokens.accent.withValues(alpha: 0.8), width: 1.5),
                ),
              ),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: AppTokens.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
              // 十字线
              _line(44, 1, Axis.horizontal),
              _line(1, 44, Axis.vertical),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(double w, double h, Axis axis) => Container(
        width: w,
        height: h,
        color: AppTokens.accent.withValues(alpha: 0.7),
      );

  /// 1.5s 扫描动画：旋转 spinner + 文案。
  Widget _buildScanOverlay() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.space5, vertical: AppTokens.space4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppTokens.radiusLg),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: AppTokens.accent,
                  backgroundColor: Colors.white12,
                ),
              ),
              SizedBox(height: AppTokens.space3),
              Text('视觉模型识别中…',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
              SizedBox(height: 4),
              Text('正在分析缺陷特征',
                  style:
                      TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }

  /// VL 识别缺陷卡片浮层（对齐 HTML runVL 渲染）。
  Widget _buildDefectOverlay() {
    return Positioned(
      left: AppTokens.space3,
      right: AppTokens.space3,
      bottom: AppTokens.space3,
      child: Container(
        padding: const EdgeInsets.all(AppTokens.space3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          boxShadow: AppTokens.elevationOverlay,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(LucideIcons.scanSearch,
                    size: 14, color: AppTokens.accent),
                SizedBox(width: 6),
                Text('视觉识别结果',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTokens.fg)),
                Spacer(),
                Text('AI · VL',
                    style:
                        TextStyle(fontSize: 10, color: AppTokens.muted)),
              ],
            ),
            const SizedBox(height: AppTokens.space2),
            ..._defects.map(_buildDefectCard),
          ],
        ),
      ),
    );
  }

  Widget _buildDefectCard(VlDefect d) {
    final sev = d.severity;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: sev.soft,
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            ),
            child: Icon(LucideIcons.alertTriangle,
                size: 16, color: sev.color),
          ),
          const SizedBox(width: AppTokens.space3),
          Expanded(
            child: Text(d.name,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.fg)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: sev.soft,
              borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            ),
            child: Text('${sev.label} · ${(d.conf * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: sev.color)),
          ),
        ],
      ),
    );
  }

  /// 拍照水印条：时间戳 / GPS / 海拔 / 楼层部位。
  Widget _buildWatermark() {
    final now = DateTime.now();
    final ts = '${now.year}-${_two(now.month)}-${_two(now.day)} '
        '${_two(now.hour)}:${_two(now.minute)}';
    final gps = '22.593${_x.toStringAsFixed(3).replaceAll('.', '')}°N '
        '113.979${_y.toStringAsFixed(3).replaceAll('.', '')}°E';
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.space3, vertical: AppTokens.space2),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.camera, size: 14, color: AppTokens.accent),
          const SizedBox(width: AppTokens.space2),
          Expanded(
            child: Text(
              '$_anchorLabel · $_floor',
              style: const TextStyle(fontSize: 11, color: Colors.white),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppTokens.space3),
          Text(ts,
              style: const TextStyle(fontSize: 10, color: Colors.white70)),
          const SizedBox(width: AppTokens.space3),
          const Icon(LucideIcons.satellite, size: 12, color: Colors.white70),
          const SizedBox(width: 4),
          Text(gps,
              style: const TextStyle(fontSize: 10, color: Colors.white70)),
          const SizedBox(width: AppTokens.space3),
          const Icon(LucideIcons.gauge, size: 12, color: Colors.white70),
          const SizedBox(width: 4),
          const Text('18.2m',
              style: TextStyle(fontSize: 10, color: Colors.white70)),
        ],
      ),
    );
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  /// 结果/照片面板。
  Widget _buildResultPanel() {
    return Container(
      padding: const EdgeInsets.all(AppTokens.space3),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: AppTokens.border),
      ),
      child: _shotPhoto == null
          ? const Row(
              children: [
                Icon(LucideIcons.image,
                    size: 16, color: AppTokens.muted),
                SizedBox(width: AppTokens.space2),
                Expanded(
                  child: Text('尚未拍摄：按下快门拍摄现场照片后自动识别',
                      style: TextStyle(
                          fontSize: 13, color: AppTokens.muted)),
                ),
              ],
            )
          : Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                  child: Image.asset(
                    'assets/photos/${_shotPhoto!.file}',
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: AppTokens.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _defects.isEmpty ? '已拍摄，等待识别…' : '已识别 ${_defects.length} 处缺陷',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTokens.fg),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _defects.isEmpty
                            ? '识别结果将叠加在图纸上'
                            : '$_anchorLabel · 置信度 ${(_defects.map((d) => d.conf).reduce((a, b) => (a + b) / 2) * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                            fontSize: 11, color: AppTokens.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  /// 控制条 + 快门。
  Widget _buildControls() {
    return Column(
      children: [
        Row(
          children: [
            _buildControlBtn(LucideIcons.scanSearch, '识别', _runScan),
            _buildControlBtn(LucideIcons.plus, '加点', _addPoint),
            const Spacer(),
            _buildShutter(),
            const Spacer(),
            _buildControlBtn(LucideIcons.rotateCcw, '重拍', _retake),
            _buildControlBtn(LucideIcons.penTool, '标注', _annotate),
          ],
        ),
        const SizedBox(height: AppTokens.space4),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: FilledButton.icon(
            onPressed: _saveRecord,
            style: FilledButton.styleFrom(
              backgroundColor: AppTokens.accent,
              foregroundColor: AppTokens.onAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              ),
            ),
            icon: const Icon(LucideIcons.save, size: 18),
            label: const Text('保存验收记录',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _buildControlBtn(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.space3, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: AppTokens.mutedA11y),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: AppTokens.mutedA11y)),
          ],
        ),
      ),
    );
  }

  /// 中央大圆快门。
  Widget _buildShutter() {
    return InkWell(
      onTap: _doCapture,
      customBorder: const CircleBorder(),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTokens.accent, AppTokens.accentHover],
          ),
          border: Border.all(color: Colors.white, width: 4),
          boxShadow: [
            BoxShadow(
              color: AppTokens.accent.withValues(alpha: 0.4),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(LucideIcons.camera, color: Colors.white, size: 28),
      ),
    );
  }
}
