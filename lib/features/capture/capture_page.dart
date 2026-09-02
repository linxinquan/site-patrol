import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/utils/camera_pick.dart';
import '../../core/utils/defect_suggestions.dart';
import 'package:app_settings/app_settings.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/utils/image_compress.dart';
import '../../core/utils/photo_watermark.dart';
import '../../core/storage/local_storage.dart';
import '../../data/cad_service.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models.dart';
import '../../data/repository/mock_repository.dart';
import '../../data/vision_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/di/providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_snack.dart';
import '../../shared/widgets/voice_input.dart';

/// 量尺校对容差默认值：±10mm 且 ±5%
const double _defaultTolMm = 10;
const double _defaultTolPct = 5;

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

/// 拍照流程步骤：先选平面 → 图纸上选坐标/部位 → 拍照。
enum _CaptureStep { selectFloor, selectPoint, capture }

class _CapturePageState extends ConsumerState<CapturePage> {
  late String _projectId;
  late String _floor;
  /// 选中平面的 Drawing key（大铲湾楼层直接用 Floor.key，避免 floorToDrawingKey 串图）。
  String _selectedFloorKey = '';
  late String _anchorLabel;
  late double _x;
  late double _y;
  /// 当前流程步骤。
  late _CaptureStep _step;

  /// 拍摄照片的压缩字节数据（Image.memory 展示）。
  Uint8List? _shotPhoto;

  /// 拍照后待确认的原始文件（拍后预览确认：重拍/使用）。
  XFile? _pendingShot;
  /// 提交（烧录水印 + 识别）进行中。
  bool _committing = false;

  /// 烧录水印后的照片字节（保存用）。
  Uint8List? _watermarkedPhoto;

  /// 水印元信息（时间/项目/部位/GPS/凭证号）。
  WatermarkMeta? _watermarkMeta;

  /// 烧录后图片 SHA-256 指纹（防篡改留痕）。
  String? _photoHash;

  /// 当前选择的附近定位（工程水印相机风格，用户可切换）。
  SiteLocation _location = siteLocations.first;

  bool _scanning = false;
  List<VlDefect> _defects = const [];

  /// 用户描述（手打 / 语音追加），保存时一并写入记录。
  final TextEditingController _noteController = TextEditingController();

  /// 识别失败的原因（null = 未失败或进行中）。UI 据此展示错误提示。
  String? _scanError;
  Timer? _scanTimer;
  bool _saved = false;

  /// 当前要显示的图纸（按项目图纸 provider 解析，避免不同项目图纸串图）。
  Drawing? _drawing;

  /// 图纸缩放控制器（拍照验收页支持双指/滚轮缩放）。
  final _drawingTransform = TransformationController();

  /// 当本地没有 PNG 资产时，尝试从 CAD 服务生成/加载的远程 PNG URL。
  String? _remotePngUrl;
  bool _remotePngLoading = false;
  String? _remotePngError;

  /// 暂存的 vision 识别结果列表（跨端持久化：移动端走 Hive、Web 走 localStorage，刷新后仍可见）。
  /// 每项：{ts, anchor, floor, count, defects:[{name, severity, conf, desc}]}
  List<Map<String, dynamic>> _storedResults = [];
  static const String _storageKey = 'stored_vision_results';

  /// Mock 开关：true 走 vlPreset（秒级，不消耗模型配额，便于验证 UI）；
  /// false 调真实 /api/vision。
  bool _useMock = false;

  List<PhotoAnchor> get _anchors => photoAnchors[_floor] ?? const [];

  // —— 量尺校对 ——
  /// 量尺校对项集合（实测 vs 图纸标注）。
  List<ScaleCheck> _scaleChecks = [];
  /// 容差：绝对偏差(mm) 与 偏差率(%) 取"且"逻辑。
  double _tolMm = _defaultTolMm;
  double _tolPct = _defaultTolPct;
  /// 当前图纸的标定比例（mm/px），由 CAD 校准仿射系数推导，无则 null。
  double? get _scaleMmPerPx {
    final m = ref.read(cadCalibrationMapProvider)[_drawingKey];
    if (m == null) return null;
    final s = m.useAffine ? m.a.abs() : m.scaleX.abs();
    return s > 0 ? s : null;
  }

  @override
  void initState() {
    super.initState();
    _projectId = widget.args.projectId ??
        ref.read(currentProjectIdProvider) ??
        allProjects.first.id;
    _floor = widget.args.floor;
    _anchorLabel = widget.args.anchorLabel.isEmpty ? '待选点' : widget.args.anchorLabel;
    _x = widget.args.x;
    _y = widget.args.y;
    // 若未指定楼层/图纸，则默认选中当前项目的地下一层平面图并进入选坐标步骤。
    if (widget.args.drawingKey != null || _floor.isNotEmpty) {
      _step = _CaptureStep.capture;
      _snapToNearestAnchor(force: true);
    } else {
      _step = _CaptureStep.selectPoint;
      final defaultFloor = _floorOptions.cast<Floor?>().firstWhere(
            (f) => f!.key == _defaultFloorKey,
            orElse: () => _floorOptions.firstOrNull,
          );
      _selectedFloorKey = defaultFloor?.key ?? '';
      _floor = defaultFloor?.floor ?? '';
      _anchorLabel = '待选点';
    }
    _loadStoredResults();
  }

  /// 启动时从跨端本地存储恢复暂存的识别结果。
  Future<void> _loadStoredResults() async {
    final raw = await LocalStorage.instance.readDoc(_storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        setState(() {
          _storedResults =
              decoded.whereType<Map<String, dynamic>>().toList();
        });
      }
    } catch (_) {
      // 损坏数据忽略，不阻塞页面。
    }
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _drawingTransform.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// 图纸区缩放：每次按固定倍率，限制在 0.8~8 之间。
  void _zoomDrawing(double factor) {
    final current = _drawingTransform.value.getMaxScaleOnAxis();
    final target = (current * factor).clamp(0.8, 8.0);
    if (target == current) return;
    _drawingTransform.value = Matrix4.identity()..scale(target);
  }

  void _resetDrawingZoom() => _drawingTransform.value = Matrix4.identity();

  // —— 流程步骤控制 ——
  /// 按当前项目返回可选图纸列表（避免串图）。
  List<Floor> get _floorOptions =>
      _projectId == tencentProject.id ? dy7Floors : floors;

  /// 当前项目默认图纸 key（地下一层平面图），用于“重选图纸”后回到默认视图。
  String get _defaultFloorKey {
    const defaults = <String, String>{
      'tencent-dy04-7': 'dy04_7_B05', // 地下室夹层组合平面图（B05 PDF 底图）
      'nkf': 'nkf_west_1f',           // 西楼一层平面图（建施报_06_V1.0_西楼一层平面图）
      'sustech': 'sustech_west_1f',
    };
    return defaults[_projectId] ?? _floorOptions.firstOrNull?.key ?? '';
  }

  /// 当前已选图纸对象（按 key 匹配，未选时返回 null）。
  Floor? get _selectedFloor {
    if (_selectedFloorKey.isEmpty) return null;
    return _floorOptions
        .cast<Floor?>()
        .firstWhere((f) => f!.key == _selectedFloorKey, orElse: () => null);
  }

  /// 图纸显示名称：同一名称存在多个 key 时，用 key 后缀区分，避免下方选项重复。
  String _floorLabel(Floor f) {
    final sameNameCount =
        _floorOptions.where((x) => x.name == f.name).length;
    if (sameNameCount > 1) {
      return '${f.name} (${f.key.toUpperCase()})';
    }
    return f.name;
  }

  /// 选中平面 → 进入选坐标步骤。
  void _selectFloor(Floor f) {
    final d = _resolveDrawing(ref.read(drawingsProvider).valueOrNull ?? {});
    setState(() {
      _selectedFloorKey = f.key;
      _floor = f.floor;
      _drawing = d;
      _remotePngUrl = null;
      _remotePngError = null;
      _step = _CaptureStep.selectPoint;
      _anchorLabel = '待选点';
      _x = 0.5;
      _y = 0.5;
    });
    // 若本地无 PNG 但有 CAD OCF key，则尝试从服务端生成/加载 PNG 底图。
    if (d != null && d.src.isEmpty && (d.cadOcfKey?.isNotEmpty ?? false)) {
      _ensureRemotePng(d);
    }
  }

  /// 从 CAD 服务请求 OCF 转 PNG。服务器会自动缓存，后续直接走 /api/ocf/{key}.png。
  Future<void> _ensureRemotePng(Drawing d) async {
    if (_remotePngLoading) return;
    setState(() {
      _remotePngLoading = true;
      _remotePngError = null;
    });
    try {
      final url = await CadService().saveOcfAsImage(d.cadOcfKey!);
      if (mounted) {
        setState(() {
          _remotePngUrl = url.startsWith('http') ? url : '${CadService.host}$url';
          _remotePngLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _remotePngError = e.toString();
          _remotePngLoading = false;
        });
      }
    }
  }

  // —— 图纸坐标换算 ——
  String get _drawingKey {
    if (_selectedFloorKey.isNotEmpty) return _selectedFloorKey;
    final argsKey = widget.args.drawingKey;
    if (argsKey != null && argsKey.isNotEmpty) return argsKey;
    return floorToDrawingKey(_floor);
  }

  Drawing? _resolveDrawing(Map<String, Drawing> projectMap) {
    final key = _drawingKey;
    if (key.isEmpty) return null;
    return projectMap[key] ?? dy7Drawings[key] ?? drawings[key];
  }

  double get _ratio =>
      _drawing == null ? 1.0 : (_drawing!.h / _drawing!.w).clamp(0.6, 1.0);

  void _onTapDrawing(Offset local, Size size) {
    final nx = (local.dx / size.width).clamp(0.02, 0.98).toDouble();
    final ny = (local.dy / size.height).clamp(0.02, 0.98).toDouble();
    final inSelectStep = _step == _CaptureStep.selectPoint;
    setState(() {
      _x = nx;
      _y = ny;
      _anchorLabel = '已选点';
      _snapToNearestAnchor();
      // 选点完成后直接进入拍照步骤，由圆快门负责实际拍照，
      // 避免与「开始拍照」按钮/圆按钮重复触发相机。
      if (inSelectStep) _step = _CaptureStep.capture;
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
    } else {
      _anchorLabel = '已选点 (${(_x * 100).toStringAsFixed(0)}%, ${(_y * 100).toStringAsFixed(0)}%)';
    }
  }

  // —— 快门 / 扫描 / 识别 ——
  final ImagePicker _picker = ImagePicker();

  /// 按平台分流取图：
  /// - Web：相册选图（桌面浏览器无法直接调相机，走文件上传）。
  /// - Android/iOS：真实相机，并做原生压缩（maxWidth / imageQuality）。
  ///   移动端提高清晰度（1920/88），验收照片需保留更多细节；Web 保持 1280/82 兼容。
  Future<XFile?> _pickImage() async {
    if (kIsWeb) {
      // Web：相册选图（桌面浏览器无法直接调相机，走文件上传）。
      return _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280.0,
        imageQuality: 82,
      );
    }
    // 移动端：通用相机兜底（权限引导 + 相机失败允改用相册）。
    return pickPhotoRobust(
      context,
      onDenied: _showPermissionGuide,
      maxWidth: 1920.0,
      imageQuality: 88,
    );
  }

  /// 权限被拒绝时，弹窗引导用户前往系统设置开启。
  void _showPermissionGuide() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('需要相机/相册权限'),
        content: const Text('现场拍照验收需要相机与相册权限。请在系统设置中开启后重试。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              AppSettings.openAppSettings();
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  Future<void> _doCapture() async {
    if (_scanning || _committing) return;

    final shot = await _pickImage();
    if (shot == null) {
      if (mounted) AppSnack.show(context, '已取消拍摄');
      return;
    }

    // 拍后预览确认：先展示待确认照片，用户「使用」后再烧录水印 + 识别，
    // 「重拍」可丢弃重来，避免误拍占用流程。
    if (mounted) {
      setState(() {
        _pendingShot = shot;
        _shotPhoto = null;
        _defects = const [];
        _scanError = null;
      });
    }
  }

  /// 取消待确认照片（重拍）。
  void _cancelPending() {
    setState(() => _pendingShot = null);
  }

  /// 确认使用待确认照片：执行烧录水印 + 缺陷识别（原提交流程）。
  Future<void> _commitPhoto() async {
    final shot = _pendingShot;
    if (shot == null || _committing) return;
    setState(() => _committing = true);
    try {
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
          _defects = const [];
          _pendingShot = null;
        });
        AppSnack.show(
          context,
          watermarked != null
              ? '已拍摄并烧录防篡改水印'
              : '已拍摄（水印烧录失败，已保留原图）',
          kind: watermarked != null
              ? AppSnackKind.success
              : AppSnackKind.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _committing = false);
    }
    await _runScan();
  }

  /// 当前拍摄人（复用登录用户姓名）。
  String get _currentUser {
    final u = ref.read(currentUserProvider);
    return u.name;
  }

  /// 严重程度严重性排序：red 最严重（rank 0），green 最轻（rank 3）。
  /// 用于一次拍照多条识别项聚合时取最严重等级。
  static int _severityRank(DefectSeverity s) {
    switch (s) {
      case DefectSeverity.red:
        return 0;
      case DefectSeverity.orange:
        return 1;
      case DefectSeverity.yellow:
        return 2;
      case DefectSeverity.green:
        return 3;
    }
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
                  // A 修复：传真实置信度，低 conf 会在卡片/巡场清单中提示人工复核
                  conf: d.conf,
                  desc: d.desc,
                  // AI 整改建议：模型返回优先，未返回时按缺陷名走本地建议库兜底
                  suggestion: (d.suggestion?.trim().isNotEmpty ?? false)
                      ? d.suggestion
                      : suggestionFor(d.name, d.desc),
                ))
            .toList();
        // 无论模型是否识别到缺陷都出结果（暂存由「保存记录」按钮触发）。
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

  /// 把一条视觉识别结果追加到暂存列表并持久化（跨端）。
  /// 接收页面内的 [VlDefect] 列表（不再依赖 VisionResult），
  /// 无论是否识别到缺陷都会暂存（无缺陷记 count=0，仅留痕）。
  /// 保存当前记录到本地暂存（由「保存记录」按钮触发，不再自动）。
  /// 聚合：水印照片（移动端落盘）、AI 分析结果、用户描述、图纸归属。
  /// 返回 true 表示已执行保存（写入暂存并同步巡场清单），false 表示未满足保存条件。
  Future<bool> _saveRecordToStorage() async {
    if (_shotPhoto == null) {
      if (mounted) {
        AppSnack.show(context, '请先拍照或选择照片', kind: AppSnackKind.danger);
      }
      return false;
    }
    final now = DateTime.now();
    final ts = '${now.year}-${_two(now.month)}-${_two(now.day)} '
        '${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}';
    final note = _noteController.text.trim();
    final entry = <String, dynamic>{
      'id': now.microsecondsSinceEpoch.toString(),
      'drawingKey': _drawingKey,
      'worldX': widget.args.drawPointWorldX,
      'worldY': widget.args.drawPointWorldY,
      'ts': ts,
      'anchor': _anchorLabel,
      'floor': _floor,
      'count': _defects.length,
      'defects': _defects
          .map((d) => {...d.toJson(), 'status': 'pending'})
          .toList(),
      'note': note,
    };
    // 把压缩照片落盘（JSON 不支持二进制，故 entry 只记相对路径）：
    // - 移动端/桌面：写入应用 Documents 目录，可长期保存；
    // - Web：写入会话内存（当前页面刷新前可用），保证「拍照 → 导出报告」链路内
    //   缺陷照片能被报告读取内嵌。
    String? photoRel;
    if (_shotPhoto != null) {
      photoRel = 'photos/${ts.replaceAll(RegExp(r'[:\s]'), '-')}.jpg';
      try {
        await LocalStorage.instance.writeFile(photoRel, _shotPhoto!);
        entry['photo'] = photoRel;
      } catch (_) {
        // 写照片失败不应阻断结构化结果暂存。
        photoRel = null;
      }
    }
    // 打通「拍照记录 → 巡场问题记录」：保存带照片的记录时生成一条问题记录
    // （报告「巡场清单及闭环情况」章节据此渲染现场照片，交付说明增强项 3）。
    //
    // **一次拍照聚合为一条记录**：VL 识别常对同一张现场照返回多条观察（多个问
    // 题），但现场一次观察即一次整改，拆成多条会在报告/列表里重复出现（同时间
    // 同位置同照片）。这里合并为单条 Defect：描述叠加、严重程度取最高、识别项
    // 名称作为标签，照片只挂一次。
    //
    // **没有识别结果也要入列表**：保证拍照留痕可追溯（避免"拍了看不到"）。
    // **照片落盘失败也要入列表**：照片缺失只影响报告配图，记录本身必须同步
    // （photoPath 为空时报告端显示占位）。
    {
      final repo = ref.read(repositoryProvider);
      // 归入当前项目，避免新增记录串到另一个项目。
      if (repo is MockRepository) {
        repo.currentIs7 = ref.read(is7DongProjectProvider);
      }
      final gpsText = _location.gpsText;
      final altText = '海拔 ${_location.altitude.toStringAsFixed(1)}m';
      final anchor = '$_anchorLabel · $_floor';
      final names = _defects
          .map((v) => v.name)
          .where((n) => n.isNotEmpty)
          .toList();
      final descs = _defects
          .map((v) => v.desc ?? '')
          .where((d) => d.isNotEmpty)
          .toList();
      // 严重程度取最高（rank 越小越严重）；无识别结果时降级为「暂未发现问题」
      final sev = _defects.isEmpty
          ? DefectSeverity.green
          : _defects
              .map((v) => v.severity)
              .reduce((a, b) => _severityRank(a) <= _severityRank(b) ? a : b);
      final primary = names.isNotEmpty ? names.first : '现场拍照记录';
      final mergedNote = [
        if (_defects.isEmpty) '本次拍照未识别出缺陷（仅现场留痕）',
        if (photoRel == null) '照片未落盘，仅保留现场记录信息',
        descs.join('；'),
        note,
      ].where((s) => s.isNotEmpty).join('\n');
      // AI 整改建议聚合（给施工单位）：多条建议按「缺陷名：建议」合并。
      final mergedSuggestion = [
        for (final v in _defects)
          if ((v.suggestion ?? '').trim().isNotEmpty)
            names.length > 1 ? '${v.name}：${v.suggestion!}' : v.suggestion!,
      ].join('\n');
      await repo.addDefect(Defect(
        id: 'cap_${now.microsecondsSinceEpoch}',
        part: names.length > 1
            ? '${anchor}·${primary}等${names.length}项'
            : '${anchor}·${primary}',
        type: primary,
        category: DefectCategory.other,
        severity: sev,
        status: DefectStatus.draft,
        anchor: anchor,
        floor: _floor,
        ts: ts,
        gps: gpsText,
        alt: altText,
        resp: '待指派',
        reporter: _currentUser,
        tags: ['拍照记录', ...names],
        note: mergedNote,
        seed: 'capture',
        drawingKey: _drawingKey,
        worldX: widget.args.drawPointWorldX,
        worldY: widget.args.drawPointWorldY,
        photoPath: photoRel,
        suggestion: mergedSuggestion.isEmpty ? null : mergedSuggestion,
      ));
      // 刷新缺陷列表，使「巡场清单」tab 立即出现新记录。
      ref.invalidate(defectsProvider);
    }
    setState(() {
      _storedResults = [entry, ..._storedResults];
    });
    // 跨端持久化：移动端落 Hive、Web 落 localStorage（不阻塞 UI）。
    unawaited(
      LocalStorage.instance
          .writeDoc(_storageKey, jsonEncode(_storedResults))
          .catchError((_) {}),
    );
    if (mounted) {
      AppSnack.show(
        context,
        _defects.isEmpty ? '记录已保存（未分析）' : '记录已保存',
        kind: AppSnackKind.brand,
      );
    }
    return true;
  }

  void _retake() {
    _scanTimer?.cancel();
    setState(() {
      _shotPhoto = null;
      _defects = const [];
      _scanError = null;
      _scanning = false;
      _saved = false;
    });
    AppSnack.show(context, '已重拍，请再次拍摄/分析后保存');
  }

  void _addPoint() {
    AppSnack.show(context, '加点：已在该位置临时标记部位（可拖拽准星微调）', kind: AppSnackKind.brand);
  }

  void _annotate() {
    AppSnack.show(context, '标注功能预留：后续支持圈选/语音备注', kind: AppSnackKind.brand);
  }

  /// 「保存记录」按钮：把当前记录写入本地暂存；识别出缺陷时同时生成巡场清单记录
  /// （带现场照片，供「导出报告」渲染缺陷照片）。
  ///
  /// 仅在真正执行了保存后才锁定按钮；首次误触（未拍照）不锁定，允许补拍后再存。
  Future<void> _saveRecord() async {
    if (_scanning) return;
    if (_saved) return;
    final ok = await _saveRecordToStorage();
    if (ok && mounted) {
      setState(() => _saved = true);
    }
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
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.fg)),
          centerTitle: false,
          backgroundColor: AppTokens.bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          actions: [
            // TODO: 待删 —— Mock 开关（_useMock）仅为联调/验证 UI 用，正式环境移除。
            // Padding(
            //   padding: const EdgeInsets.only(right: AppTokens.space3),
            //   child: Row(
            //     children: [
            //       Text('Mock',
            //           style: TextStyle(
            //               fontSize: 12,
            //               fontWeight: FontWeight.w400,
            //               color:
            //                   _useMock ? AppTokens.accent : AppTokens.muted)),
            //       const SizedBox(width: 4),
            //       Switch(
            //         value: _useMock,
            //         onChanged: (v) => setState(() => _useMock = v),
            //         activeThumbColor: AppTokens.accent,
            //       ),
            //     ],
            //   ),
            // ),
          ],
        ),
        body: Column(
          children: [
            _buildAnchorBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    AppTokens.space3, AppTokens.space2, AppTokens.space3, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildDrawingStage(),
                    const SizedBox(height: AppTokens.space3),
                    _buildStepPanel(),
                    const SizedBox(height: AppTokens.space3),
                    _buildWatermark(),
                    const SizedBox(height: AppTokens.space3),
                    _buildPhotoPanel(),
                    if (_defects.isNotEmpty) ...[
                      const SizedBox(height: AppTokens.space3),
                      _buildDefectSection(),
                    ],
                    const SizedBox(height: AppTokens.space3),
                    _buildNoteField(),
                    const SizedBox(height: AppTokens.space3),
                    _buildScaleCheckSection(),
                    const SizedBox(height: AppTokens.space3),
                    _buildControls(),
                    const SizedBox(height: AppTokens.space3),
                    _buildStoredResults(),
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
  Widget _buildAnchorBar() {
    final currentDrawingName = _selectedFloor?.name ?? '—';
    final subtitle = _step == _CaptureStep.selectFloor
        ? '请选择图纸与具体部位'
        : '$_anchorLabel · $currentDrawingName';
    return Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(
            AppTokens.space3, AppTokens.space2, AppTokens.space3, 0),
        padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.space3, vertical: AppTokens.space3),
        decoration: BoxDecoration(
          color: AppTokens.surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
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
                      text: _step == _CaptureStep.selectFloor
                          ? '待选择'
                          : _anchorLabel,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTokens.fg),
                    ),
                    TextSpan(
                      text: ' · $subtitle',
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
  }

  /// 无 PNG 底图时的占位图，可展示错误信息并提供重试。
  Widget _buildMissingPngPlaceholder(String? error) {
    return Container(
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: AppTokens.border),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.fileX, size: 48, color: AppTokens.muted),
          const SizedBox(height: AppTokens.space2),
          Text(
            _remotePngLoading ? '正在生成 PNG 底图…' : '该图纸暂无 PNG 底图',
            style: TextStyle(
              color: AppTokens.muted,
              fontWeight: FontWeight.w600,
            ),
            ),
            if (error != null && error.isNotEmpty && !_remotePngLoading) ...[
            const SizedBox(height: AppTokens.space1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTokens.space4),
              child: Text(
                error,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppTokens.danger),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ],
            if (!_remotePngLoading &&
              (_drawing?.cadOcfKey?.isNotEmpty ?? false)) ...[
            const SizedBox(height: AppTokens.space2),
            TextButton.icon(
              onPressed: () => _ensureRemotePng(_drawing!),
              icon: Icon(LucideIcons.refreshCw, size: 14, color: AppTokens.accent),
              label: Text('重新生成', style: TextStyle(color: AppTokens.accent)),
            ),
          ],
        ],
      ),
    );
  }

  /// 图纸 + 图钉 + 准星交互区（支持双指/滚轮缩放）。
  Widget _buildDrawingStage() {
    final stepHint = _step == _CaptureStep.selectFloor
        ? '请先选择下方图纸，再进入图纸选点'
        : '点击图纸选点，将自动吸附最近锚点';
    return AspectRatio(
      aspectRatio: 1 / _ratio,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final box = constraints.biggest;
          return Stack(
            children: [
              InteractiveViewer(
                transformationController: _drawingTransform,
                minScale: 0.8,
                maxScale: 8.0,
                boundaryMargin: const EdgeInsets.all(40),
                child: SizedBox(
                  width: box.width,
                  height: box.height,
                  child: GestureDetector(
                    onTapUp: _step == _CaptureStep.selectFloor
                        ? null
                        : (d) => _onTapDrawing(d.localPosition, box),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_drawing != null && _drawing!.src.isNotEmpty)
                          ClipRRect(
                            borderRadius:
                                BorderRadius.circular(AppTokens.radiusLg),
                            child: Image.asset(
                              _drawing!.src,
                              fit: BoxFit.fill,
                              filterQuality: FilterQuality.medium,
                            ),
                          )
                        else if (_drawing != null &&
                            _drawing!.src.isEmpty &&
                            _remotePngUrl != null)
                          ClipRRect(
                            borderRadius:
                                BorderRadius.circular(AppTokens.radiusLg),
                            child: Image.network(
                              _remotePngUrl!,
                              fit: BoxFit.fill,
                              filterQuality: FilterQuality.medium,
                              loadingBuilder: (context, child, progress) =>
                                  progress == null
                                      ? child
                                      : Container(
                                          alignment: Alignment.center,
                                          child: CircularProgressIndicator(
                                            value: progress.expectedTotalBytes !=
                                                    null
                                                ? progress.cumulativeBytesLoaded /
                                                    progress.expectedTotalBytes!
                                                : null,
                                          ),
                                        ),
                              errorBuilder: (context, error, stackTrace) =>
                                  _buildMissingPngPlaceholder(error.toString()),
                            ),
                          )
                        else if (_drawing != null && _drawing!.src.isEmpty)
                          _buildMissingPngPlaceholder(_remotePngError)
                        else
                          Container(
                            decoration: BoxDecoration(
                              color: AppTokens.surface,
                              borderRadius:
                                  BorderRadius.circular(AppTokens.radiusLg),
                              border: Border.all(color: AppTokens.border),
                            ),
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.map,
                                    size: 48, color: AppTokens.muted),
                                const SizedBox(height: AppTokens.space2),
                                Text('未选择图纸',
                                    style: TextStyle(
                                        color: AppTokens.muted,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        // 半透明遮罩，突出蓝图观感
                        if (_drawing != null &&
                            (_drawing!.src.isNotEmpty ||
                                _remotePngUrl != null))
                          Container(
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(AppTokens.radiusLg),
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
                        if (_drawing != null &&
                            (_drawing!.src.isNotEmpty ||
                                _remotePngUrl != null))
                          ..._anchors.map((a) => _buildPin(a)),
                        // 准星选点（仅在已选图纸且处于选点/拍照步骤时显示）
                        if (_drawing != null &&
                            _step != _CaptureStep.selectFloor) ...[
                          _buildCrosshair(),
                          _buildPickPin(),
                        ],
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
                              borderRadius:
                                  BorderRadius.circular(AppTokens.radiusPill),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(LucideIcons.mousePointerClick,
                                    size: 12, color: Colors.white),
                                const SizedBox(width: 6),
                                Text(stepHint,
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                        // 扫描动画
                        if (_scanning) _buildScanOverlay(),
                      ],
                    ),
                  ),
                ),
              ),
              // 缩放控制按钮（浮在图纸之上，保持不随图纸缩放）
              Positioned(
                top: 8,
                right: 8,
                child: _ZoomToolbar(
                  onZoomIn: () => _zoomDrawing(1.2),
                  onZoomOut: () => _zoomDrawing(1 / 1.2),
                  onReset: _resetDrawingZoom,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 步骤面板：选平面 / 选坐标 / 拍照。
  Widget _buildStepPanel() {
    switch (_step) {
      case _CaptureStep.selectFloor:
        return _buildFloorSelector();
      case _CaptureStep.selectPoint:
        return _buildPointConfirm();
      case _CaptureStep.capture:
        return _buildCaptureInfo();
    }
  }

  /// 步骤 ①：选择平面（楼层）。
  Widget _buildFloorSelector() {
    return Card(
      color: AppTokens.surface,
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(LucideIcons.layers, size: 16, color: AppTokens.accent),
                SizedBox(width: AppTokens.space2),
                Text('选择图纸',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: AppTokens.space2),
            Wrap(
              spacing: AppTokens.space2,
              runSpacing: AppTokens.space2,
              children: _floorOptions.map((f) {
                return ChoiceChip(
                  label: Text(_floorLabel(f)),
                  selected: _selectedFloorKey == f.key,
                  onSelected: (_) => _selectFloor(f),
                  selectedColor: AppTokens.accent.withOpacity(0.2),
                  labelStyle: TextStyle(
                    color: _selectedFloorKey == f.key
                        ? AppTokens.accent
                        : AppTokens.fg,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  /// 步骤 ②：确认图纸上选中的部位。
  Widget _buildPointConfirm() {
    return Card(
      color: AppTokens.surface,
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.mapPin,
                    size: 16, color: AppTokens.accent),
                const SizedBox(width: AppTokens.space2),
                Expanded(
                  child: Text('已选部位：${_anchorLabel}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.space1),
            Text('在图纸上点击可重新选择部位',
                style: TextStyle(fontSize: 12, color: AppTokens.muted)),
            const SizedBox(height: AppTokens.space3),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  final defaultFloor = _floorOptions.cast<Floor?>().firstWhere(
                        (f) => f!.key == _defaultFloorKey,
                        orElse: () => _floorOptions.firstOrNull,
                      );
                  setState(() {
                    _step = _CaptureStep.selectFloor;
                    _selectedFloorKey = defaultFloor?.key ?? '';
                    _floor = defaultFloor?.floor ?? '';
                    _anchorLabel = '待选点';
                    _drawing = _resolveDrawing(
                        ref.read(drawingsProvider).valueOrNull ?? {});
                    _remotePngUrl = null;
                    _remotePngError = null;
                  });
                  if (_drawing != null &&
                      _drawing!.src.isEmpty &&
                      (_drawing!.cadOcfKey?.isNotEmpty ?? false)) {
                    _ensureRemotePng(_drawing!);
                  }
                },
                icon: const Icon(LucideIcons.arrowLeft, size: 16),
                label: const Text('重选图纸'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 步骤 ③：拍照阶段信息条。
  Widget _buildCaptureInfo() {
    return Card(
      color: AppTokens.surface,
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.space3),
        child: Row(
          children: [
            const Icon(LucideIcons.camera, size: 16, color: AppTokens.accent),
            const SizedBox(width: AppTokens.space2),
            Expanded(
              child: Text('${_drawing?.title ?? '—'} · ${_anchorLabel}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            TextButton.icon(
              onPressed: () => setState(() => _step = _CaptureStep.selectPoint),
              icon: const Icon(LucideIcons.arrowLeft, size: 14),
              label: const Text('重选', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
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
          padding: const EdgeInsets.all(AppTokens.space3),
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
                          fontWeight: FontWeight.w600,
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

  /// 选点图钉：在当前选点 (_x,_y) 处渲染固定图钉。
  Widget _buildPickPin() {
    return Positioned.fill(
      child: Align(
        alignment: Alignment(_x * 2 - 1, _y * 2 - 1),
        child: IgnorePointer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                ),
                child: Text(
                  _anchorLabel,
                  style: const TextStyle(fontSize: 10, color: Colors.white, height: 1.2),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: AppTokens.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: AppTokens.accent.withValues(alpha: 0.6),
                      blurRadius: 8,
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
              horizontal: AppTokens.space5, vertical: AppTokens.space3),
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
                      fontWeight: FontWeight.w600,
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

  // ============ 量尺校对（实测 vs 图纸标注） ============

  /// 量尺校对区块：列出各构件实测/图纸尺寸，按容差判定合格，并显示当前图纸标定比例。
  Widget _buildScaleCheckSection() {
    final passCount = _scaleChecks.where((c) => c.pass(_tolMm, _tolPct)).length;
    final total = _scaleChecks.length;
    final rate = total == 0 ? 0.0 : passCount / total * 100;
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
              const Icon(LucideIcons.ruler, size: 14, color: AppTokens.accent),
              const SizedBox(width: 6),
              const Text('拍照量尺校对',
                  style:
                      TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              TextButton.icon(
                onPressed: () async {
                  final projectId =
                      ref.read(currentProjectIdProvider) ??
                          (await ref.read(projectProvider.future)).id;
                  if (!mounted) return;
                  context.push(
                    '/measure',
                    extra: MeasureArgs(
                      projectKey: projectId,
                      drawingKey: _drawingKey,
                      floor: _floor,
                    ),
                  );
                },
                icon: const Icon(LucideIcons.ruler, size: 14),
                label: const Text('智能量尺校对',
                    style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: AppTokens.accent,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const Spacer(),
              if (total > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: passCount == total
                        ? AppTokens.success.withValues(alpha: 0.12)
                        : AppTokens.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '合格 $passCount/$total · ${rate.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: passCount == total
                          ? AppTokens.success
                          : AppTokens.warning,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppTokens.space2),
          // 当前图纸标定比例（mm/px）—— 把"实测"和"图纸坐标/真实尺寸"关联起来
          if (_scaleMmPerPx != null)
            Container(
              margin: const EdgeInsets.only(bottom: AppTokens.space2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTokens.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              ),
              child: Text.rich(
                TextSpan(
                  text: '当前图纸标定比例：',
                  style:
                      const TextStyle(fontSize: 11, color: AppTokens.muted),
                  children: [
                    TextSpan(
                      text: '${_scaleMmPerPx!.toStringAsFixed(4)} mm/px',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTokens.accent),
                    ),
                    const TextSpan(
                        text: '  （照片像素↔真实尺寸）',
                        style: TextStyle(fontSize: 11, color: AppTokens.muted)),
                  ],
                ),
              ),
            ),
          // 容差设置
          _buildToleranceRow(),
          const SizedBox(height: AppTokens.space2),
          if (total == 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('尚未添加量尺项。点击「+ 添加量尺项」，录入现场实测与图纸标注尺寸进行比对。',
                  style: TextStyle(fontSize: 12, color: AppTokens.muted)),
            )
          else
            ..._scaleChecks.asMap().entries.map((e) {
              final i = e.key;
              final c = e.value;
              final ok = c.pass(_tolMm, _tolPct);
              return _buildScaleCheckCard(i, c, ok);
            }),
          const SizedBox(height: AppTokens.space2),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _addScaleCheck,
              icon: const Icon(LucideIcons.plus, size: 14),
              label: const Text('添加量尺项',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTokens.accent,
                side: BorderSide(color: AppTokens.accent.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppTokens.radiusMd)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToleranceRow() {
    return Row(
      children: [
        const Text('容差',
            style: TextStyle(fontSize: 12, color: AppTokens.muted)),
        const SizedBox(width: 6),
        Expanded(
          child: _tolField('±', _tolMm, 'mm', (v) => setState(() => _tolMm = v)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _tolField('±', _tolPct, '%', (v) => setState(() => _tolPct = v)),
        ),
      ],
    );
  }

  Widget _tolField(
      String prefix, double value, String unit, ValueChanged<double> onChanged) {
    final ctrl = TextEditingController(text: value.toStringAsFixed(0));
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppTokens.bg,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        border: Border.all(color: AppTokens.border),
      ),
      child: Row(
        children: [
          Text(prefix,
              style: const TextStyle(fontSize: 12, color: AppTokens.muted)),
          const SizedBox(width: 2),
          Expanded(
            child: TextField(
              controller: ctrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                hintText: '0',
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: (s) =>
                  onChanged(double.tryParse(s) ?? 0),
            ),
          ),
          Text(' $unit',
              style: const TextStyle(fontSize: 12, color: AppTokens.muted)),
        ],
      ),
    );
  }

  Widget _buildScaleCheckCard(int index, ScaleCheck c, bool ok) {
    final dev = c.deviation;
    final devPct = c.deviationPct;
    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.space2),
      padding: const EdgeInsets.all(AppTokens.space2),
      decoration: BoxDecoration(
        color: AppTokens.bg,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: AppTokens.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _textField(c.name, '量尺项（如 梁宽）',
                    (v) => _updateCheck(index, c.copyWith(name: v))),
              ),
              IconButton(
                onPressed: () => setState(() => _scaleChecks.removeAt(index)),
                icon: const Icon(LucideIcons.trash2,
                    size: 16, color: AppTokens.danger),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: AppTokens.space2),
          Row(
            children: [
              Expanded(
                child: _numField(c.measuredMm.toStringAsFixed(0), '实测 mm',
                    (v) => _updateCheck(index, c.copyWith(measuredMm: v)),
                    isDouble: true),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _numField(c.drawingMm.toStringAsFixed(0), '图纸 mm',
                    (v) => _updateCheck(index, c.copyWith(drawingMm: v)),
                    isDouble: true),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: ok
                      ? AppTokens.success.withValues(alpha: 0.12)
                      : AppTokens.danger.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                ),
                child: Column(
                  children: [
                    Icon(ok ? LucideIcons.check : LucideIcons.x,
                        size: 14,
                        color: ok ? AppTokens.success : AppTokens.danger),
                    Text(ok ? '合格' : '超差',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: ok ? AppTokens.success : AppTokens.danger)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.space1),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '偏差 ${dev >= 0 ? '+' : ''}${dev.toStringAsFixed(1)}mm'
              '（${devPct >= 0 ? '+' : ''}${devPct.toStringAsFixed(1)}%）',
              style: TextStyle(
                fontSize: 11,
                color: ok ? AppTokens.muted : AppTokens.danger,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _numField(String initial, String hint, ValueChanged<double> onChanged,
      {bool isDouble = false}) {
    final ctrl = TextEditingController(text: initial);
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        border: Border.all(color: AppTokens.border),
      ),
      child: TextField(
        controller: ctrl,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true, signed: true),
        inputFormatters: isDouble
            ? [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*'))]
            : [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 12, color: AppTokens.muted),
        ),
        style: const TextStyle(fontSize: 13),
        onChanged: (s) => onChanged(double.tryParse(s) ?? 0),
      ),
    );
  }

  void _updateCheck(int index, ScaleCheck c) {
    if (index < 0 || index >= _scaleChecks.length) return;
    setState(() => _scaleChecks[index] = c);
  }

  void _addScaleCheck() {
    setState(() => _scaleChecks.add(
        const ScaleCheck(name: '', measuredMm: 0, drawingMm: 0)));
  }

  Widget _textField(
      String initial, String hint, ValueChanged<String> onChanged) {
    final ctrl = TextEditingController(text: initial);
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        border: Border.all(color: AppTokens.border),
      ),
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 12, color: AppTokens.muted),
        ),
        style: const TextStyle(fontSize: 13),
        onChanged: onChanged,
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
                              fontWeight: FontWeight.w400,
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
                if (d.suggestion != null && d.suggestion!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTokens.brandTint,
                      borderRadius:
                          BorderRadius.circular(AppTokens.radiusSm),
                    ),
                    child: Text('AI整改建议：${d.suggestion!}',
                        style: const TextStyle(
                            fontSize: 12, height: 1.45, color: AppTokens.fg)),
                  ),
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
    // 置信度标签统一走设计规范语义色 + 原色 5% 浅底。
    if (conf >= 0.8) {
      return const _ConfBucket('高', AppTokens.success, AppTokens.successTint);
    }
    if (conf >= 0.5) {
      return const _ConfBucket('中', AppTokens.warning, AppTokens.warningTint);
    }
    return const _ConfBucket('低', AppTokens.danger, AppTokens.dangerTint);
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
                          fontWeight: FontWeight.w600,
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
          const SizedBox(width: AppTokens.space3),
          const Icon(MingCuteIcons.spaceLine,
              size: 12, color: Colors.white70),
          const SizedBox(width: 4),
          Text(_location.gpsText,
              style: const TextStyle(fontSize: 10, color: Colors.white70)),
          const SizedBox(width: AppTokens.space3),
          const Icon(MingCuteIcons.dashboard2Line,
              size: 12, color: Colors.white70),
          const SizedBox(width: 4),
          const Text('18.2m',
              style: TextStyle(fontSize: 10, color: Colors.white70)),
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
          padding: const EdgeInsets.all(AppTokens.space3),
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
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
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
                          fontWeight: FontWeight.w600,
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
                    fontWeight: FontWeight.w400,
                    color: selected ? AppTokens.brand : AppTokens.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  /// 照片预览面板（图纸下方独立卡片）：
  /// 拍后确认卡 → 拍照控制行（加点/快门/重拍/标注）→ 已拍大图 → AI 分析按钮。
  Widget _buildPhotoPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.space3),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1) 拍后确认卡（在 AI 分析之前，提示"重拍 / 使用"）
          if (_pendingShot != null) _buildPendingPreview(),
          // 2) 拍照控制行：两端控件 + 中央快门（Stack 叠放让快门始终水平居中）
          SizedBox(
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 底层：左「加点」+ 右「重拍 / 标注」
                Row(
                  children: [
                    _buildControlBtn(LucideIcons.plus, '加点', _addPoint),
                    const Spacer(),
                    _buildControlBtn(LucideIcons.rotateCcw, '重拍', _retake),
                    _buildControlBtn(LucideIcons.penTool, '标注', _annotate),
                  ],
                ),
                // 顶层：快门圆按钮水平居中
                _buildShutter(),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.space3),
          if (_shotPhoto == null)
            const Row(
              children: [
                Icon(LucideIcons.image, size: 16, color: AppTokens.muted),
                SizedBox(width: AppTokens.space2),
                Expanded(
                  child: Text('尚未拍摄：按下快门或选择照片后，可点「AI 分析」',
                      style: TextStyle(fontSize: 13, color: AppTokens.muted)),
                ),
              ],
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              child: Image.memory(
                _shotPhoto!,
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: AppTokens.space2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _scanError ??
                        (_defects.isEmpty
                            ? '已拍摄，等待识别…'
                            : '已识别 ${_defects.length} 处缺陷'),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _scanError != null
                            ? const Color(0xFFDC2626)
                            : AppTokens.fg),
                  ),
                ),
                TextButton(
                  onPressed: _retake,
                  child: const Text('重拍 / 重选',
                      style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppTokens.space2),
          // 3) AI 分析按钮（点击才调用，未拍照置灰）
          SizedBox(
            width: double.infinity,
            child: AppButton(
              label: _scanning ? '分析中…' : 'AI 分析',
              onPressed: (_shotPhoto == null || _scanning) ? null : _runScan,
            ),
          ),
        ],
      ),
    );
  }

  /// 问题描述输入区：手打文本框 + 语音录入（结果追加到 note）。
  Widget _buildNoteField() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.space3),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('问题描述',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.fg)),
          const SizedBox(height: AppTokens.space2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _noteController,
                  maxLines: 3,
                  minLines: 1,
                  style: const TextStyle(fontSize: 13, color: AppTokens.fg),
                  decoration: InputDecoration(
                    hintText: '记录现场情况，或点右侧麦克风语音输入…',
                    hintStyle:
                        TextStyle(fontSize: 12, color: AppTokens.muted),
                    filled: true,
                    fillColor: AppTokens.surface2,
                    contentPadding: const EdgeInsets.all(AppTokens.space2),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppTokens.radiusMd),
                      borderSide: BorderSide(color: AppTokens.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppTokens.radiusMd),
                      borderSide: BorderSide(color: AppTokens.border),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppTokens.space2),
              VoiceInputButton(
                holdToTalk: false,
                size: 44,
                iconSize: 20,
                onResult: (t) {
                  final cur = _noteController.text;
                  _noteController.text =
                      cur.isEmpty ? t : '$cur${cur.endsWith(' ') ? '' : ' '}$t';
                  _noteController.selection = TextSelection.fromPosition(
                    TextPosition(offset: _noteController.text.length),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 「保存记录」主按钮（仅拍照步骤显示）。
  Widget _buildControls() {
    if (_step != _CaptureStep.capture) return const SizedBox.shrink();
    return SizedBox(
      width: double.infinity,
      child: AppButton(
        size: AppButtonSize.lg,
        width: double.infinity,
        label: _saved ? '已保存（可继续拍摄）' : '保存记录',
        onPressed: _saved ? null : _saveRecord,
      ),
    );
  }

  /// 当前图纸的拍照记录列表（按 drawingKey 过滤）。
  List<Map<String, dynamic>> get _filteredStoredResults =>
      _storedResults.where((e) => (e['drawingKey'] as String? ?? '') == _drawingKey).toList();

  /// 拍照记录列表（按当前图纸筛选，置于页内底部）。
  Widget _buildStoredResults() {
    final items = _filteredStoredResults;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
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
              const Text('本图纸拍照记录',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTokens.fg)),
              const Spacer(),
              Text('${items.length} 条',
                  style: const TextStyle(fontSize: 11, color: AppTokens.muted)),
            ],
          ),
          const SizedBox(height: AppTokens.space2),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('本图纸暂无拍照记录',
                  style: TextStyle(fontSize: 12, color: AppTokens.muted)),
            )
          else
            ...items.map((e) => _buildStoredResultTile(e)),
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
    final note = (e['note'] as String? ?? '').trim();
    return InkWell(
      onTap: () => _openStoredDetail(e),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStoredPhoto(e),
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
                Text(
                  '识别 $count 处缺陷 · $names'
                  '${note.isNotEmpty ? ' · 含描述' : ''}',
                  style:
                      const TextStyle(fontSize: 11, color: AppTokens.muted)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            color: AppTokens.muted,
            tooltip: '删除该暂存记录',
            visualDensity: VisualDensity.compact,
            onPressed: () => _confirmDeleteStored(e),
          ),
        ],
      ),
      ),
    );
  }

  /// 删除暂存条目前二次确认（避免误删照片文件）。
  Future<void> _confirmDeleteStored(Map<String, dynamic> e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除暂存记录'),
        content: const Text('将同时删除该记录及关联照片，确定？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) await _deleteStoredResult(e);
  }

  /// 删除一条暂存记录：从列表移除、重写本地文档，并清理移动端照片文件。
  Future<void> _deleteStoredResult(Map<String, dynamic> e) async {
    final photo = e['photo'] as String?;
    setState(() {
      _storedResults =
          _storedResults.where((x) => !identical(x, e)).toList();
    });
    unawaited(
      LocalStorage.instance
          .writeDoc(_storageKey, jsonEncode(_storedResults))
          .catchError((_) {}),
    );
    // 移动端：回收已落盘的照片文件，避免占用 Documents 空间。
    if (photo != null) {
      unawaited(
        LocalStorage.instance.deleteFile(photo).catchError((_) {}),
      );
    }
    if (mounted) {
      AppSnack.show(context, '已删除该暂存记录', kind: AppSnackKind.brand);
    }
  }

  /// 暂存条目的照片缩略图：移动端从 LocalStorage 读文件，Web 无图则不显示。
  Widget _buildStoredPhoto(Map<String, dynamic> e) {
    final rel = e['photo'] as String?;
    if (rel == null) return const SizedBox.shrink();
    return FutureBuilder<Uint8List?>(
      future: LocalStorage.instance.readFile(rel),
      builder: (ctx, snap) {
        final bytes = snap.data;
        if (bytes == null || bytes.isEmpty) return const SizedBox.shrink();
        return Container(
          width: 56,
          height: 56,
          margin: const EdgeInsets.only(right: AppTokens.space2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            border: Border.all(color: AppTokens.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.memory(bytes, fit: BoxFit.cover),
        );
      },
    );
  }

  /// 打开拍照记录详情底部弹层。
  void _openStoredDetail(Map<String, dynamic> e) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => StoredDetailSheet(
        entry: e,
        onDelete: () => _confirmDeleteStored(e),
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
            Text(label,
                style:
                    const TextStyle(fontSize: 11, color: AppTokens.note)),
          ],
        ),
      ),
    );
  }

  /// 拍后预览确认卡片：展示刚拍的照片，提供「重拍 / 使用」。
  Widget _buildPendingPreview() {
    final shot = _pendingShot!;
    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.space3),
      padding: const EdgeInsets.all(AppTokens.space3),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: AppTokens.brand.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.circleCheck,
                  size: 16, color: AppTokens.brand),
              const SizedBox(width: AppTokens.space2),
              const Text('拍照完成，请确认',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const Spacer(),
              if (_committing)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: AppTokens.space2),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            child: FutureBuilder<Uint8List>(
              future: shot.readAsBytes(),
              builder: (ctx, snap) => snap.hasData
                  ? Image.memory(snap.data!,
                      height: 200, width: double.infinity, fit: BoxFit.cover)
                  : const SizedBox(
                      height: 200,
                      child: Center(child: CircularProgressIndicator())),
            ),
          ),
          const SizedBox(height: AppTokens.space3),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _committing ? null : _cancelPending,
                  icon: const Icon(LucideIcons.rotateCcw, size: 16),
                  label: const Text('重拍'),
                ),
              ),
              const SizedBox(width: AppTokens.space3),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _committing ? null : _commitPhoto,
                  icon: const Icon(LucideIcons.check, size: 16),
                  label: const Text('使用'),
                ),
              ),
            ],
          ),
        ],
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

/// 悬浮缩放工具条（拍照验收 / 量尺页复用）。
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

/// 拍照记录详情底部弹层：照片 + AI 结果 + 描述 + 删除。
class StoredDetailSheet extends StatelessWidget {
  final Map<String, dynamic> entry;
  final VoidCallback onDelete;

  const StoredDetailSheet({
    super.key,
    required this.entry,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final defects = (entry['defects'] as List? ?? const [])
        .map((d) => d is Map<String, dynamic> ? d : const <String, dynamic>{})
        .toList();
    final count = entry['count'] as int? ?? defects.length;
    final note = (entry['note'] as String? ?? '').trim();
    final photo = entry['photo'] as String?;

    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scroll) => SingleChildScrollView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 拖拽条
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppTokens.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // 头部：部位·楼层·时间 + 关闭
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${entry['anchor']} · ${entry['floor']}',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTokens.fg),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x,
                        color: AppTokens.muted, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                    splashRadius: 16,
                  ),
                ],
              ),
              Text('${entry['ts']}',
                  style: const TextStyle(fontSize: 11, color: AppTokens.muted)),
              const SizedBox(height: 14),
              // 照片大图
              if (photo != null)
                FutureBuilder<Uint8List?>(
                  future: LocalStorage.instance.readFile(photo),
                  builder: (ctx, snap) {
                    final bytes = snap.data;
                    if (bytes == null || bytes.isEmpty) {
                      return Container(
                        width: double.infinity,
                        height: 200,
                        decoration: BoxDecoration(
                          color: AppTokens.surface2,
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusMd),
                        ),
                        alignment: Alignment.center,
                        child: const Text('照片不可用',
                            style: TextStyle(
                                fontSize: 12, color: AppTokens.muted)),
                      );
                    }
                    return ClipRRect(
                      borderRadius:
                          BorderRadius.circular(AppTokens.radiusMd),
                      child: Image.memory(bytes, fit: BoxFit.cover),
                    );
                  },
                )
              else
                Container(
                  width: double.infinity,
                  height: 160,
                  decoration: BoxDecoration(
                    color: AppTokens.surface2,
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                  ),
                  alignment: Alignment.center,
                  child: const Text('无照片（Web 端不落盘）',
                      style: TextStyle(fontSize: 12, color: AppTokens.muted)),
                ),
              const SizedBox(height: 16),
              // AI 识别结果
              const Text('AI 识别结果',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTokens.fg)),
              const SizedBox(height: 8),
              if (count == 0)
                const Text('未分析 / 未识别到缺陷',
                    style: TextStyle(fontSize: 12, color: AppTokens.muted))
              else
                ...defects.map((d) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(AppTokens.space2),
                      decoration: BoxDecoration(
                        color: AppTokens.surface2,
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusMd),
                        border: Border.all(color: AppTokens.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(d['name']?.toString() ?? '',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppTokens.fg)),
                                if ((d['desc'] as String? ?? '').isNotEmpty)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(top: 2),
                                    child: Text(
                                      d['desc'] as String,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppTokens.muted),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${((d['conf'] as num? ?? 0) * 100).toInt()}%',
                            style: const TextStyle(
                                fontSize: 11, color: AppTokens.muted),
                          ),
                        ],
                      ),
                    )),
              const SizedBox(height: 16),
              // 问题描述
              const Text('问题描述',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTokens.fg)),
              const SizedBox(height: 6),
              Text(
                note.isEmpty ? '无描述' : note,
                style: TextStyle(
                  fontSize: 13,
                  color: note.isEmpty ? AppTokens.muted : AppTokens.fg2,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              // 删除
              SizedBox(
                width: double.infinity,
                child: AppButton(
                  text: true,
                  label: '删除该记录',
                  onPressed: () {
                    Navigator.of(context).pop();
                    onDelete();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
