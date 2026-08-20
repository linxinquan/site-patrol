import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/utils/image_compress.dart';
import '../../core/utils/photo_watermark.dart';
import '../../core/utils/web_storage.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models.dart';
import '../../data/vision_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/di/providers.dart';
import '../../shared/widgets/app_snack.dart';

/// 拍照记录页（P3）：图纸 + 图钉选点 → 模拟快门（对齐原型 mockPhotoSVG 选历史照片）
/// → 1.5s 扫描 → VL 识别 → 保存记录。
/// 注：真实相机（image_picker）代码已注释，改走"关联历史照片"的模拟拍照。
class CapturePage extends ConsumerStatefulWidget {
  final CaptureArgs args;
  const CapturePage({super.key, this.args = const CaptureArgs()});

  @override
  ConsumerState<CapturePage> createState() => _CapturePageState();
}

/// 置信度档位（低/中/高）对应的配色与文案。
class _ConfBucket {
  final String label; // 低 / 中 / 高
  final Color fg; // 文字色
  final Color bg; // 背景色
  const _ConfBucket(this.label, this.fg, this.bg);
}

class _CapturePageState extends ConsumerState<CapturePage> {
  late String _floor;
  late String _anchorLabel;
  late double _x;
  late double _y;

  /// 拍摄照片的压缩字节数据（Image.memory 展示）。
  Uint8List? _shotPhoto;

  /// 烧录水印后的照片字节（保存用）。
  Uint8List? _watermarkedPhoto;

  /// 水印元信息（时间/项目/部位/GPS/凭证号）。
  WatermarkMeta? _watermarkMeta;

  /// 烧录后图片 SHA-256 指纹（防篡改留痕）。
  String? _photoHash;

  /// 拍摄来源描述（文件名，不含文件大小）。
  String _shotCaption = '';

  /// 当前选择的附近定位（工程水印相机风格，用户可切换）。
  SiteLocation _location = siteLocations.first;

  bool _scanning = false;
  List<VlDefect> _defects = const [];

  /// 识别失败的原因（null = 未失败或进行中）。UI 据此展示错误提示。
  String? _scanError;
  Timer? _scanTimer;
  bool _saved = false;

  /// 当前要显示的图纸（按项目图纸 provider 解析，避免不同项目图纸串图）。
  Drawing? _drawing;

  /// 暂存的 vision 识别结果列表（Web localStorage 持久化，刷新后仍可见）。
  /// 每项：{ts, anchor, floor, count, defects:[{name, desc}]}
  List<Map<String, dynamic>> _storedResults = [];
  static const String _storageKey = 'stored_vision_results';

  /// Mock 开关：true 走 vlPreset（秒级，不消耗模型配额，便于验证 UI）；
  /// false 调真实 /api/vision。
  bool _useMock = false;

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
    _loadStoredResults();
  }

  /// 启动时从 Web localStorage 恢复暂存的识别结果。
  void _loadStoredResults() {
    final list = WebStorage.getList(_storageKey);
    if (list.isEmpty) return;
    setState(() {
      _storedResults = list.whereType<Map<String, dynamic>>().toList();
    });
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    super.dispose();
  }

  // —— 图纸坐标换算 ——
  String get _drawingKey {
    final argsKey = widget.args.drawingKey;
    if (argsKey != null && argsKey.isNotEmpty) return argsKey;
    return floorToDrawingKey(_floor);
  }

  Drawing _resolveDrawing(Map<String, Drawing> projectMap) {
    final key = _drawingKey;
    final d = projectMap[key] ?? dy7Drawings[key] ?? drawings[key];
    return d ?? drawings['nkf_west_1f']!;
  }

  double get _ratio => (_drawing!.h / _drawing!.w).clamp(0.6, 1.0);

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
  final ImagePicker _picker = ImagePicker();

  /// 按平台分流取图：
  /// - Web：相册选图（桌面浏览器无法直接调相机，走文件上传）。
  /// - Android/iOS：真实相机，并做原生压缩（maxWidth / imageQuality）。
  Future<XFile?> _pickImage() async {
    const source = kIsWeb ? ImageSource.gallery : ImageSource.camera;
    try {
      return await _picker.pickImage(
        source: source,
        maxWidth: 1280,
        imageQuality: 82,
      );
    } catch (_) {
      if (mounted) {
        AppSnack.show(context, '无法调用相机/相册，请检查权限', kind: AppSnackKind.danger);
      }
      return null;
    }
  }

  Future<void> _doCapture() async {
    if (_scanning) return;

    final shot = await _pickImage();
    if (shot == null) {
      if (mounted) AppSnack.show(context, '已取消拍摄');
      return;
    }

    // 读取图片字节 → 简单压缩（压缩后的字节用于展示与烧录水印）。
    final rawBytes = await shot.readAsBytes();
    final compressed = compressImage(rawBytes);

    // 构造水印元信息（工程记录：时间 / 项目 / 部位 / GPS / 凭证号）。
    // 定位信息来自用户选择的「附近定位点」（工程水印相机风格）。
    final now = DateTime.now();
    final meta = WatermarkMeta(
      project: _location.name,
      anchor: '$_anchorLabel · $_floor',
      time: '${now.year}-${_two(now.month)}-${_two(now.day)} '
          '${_two(now.hour)}:${_two(now.minute)}',
      gps: _location.gpsText,
      altitude: '${_location.altitude.toStringAsFixed(1)}m',
      reporter: _currentUser,
      serial: '${now.millisecondsSinceEpoch}',
      worldCoord: widget.args.drawPointWorldX != null &&
              widget.args.drawPointWorldY != null
          ? '图纸坐标 X=${widget.args.drawPointWorldX!.toStringAsFixed(1)} '
              'Y=${widget.args.drawPointWorldY!.toStringAsFixed(1)}'
          : null,
    );

    // 烧录水印（失败时回退原始压缩图，避免阻断拍照流程）。
    Uint8List? watermarked;
    try {
      watermarked = await applyPhotoWatermark(compressed, meta);
    } catch (e) {
      debugPrint('[capture] watermark failed: $e');
      watermarked = null;
    }
    final finalPhoto = watermarked ?? compressed;

    if (mounted) {
      setState(() {
        _shotPhoto = finalPhoto;
        _watermarkedPhoto = watermarked;
        _watermarkMeta = meta;
        _photoHash = imageSha256(finalPhoto);
        _shotCaption = shot.name;
        _defects = const [];
      });
      AppSnack.show(
        context,
        watermarked != null
            ? '已拍摄并烧录防篡改水印'
            : '已拍摄（水印烧录失败，已保留原图）',
        kind: watermarked != null ? AppSnackKind.success : AppSnackKind.danger,
      );
    }
    await _runScan();
  }

  /// 当前拍摄人（复用登录用户姓名）。
  String get _currentUser {
    final u = ref.read(currentUserProvider);
    return u.name;
  }

  Future<void> _runScan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _scanError = null;
    });
    _scanTimer?.cancel();

    // 先展示至少 800ms 扫描动画，避免一闪而过。
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    List<VlDefect> result = const [];
    // Mock 开关开启：秒级返回「上次真实模型返回」还原数据，便于验证 UI。
    if (_useMock) {
      result = vlPreset(_anchorLabel, replayReal: true);
    } else if (_shotPhoto != null) {
      try {
        final vision = await VisionService().recognizeDefects(_shotPhoto!);
        result = vision.defects
            .map((d) => VlDefect(
                  name: d.name,
                  // severity 模型尚未返回，暂默认 orange；后端补返回严重程度后再映射
                  severity: DefectSeverity.orange,
                  // A 修复：传真实置信度，低 conf 会在卡片/工单中提示人工复核
                  conf: d.conf,
                  desc: d.desc,
                ))
            .toList();
        // 只要有返回就暂存（刷新页面仍可见），不依赖当前页 UI 状态。
        if (vision.defects.isNotEmpty) {
          _persistResult(vision);
        }
      } on TimeoutException catch (e) {
        if (mounted) {
          setState(() =>
              _scanError = '识别超时（${e.duration?.inSeconds ?? 180}s）：模型响应过慢，可重试');
        }
        debugPrint('[runScan] vision timeout: $e');
      } catch (e) {
        if (mounted) {
          setState(() => _scanError = '识别失败：$e');
        }
        debugPrint('[runScan] vision error: $e');
      }
    } else {
      result = vlPreset(_anchorLabel);
    }

    if (!mounted) return;
    setState(() {
      _scanning = false;
      _defects = result;
    });
  }

  /// 把一条 vision 识别结果追加到暂存列表并持久化（Web localStorage）。
  void _persistResult(VisionResult vision) {
    final now = DateTime.now();
    final ts = '${now.year}-${_two(now.month)}-${_two(now.day)} '
        '${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}';
    final entry = <String, dynamic>{
      'ts': ts,
      'anchor': _anchorLabel,
      'floor': _floor,
      'count': vision.count,
      'defects': vision.defects.map((d) => d.toJson()).toList(),
    };
    setState(() {
      _storedResults = [entry, ..._storedResults];
    });
    WebStorage.setList(_storageKey, _storedResults);
    if (mounted) {
      AppSnack.show(context, '识别结果已暂存（刷新页面仍可查看）', kind: AppSnackKind.brand);
    }
  }

  void _retake() {
    _scanTimer?.cancel();
    setState(() {
      _shotPhoto = null;
      _defects = const [];
      _scanError = null;
      _scanning = false;
    });
    AppSnack.show(context, '已重拍，请再次按下快门');
  }

  void _addPoint() {
    AppSnack.show(context, '加点：已在该位置临时标记部位（可拖拽准星微调）', kind: AppSnackKind.brand);
  }

  void _annotate() {
    AppSnack.show(context, '标注功能预留：后续支持圈选/语音备注', kind: AppSnackKind.brand);
  }

  void _saveRecord() {
    if (_scanning) return;
    if (_shotPhoto == null) {
      AppSnack.show(context, '请先按下快门拍摄现场照片', kind: AppSnackKind.danger);
      return;
    }
    if (_saved) return;

    final repo = ref.read(repositoryProvider);

    // 未识别到缺陷：仅提示，不生成空工单污染列表
    if (_defects.isEmpty) {
      AppSnack.show(context, '未识别到缺陷，记录已留痕', kind: AppSnackKind.success);
      _saved = true;
      Navigator.of(context).pop();
      return;
    }

    // 将每条识别结果转为缺陷工单写入仓库
    final now = DateTime.now();
    final ts = '${now.year}-${_two(now.month)}-${_two(now.day)} '
        '${_two(now.hour)}:${_two(now.minute)}';
    for (var i = 0; i < _defects.length; i++) {
      final vl = _defects[i];
      repo.addDefect(Defect(
        id: 'v${now.millisecondsSinceEpoch}_$i',
        part: '$_floor · $_anchorLabel · ${vl.name}',
        type: vl.name,
        category: _guessCategory(vl.name),
        severity: vl.severity,
        status: DefectStatus.draft,
        anchor: _anchorLabel,
        floor: _floor,
        ts: ts,
        gps: _location.gpsText,
        alt: '${_location.altitude.toStringAsFixed(1)}m',
        resp: '待指派',
        respUnit: '待指派',
        reporter: '现场拍照',
        tags: const ['AI 识别'],
        note: vl.desc ?? '',
        seed: String.fromCharCode(97 + (i % 6)), // a~f 轮替，水印配色多样
        // 关联图纸坐标：图钉 → 拍照生成的缺陷自动继承真实图纸坐标
        drawingKey: widget.args.drawingKey,
        worldX: widget.args.drawPointWorldX,
        worldY: widget.args.drawPointWorldY,
        // 防篡改留痕：水印照片哈希 + 凭证号
        photoHash: _photoHash,
        watermarkSerial: _watermarkMeta?.serial,
      ));
    }

    // 刷新缺陷列表，使新工单在 DefectsPage 立即可见
    ref.invalidate(defectsProvider);

    AppSnack.show(context, '已生成 ${_defects.length} 条缺陷工单（$_anchorLabel）',
        kind: AppSnackKind.success);
    _saved = true;
    Navigator.of(context).pop();
  }

  /// 根据 AI 识别的缺陷名粗略推断专业分类（无法判断时归为「其他」）。
  DefectCategory _guessCategory(String name) {
    final n = name.toLowerCase();
    if (n.contains('裂缝') || n.contains('钢筋') || n.contains('沉降') ||
        n.contains('梁') || n.contains('柱') || n.contains('板')) {
      return DefectCategory.structure;
    }
    if (n.contains('渗') || n.contains('水') || n.contains('漏')) {
      return DefectCategory.water;
    }
    if (n.contains('电') || n.contains('线')) {
      return DefectCategory.electric;
    }
    if (n.contains('空鼓') || n.contains('涂') || n.contains('砖')) {
      return DefectCategory.decoration;
    }
    return DefectCategory.other;
  }

  // —— 渲染 ——
  @override
  Widget build(BuildContext context) {
    final drawingsAsync = ref.watch(drawingsProvider);
    _drawing = _resolveDrawing(drawingsAsync.valueOrNull ?? {});
    return Scaffold(
        backgroundColor: AppTokens.bg,
        appBar: AppBar(
          title: const Text('拍照记录',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTokens.fg)),
          centerTitle: false,
          backgroundColor: AppTokens.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: AppTokens.space3),
              child: Row(
                children: [
                  Text('Mock',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color:
                              _useMock ? AppTokens.accent : AppTokens.muted)),
                  const SizedBox(width: 4),
                  Switch(
                    value: _useMock,
                    onChanged: (v) => setState(() => _useMock = v),
                    activeThumbColor: AppTokens.accent,
                  ),
                ],
              ),
            ),
          ],
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
                    if (_defects.isNotEmpty) ...[
                      const SizedBox(height: AppTokens.space4),
                      _buildDefectSection(),
                    ],
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
  }

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
                  style: const TextStyle(fontSize: 13, color: AppTokens.muted),
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
                      style:
                          const TextStyle(fontSize: 12, color: AppTokens.muted),
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
                    _drawing!.src,
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
                            style:
                                TextStyle(fontSize: 11, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
                // 扫描动画
                if (_scanning) _buildScanOverlay(),
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
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
      AppSnack.show(context, '「${a.label}」暂无历史照片', kind: AppSnackKind.muted);
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
                      color: AppTokens.accent.withValues(alpha: 0.8),
                      width: 1.5),
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
                  style: TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }

  /// VL 识别缺陷卡片区块（独立放在页面 Column 内，突破图纸 Stack 边界，
  /// 避免缺陷卡片被图纸裁剪/遮挡）。
  Widget _buildDefectSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.space3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: AppTokens.border),
        boxShadow: AppTokens.elevationOverlay,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.scanSearch,
                  size: 14, color: AppTokens.accent),
              const SizedBox(width: 6),
              const Text('视觉识别结果',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTokens.fg)),
              const Spacer(),
              Text('AI · VL · ${_defects.length} 处',
                  style: const TextStyle(fontSize: 10, color: AppTokens.muted)),
            ],
          ),
          const SizedBox(height: AppTokens.space2),
          ..._defects.map(_buildDefectCard),
        ],
      ),
    );
  }

  Widget _buildDefectCard(VlDefect d) {
    final bucket = _confBucket(d.conf);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: bucket.bg,
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            ),
            child: Icon(LucideIcons.alertTriangle, size: 16, color: bucket.fg),
          ),
          const SizedBox(width: AppTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(d.name,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTokens.fg)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: bucket.bg,
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusPill),
                      ),
                      child: Text(
                          '${bucket.label} · ${(d.conf * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: bucket.fg)),
                    ),
                  ],
                ),
                if (d.desc != null && d.desc!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(d.desc!,
                      style: const TextStyle(
                          fontSize: 12, height: 1.4, color: AppTokens.muted)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 置信度档位：<0.5 低（红）、0.5~0.8 中（橙）、>0.8 高（绿）。
  _ConfBucket _confBucket(double conf) {
    if (conf >= 0.8) {
      return const _ConfBucket('高', Color(0xFF16A34A), Color(0xFFDCFCE7));
    }
    if (conf >= 0.5) {
      return const _ConfBucket('中', Color(0xFFEA580C), Color(0xFFFFEDD5));
    }
    return const _ConfBucket('低', Color(0xFFDC2626), Color(0xFFFEE2E2));
  }

  /// 拍照水印条：定位（可点击切换「附近定位」）/ 时间 / 部位 / 凭证号 / 哈希指纹。
  /// 定位信息来自 [_location]（用户从附近定位点选择，工程水印相机风格）。
  Widget _buildWatermark() {
    final m = _watermarkMeta;
    final now = DateTime.now();
    final ts = '${now.year}-${_two(now.month)}-${_two(now.day)} '
        '${_two(now.hour)}:${_two(now.minute)}';
    final burned = _watermarkedPhoto != null;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.space3, vertical: AppTokens.space2),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Row(
        children: [
          // 定位图标 + 地点名（点击切换附近定位）
          InkWell(
            onTap: _pickLocation,
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.space2, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.mapPin,
                      size: 14, color: AppTokens.accent),
                  const SizedBox(width: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(
                      _location.name,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(LucideIcons.chevronDown,
                      size: 12, color: Colors.white54),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppTokens.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_anchorLabel · $_floor',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (m != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '凭证 ${m.serial} · ${_photoHash != null ? _photoHash!.substring(0, 12) : '--'}…',
                    style: const TextStyle(
                        fontSize: 9,
                        color: Colors.white38,
                        fontFeatures: [FontFeature.tabularFigures()]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppTokens.space3),
          if (burned)
            const Tooltip(
              message: '防篡改水印已烧录进照片像素，裁剪/涂抹即破坏原始画面',
              child: Icon(LucideIcons.shieldCheck, size: 14, color: Color(0xFF34D399)),
            )
          else
            const Icon(LucideIcons.shieldAlert, size: 14, color: Color(0xFFFBBF24)),
          const SizedBox(width: AppTokens.space2),
          Text(ts, style: const TextStyle(fontSize: 10, color: Colors.white70)),
        ],
      ),
    );
  }

  /// 打开「附近定位」选择器：列出所有定位点（含 GPS / 地址 / 距离），
  /// 用户选择后切换 [_location]，水印/照片上的定位信息随之更新。
  void _pickLocation() {
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
                  const Icon(LucideIcons.navigation,
                      size: 15, color: AppTokens.accent),
                  const SizedBox(width: 6),
                  const Text('选择附近定位',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTokens.fg)),
                  const Spacer(),
                  Text('${siteLocations.length} 处',
                      style: const TextStyle(
                          fontSize: 11, color: AppTokens.muted)),
                ],
              ),
              const SizedBox(height: AppTokens.space2),
              const Text('定位将烧录到照片水印中（工程取证）',
                  style: TextStyle(
                      fontSize: 11, color: AppTokens.muted)),
              const SizedBox(height: AppTokens.space3),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: siteLocations.length,
                  itemBuilder: (ctx, i) => _buildLocationTile(siteLocations[i]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 单个附近定位项：名称 + 地址 + GPS/海拔 + 距当前定位距离。
  Widget _buildLocationTile(SiteLocation loc) {
    final selected = loc.id == _location.id;
    final km = _location.distanceKmTo(loc);
    final distText = km < 1
        ? '${(km * 1000).round()}m'
        : '${km.toStringAsFixed(1)}km';
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        setState(() => _location = loc);
        AppSnack.show(context, '定位已切换：${loc.name}', kind: AppSnackKind.accent);
      },
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.space3, vertical: AppTokens.space3),
        decoration: BoxDecoration(
          color: selected
              ? AppTokens.brand.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          border: Border.all(
            color: selected ? AppTokens.brand : AppTokens.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: selected
                    ? AppTokens.brand
                    : AppTokens.bg,
                shape: BoxShape.circle,
              ),
              child: Icon(
                selected
                    ? LucideIcons.mapPinCheck
                    : LucideIcons.mapPin,
                size: 16,
                color: selected ? Colors.white : AppTokens.muted,
              ),
            ),
            const SizedBox(width: AppTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(loc.name,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTokens.fg)),
                  const SizedBox(height: 2),
                  Text(
                    '${loc.address} · ${loc.gpsText} · ${loc.altitude.toStringAsFixed(0)}m',
                    style: const TextStyle(
                        fontSize: 10.5, color: AppTokens.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppTokens.space2),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTokens.bg,
                borderRadius: BorderRadius.circular(AppTokens.radiusPill),
              ),
              child: Text(
                selected ? '当前' : '距 ${_location.name} $distText',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: selected ? AppTokens.brand : AppTokens.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  /// 结果面板：缩略图 + 识别状态（不含文件大小与置信度数字）。
  Widget _buildResultPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.space3),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: AppTokens.border),
      ),
      child: _shotPhoto == null
          ? const Row(
              children: [
                Icon(LucideIcons.image, size: 16, color: AppTokens.muted),
                SizedBox(width: AppTokens.space2),
                Expanded(
                  child: Text('尚未拍摄：按下快门拍摄现场照片后自动识别',
                      style: TextStyle(fontSize: 13, color: AppTokens.muted)),
                ),
              ],
            )
          : Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                  child: Image.memory(
                    _shotPhoto!,
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
                        _scanError ??
                            (_defects.isEmpty
                                ? '已拍摄，等待识别…'
                                : '已识别 ${_defects.length} 处缺陷'),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _scanError != null
                                ? const Color(0xFFDC2626)
                                : AppTokens.fg),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$_anchorLabel · $_floor · $_shotCaption',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
            label: const Text('保存记录',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
        if (_storedResults.isNotEmpty) ...[
          const SizedBox(height: AppTokens.space4),
          _buildStoredResults(),
        ],
      ],
    );
  }

  /// 暂存识别结果列表（测试用，置于保存按钮下方）。
  Widget _buildStoredResults() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: AppTokens.border),
      ),
      padding: const EdgeInsets.all(AppTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.history,
                  size: 15, color: AppTokens.accent),
              const SizedBox(width: 6),
              const Text('暂存识别结果',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTokens.fg)),
              const Spacer(),
              Text('${_storedResults.length} 条',
                  style: const TextStyle(fontSize: 11, color: AppTokens.muted)),
            ],
          ),
          const SizedBox(height: AppTokens.space2),
          ..._storedResults.map((e) => _buildStoredResultTile(e)),
        ],
      ),
    );
  }

  Widget _buildStoredResultTile(Map<String, dynamic> e) {
    final defects = (e['defects'] as List? ?? const [])
        .map((d) => d is Map<String, dynamic> ? d : const <String, dynamic>{})
        .toList();
    final count = e['count'] as int? ?? defects.length;
    final names = defects
        .map((d) => d['name']?.toString() ?? '')
        .where((n) => n.isNotEmpty)
        .join('、');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 5),
            decoration: const BoxDecoration(
              color: AppTokens.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppTokens.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('${e['anchor']} · ${e['floor']}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTokens.fg)),
                    const Spacer(),
                    Text('${e['ts']}',
                        style: const TextStyle(
                            fontSize: 10, color: AppTokens.muted)),
                  ],
                ),
                const SizedBox(height: 2),
                Text('识别 $count 处缺陷 · $names',
                    style:
                        const TextStyle(fontSize: 11, color: AppTokens.muted)),
              ],
            ),
          ),
        ],
      ),
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
                style:
                    const TextStyle(fontSize: 11, color: AppTokens.mutedA11y)),
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
