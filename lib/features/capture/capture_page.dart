import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/utils/camera_pick.dart';
import '../../core/utils/defect_suggestions.dart';
import '../../core/utils/mm_format.dart';
import 'package:app_settings/app_settings.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/utils/image_compress.dart';
import '../../core/utils/photo_watermark.dart';
import '../../core/storage/local_storage.dart';
import '../../data/cad_service.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models.dart';
import '../../shared/widgets/drawing_image.dart';
import '../../data/repository/mock_repository.dart';
import '../../data/vision_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/di/providers.dart';
import '../../shared/widgets/app_bottom_sheet.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/app_snack.dart';
import '../../shared/widgets/nav_icon_button.dart';
import '../../shared/widgets/user_switcher.dart';
import '../../shared/widgets/voice_input.dart';

/// 量尺校对容差默认值：±10mm 且 ±5%
const double _defaultTolMm = 10;
const double _defaultTolPct = 5;

/// Web 产物构建戳：挂在结果区 Semantics 上（无 UI 影响）。
/// 构建后用它在 main.dart.js 里验证产物确实是本次编译——
/// 沙箱构建常部分失败，此前曾把旧缓存 bundle 当最新交付过（用户三次反馈间距未生效）。
const String kCaptureBuildStamp = 'capture-web-build-20260917-1800';

/// 拍照记录页（P3）：图纸 + 图钉选点 → 模拟快门（对齐原型 mockPhotoSVG 选历史照片）
/// → 1.5s 扫描 → VL 识别 → 保存记录。
/// 注：真实相机（image_picker）代码已注释，改走"关联历史照片"的模拟拍照。
class CapturePage extends ConsumerStatefulWidget {
  final CaptureArgs args;
  final CapturePageStage stage;
  const CapturePage({
    super.key,
    this.args = const CaptureArgs(),
    this.stage = CapturePageStage.operate,
  });

  @override
  ConsumerState<CapturePage> createState() => _CapturePageState();
}

/// 验收二级页类型：
/// - `select`：只负责选图纸与定位部位
/// - `operate`：只负责拍照、识别和保存
enum CapturePageStage { select, operate }

/// 拍照流程步骤：先选平面 → 图纸上选坐标/部位 → 拍照。
enum _CaptureStep { selectFloor, selectPoint, capture }

class _CapturePageState extends ConsumerState<CapturePage> {
  /// 是否从巡场“标记问题”快捷进入：用于区分顶部提示、按钮文案和保存后动作。
  bool get _isPatrolEntry => widget.args.source == CaptureEntrySource.patrol;

  late String _projectId;
  late String _floor;

  /// 选中平面的 Drawing key（大铲湾楼层直接用 Floor.key，避免 floorToDrawingKey 串图）。
  String _selectedFloorKey = '';
  late String _anchorLabel;
  late double _x;
  late double _y;

  /// 当前选点对应的图纸坐标：跟随选点变化，避免继续标记时仍沿用入口旧坐标。
  double? _drawPointWorldX;
  double? _drawPointWorldY;

  /// 当前流程步骤。
  late _CaptureStep _step;

  /// 底部「验收结果」区分段索引：0 缺陷识别 / 1 量尺校对 / 2 问题描述 / 3 拍照记录。
  ///
  /// 用分段切换而非 TabBarView：本页整体是 SingleChildScrollView，
  /// TabBarView 需要固定高度或外层 Expanded，嵌套滚动会冲突且图纸区需常驻；
  /// 分段 + setState 切换内容，各区块自然撑高，无需写死高度。
  int _resultTab = 0;

  /// 拍摄照片的压缩字节数据（Image.memory 展示）。
  Uint8List? _shotPhoto;

  /// 拍照后待确认的原始文件（拍后预览确认：重拍/使用）。
  XFile? _pendingShot;

  /// 提交（烧录水印 + 识别）进行中。
  ///
  /// 水印烧录必须在 UI isolate，期间 main thread 被阻塞 300-800ms，
  /// `setState` 调度的 build 也会被推迟——但本字段在 setState 中立刻变化，
  /// build 一次性执行时看到的最终态一致。
  /// 注：流程中**不调用其他 setState**，仅在最后一次性更新 UI；
  /// loading UI（蒙层、旋转、按钮"处理中…"）保留，未来若水印移到 isolate
  /// 不阻塞 main thread 即可正常工作。
  bool _committing = false;

  /// 水印烧录前的原始压缩图（用于 AI 识别，避免水印文字/色块干扰模型判断）。
  Uint8List? _originalPhoto;

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
  bool _didAutoOpenCamera = false;

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

  /// Mock 开关：Web 预览环境自动走 vlPreset（跨域无法调真实模型，便于验证 UI）；
  /// 移动端真机默认走真实 VisionService（需后端）。需要强制 Mock 时改为 true。
  bool _useMock = kIsWeb;

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
    _anchorLabel =
        widget.args.anchorLabel.isEmpty ? '待选点' : widget.args.anchorLabel;
    _x = widget.args.x;
    _y = widget.args.y;
    _drawPointWorldX = widget.args.drawPointWorldX;
    _drawPointWorldY = widget.args.drawPointWorldY;
    _restoreSelectedFloorFromArgs();
    // 二级页「选图纸/部位」：进入后优先停留在选择流程，不直接跳拍照。
    if (widget.stage == CapturePageStage.select) {
      if (widget.args.drawingKey != null || _floor.isNotEmpty) {
        _step = _CaptureStep.selectPoint;
        _snapToNearestAnchor(force: true);
      } else {
        // 验收页默认直接落到第一张图纸，不再先停在“选择图纸”步骤。
        _bootstrapFirstFloorForSelectStage();
      }
    }
    // 二级页「现场拍照与保存」：只要入口已经带了图纸/部位，就直接进入拍照。
    else if (widget.args.drawingKey != null || _floor.isNotEmpty) {
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
      final world = _resolveWorldCoordFor(
        relX: _x,
        relY: _y,
        drawingKey: _selectedFloorKey,
      );
      _drawPointWorldX = world?.dx;
      _drawPointWorldY = world?.dy;
    }
    _loadStoredResults();
    if (widget.stage == CapturePageStage.operate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoOpenCameraOnPhotoPage();
      });
    }
  }

  /// 根据路由参数恢复当前图纸选择，确保二级页之间跳转后仍能显示之前选中的图纸名称。
  void _restoreSelectedFloorFromArgs() {
    final argsKey = widget.args.drawingKey?.trim() ?? '';
    Floor? matchedFloor;
    if (argsKey.isNotEmpty) {
      matchedFloor = _floorOptions.cast<Floor?>().firstWhere(
            (f) => f?.key == argsKey,
            orElse: () => null,
          );
    }
    if (matchedFloor == null && _floor.isNotEmpty) {
      matchedFloor = _floorOptions.cast<Floor?>().firstWhere(
            (f) => f?.floor == _floor,
            orElse: () => null,
          );
    }
    if (matchedFloor == null) return;

    final projectMap =
        ref.read(drawingsProvider).valueOrNull ?? const <String, Drawing>{};
    final drawing = projectMap[matchedFloor.key] ??
        dy7Drawings[matchedFloor.key] ??
        drawings[matchedFloor.key];

    _selectedFloorKey = matchedFloor.key;
    _floor = matchedFloor.floor;
    _drawing = drawing;
    _remotePngUrl = null;
    _remotePngError = null;

    if (drawing != null &&
        drawing.src.isEmpty &&
        (drawing.cadOcfKey?.isNotEmpty ?? false)) {
      unawaited(_ensureRemotePng(drawing));
    }
  }

  /// 验收页默认态：自动选中当前项目第一张图纸，并直接进入“选部位”。
  void _bootstrapFirstFloorForSelectStage() {
    final firstFloor = _floorOptions.firstOrNull;
    if (firstFloor == null) {
      _step = _CaptureStep.selectPoint;
      _selectedFloorKey = '';
      _floor = '';
      _anchorLabel = '待选点';
      return;
    }
    final projectMap =
        ref.read(drawingsProvider).valueOrNull ?? const <String, Drawing>{};
    final drawing = projectMap[firstFloor.key] ??
        dy7Drawings[firstFloor.key] ??
        drawings[firstFloor.key];
    final world =
        _resolveWorldCoordFor(relX: 0.5, relY: 0.5, drawingKey: firstFloor.key);
    _step = _CaptureStep.selectPoint;
    _selectedFloorKey = firstFloor.key;
    _floor = firstFloor.floor;
    _drawing = drawing;
    _remotePngUrl = null;
    _remotePngError = null;
    _anchorLabel = '待选点';
    _x = 0.5;
    _y = 0.5;
    _drawPointWorldX = world?.dx;
    _drawPointWorldY = world?.dy;
    // 第一张图如果没有本地 PNG，则继续按原逻辑尝试拉远程底图。
    if (drawing != null &&
        drawing.src.isEmpty &&
        (drawing.cadOcfKey?.isNotEmpty ?? false)) {
      unawaited(_ensureRemotePng(drawing));
    }
  }

  /// 拍照页首次进入时自动拉起相机，让“验收页 -> 拍照 -> 拍照完成后识别保存”
  /// 这条链路更顺，不需要用户在第二页再点一次快门。
  Future<void> _autoOpenCameraOnPhotoPage() async {
    if (!mounted || _didAutoOpenCamera) return;
    if (_pendingShot != null || _shotPhoto != null) return;
    _didAutoOpenCamera = true;
    await _doCapture();
  }

  /// 启动时从跨端本地存储恢复暂存的识别结果。
  Future<void> _loadStoredResults() async {
    final raw = await LocalStorage.instance.readDoc(_storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        setState(() {
          _storedResults = decoded.whereType<Map<String, dynamic>>().toList();
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
      'nkf': 'nkf_west_1f', // 西楼一层平面图（建施报_06_V1.0_西楼一层平面图）
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
    final sameNameCount = _floorOptions.where((x) => x.name == f.name).length;
    if (sameNameCount > 1) {
      return '${f.name} (${f.key.toUpperCase()})';
    }
    return f.name;
  }

  /// 选中平面 → 进入选坐标步骤。
  void _selectFloor(Floor f) {
    final projectMap =
        ref.read(drawingsProvider).valueOrNull ?? const <String, Drawing>{};
    final d = projectMap[f.key] ?? dy7Drawings[f.key] ?? drawings[f.key];
    final world =
        _resolveWorldCoordFor(relX: 0.5, relY: 0.5, drawingKey: f.key);
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
      _drawPointWorldX = world?.dx;
      _drawPointWorldY = world?.dy;
    });
    // 若本地无 PNG 但有 CAD OCF key，则尝试从服务端生成/加载 PNG 底图。
    if (d != null && d.src.isEmpty && (d.cadOcfKey?.isNotEmpty ?? false)) {
      _ensureRemotePng(d);
    }
  }

  /// 重选图纸：底部弹窗选择当前项目的图纸（统一壳 AppBottomSheet）。
  void _showFloorSheet() {
    AppBottomSheet.show<void>(
      context: context,
      title: '选择图纸',
      body: (ctx) => ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 424),
        child: SingleChildScrollView(
          // 给长列表补底部安全区滚动余量，避免最后一项被 Home 指示条遮挡。
          padding: EdgeInsets.only(
            bottom: math.max(12, MediaQuery.viewPaddingOf(ctx).bottom),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < _floorOptions.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _FloorPickRow(
                  label: _floorLabel(_floorOptions[i]),
                  selected: _selectedFloorKey == _floorOptions[i].key,
                  onTap: () {
                    Navigator.pop(ctx);
                    _selectFloor(_floorOptions[i]);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
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
          _remotePngUrl =
              url.startsWith('http') ? url : '${CadService.host}$url';
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

  /// 把当前相对点位换算成图纸坐标；无标定时返回 null，保持页面降级可用。
  Offset? _resolveWorldCoordFor({
    required double relX,
    required double relY,
    String? drawingKey,
  }) {
    final key = (drawingKey ?? _drawingKey).trim();
    if (key.isEmpty) return null;
    final projectMap =
        ref.read(drawingsProvider).valueOrNull ?? const <String, Drawing>{};
    final drawing = projectMap[key] ?? dy7Drawings[key] ?? drawings[key];
    final mapper = ref.read(cadCalibrationMapProvider)[key];
    if (drawing == null || mapper == null) return null;
    final px = relX * drawing.w;
    final py = relY * drawing.h;
    return mapper.screenToWorld(px, py);
  }

  double get _ratio =>
      _drawing == null ? 1.0 : (_drawing!.h / _drawing!.w).clamp(0.6, 1.0);

  void _onTapDrawing(Offset local, Size size) {
    final nx = (local.dx / size.width).clamp(0.02, 0.98).toDouble();
    final ny = (local.dy / size.height).clamp(0.02, 0.98).toDouble();
    final world = _resolveWorldCoordFor(relX: nx, relY: ny);
    setState(() {
      _x = nx;
      _y = ny;
      _drawPointWorldX = world?.dx;
      _drawPointWorldY = world?.dy;
      _anchorLabel = '已选点';
      _snapToNearestAnchor();
      if (widget.stage == CapturePageStage.operate) {
        // 拍照页里仍保持原来的“选点后进入拍照态”逻辑。
        _step = _CaptureStep.capture;
      }
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
      _anchorLabel =
          '已选点 (${(_x * 100).toStringAsFixed(0)}%, ${(_y * 100).toStringAsFixed(0)}%)';
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
    AppDialog.show<void>(
      context: context,
      title: '需要相机/相册权限',
      description: '现场拍照验收需要相机与相册权限。请在系统设置中开启后重试。',
      actions: AppDialogActions(
        children: [
          AppDialogButton.secondary(
            label: '稍后',
            onTap: () => Navigator.of(context, rootNavigator: true).pop(),
          ),
          AppDialogButton.primary(
            label: '去设置',
            onTap: () {
              Navigator.of(context, rootNavigator: true).pop();
              AppSettings.openAppSettings();
            },
          ),
        ],
      ),
    );
  }

  /// 巡场入口说明条：明确告诉用户这是“快捷标记”模式，而不是普通验收入口。
  Widget _buildPatrolEntryBanner() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppTokens.space3),
        decoration: BoxDecoration(
          color: AppTokens.brandTint,
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTokens.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                MingCuteIcons.routeLine,
                size: 16,
                color: AppTokens.brand,
              ),
            ),
            const SizedBox(width: AppTokens.space3),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '来自巡场快捷标记',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 22 / 14,
                      color: AppTokens.brand,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '当前图纸和当前位置已带入，保存后可直接返回巡场继续。',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      height: 20 / 12,
                      color: AppTokens.fg2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Future<void> _doCapture() async {
    if (_scanning || _committing) return;

    // 验收页允许在“已选图纸 + 已选部位”后直接发起拍照；
    // 拍照页则维持原先的拍照态守护。
    final canCaptureFromSelect = widget.stage == CapturePageStage.select &&
        _selectedFloor != null &&
        _anchorLabel != '待选点';
    if (_step != _CaptureStep.capture && !canCaptureFromSelect) {
      if (mounted) {
        AppSnack.show(context, '请先在图纸上选点', kind: AppSnackKind.brand);
      }
      return;
    }

    final shot = await _pickImage();
    if (shot == null) {
      if (mounted) AppSnack.show(context, '已取消拍摄');
      return;
    }

    // 拍后自动使用：直接置为待确认并立即烧录水印 + 留痕，无需手动「使用」。
    // 「重拍」可丢弃重来（_retake 会清掉 _pendingShot，进行中的烧录会被跳过）。
    if (mounted) {
      setState(() {
        _pendingShot = shot;
        _shotPhoto = null;
        _defects = const [];
        _scanError = null;
      });
      _commitPhoto();
    }
  }

  /// 确认使用待确认照片：执行烧录水印 + 缺陷识别（原提交流程）。
  ///
  /// **核心约束**：水印烧录（`applyPhotoWatermark`）必须运行在 UI isolate，
  /// 期间 main thread 被阻塞 300-800ms。`setState` 调度 build 也会被推迟——
  /// 但 build 一次性执行时看到的最终态一致。
  ///
  /// 流程策略：
  /// - 开头 setState `_committing = true`（UI 状态置位）
  /// - 流程中**不调用任何 setState**，避免累积推迟
  /// - 最后一次性 setState 设最终态（含 `_pendingShot = null`）
  /// - finally setState `_committing = false`
  /// - 取消/重拍：流程中 `_pendingShot` 被设为 null，最后 setState 检查
  ///   `_pendingShot == shot` 跳过结果应用，避免"复活"已取消的照片
  Future<void> _commitPhoto() async {
    final shot = _pendingShot;
    if (shot == null || _committing) return;
    setState(() => _committing = true);
    try {
      // 1. 读原图字节（一次 IO，让出主线程 ~几十 ms）
      final rawBytes = await shot.readAsBytes();
      // 2. 压缩（VM isolate；Web fallback 主线程 ~100-500ms）
      final compressed = await compressImageAsync(rawBytes);

      // 构造水印元信息（工程记录：时间 / 项目 / 部位 / GPS / 凭证号）。
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
        worldCoord: _drawPointWorldX != null && _drawPointWorldY != null
            ? '图纸坐标 X=${_drawPointWorldX!.toStringAsFixed(1)} '
                'Y=${_drawPointWorldY!.toStringAsFixed(1)}'
            : null,
      );

      // 3. 烧录水印（必须 UI isolate，~300-800ms，期间 main thread 阻塞）
      Uint8List? watermarked;
      try {
        watermarked = await applyPhotoWatermark(compressed, meta);
      } catch (e) {
        debugPrint('[capture] watermark failed: $e');
        watermarked = null;
      }
      final finalPhoto = watermarked ?? compressed;

      // 5. 一次性 setState：所有最终态同时生效。
      //    检查 _pendingShot == shot：若流程中被取消（_retake 把 _pendingShot
      //    设为 null），跳过结果应用，避免"复活"已取消的照片。
      if (mounted && _pendingShot == shot) {
        setState(() {
          _shotPhoto = finalPhoto;
          _originalPhoto = compressed;
          _defects = const [];
          _pendingShot = null;
        });
        if (widget.stage == CapturePageStage.select) {
          context.push(
            '/capture/photo',
            extra: CaptureArgs(
              projectId: _projectId,
              source: widget.args.source,
              floor: _floor,
              anchorLabel: _anchorLabel,
              x: _x,
              y: _y,
              drawingKey: _drawingKey,
              drawPointWorldX: _drawPointWorldX,
              drawPointWorldY: _drawPointWorldY,
            ),
          );
        }
        AppSnack.show(
          context,
          watermarked != null ? '已拍摄并烧录防篡改水印' : '已拍摄（水印烧录失败，已保留原图）',
          kind:
              watermarked != null ? AppSnackKind.success : AppSnackKind.danger,
        );
      }
    } catch (e) {
      if (mounted && _pendingShot == shot) {
        AppSnack.show(context, '提交失败：$e', kind: AppSnackKind.danger);
      }
    } finally {
      if (mounted) setState(() => _committing = false);
    }
    // 不再自动触发 AI 分析 —— 由用户在「AI 分析」按钮上手动触发。
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
        // 优先使用无水印原始压缩图（_originalPhoto），无则回退到 _shotPhoto。
        final bytesForAi = _originalPhoto ?? _shotPhoto!;
        final vision = await VisionService().recognizeDefects(bytesForAi);
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
      'worldX': _drawPointWorldX,
      'worldY': _drawPointWorldY,
      'ts': ts,
      'anchor': _anchorLabel,
      'floor': _floor,
      'count': _defects.length,
      'defects':
          _defects.map((d) => {...d.toJson(), 'status': 'pending'}).toList(),
      'note': note,
      // 转入问题清单时会被透传到 Defect（见 buildDefectFromCaptureDefect）：
      // 缺了它们，转入的记录就没有 GPS / 海拔 / 真实记录人。
      'gps': _location.gpsText,
      'alt': '海拔 ${_location.altitude.toStringAsFixed(1)}m',
      'reporter': _currentUser,
    };
    // 跨端统一把压缩照片落盘（JSON 不支持二进制，故 entry 只记相对路径）：
    // - 移动端/桌面：写入应用目录的真实文件，可长期保存；
    // - Web（演示实现）：写入内存 Map，当前会话内可读（刷新即丢——Web 演示特性），
    //   但 entry 也能拿到 photo 字段，验收记录页可展示，且「拍照 → 导出报告」
    //   链路内缺陷照片能被报告读取内嵌。
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
    // （photoPath 为空时报告端**不渲染照片区**，见 report_builder._photoBlock）。
    {
      final repo = ref.read(repositoryProvider);
      // 归入当前项目，避免新增记录串到另一个项目。
      if (repo is MockRepository) {
        repo.currentIs7 = ref.read(is7DongProjectProvider);
      }
      final gpsText = _location.gpsText;
      final altText = '海拔 ${_location.altitude.toStringAsFixed(1)}m';
      // anchor 口径统一：与验收记录 entry.anchor、以及「转入」路径生成的
      // Defect.anchor 保持一致（都只放部位）。时间轴按 `d.anchor` 精确匹配，
      // 只有聚合条带「· 楼层」会导致同一张照片的两条记录互相匹配不到。
      final anchorLabel = _anchorLabel;
      final anchor = '$anchorLabel · $_floor';
      final names =
          _defects.map((v) => v.name).where((n) => n.isNotEmpty).toList();
      final descs =
          _defects.map((v) => v.desc ?? '').where((d) => d.isNotEmpty).toList();
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
            ? '$anchor·$primary等${names.length}项'
            : '$anchor·$primary',
        type: primary,
        category: DefectCategory.other,
        severity: sev,
        status: DefectStatus.draft,
        anchor: anchorLabel,
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
        worldX: _drawPointWorldX,
        worldY: _drawPointWorldY,
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
        _isPatrolEntry
            ? (_defects.isEmpty ? '巡场标记已保存（未分析）' : '巡场标记已保存')
            : (_defects.isEmpty ? '记录已保存（未分析）' : '记录已保存'),
        kind: AppSnackKind.brand,
      );
    }
    return true;
  }

  /// 重拍：仅重新调用相机拍照并自动烧录水印，图纸/部位保持不变。
  /// 不回到选图纸/选点流程；取消拍摄则保留当前照片不动。
  Future<void> _retake() async {
    _scanTimer?.cancel();
    await _doCapture();
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

  /// 返回巡场页：从巡场 push 进入时优先 pop，兜底再回到巡场根路由。
  void _returnToPatrol() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/patrol');
  }

  /// 保存后继续下一条：清空本次拍照草稿，并回到“重新选点”状态。
  void _startNextCaptureCycle() {
    if (widget.stage == CapturePageStage.operate) {
      context.go(
        '/capture',
        extra: CaptureArgs(
          projectId: _projectId,
          source: widget.args.source,
          floor: _floor,
          x: 0.5,
          y: 0.5,
          drawingKey: _drawingKey,
        ),
      );
      return;
    }
    _scanTimer?.cancel();
    _noteController.clear();
    setState(() {
      _pendingShot = null;
      _shotPhoto = null;
      _originalPhoto = null;
      _defects = const [];
      _scanError = null;
      _scanning = false;
      _saved = false;
      _committing = false;
      _resultTab = 0;
      _step = _CaptureStep.selectPoint;
      _anchorLabel = '待选点';
    });
    AppSnack.show(
      context,
      _isPatrolEntry ? '请在图纸上点选下一个问题位置' : '请重新选择部位，继续验收',
      kind: AppSnackKind.brand,
    );
  }

  /// 从验收页进入拍照页：把当前图纸、部位和图纸坐标一起带过去。
  void _openPhotoStage() {
    if (_selectedFloor == null || _anchorLabel == '待选点') {
      AppSnack.show(context, '请先选择图纸和部位', kind: AppSnackKind.brand);
      return;
    }
    context.push(
      '/capture/photo',
      extra: CaptureArgs(
        projectId: _projectId,
        source: widget.args.source,
        floor: _floor,
        anchorLabel: _anchorLabel,
        x: _x,
        y: _y,
        drawingKey: _drawingKey,
        drawPointWorldX: _drawPointWorldX,
        drawPointWorldY: _drawPointWorldY,
      ),
    );
  }

  // —— 渲染 ——
  @override
  Widget build(BuildContext context) {
    final drawingsAsync = ref.watch(drawingsProvider);
    _drawing = _resolveDrawing(drawingsAsync.valueOrNull ?? {});
    final isSelectStage = widget.stage == CapturePageStage.select;
    final showPhotoPreview =
        !isSelectStage && (_pendingShot != null || _shotPhoto != null);
    final bodyHorizontal = isSelectStage && _step == _CaptureStep.selectPoint
        ? 0.0
        : AppTokens.space3;
    final pageTitle = _isPatrolEntry ? '标记问题' : (isSelectStage ? '验收' : '拍照识别');
    return Scaffold(
      backgroundColor: AppTokens.bg,
      appBar: AppBar(
        backgroundColor: AppTokens.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 48,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        leadingWidth: isSelectStage ? null : 0,
        titleSpacing: isSelectStage ? 12 : 0,
        centerTitle: !isSelectStage,
        title: isSelectStage
            ? Text(
                pageTitle,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  height: 32 / 24,
                  color: AppTokens.fg,
                ),
              )
            : Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: NavIconButton(
                        icon: MingCuteIcons.leftLine,
                        color: const Color(0xFF09244B),
                        onPressed: () => context.pop(),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Text(
                      pageTitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 24 / 16,
                        color: AppTokens.fg,
                      ),
                    ),
                  ),
                ],
              ),
        actions: isSelectStage
            ? const [
                Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: UserSwitcher(),
                ),
              ]
            : [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: NavIconButton(
                    icon: MingCuteIcons.photoAlbumLine,
                    color: const Color(0xFF09244B),
                    onPressed: _showStoredSheet,
                  ),
                ),
              ],
      ),
      body: Column(
        children: [
          // ① 验收页保留顶部信息卡；拍照识别页改为随内容一起滚动，避免吸顶遮挡。
          if (isSelectStage) _buildContextCard(),
          Expanded(
            child: SingleChildScrollView(
              primary: false,
              padding: EdgeInsets.fromLTRB(
                  bodyHorizontal,
                  isSelectStage ? AppTokens.space2 : AppTokens.space3,
                  bodyHorizontal,
                  0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ③ 验收页显示图纸交互区；拍照识别页不再显示图纸/选点内容，
                  // 选点调整走「重选部位」回验收页。
                  if (isSelectStage) _buildDrawingStage(),
                  if (isSelectStage) ...[
                    const SizedBox(height: AppTokens.space3),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.space3,
                      ),
                      child: _buildSelectControls(),
                    ),
                  ],
                  if (isSelectStage && _step != _CaptureStep.selectPoint) ...[
                    const SizedBox(height: AppTokens.space3),
                    // ④ 仅在"选图纸"阶段保留步骤卡；选点阶段直接在图纸上操作，避免重复说明。
                    _buildStepPanel(),
                  ],
                  // 拍照识别页（operate 阶段）：只保留拍摄定位 + 正方形拍照区。
                  // 未拍照不显示结果区；拍照后照片作为首元素（距顶 12 由 scroll padding 提供）。
                  if (!isSelectStage) ...[
                    if (!showPhotoPreview) ...[
                      _buildLocationPickerRow(),
                      const SizedBox(height: AppTokens.space3),
                    ],
                    _buildPhotoPreviewBlock(),
                    if (showPhotoPreview) ...[
                      if (_shotPhoto != null && _scanError != null) ...[
                        const SizedBox(height: AppTokens.space2),
                        Text(
                          _scanError!,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            height: 20 / 12,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                      ],
                      // 验收概览：「重拍 | AI 识别」按钮行下方。
                      if (_defects.isNotEmpty ||
                          _scaleChecks.isNotEmpty ||
                          _storedResults.isNotEmpty) ...[
                        const SizedBox(height: AppTokens.space3),
                        _buildSummaryCard(),
                      ],
                      const SizedBox(height: AppTokens.space3),
                      // ⑥ 结果区：分段（问题清单同款，卡外）+ 白卡内容。
                      _buildResultTabs(),
                      const SizedBox(height: AppTokens.space2),
                      _buildResultBody(),
                      const SizedBox(height: AppTokens.space3),
                      // ⑦ 保存记录按钮随内容滚动（不吸附底部）。
                      _buildControls(),
                    ],
                  ],
                  const SizedBox(height: AppTokens.space6),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 验收页主按钮：放在图纸下方，只负责进入拍照页，不在这里做识别和保存。
  Widget _buildSelectControls() {
    return SizedBox(
      width: double.infinity,
      child: AppButton(
        size: AppButtonSize.lg,
        width: double.infinity,
        radius: AppTokens.radiusMd,
        label: '拍照',
        onPressed: _openPhotoStage,
      ),
    );
  }

  /// 全页统一的区块卡片外壳。
  ///
  /// 白底 + 外层圆角 12 + 内边距 12，**不加灰描边、不加阴影**。
  /// 标题层级统一收口到 14/W500，减少局部标题抢戏。
  Widget _sectionCard({
    required IconData icon,
    required String title,
    String? helper,
    String? count,
    Color? countColor,
    Widget? action,
    Widget? trailing,
    required Widget child,
  }) {
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: AppTokens.accent),
              const SizedBox(width: AppTokens.space1 + 2),
              Flexible(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: AppTokens.heightCalibrated,
                        color: AppTokens.fg)),
              ),
              if (count != null) ...[
                const SizedBox(width: AppTokens.space2),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (countColor ?? AppTokens.accent)
                        .withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                  ),
                  child: Text(count,
                      style: TextStyle(
                          fontSize: 11,
                          height: AppTokens.heightCalibrated,
                          fontWeight: FontWeight.w600,
                          color: countColor ?? AppTokens.accent)),
                ),
              ],
              if (trailing != null) trailing,
              if (action != null) action,
            ],
          ),
          if (helper != null) ...[
            const SizedBox(height: 4),
            Text(
              helper,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                height: 20 / 12,
                color: AppTokens.muted,
              ),
            ),
          ],
          const SizedBox(height: AppTokens.space3),
          child,
        ],
      ),
    );
  }

  /// 顶部上下文卡：仅验收/选点阶段显示图纸与部位信息；
  /// 拍照识别阶段（operate）不再堆叠顶部卡片，取景区优先，相关信息已在选点阶段确认。
  Widget _buildContextCard() {
    if (widget.stage != CapturePageStage.select) return const SizedBox.shrink();
    final drawingName = _selectedFloor?.name ?? '未选择图纸';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
          AppTokens.space3, AppTokens.space3, AppTokens.space3, 0),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppTokens.space3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isPatrolEntry) ...[
                  // 巡场快捷入口单独保留提示，避免用户误以为自己在普通验收流程里。
                  _buildPatrolEntryBanner(),
                  const SizedBox(height: AppTokens.space3),
                ],
                _buildSelectSummaryCard(drawingName),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 验收页顶部摘要：只保留图纸和部位，去掉重复任务标题、定位卡和状态胶囊。
  Widget _buildSelectSummaryCard(String drawingName) {
    final hasPoint = _anchorLabel != '待选点';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Expanded(
              child: Text(
                '当前图纸',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  height: 20 / 14,
                  color: AppTokens.fg2,
                ),
              ),
            ),
            const SizedBox(width: AppTokens.space2),
            _buildGhostBtn(
              icon: MingCuteIcons.repeatLine,
              label: '切换图纸',
              onTap: _showFloorSheet,
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 图纸名称单独占一行，去掉省略，优先完整展示。
        Text(
          drawingName,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 22 / 14,
            color: AppTokens.fg,
          ),
        ),
        const SizedBox(height: 12),
        const Divider(height: 1, thickness: 1, color: AppTokens.border),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Expanded(
              child: Text(
                '当前部位',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  height: 20 / 14,
                  color: AppTokens.fg2,
                ),
              ),
            ),
            Text(
              hasPoint ? '已选点' : '未选点',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 22 / 14,
                color: AppTokens.fg,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 轻量幽灵按钮（区块右上角的次要操作，带图标 + 文字严格居中对齐）。
  Widget _buildGhostBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = AppTokens.accent,
  }) {
    return SizedBox(
      height: 28,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: color,
          backgroundColor: color.withValues(alpha: 0.06),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 20 / 12)),
          ],
        ),
      ),
    );
  }

  /// 本次验收概览：识别缺陷 / 量尺合格 / 留痕照片。
  /// 样式对齐首页项目统计条（_MetricItem）：彩色数值 20/W600 + 标签 12/W400，无图标无分隔线。
  Widget _buildSummaryCard() {
    final defectTotal = _defects.length;
    final severe = _defects
        .where((d) =>
            d.severity == DefectSeverity.red ||
            d.severity == DefectSeverity.orange)
        .length;
    final scaleTotal = _scaleChecks.length;
    final scalePass = _scaleChecks.where((c) => c.pass(_tolMm, _tolPct)).length;
    final photoTotal = _storedResults.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: AppTokens.space3),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      ),
      child: Row(
        children: [
          _statItem(
              '$defectTotal',
              '识别缺陷',
              severe > 0
                  ? AppTokens.danger
                  : (defectTotal > 0 ? AppTokens.fg : AppTokens.fg2)),
          _statItem(
              '$scalePass/$scaleTotal',
              '量尺合格',
              scaleTotal > 0 && scalePass == scaleTotal
                  ? AppTokens.success
                  : (scaleTotal > 0 ? AppTokens.warning : AppTokens.fg2)),
          _statItem('$photoTotal', '留痕照片',
              photoTotal > 0 ? AppTokens.fg : AppTokens.fg2),
        ],
      ),
    );
  }

  /// 统计项（首页同款）：彩色数值 20/W600 + 标签 12/W400。
  Widget _statItem(String value, String label, Color valueColor) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: valueColor,
                  height: 28 / 20)),
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: AppTokens.fg,
                  height: 20 / 12)),
        ],
      ),
    );
  }

  /// 结果区分段（问题清单 `_StatusSegmented` 同款）：灰底轨道 + 选中白底片，
  /// 独立于内容卡片之外；轨道 #E9EAEB / 高 34 / 圆角 8，分段高 30 / 圆角 6。
  Widget _buildResultTabs() {
    final tabs = <_ResultTabDef>[
      _ResultTabDef('AI 识别', _defects.isEmpty ? null : '${_defects.length}'),
      _ResultTabDef(
          '量尺校对', _scaleChecks.isEmpty ? null : '${_scaleChecks.length}'),
      const _ResultTabDef('问题描述', null),
    ];
    return Container(
      width: double.infinity,
      height: 34,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppTokens.surface3,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final t = tabs[i];
          final selected = _resultTab == i;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _resultTab = i),
              // 与问题清单 _SegBtn 一致：瞬时切换，无过渡动画（动画会闪）。
              child: Container(
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppTokens.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  t.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14,
                      height: 22 / 14,
                      fontWeight: FontWeight.w500,
                      color: selected
                          ? const Color(0xFF202224)
                          : const Color(0xFF919499)),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// 结果区内容卡（白卡）：承载当前分段的内容，分段控件已移到卡片外。
  Widget _buildResultBody() {
    return Semantics(
      label: kCaptureBuildStamp, // 构建戳：仅用于产物校验，无 UI 影响。
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppTokens.space3),
        decoration: BoxDecoration(
          color: AppTokens.surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        ),
        // 直接切换内容，不加淡入淡出动画（与问题清单分段一致，避免切换闪烁）。
        child: switch (_resultTab) {
          0 => _resultDefects(),
          1 => _resultScale(),
          _ => _resultNote(),
        },
      ),
    );
  }

  /// 结果区空状态：统一的居中占位（图标 + 说明 + 可选操作）。
  Widget _resultEmpty(
      {required IconData icon, required String text, Widget? action}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: AppTokens.space5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTokens.surface2,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 22, color: AppTokens.muted),
          ),
          const SizedBox(height: AppTokens.space2 + 2),
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12, height: 1.5, color: AppTokens.muted)),
          if (action != null) ...[
            const SizedBox(height: AppTokens.space3),
            action,
          ],
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
          Icon(MingCuteIcons.fileLine, size: 48, color: AppTokens.muted),
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
              icon: Icon(MingCuteIcons.refresh1Line,
                  size: 14, color: AppTokens.accent),
              label: Text('重新生成', style: TextStyle(color: AppTokens.accent)),
            ),
          ],
        ],
      ),
    );
  }

  /// 图纸 + 图钉 + 准星交互区（支持双指/滚轮缩放）。
  Widget _buildDrawingStage() {
    final isSelectStage = widget.stage == CapturePageStage.select;
    final stepHint = _step == _CaptureStep.selectFloor
        ? '请先选择下方图纸，再进入图纸选点'
        : '点击图纸选点，将自动吸附最近锚点';
    final drawingBox = LayoutBuilder(
      builder: (context, rootConstraints) {
        return SizedBox(
          width: double.infinity,
          height: isSelectStage
              ? rootConstraints.maxWidth
              : (rootConstraints.maxWidth * _ratio),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final box = constraints.biggest;
              final contentWidth = isSelectStage
                  ? math.min(box.width, box.height / _ratio)
                  : box.width;
              final contentHeight =
                  isSelectStage ? contentWidth * _ratio : box.height;
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
                      child: Center(
                        child: SizedBox(
                          width: contentWidth,
                          height: contentHeight,
                          child: GestureDetector(
                            onTapUp: _step == _CaptureStep.selectFloor
                                ? null
                                : (d) => _onTapDrawing(
                                      d.localPosition,
                                      Size(contentWidth, contentHeight),
                                    ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (_drawing != null &&
                                    _drawing!.src.isNotEmpty)
                                  DrawingImage(
                                    _drawing!.src,
                                    fit: BoxFit.fill,
                                  )
                                else if (_drawing != null &&
                                    _drawing!.src.isEmpty &&
                                    _remotePngUrl != null)
                                  Image.network(
                                    _remotePngUrl!,
                                    fit: BoxFit.fill,
                                    filterQuality: FilterQuality.medium,
                                    loadingBuilder:
                                        (context, child, progress) =>
                                            progress == null
                                                ? child
                                                : Container(
                                                    alignment: Alignment.center,
                                                    child:
                                                        CircularProgressIndicator(
                                                      value: progress
                                                                  .expectedTotalBytes !=
                                                              null
                                                          ? progress
                                                                  .cumulativeBytesLoaded /
                                                              progress
                                                                  .expectedTotalBytes!
                                                          : null,
                                                    ),
                                                  ),
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            _buildMissingPngPlaceholder(
                                                error.toString()),
                                  )
                                else if (_drawing != null &&
                                    _drawing!.src.isEmpty)
                                  _buildMissingPngPlaceholder(_remotePngError)
                                else
                                  Container(
                                    color: AppTokens.surface,
                                    alignment: Alignment.center,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(MingCuteIcons.mapLine,
                                            size: 48, color: AppTokens.muted),
                                        const SizedBox(
                                            height: AppTokens.space2),
                                        Text('未选择图纸',
                                            style: TextStyle(
                                                color: AppTokens.muted,
                                                fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  ),
                                if (_drawing != null &&
                                    (_drawing!.src.isNotEmpty ||
                                        _remotePngUrl != null))
                                  Container(
                                    decoration: BoxDecoration(
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
                                if (_drawing != null &&
                                    (_drawing!.src.isNotEmpty ||
                                        _remotePngUrl != null))
                                  ..._anchors.map((a) => _buildPin(a)),
                                if (_drawing != null &&
                                    _step != _CaptureStep.selectFloor &&
                                    _anchorLabel != '待选点') ...[
                                  _buildPointMarker(),
                                ],
                                if (!isSelectStage)
                                  Positioned(
                                    top: AppTokens.space3,
                                    left: AppTokens.space3,
                                    right: AppTokens.space3,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: AppTokens.space3,
                                          vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.black
                                            .withValues(alpha: 0.45),
                                        borderRadius: BorderRadius.circular(
                                            AppTokens.radiusPill),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(MingCuteIcons.cursorLine,
                                              size: 12, color: Colors.white),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(stepHint,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    height: AppTokens
                                                        .heightCalibrated,
                                                    color: Colors.white)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (_scanning) _buildScanOverlay(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    bottom: 40,
                    child: _ZoomFab(
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
      },
    );
    return isSelectStage
        ? drawingBox
        : AspectRatio(
            aspectRatio: 1 / _ratio,
            child: drawingBox,
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
    return _sectionCard(
      icon: MingCuteIcons.layersLine,
      title: '选择图纸',
      helper: '图纸名称会完整显示，当前选中的图纸会固定高亮。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < _floorOptions.length; i++) ...[
            if (i > 0) const SizedBox(height: AppTokens.space2),
            _FloorOptionTile(
              label: _floorLabel(_floorOptions[i]),
              selected: _selectedFloorKey == _floorOptions[i].key,
              onTap: () => _selectFloor(_floorOptions[i]),
            ),
          ],
        ],
      ),
    );
  }

  /// 步骤 ②：确认图纸上选中的部位。
  Widget _buildPointConfirm() {
    return _sectionCard(
      icon: MingCuteIcons.mapPinLine,
      title: '确认部位',
      helper: '若点位不准确，可以继续在图纸上点击修正，或重新切换图纸。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text('已选部位：$_anchorLabel',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        height: 24 / 16)),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.space2),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppTokens.space3),
            decoration: BoxDecoration(
              color: AppTokens.surface2,
              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            ),
            child: const Text('在图纸上点击可重新选择部位，系统会自动吸附到最近的预设锚点。',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    height: 22 / 14,
                    color: AppTokens.fg2)),
          ),
          const SizedBox(height: AppTokens.space3),
          SizedBox(
            width: double.infinity,
            child: AppButton(
              outlined: true,
              radius: AppTokens.radiusMd,
              label: '重选图纸',
              onPressed: _showFloorSheet,
            ),
          ),
        ],
      ),
    );
  }

  /// 步骤 ③：拍照阶段信息条。
  Widget _buildCaptureInfo() {
    return _sectionCard(
      icon: MingCuteIcons.cameraLine,
      title: '现场拍照',
      helper: _isPatrolEntry
          ? '当前图纸和巡场位置已带入，拍照后可直接保存为本次巡场标记。'
          : '当前图纸和部位已锁定，拍照后可直接进行 AI 识别和记录保存。',
      action: _buildGhostBtn(
        icon: MingCuteIcons.arrowLeftLine,
        label: '重选部位',
        onTap: () => setState(() => _step = _CaptureStep.selectPoint),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppTokens.space3),
        decoration: BoxDecoration(
          color: AppTokens.surface2,
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        ),
        child: Text(
          '${_drawing?.title ?? '—'} · $_anchorLabel',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 22 / 14,
            color: AppTokens.fg,
          ),
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
    AppBottomSheet.show<void>(
      context: context,
      title: '${a.label} · 历史照片',
      body: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
    );
  }

  /// 当前选点标记：准心与蓝点统一按同一个中心点绘制，避免出现视觉偏移。
  Widget _buildPointMarker() {
    return Positioned.fill(
      child: Align(
        alignment: Alignment(_x * 2 - 1, _y * 2 - 1),
        child: IgnorePointer(
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppTokens.accent.withValues(alpha: 0.8),
                      width: 1.5),
                ),
              ),
              // 十字线长度与外圈统一，保证中心线和蓝点共用一个几何中心。
              _line(48, 2, Axis.horizontal),
              _line(2, 48, Axis.vertical),
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: AppTokens.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: AppTokens.accent.withValues(alpha: 0.6),
                      blurRadius: 10,
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
  /// 分段「AI 识别」：严重度分布概览 + 缺陷卡列表。
  Widget _resultDefects() {
    if (_defects.isEmpty) {
      return _resultEmpty(
        icon: MingCuteIcons.scanLine,
        text: '尚未识别到缺陷\n在下方拍照区拍摄后，点「AI 分析」自动识别',
      );
    }
    final counts = <DefectSeverity, int>{};
    for (final d in _defects) {
      counts[d.severity] = (counts[d.severity] ?? 0) + 1;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 严重度分布（Wrap 自动换行，防窄屏溢出）
        Wrap(
          spacing: AppTokens.space1 + 2,
          runSpacing: AppTokens.space1 + 2,
          children: DefectSeverity.values
              .where(counts.containsKey)
              .map((s) => _severityChip(s, counts[s]!))
              .toList(),
        ),
        const SizedBox(height: AppTokens.space2 + 2),
        ..._defects.map(_buildDefectCard),
      ],
    );
  }

  /// 严重度分布胶囊：色点 + 标签 + 数量（浅底取自身 5% 透明）。
  Widget _severityChip(DefectSeverity s, int n) {
    final c = s.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text('${s.label} $n',
              style: TextStyle(
                  fontSize: 11,
                  height: 1,
                  fontWeight: FontWeight.w500,
                  color: c)),
        ],
      ),
    );
  }

  // ============ 量尺校对（实测 vs 图纸标注） ============

  /// 分段「量尺校对」：列出各构件实测 / 图纸标注，按容差判定合格。
  Widget _resultScale() {
    final passCount = _scaleChecks.where((c) => c.pass(_tolMm, _tolPct)).length;
    final total = _scaleChecks.length;
    final rate = total == 0 ? 0.0 : passCount / total * 100;
    final allPass = total > 0 && passCount == total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (total > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: allPass
                      ? AppTokens.success.withValues(alpha: 0.05)
                      : AppTokens.warning.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                        allPass
                            ? MingCuteIcons.checkCircleLine
                            : MingCuteIcons.alertLine,
                        size: 13,
                        color: allPass ? AppTokens.success : AppTokens.warning),
                    const SizedBox(width: 4),
                    Text(
                      '合格 $passCount/$total · ${rate.toStringAsFixed(0)}%',
                      style: TextStyle(
                          fontSize: 11,
                          height: AppTokens.heightCalibrated,
                          fontWeight: FontWeight.w600,
                          color:
                              allPass ? AppTokens.success : AppTokens.warning),
                    ),
                  ],
                ),
              ),
            const Spacer(),
            _buildGhostBtn(
              icon: MingCuteIcons.rulerLine,
              label: '智能量尺',
              onTap: () async {
                final projectId = ref.read(currentProjectIdProvider) ??
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
                style: const TextStyle(fontSize: 11, color: AppTokens.muted),
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
          _resultEmpty(
            icon: MingCuteIcons.rulerLine,
            text: '尚未添加量尺项\n录入现场实测与图纸标注尺寸，系统按容差自动判定',
            action: AppButton(
              size: AppButtonSize.sm,
              outlined: true,
              radius: AppTokens.radiusMd,
              label: '添加量尺项',
              onPressed: _addScaleCheck,
            ),
          )
        else ...[
          ..._scaleChecks.asMap().entries.map((e) {
            final i = e.key;
            final c = e.value;
            final ok = c.pass(_tolMm, _tolPct);
            return _buildScaleCheckCard(i, c, ok);
          }),
          const SizedBox(height: AppTokens.space2 + 2),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _addScaleCheck,
              icon: const Icon(MingCuteIcons.addLine, size: 14),
              label: const Text('继续添加量尺项',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTokens.accent,
                side:
                    BorderSide(color: AppTokens.accent.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildToleranceRow() {
    return Row(
      children: [
        const Text('容差',
            style: TextStyle(fontSize: 12, color: AppTokens.muted)),
        const SizedBox(width: 6),
        Expanded(
          child:
              _tolField('±', _tolMm, 'mm', (v) => setState(() => _tolMm = v)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child:
              _tolField('±', _tolPct, '%', (v) => setState(() => _tolPct = v)),
        ),
      ],
    );
  }

  Widget _tolField(String prefix, double value, String unit,
      ValueChanged<double> onChanged) {
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
              onChanged: (s) => onChanged(double.tryParse(s) ?? 0),
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
                icon: const Icon(MingCuteIcons.deleteLine,
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: ok
                      ? AppTokens.success.withValues(alpha: 0.12)
                      : AppTokens.danger.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                ),
                child: Column(
                  children: [
                    Icon(ok ? MingCuteIcons.checkLine : MingCuteIcons.closeLine,
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
              '偏差 ${fmtMmSigned(dev)}mm'
              '（${fmtPctSigned(devPct)}%）',
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
    setState(() => _scaleChecks
        .add(const ScaleCheck(name: '', measuredMm: 0, drawingMm: 0)));
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
    final sev = d.severity;
    final sevColor = sev.color;
    final conf = (d.conf * 100).clamp(0.0, 100.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(AppTokens.space2 + 2),
        decoration: BoxDecoration(
          color: AppTokens.surface2,
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                // 标签浅底规范：取自身文字色 5% 透明
                color: sevColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              ),
              child: Icon(MingCuteIcons.alertLine, size: 17, color: sevColor),
            ),
            const SizedBox(width: AppTokens.space2 + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(d.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                                color: AppTokens.fg)),
                      ),
                      const SizedBox(width: AppTokens.space2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: sevColor.withValues(alpha: 0.05),
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusPill),
                        ),
                        child: Text(sev.label,
                            style: TextStyle(
                                fontSize: 11,
                                height: 1,
                                fontWeight: FontWeight.w500,
                                color: sevColor)),
                      ),
                    ],
                  ),
                  if (d.desc != null && d.desc!.isNotEmpty) ...[
                    const SizedBox(height: AppTokens.space1 + 2),
                    Text(d.desc!,
                        style: const TextStyle(
                            fontSize: 12, height: 1.5, color: AppTokens.muted)),
                  ],
                  const SizedBox(height: AppTokens.space2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusPill),
                          child: LinearProgressIndicator(
                            value: conf / 100,
                            minHeight: 4,
                            backgroundColor: AppTokens.border,
                            valueColor: AlwaysStoppedAnimation(sevColor),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppTokens.space2),
                      Text('置信度 ${conf.toStringAsFixed(0)}%',
                          style: const TextStyle(
                              fontSize: 11, height: 1, color: AppTokens.muted)),
                    ],
                  ),
                  if (d.suggestion != null && d.suggestion!.isNotEmpty) ...[
                    const SizedBox(height: AppTokens.space2 + 2),
                    // 整改建议：平铺在灰卡内（图标行 + 正文），不再嵌套色块，
                    // 层级保持「页面 → 灰卡」两层。
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(MingCuteIcons.flashLine,
                            size: 12, color: AppTokens.accent),
                        const SizedBox(width: 4),
                        Text('整改建议 · ${sev.action}',
                            style: const TextStyle(
                                fontSize: 11,
                                height: AppTokens.heightCalibrated,
                                fontWeight: FontWeight.w600,
                                color: AppTokens.accent)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(d.suggestion!,
                        style: const TextStyle(
                            fontSize: 12, height: 1.5, color: AppTokens.fg)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 拍照完成后的主照片区：照片在正方形区域内按原始比例居中显示（contain），
  /// 四周留白用灰白占位；拍完自动使用并烧录防篡改水印，无需手动确认。
  /// 拍照区：居中正方形照片（contain 显示，留白灰白方块）。
  /// - 未拍照：方块内居中显示「拍照」入口（点击调相机，替代原蓝色圆形快门）。
  /// - 已拍照：显示照片，下方一行 [重拍 | AI 识别]（左重拍、右 AI 识别）。
  Widget _buildPhotoPreviewBlock() {
    final committedPhoto = _shotPhoto;
    final pendingShot = _pendingShot;
    final hasPhoto = committedPhoto != null || pendingShot != null;

    if (!hasPhoto) {
      return InkWell(
        onTap: _doCapture,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        child: AspectRatio(
          aspectRatio: 1,
          child: Container(
            color: AppTokens.surface3,
            alignment: Alignment.center,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  MingCuteIcons.cameraLine,
                  size: 36,
                  color: AppTokens.muted,
                ),
                SizedBox(height: 8),
                Text(
                  '拍照',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 20 / 14,
                    color: AppTokens.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          child: AspectRatio(
            aspectRatio: 1,
            child: Container(
              color: AppTokens.surface3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (committedPhoto != null)
                    Positioned.fill(
                      child: Image.memory(
                        committedPhoto,
                        fit: BoxFit.contain,
                      ),
                    )
                  else if (pendingShot != null)
                    Positioned.fill(
                      child: FutureBuilder<Uint8List>(
                        future: pendingShot.readAsBytes(),
                        builder: (ctx, snap) => snap.hasData
                            ? Image.memory(
                                snap.data!,
                                fit: BoxFit.contain,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  if (_committing)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppTokens.bg.withValues(alpha: 0.72),
                        ),
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              ),
                              SizedBox(height: 10),
                              Text(
                                '正在烧录防篡改水印…',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppTokens.fg,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                '水印将作为取证凭证写入像素',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTokens.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppTokens.space2),
        Row(
          children: [
            Expanded(
              child: AppButton(
                size: AppButtonSize.lg,
                outlined: true,
                radius: AppTokens.radiusMd,
                label: '重拍',
                onPressed: _committing ? null : () => _retake(),
              ),
            ),
            const SizedBox(width: AppTokens.space3),
            Expanded(
              child: AppButton(
                size: AppButtonSize.lg,
                radius: AppTokens.radiusMd,
                label: _scanning ? '分析中…' : 'AI 识别',
                onPressed: (_shotPhoto == null || _scanning || _committing)
                    ? null
                    : _runScan,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 拍摄前定位选择行：可点开附近定位列表，切换 [_location] 后下次拍照烧录即采用新定位。
  Widget _buildLocationPickerRow() {
    return InkWell(
      onTap: _pickLocation,
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            MingCuteIcons.mapPinLine,
            size: 16,
            color: AppTokens.accent,
          ),
          const SizedBox(width: AppTokens.space2),
          const Text(
            '拍摄定位',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              height: 20 / 14,
              color: AppTokens.fg2,
            ),
          ),
          const Spacer(),
          Text(
            _location.name,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 22 / 14,
              color: AppTokens.fg,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(
            MingCuteIcons.arrowRightLine,
            size: 16,
            color: AppTokens.muted,
          ),
        ],
      ),
    );
  }

  /// 打开「附近定位」选择器：列出所有定位点（含 GPS / 地址 / 距离），
  /// 用户选择后切换 [_location]；仅在拍摄前可调，切换后下次拍照烧录即采用新定位
  /// （拍完后白卡为只读，本方法不再有入口，照片定位随之锁定）。
  void _pickLocation() {
    AppBottomSheet.show<void>(
      context: context,
      title: '选择附近定位',
      body: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '附近 ${siteLocations.length} 处定位',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  height: 24 / 14,
                  color: AppTokens.fg2,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '定位将烧录到照片水印中（工程取证）',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    height: 24 / 14,
                    color: AppTokens.fg2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 424),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: siteLocations.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (ctx, i) =>
                  _buildLocationTile(ctx, siteLocations[i]),
            ),
          ),
        ],
      ),
    );
  }

  /// 单个附近定位项：名称 + 地址 + GPS/海拔 + 距当前定位距离。
  Widget _buildLocationTile(BuildContext sheetContext, SiteLocation loc) {
    final selected = loc.id == _location.id;
    final km = _location.distanceKmTo(loc);
    final distText =
        km < 1 ? '${(km * 1000).round()}m' : '${km.toStringAsFixed(1)}km';
    return InkWell(
      onTap: () {
        // 只关闭底部弹窗本身，避免误把整个验收页面路由 pop 掉导致黑屏。
        Navigator.pop(sheetContext);
        setState(() => _location = loc);
        AppSnack.show(context, '定位已切换：${loc.name}', kind: AppSnackKind.accent);
      },
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTokens.surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          border: Border.all(
            color: selected ? AppTokens.brand : Colors.transparent,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              MingCuteIcons.location2Line,
              size: 20,
              color: selected ? AppTokens.brand : AppTokens.fg,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 22 / 14,
                      color: selected ? AppTokens.brand : AppTokens.fg,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${loc.address} · ${loc.gpsText} · ${loc.altitude.toStringAsFixed(0)}m',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      height: 20 / 12,
                      color: selected ? AppTokens.muted : AppTokens.fg2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!selected) ...[
                    const SizedBox(height: 4),
                    Text(
                      '距 ${_location.name} $distText',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        height: 20 / 12,
                        color: AppTokens.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  /// 分段「问题描述」：手打文本框 + 语音录入（结果追加到 note）。
  Widget _resultNote() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(MingCuteIcons.editLine, size: 13, color: AppTokens.muted),
            const SizedBox(width: 4),
            const Text('现场情况说明',
                style: TextStyle(
                    fontSize: 11,
                    height: AppTokens.heightCalibrated,
                    color: AppTokens.muted)),
            const Spacer(),
            Text('${_noteController.text.trim().length} 字',
                style: const TextStyle(
                    fontSize: 11,
                    height: AppTokens.heightCalibrated,
                    color: AppTokens.note)),
          ],
        ),
        const SizedBox(height: AppTokens.space2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _noteController,
                maxLines: 4,
                minLines: 3,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                    fontSize: 13, height: 1.5, color: AppTokens.fg),
                decoration: InputDecoration(
                  hintText: '记录现场情况，或点右侧麦克风语音输入…',
                  hintStyle: const TextStyle(
                      fontSize: 12, height: 1.5, color: AppTokens.muted),
                  filled: true,
                  fillColor: AppTokens.surface2,
                  contentPadding: const EdgeInsets.all(AppTokens.space2 + 2),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                    borderSide:
                        const BorderSide(color: AppTokens.accent, width: 1),
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
                final next =
                    cur.isEmpty ? t : '$cur${cur.endsWith(' ') ? '' : ' '}$t';
                setState(() {
                  _noteController.text = next;
                  _noteController.selection = TextSelection.fromPosition(
                    TextPosition(offset: next.length),
                  );
                });
              },
            ),
          ],
        ),
      ],
    );
  }

  /// 「保存记录」主按钮（仅拍照步骤显示）。随页面内容滚动，不吸附底部。
  ///
  /// 按钮禁用态：
  /// - `_saved` → 「已保存（可继续拍摄）」（保存成功后停留）
  /// - `_shotPhoto == null` → 「请先拍照」（未拍摄）
  /// - `_pendingShot != null` → 「请确认使用照片」（拍了但未点「使用」）
  /// - `_scanning` → 「分析中…」
  /// - 其余 → 「保存记录」
  Widget _buildControls() {
    if (_step != _CaptureStep.capture) return const SizedBox.shrink();
    final canSave =
        _shotPhoto != null && _pendingShot == null && !_scanning && !_saved;
    String label;
    if (_committing) {
      // 注：水印烧录期间 main thread 阻塞，build 推迟，
      // 此分支实际不会渲染；但保留 UI 设计以适配未来 isolate 化水印。
      label = '处理中…';
    } else if (_scanning) {
      label = '分析中…';
    } else if (_pendingShot != null) {
      label = '请确认使用照片';
    } else if (_shotPhoto == null) {
      label = '请先拍照';
    } else {
      label = _isPatrolEntry ? '保存巡场标记' : '保存记录';
    }
    return _saved
        ? LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 340;
              final secondaryLabel = _isPatrolEntry ? '返回巡场继续' : '查看验收记录';
              final primaryLabel = _isPatrolEntry ? '继续标记下一个问题' : '继续验收';
              final secondaryAction = SizedBox(
                width: compact ? double.infinity : null,
                child: AppButton(
                  size: AppButtonSize.lg,
                  width: compact ? double.infinity : null,
                  outlined: true,
                  radius: AppTokens.radiusMd,
                  label: secondaryLabel,
                  onPressed: _isPatrolEntry
                      ? _returnToPatrol
                      : () => context.push('/capture-records'),
                ),
              );
              final primaryAction = SizedBox(
                width: compact ? double.infinity : null,
                child: AppButton(
                  size: AppButtonSize.lg,
                  width: compact ? double.infinity : null,
                  radius: AppTokens.radiusMd,
                  label: primaryLabel,
                  onPressed: _startNextCaptureCycle,
                ),
              );
              if (compact) {
                // 窄屏时把两个底部动作改成上下堆叠，避免文案过长挤压。
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    secondaryAction,
                    const SizedBox(height: AppTokens.space2),
                    primaryAction,
                  ],
                );
              }
              // 常规宽度保持左右并排，强调“查看/返回”和“继续下一条”的分层关系。
              return Row(
                children: [
                  Expanded(child: secondaryAction),
                  const SizedBox(width: AppTokens.space3),
                  Expanded(child: primaryAction),
                ],
              );
            },
          )
        : SizedBox(
            width: double.infinity,
            child: AppButton(
              size: AppButtonSize.lg,
              width: double.infinity,
              radius: AppTokens.radiusMd,
              label: label,
              onPressed: canSave ? _saveRecord : null,
            ),
          );
  }

  /// 当前图纸的拍照记录列表（按 drawingKey 过滤）。
  List<Map<String, dynamic>> get _filteredStoredResults => _storedResults
      .where((e) => (e['drawingKey'] as String? ?? '') == _drawingKey)
      .toList();

  /// 「拍照记录」图标入口：底部弹窗展示当前图纸的历史留痕列表
  /// （内容复用分段 [_resultStored]，按 drawingKey 过滤）。
  void _showStoredSheet() {
    AppBottomSheet.show<void>(
      context: context,
      title: '拍照记录',
      body: (ctx) => _resultStored(),
    );
  }

  /// 「拍照记录」底部弹窗内容：当前图纸的历史留痕列表（按 drawingKey 过滤）。
  /// 设计规范：弹窗底 #F4F6F7，列表项为白卡（surface，radiusLg，padding 12），无描边。
  Widget _resultStored() {
    final items = _filteredStoredResults;
    if (items.isEmpty) {
      return _resultEmpty(
        icon: MingCuteIcons.historyLine,
        text: '本图纸暂无拍照记录\n保存后会自动归档到此处，可随时回看',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('本图纸拍照记录 · ${items.length} 条',
            style: const TextStyle(
                fontSize: 11,
                height: AppTokens.heightCalibrated,
                color: AppTokens.muted)),
        const SizedBox(height: AppTokens.space2),
        ...items.map(_buildStoredResultTile),
      ],
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
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.space2),
      child: Material(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        child: InkWell(
          onTap: () => _openStoredDetail(e),
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.space3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildStoredPhoto(e),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text('${e['anchor']} · ${e['floor']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    height: AppTokens.heightCalibrated,
                                    color: AppTokens.fg)),
                          ),
                          const SizedBox(width: AppTokens.space2),
                          Text('${e['ts']}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  height: AppTokens.heightCalibrated,
                                  color: AppTokens.muted)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                          '识别 $count 处缺陷 · $names'
                          '${note.isNotEmpty ? ' · 含描述' : ''}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11,
                              height: AppTokens.heightCalibrated,
                              color: AppTokens.muted)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(MingCuteIcons.deleteLine, size: 18),
                  color: AppTokens.muted,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _confirmDeleteStored(e),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 删除暂存条目前二次确认（避免误删照片文件）。
  Future<void> _confirmDeleteStored(Map<String, dynamic> e) async {
    final ok = await AppDialog.show<bool>(
      context: context,
      title: '删除暂存记录',
      description: '将同时删除该记录及关联照片，确定？',
      actions: AppDialogActions(
        children: [
          AppDialogButton.secondary(
            label: '取消',
            onTap: () => Navigator.of(context, rootNavigator: true).pop(false),
          ),
          AppDialogButton.danger(
            label: '删除',
            onTap: () => Navigator.of(context, rootNavigator: true).pop(true),
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
      _storedResults = _storedResults.where((x) => !identical(x, e)).toList();
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
    AppBottomSheet.showCustom<void>(
      context: context,
      isScrollControlled: true,
      builder: (_, bottomSafeInset) => StoredDetailSheet(
        entry: e,
        bottomSafeInset: bottomSafeInset,
        onDelete: () => _confirmDeleteStored(e),
      ),
    );
  }
}

/// 画布右侧悬浮的缩放控件：与图纸详情页统一为三张独立白卡。
class _ZoomFab extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  const _ZoomFab({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _zoomCard(MingCuteIcons.fullscreenLine, '复位', onReset),
          const SizedBox(height: 8),
          _zoomCard(MingCuteIcons.addLine, '放大', onZoomIn),
          const SizedBox(height: 8),
          _zoomCard(MingCuteIcons.minimizeLine, '缩小', onZoomOut),
        ],
      );

  Widget _zoomCard(IconData icon, String label, VoidCallback onTap) => Material(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 40,
            height: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 24, color: const Color(0xFF09244B)),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 20,
                    child: Center(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 20 / 12,
                          color: Color(0xFF60656B),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// 重选图纸底部弹窗的图纸行：白底 46 高圆角 8，
/// 当前选中态使用品牌蓝描边卡，和其他底部弹窗列表风格保持一致。
class _FloorPickRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FloorPickRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 46,
        child: Material(
          color: AppTokens.surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            onTap: onTap,
            child: Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                border: Border.all(
                  color: selected ? AppTokens.brand : Colors.transparent,
                ),
              ),
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 22 / 14,
                      color: selected ? AppTokens.brand : AppTokens.fg2)),
            ),
          ),
        ),
      );
}

/// 验收页步骤里的图纸选项行：比底部弹窗项更高一些，方便在主页面直接选择。
class _FloorOptionTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FloorOptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? AppTokens.brandTint : AppTokens.surface2,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: AppTokens.heightCalibrated,
                      color: selected ? AppTokens.accent : AppTokens.fg,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: selected ? AppTokens.accent : Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border:
                        selected ? null : Border.all(color: AppTokens.border),
                  ),
                  child: selected
                      ? const Icon(
                          MingCuteIcons.checkLine,
                          size: 12,
                          color: Colors.white,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      );
}

/// 拍照记录详情底部弹层：照片 + AI 结果 + 描述 + 删除 + （可选）转入问题清单。
///
/// 透传回调：
/// - [onDelete]：用户点击「删除该记录」时触发（capture 与验收记录页共用）。
/// - [onConvert]：可选；传入时显示每条 pending 缺陷的「转入问题清单」按钮 + 底部
///   「批量转入问题清单（N）」。调用方负责：构造 [Defect] → `Repository.addDefect` →
///   `refreshDefects(ref)` → 验收记录 status 回写。返回 `true` 表示至少有一条
///   转换成功，弹层会就地刷新显示「已转入问题清单 ✓」（不会关闭弹层）。
/// 结果区分段项：标签 + 可选计数徽标。
class _ResultTabDef {
  final String label;
  final String? badge;
  const _ResultTabDef(this.label, this.badge);
}

class StoredDetailSheet extends StatefulWidget {
  final Map<String, dynamic> entry;
  final VoidCallback onDelete;
  final double bottomSafeInset;

  /// 接收待转的 defects 索引列表（弹层已按 pending 过滤）。
  /// 返回 `true` 表示成功，弹层会就地标记这些条目为 `converted`。
  final Future<bool> Function(List<int> pendingIdxs)? onConvert;

  const StoredDetailSheet({
    super.key,
    required this.entry,
    required this.onDelete,
    this.bottomSafeInset = 0,
    this.onConvert,
  });

  @override
  State<StoredDetailSheet> createState() => _StoredDetailSheetState();
}

class _StoredDetailSheetState extends State<StoredDetailSheet> {
  /// 内部 entry 副本；转入问题清单成功后原地更新 defects[*].status。
  late List<Map<String, dynamic>> _defects;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _defects = (widget.entry['defects'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m.cast<String, dynamic>()))
        .toList();
  }

  int get _pendingCount => _defects
      .where((d) => (d['status']?.toString() ?? 'pending') != 'converted')
      .length;

  Future<void> _convert(List<int> idxs) async {
    if (_busy || widget.onConvert == null || idxs.isEmpty) return;
    setState(() => _busy = true);
    try {
      final ok = await widget.onConvert!(idxs);
      if (ok) {
        setState(() {
          for (final i in idxs) {
            if (i >= 0 && i < _defects.length) {
              _defects[i]['status'] = 'converted';
            }
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final note = (entry['note'] as String? ?? '').trim();
    final photo = entry['photo'] as String?;
    final canConvert = widget.onConvert != null;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scroll) => SingleChildScrollView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(20, 12, 20, 28 + widget.bottomSafeInset),
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
                        // 与右侧 18 关闭图标横排居中，锁行高
                        // （标题可能换行，取 1.1 兼顾行距）
                        height: AppTokens.heightCalibrated,
                        fontWeight: FontWeight.w700,
                        color: AppTokens.fg),
                  ),
                ),
                IconButton(
                  icon: const Icon(MingCuteIcons.closeLine,
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
                        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                      ),
                      alignment: Alignment.center,
                      child: const Text('照片不可用',
                          style:
                              TextStyle(fontSize: 12, color: AppTokens.muted)),
                    );
                  }
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
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
            if (_defects.isEmpty)
              const Text('未分析 / 未识别到缺陷',
                  style: TextStyle(fontSize: 12, color: AppTokens.muted))
            else
              ...List.generate(_defects.length, (i) {
                final d = _defects[i];
                final isConverted =
                    (d['status']?.toString() ?? '') == 'converted';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(AppTokens.space2),
                  decoration: BoxDecoration(
                    color: AppTokens.surface2,
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
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
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  d['desc'] as String,
                                  style: const TextStyle(
                                      fontSize: 11, color: AppTokens.muted),
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
                      if (canConvert) ...[
                        const SizedBox(width: 8),
                        if (isConverted)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTokens.surface2,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppTokens.border),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(MingCuteIcons.checkLine,
                                    size: 12, color: AppTokens.muted),
                                SizedBox(width: 2),
                                Text('已转入问题清单',
                                    style: TextStyle(
                                        fontSize: 11,
                                        // 与 12 check 图标横排居中，锁行高
                                        height: AppTokens.heightCalibrated,
                                        color: AppTokens.muted)),
                              ],
                            ),
                          )
                        else
                          AppButton(
                            label: '转入问题清单',
                            size: AppButtonSize.sm,
                            radius: AppTokens.radiusMd,
                            onPressed: _busy ? null : () => _convert([i]),
                          ),
                      ],
                    ],
                  ),
                );
              }),
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
            // 批量转入问题清单（仅当支持转入问题清单时显示）
            if (canConvert && _pendingCount > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    label: '批量转入问题清单（$_pendingCount）',
                    radius: AppTokens.radiusMd,
                    onPressed: _busy
                        ? null
                        : () => _convert([
                              for (var i = 0; i < _defects.length; i++)
                                if ((_defects[i]['status']?.toString() ?? '') !=
                                    'converted')
                                  i,
                            ]),
                  ),
                ),
              ),
            // 删除
            SizedBox(
              width: double.infinity,
              child: AppButton(
                text: true,
                radius: AppTokens.radiusMd,
                label: '删除该记录',
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onDelete();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
