import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../core/utils/cad_coord.dart';
import '../../core/utils/open_web.dart';
import '../../shared/widgets/async_state.dart';
import '../../shared/widgets/cad_info_panel.dart';
import '../../data/models.dart';

/// 图纸查看器：缩放/平移/工具条 + 热点跳转确认 + 长按锚定。
/// 进入与热点跳转均用 context.push，形成返回栈（返回退上一张图，根层才退出）。
class DrawingViewerPage extends ConsumerWidget {
  final String drawingKey;
  const DrawingViewerPage({super.key, required this.drawingKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drawings = ref.watch(drawingsProvider);
    final current =
        drawings.maybeWhen(data: (m) => m[drawingKey], orElse: () => null);
    return Scaffold(
      appBar: AppBar(
        title: current == null
            ? const Text('图纸查看')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(current.title,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTokens.fg),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(current.crumb,
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppTokens.muted,
                          fontWeight: FontWeight.normal)),
                ],
              ),
      ),
      body: AsyncState(
        value: drawings,
        builder: (map) {
          final d = map[drawingKey];
          if (d == null) {
            return const Center(child: Text('未找到该图纸'));
          }
          return _Viewer(
            key: ValueKey(drawingKey),
            d: d,
            allDrawings: map,
          );
        },
      ),
    );
  }
}

class _Viewer extends ConsumerStatefulWidget {
  final Drawing d;
  final Map<String, Drawing> allDrawings;
  const _Viewer({super.key, required this.d, required this.allDrawings});

  @override
  ConsumerState<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends ConsumerState<_Viewer> {
  final _controller = TransformationController();

  @override
  void initState() {
    super.initState();
    // 加载本图纸的坐标校准（离线本地存储）。
    Future.microtask(() async {
      if (!mounted) return;
      await loadCadCalibration(ref, widget.d.key);
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _zoom(double factor) {
    final current = _controller.value.getMaxScaleOnAxis();
    final target = (current * factor).clamp(0.5, 4.0);
    if (target == current) return;
    final f = target / current;
    _controller.value = _controller.value.clone()..scaleByDouble(f, f, f, 1);
  }

  void _reset() => _controller.value = Matrix4.identity();

  void _jumpConfirm(Hotspot h) {
    final target = widget.allDrawings[h.target];
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.space5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('索引 ${h.num} · ${h.label}',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTokens.fg)),
              const SizedBox(height: 6),
              Text('跳转到：${target?.title ?? h.target}',
                  style: const TextStyle(fontSize: 13, color: AppTokens.muted)),
              const SizedBox(height: AppTokens.space4),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(sheetCtx),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: AppTokens.space3),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppTokens.accent),
                      onPressed: () {
                        Navigator.pop(sheetCtx);
                        context.push('/projects/drawing/${h.target}');
                      },
                      child: const Text('跳转'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _anchor() {
    context.push(
      '/capture',
      extra: CaptureArgs(
        floor: widget.d.crumb.replaceAll(' ', ''),
        anchorLabel: '${widget.d.title}·锚点',
        x: 0.5,
        y: 0.5,
      ),
    );
  }

  /// 打开 CAD 专业看图（GStarSDK 矢量渲染页）。
  /// 仅在 Web 平台可用；跳转到同一静态服务的 cad_viewer.html?key=xxx。
  /// 移动端（Android/iOS）走 Flutter 原生「截图底图 + 坐标校准」方案，
  /// 此 Web 入口不可用，点击仅提示。
  void _openCadViewer() {
    if (!kIsWeb || !canOpenWebWindow) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('平板端使用「校准 + 坐标」进行图纸定位'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final key = widget.d.cadOcfKey ?? widget.d.key;
    openWebWindow('/cad_viewer.html?key=$key');
  }

  /// 打开坐标校准弹窗：粘贴 JSON 校准参数（来自 web/cad_viewer_hybrid.html
  /// 的「复制参数」/「复制链接」），或直接应用内置的 B05 校准（已验证 <2mm）。
  Future<void> _openCalibrationDialog() async {
    final d = widget.d;
    final controller = TextEditingController(
      text: _isCalibrated ? _jsonOfCurrent() : '',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('坐标校准'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '粘贴浏览器端校准参数（JSON），或直接应用内置 B05 校准。\n'
                  '获取方式：浏览器打开 cad_viewer_hybrid.html → 校准面板 → 「复制参数」。',
                  style: TextStyle(fontSize: 12, color: AppTokens.muted),
                ),
                const SizedBox(height: AppTokens.space3),
                TextField(
                  controller: controller,
                  maxLines: 5,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  decoration: const InputDecoration(
                    hintText: '{"imgW":4500,"imgH":2551,"a":...,"d":...}',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: AppTokens.space3),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx, 'BUILTIN');
                      },
                      child: const Text('应用内置B05'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('应用'),
          ),
        ],
      ),
    );
    if (result == null) return;

    CadCoordMapper? mapper;
    if (result == 'BUILTIN') {
      // B05 内置校准：X=1/3.022 方向，单点已校（中心偏移）。仅用于未联网快速演示。
      mapper = CadCoordMapper.fromAffine(
        viewWidth: d.w,
        viewHeight: d.h,
        a: 1 / 3.022, // 1489mm / 4500px
        d: -1 / 3.022,
        c: -d.w / 2 * (1 / 3.022),
        f: d.h / 2 / 3.022,
      );
    } else {
      try {
        final j = jsonDecode(result);
        if (j is Map<String, dynamic>) {
          mapper = CadCoordMapper.fromCalibrationMap(j);
        }
      } catch (_) {}
      if (mapper == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('校准参数格式无效，请检查 JSON'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }
    await saveCadCalibration(ref, d.key, mapper);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('校准已保存，图纸坐标定位已生效'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _jsonOfCurrent() {
    final m = ref.read(cadCalibrationMapProvider)[widget.d.key];
    if (m == null) return '';
    return jsonEncode(m.toCalibrationMap());
  }

  /// 打开 CAD 专业看图面板（图层开关 / 布局切换）。
  void _openCadPanel() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => CadInfoPanel(
        drawingKey: widget.d.key,
        // 真实 DWG 关联后在此传入 dwgFileUrl / dwgBase64。
        // 可用 --dart-define=CAD_TEST_DWG_URL=<公网URL> 提供测试 DWG，
        // 面板即会走 getDwgInfo 拉取真实图层/布局（不扣次）。
        dwgFileUrl: _testDwgUrl,
      ),
    );
  }

  /// 编译期测试 DWG URL（可选）；未配置时面板提示未关联数据源。
  String? get _testDwgUrl {
    const url = String.fromEnvironment('CAD_TEST_DWG_URL', defaultValue: '');
    return url.isEmpty ? null : url;
  }

  /// 当前图纸的坐标校准映射（离线本地存储，截图底图仿射校准）。
  /// 若已校准则用真实系数；未校准则回退演示坐标系（便于预览）。
  CadCoordMapper get _coordMapper {
    final calib = ref.watch(cadCalibrationMapProvider)[widget.d.key];
    if (calib != null) return calib;
    // 演示坐标系（未校准时的兜底换算）
    return CadCoordMapper(
      viewWidth: widget.d.w,
      viewHeight: widget.d.h,
      worldLeft: 0,
      worldTop: 50000, // 假设 50m 范围
      worldWidth: 50000,
      worldHeight: 50000,
    );
  }

  /// 本图纸是否已校准。
  bool get _isCalibrated =>
      ref.watch(cadCalibrationMapProvider)[widget.d.key] != null;

  /// 坐标拾取：点击图纸打点，换算为真实图纸坐标并记录缺陷。
  ///
  /// [localPos] 为点击点在 InteractiveViewer 约束盒子坐标系的位置
  /// （来自盒子层 GestureDetector.localPosition，范围 [0..maxW,0..maxH]）。
  /// [matrix] 为 InteractiveViewer 当前的变换矩阵（缩放/平移）。
  /// [containedSize] 为约束盒子尺寸（maxW×maxH），图片在其中按 BoxFit.contain 居中显示。
  ///
  /// 关键：InteractiveViewer 缩放/平移后，localPos 必须先经
  /// [CadCoordMapper.localToViewPixel] 反算回「整图像素坐标（0..imgW, 0..imgH）」，
  /// 再换算真实图纸坐标。切勿把 localPos 直接按显示比例当整图坐标（会系统性偏移）。
  void _pickAnnotation(
    Offset localPos,
    Matrix4 matrix,
    Size containedSize,
  ) {
    // 1. 经变换矩阵反算点击在「整图像素坐标（0..imgW, 0..imgH）」中的位置。
    final pixel = _coordMapper.localToViewPixel(localPos, matrix, containedSize);
    final px = pixel.dx;
    final py = pixel.dy;
    // 2. 归一化比例（供图钉标记定位，与 display 尺寸无关）
    final relX = (widget.d.w > 0) ? (px / widget.d.w).clamp(0.0, 1.0) : 0.0;
    final relY = (widget.d.h > 0) ? (py / widget.d.h).clamp(0.0, 1.0) : 0.0;
    // 3. 用校准映射换算真实图纸坐标（未校准回退演示坐标系）
    final world = _coordMapper.screenToWorld(px, py);

    final now = DateTime.now();
    final ann = CadAnnotation(
      id: '${widget.d.key}_${now.millisecondsSinceEpoch}',
      drawingKey: widget.d.key,
      label: '缺陷点',
      worldX: world.dx,
      worldY: world.dy,
      relX: relX,
      relY: relY,
      createdAt: now,
    );

    // 存入坐标标注 provider（内存态，供图纸上红点显示）
    final map = ref.read(cadAnnotationsProvider);
    final list = [...(map[widget.d.key] ?? const <CadAnnotation>[]), ann];
    ref.read(cadAnnotationsProvider.notifier).state = {
      ...map,
      widget.d.key: list,
    };

    // 退出拾取模式
    ref.read(cadPickModeProvider.notifier).state = false;

    // 打通巡查记录：新建一条缺陷工单（带真实图纸坐标 worldX/worldY）
    _createDefectFromPick(ann, world);
  }

  /// 根据打点坐标创建并写入一条缺陷记录（打通「图纸打点 → 巡查记录」）。
  void _createDefectFromPick(CadAnnotation ann, Offset world) {
    final now = DateTime.now();
    final defect = Defect(
      id: '${widget.d.key}_${now.millisecondsSinceEpoch}',
      part: '${widget.d.title}·缺陷点',
      type: '待分类',
      category: DefectCategory.other,
      severity: DefectSeverity.orange,
      status: DefectStatus.draft,
      anchor: '${widget.d.title}-图纸点',
      floor: widget.d.crumb.replaceAll(' ', ''),
      ts: now.toIso8601String(),
      gps: '',
      alt: '',
      resp: '待指派',
      respUnit: '',
      reporter: '现场巡检',
      tags: ['CAD定位'],
      note: '从图纸拾取定位，坐标 ${ann.coordText}',
      seed: 'cad_pick',
      drawingKey: widget.d.key,
      worldX: world.dx,
      worldY: world.dy,
    );

    final repo = ref.read(repositoryProvider);
    repo.addDefect(defect);

    final calibrated = _isCalibrated;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          calibrated
              ? '已记录缺陷（已校准）：${ann.coordText}\n可在「缺陷」列表查看'
              : '已记录缺陷（未校准，演示值！）：${ann.coordText}\n点「校准」按钮粘贴真实参数后再打点',
        ),
        backgroundColor: calibrated ? null : AppTokens.warning,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
    ref.invalidate(defectsProvider);
  }

  /// 渲染当前图纸的坐标标注标记：图钉 + 序号 + 坐标小标签。
  /// 紧凑显示：大图缩放下也能看清；点击图钉弹窗显示完整坐标 + 跳转到缺陷详情。
  List<Widget> _buildAnnotationMarks(double dispW, double dispH) {
    final list =
        ref.watch(cadAnnotationsProvider)[widget.d.key] ?? const <CadAnnotation>[];
    return List.generate(list.length, (i) {
      final a = list[i];
      final idx = i + 1;
      return Positioned(
        left: a.relX * dispW - 14,
        top: a.relY * dispH - 14,
        child: GestureDetector(
          onTap: () => _showAnnotationDetail(a, idx),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 主图钉（紧凑，红圆+数字序号）
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppTokens.danger,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: AppTokens.elevationRaised,
                ),
                child: Center(
                  child: Text(
                    '$idx',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              // 坐标简略标签（图钉右侧，白底胶囊）
              Positioned(
                left: 32,
                top: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTokens.border, width: 1),
                    boxShadow: AppTokens.elevationRaised,
                  ),
                  child: Text(
                    'X=${a.worldX.toStringAsFixed(1)} Y=${a.worldY.toStringAsFixed(1)}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTokens.fg,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  /// 显示标注详情（弹窗：完整坐标 + 关联缺陷）。
  void _showAnnotationDetail(CadAnnotation a, int idx) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('标注 #$idx'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('图纸坐标', a.coordText),
            _detailRow('相对位置', '${(a.relX * 100).toStringAsFixed(1)}% · ${(a.relY * 100).toStringAsFixed(1)}%'),
            _detailRow('记录时间', a.createdAt.toString().substring(0, 19)),
            _detailRow('校准状态', _isCalibrated ? '已校准（真实图纸坐标）' : '未校准（演示值）'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(cadAnnotationsProvider.notifier).state = {
                ...ref.read(cadAnnotationsProvider),
                widget.d.key: (ref.read(cadAnnotationsProvider)[widget.d.key] ?? const <CadAnnotation>[])
                    .where((x) => x.id != a.id).toList(),
              };
            },
            child: const Text('删除'),
            style: TextButton.styleFrom(foregroundColor: AppTokens.danger),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 76,
              child: Text(k,
                  style: const TextStyle(fontSize: 12, color: AppTokens.muted)),
            ),
            Expanded(
              child: Text(v,
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppTokens.fg,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    return Column(
      children: [
        Expanded(
          child: InteractiveViewer(
            transformationController: _controller,
            minScale: 0.5,
            maxScale: 4,
            boundaryMargin: const EdgeInsets.all(20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // BoxFit.contain：按原始宽高比在可用空间内缩放图，
                // 这里把图放进 FittedBox 让缩放自适应，hotspot 用同一坐标系。
                final maxW = constraints.maxWidth;
                final maxH = constraints.maxHeight;
                final ar = d.w / d.h;
                double dispW = maxW;
                double dispH = dispW / ar;
                if (dispH > maxH) {
                  dispH = maxH;
                  dispW = dispH * ar;
                }
                // 盒子层：占满 InteractiveViewer 约束盒子，接收盒子坐标系的点击，
                // 用于打点/锚定。localPosition ∈ [0..maxW, 0..maxH]，与
                // CadCoordMapper.localToViewPixel 的 containedSize 语义一致。
                return Stack(
                  children: [
                    // 居中的整图（图片坐标系层，含底图/热点/标注标记）
                    Center(
                      child: SizedBox(
                        width: dispW,
                        height: dispH,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // 底图：按 contain 自然尺寸显示。
                            // CAD/OCF 图纸：有截图底图 src 时用 Image.asset 渲染（截图底图+矢量坐标方案，
                            // 离线可用、精度已校验 <2mm）；无底图时回退待渲染占位。
                            Positioned.fill(
                              child: d.src.isNotEmpty
                                  ? Image.asset(
                                      d.src,
                                      fit: BoxFit.fill,
                                      errorBuilder: (_, __, ___) =>
                                          _CadPlaceholder(
                                        ocfKey: d.cadOcfKey ?? d.key,
                                        title: d.title,
                                      ),
                                    )
                                  : _CadPlaceholder(
                                      ocfKey: d.cadOcfKey ?? d.key,
                                      title: d.title,
                                    ),
                            ),
                            // 热点：用 (x * dispW, y * dispH) 定位，与显示像素一致
                            ...d.hotspots.map(
                              (h) => Positioned(
                                left: h.x * dispW - 50,
                                top: h.y * dispH - 14,
                                child: GestureDetector(
                                  onTap: () => _jumpConfirm(h),
                                  onLongPress: _anchor,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      // 数字圆（白底 + 蓝色边框，对齐原型 dv__hotspot）
                                      Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color: AppTokens.surface,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: AppTokens.brand, width: 2),
                                          boxShadow: AppTokens.elevationRaised,
                                        ),
                                        child: Center(
                                          child: Text('${h.num}',
                                              style: const TextStyle(
                                                  color: AppTokens.brand,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold)),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      // 文字标签（白底小药丸，对齐原型 dv__label）
                                      Flexible(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppTokens.surface,
                                            borderRadius: BorderRadius.circular(
                                                AppTokens.radiusSm),
                                            border: Border.all(
                                                color: AppTokens.border),
                                            boxShadow:
                                                AppTokens.elevationRaised,
                                          ),
                                          child: Text(
                                            h.label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 10,
                                                color: AppTokens.fg),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // 坐标标注标记
                            ..._buildAnnotationMarks(dispW, dispH),
                          ],
                        ),
                      ),
                    ),
                    // 盒子层打点/锚定：覆盖全盒子，拾取模式下点击打点
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onLongPress: _anchor,
                        onTapUp: ref.watch(cadPickModeProvider)
                            ? (details) {
                                // 盒子坐标系点击，containedSize 用盒子尺寸
                                final local = details.localPosition;
                                _pickAnnotation(
                                  local,
                                  _controller.value,
                                  Size(maxW, maxH),
                                );
                              }
                            : null,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        _Toolbar(
          onZoomIn: () => _zoom(1.3),
          onZoomOut: () => _zoom(1 / 1.3),
          onReset: _reset,
          onPdf: () => context.push('/blueprint'),
          onLayers: _openCadPanel,
          onCad: _openCadViewer,
          onCalibrate: () => _openCalibrationDialog(),
          onPick: () {
            final cur = ref.read(cadPickModeProvider);
            ref.read(cadPickModeProvider.notifier).state = !cur;
          },
          pickActive: ref.watch(cadPickModeProvider),
          isCalibrated: _isCalibrated,
        ),
        if (d.hotspots.isNotEmpty) _IndexBar(d: d, onJump: _jumpConfirm),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;
  final VoidCallback onPdf;
  final VoidCallback onLayers;
  final VoidCallback onCad;
  final VoidCallback onCalibrate;
  final VoidCallback onPick;
  final bool pickActive;
  final bool isCalibrated;
  const _Toolbar({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
    required this.onPdf,
    required this.onLayers,
    required this.onCad,
    required this.onCalibrate,
    required this.onPick,
    required this.pickActive,
    required this.isCalibrated,
  });

  @override
  Widget build(BuildContext context) => Container(
        color: AppTokens.surface,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _ToolBtn(
                  icon: LucideIcons.box,
                  label: '专业看图',
                  onTap: onCad,
                  accent: true),
              _ToolBtn(icon: LucideIcons.zoomIn, label: '放大', onTap: onZoomIn),
              _ToolBtn(icon: LucideIcons.zoomOut, label: '缩小', onTap: onZoomOut),
              _ToolBtn(
                  icon: LucideIcons.layers,
                  label: '图层',
                  onTap: onLayers,
                  active: true),
              _ToolBtn(
                  icon: LucideIcons.ruler,
                  label: '校准',
                  onTap: onCalibrate,
                  active: isCalibrated),
              _ToolBtn(
                  icon: LucideIcons.mapPin,
                  label: '坐标',
                  onTap: onPick,
                  active: pickActive),
              _ToolBtn(
                  icon: LucideIcons.fileText,
                  label: 'PDF原稿',
                  onTap: onPdf),
              _ToolBtn(
                  icon: LucideIcons.maximize, label: '复位', onTap: onReset),
            ],
          ),
        ),
      );
}

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool accent;
  const _ToolBtn(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.active = false,
      this.accent = false});

  @override
  Widget build(BuildContext context) {
    final Color fg =
        accent ? AppTokens.accent : (active ? AppTokens.brand : AppTokens.mutedA11y);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        decoration: accent
            ? BoxDecoration(
                color: AppTokens.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              )
            : active
                ? BoxDecoration(
                    color: AppTokens.brand.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                  )
                : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: accent
                        ? AppTokens.accent
                        : active
                            ? AppTokens.brand
                            : AppTokens.muted)),
          ],
        ),
      ),
    );
  }
}

class _IndexBar extends StatelessWidget {
  final Drawing d;
  final ValueChanged<Hotspot> onJump;
  const _IndexBar({required this.d, required this.onJump});

  @override
  Widget build(BuildContext context) => Container(
        color: AppTokens.surface,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: d.hotspots
                .map(
                  (h) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      avatar: CircleAvatar(
                        backgroundColor: AppTokens.accent,
                        radius: 10,
                        child: Text('${h.num}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11)),
                      ),
                      label: Text(h.label),
                      onPressed: () => onJump(h),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      );
}

/// CAD/OCF 图纸的待渲染占位。
/// 真实 OCF 需 GStarSDK.js 矢量渲染（未接入）；当前展示图纸信息与状态提示。
class _CadPlaceholder extends StatelessWidget {
  final String ocfKey;
  final String title;
  const _CadPlaceholder({required this.ocfKey, required this.title});

  @override
  Widget build(BuildContext context) => Container(
        color: AppTokens.surface2,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTokens.brandSoft,
                borderRadius: BorderRadius.circular(AppTokens.radiusLg),
              ),
              child: const Icon(LucideIcons.fileText,
                  size: 30, color: AppTokens.brand),
            ),
            const SizedBox(height: AppTokens.space4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTokens.space6),
              child: Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTokens.fg)),
            ),
            const SizedBox(height: AppTokens.space2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTokens.space6),
              child: Text('OCF: $ocfKey',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12, color: AppTokens.muted)),
            ),
            const SizedBox(height: AppTokens.space4),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.space4, vertical: AppTokens.space2),
              decoration: BoxDecoration(
                color: AppTokens.warningSoft,
                borderRadius: BorderRadius.circular(AppTokens.radiusPill),
              ),
              child: const Text('矢量渲染待 GStarSDK 接入',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTokens.warning)),
            ),
          ],
        ),
      );
}
