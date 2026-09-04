import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../shared/widgets/nav_icon_button.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_bottom_sheet.dart';
import '../../shared/widgets/app_snack.dart';
import '../../core/utils/cad_coord.dart';
import '../../core/utils/open_web.dart';
import '../../core/cad/axis_calibration.dart';
import '../../core/cad/axis_auto_calibration.dart';
import '../../shared/widgets/async_state.dart';
import '../../shared/widgets/cad_info_panel.dart';
import '../../data/models.dart';
import '../../shared/widgets/drawing_image.dart';
import '../../data/repository/mock_repository.dart';

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
      backgroundColor: AppTokens.bg,
      appBar: AppBar(
        backgroundColor: AppTokens.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        leading: NavIconButton(icon: MingCuteIcons.leftLine),
        titleSpacing: 12,
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
                          fontSize: 12,
                          color: AppTokens.fg2,
                          fontWeight: FontWeight.w400)),
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

/// 轴网校准的交互阶段。
enum _CalibPhase { idle, collecting }

class _ViewerState extends ConsumerState<_Viewer> {
  final _controller = TransformationController();

  /// 持久化的浏览器原始校准 JSON（用于弹窗预填，免重复粘贴）。
  String? _persistedRawJson;

  // —— 轴网多点校准状态（支持 3+ 点最小二乘拟合）——
  _CalibPhase _calibPhase = _CalibPhase.idle;
  /// 已收集的点对（像素坐标 + 真实图纸坐标 mm）。
  List<CalibPointPair> _calibPairs = [];
  /// 拟合后每点残差（mm），用于在图上标注哪些点偏差大。
  List<double>? _calibResiduals;
  /// 拟合平均残差。
  double? _calibMeanResidual;
  AxisGrid? _axisGrid; // 自动检测的轴线（"红线"），叠加显示辅助点选
  bool _detectingAxis = false;

  @override
  void initState() {
    super.initState();
    // 加载本图纸的坐标校准（离线本地存储），并自动尝试校准（默认自动）。
    Future.microtask(() async {
      if (!mounted) return;
      await loadCadCalibration(ref, widget.d.key);
      // 从校准库读取原始浏览器 JSON（清单已含），供校准弹窗预填。
      _persistedRawJson =
          await ref.read(calibrationLibraryProvider).readRaw(widget.d.key);
      // ★ 默认自动校准：图纸未校准时，自动尝试内置种子/内置演示坐标系，
      //    让"打开即带坐标"，不依赖浏览器端手动导出 JSON。
      if (ref.read(cadCalibrationMapProvider)[widget.d.key] == null) {
        await _autoCalibrateSilently();
      }
      if (mounted) setState(() {});
    });
  }

  /// 静默自动校准：图纸未校准时尝试内置种子校准（随包预置，B05 已验证 <2mm）。
  /// 其次尝试「轴网交点自动套图」（底图轴线交点 ↔ DXF 轴网交点），
  /// 无种子则回退内置演示坐标系（图纸中心=原点），保证"打开即有坐标可用"。
  Future<void> _autoCalibrateSilently() async {
    final d = widget.d;
    try {
      // 1) 优先用随包内置的真实种子（若本图在种子表内）。
      final builtin = _builtinCalibrationFor(d);
      if (builtin != null) {
        await saveCadCalibration(ref, d.key, builtin, null);
        _persistedRawJson = null;
        return;
      }
      // 2) 轴网交点自动套图：识别底图轴线交点 + 匹配随包 CAD 轴网交点，
      //    成功即得真实仿射校准（<2mm），覆盖 D01/D03/D04/B01。
      final axisFit = await _autoCalibrateByAxisGrid();
      if (axisFit != null) {
        await saveCadCalibration(ref, d.key, axisFit.mapper, null);
        _persistedRawJson = null;
        return;
      }
      // 3) 无真实种子：应用内置演示坐标系（图纸中心=原点），
      //    使打点/量尺在当前图仍可用（精度取决于图幅，现场可再手动精校）。
      final scale = ((d.w / 1489) + (d.h / 844)) / 2;
      final demo = CadCoordMapper.fromAffine(
        viewWidth: d.w,
        viewHeight: d.h,
        a: 1 / scale,
        d: -1 / scale,
        c: -d.w / 2 / scale,
        f: d.h / 2 / scale,
      );
      await saveCadCalibration(ref, d.key, demo, null);
    } catch (_) {
      // 自动校准失败不打扰用户，仍可手动校准。
    }
  }

  /// 轴网交点自动套图校准：
  ///   1. 读底图 → 识别横/竖轴线 → 求交点（像素）
  ///   2. 读随包 CAD 轴网交点 JSON（毫米，服务端从 DXF 提取）
  ///   3. [matchAxisIntersections] 行列自动配对 → 仿射最小二乘拟合
  /// 成功返回拟合结果（均值残差 <5mm），失败返回 null（回退其他校准）。
  Future<AffineFitResult?> _autoCalibrateByAxisGrid() async {
    final d = widget.d;
    if (d.src.isEmpty) return null;
    List<ui.Offset>? cadPts;
    try {
      final jsonStr =
          await rootBundle.loadString('assets/axis_data/${d.key}.json');
      final decoded = jsonDecode(jsonStr);
      final pts = decoded['points'] as List;
      cadPts = [
        for (final p in pts)
          ui.Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()),
      ];
    } catch (_) {
      return null; // 该图没有随包轴网数据
    }
    if (cadPts.length < 4) return null;
    try {
      final bytes = await rootBundle.load(d.src);
      final codec = await ui.instantiateImageCodec(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final rgba = await imageToRgba(img);
      img.dispose();
      if (rgba == null) return null;
      final grid = detectAxisLines(
        rgba,
        d.w.round(),
        d.h.round(),
        sampleW: 700,
        minRatio: 0.5,
        maxGap: 4,
        clusterTol: 8,
        maxLines: 40,
      );
      final result = calibrateByAxisGrid(
        grid,
        cadPts,
        d.w,
        d.h,
        trials: 600,
        matchRadiusMm: 3000,
        minInliers: 4,
      );
      if (result.fit == null) return null;
      // 质量门限：均值残差太大视为失败（避免错配套到错误区域）。
      if (result.fit!.meanResidualMm > 5.0) return null;
      return result.fit;
    } catch (_) {
      return null;
    }
  }

  /// 返回本图纸的随包内置真实校准；委托到 [builtinCalibrationFor] 共享同一表。
  /// 运行时轴网匹配见 [_autoCalibrateByAxisGrid]。
  CadCoordMapper? _builtinCalibrationFor(Drawing d) => builtinCalibrationFor(d);

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
    AppBottomSheet.show<void>(
      context: context,
      title: '索引 ${h.num} · ${h.label}',
      body: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('跳转到：${target?.title ?? h.target}',
              style: const TextStyle(fontSize: 14, color: AppTokens.muted)),
          const SizedBox(height: AppTokens.space4),
          AppSheetFooter.cancelSave(
            cancelLabel: '取消',
            saveLabel: '跳转',
            onCancel: () => Navigator.pop(ctx),
            onSave: () {
              Navigator.pop(ctx);
              context.push('/projects/drawing/${h.target}');
            },
          ),
        ],
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
        drawingKey: widget.d.key,
      ),
    );
  }

  /// 打开 CAD 专业看图（GStarSDK 矢量渲染页）。
  /// 仅在 Web 平台可用；跳转到同一静态服务的 cad_viewer.html?key=xxx。
  /// 移动端（Android/iOS）走 Flutter 原生「截图底图 + 坐标校准」方案，
  /// 此 Web 入口不可用，点击仅提示。
  void _openCadViewer() {
    if (!kIsWeb || !canOpenWebWindow) {
      AppSnack.show(context, '平板端使用「校准 + 坐标」进行图纸定位');
      return;
    }
    final key = widget.d.cadOcfKey ?? widget.d.key;
    openWebWindow('/cad_viewer.html?key=$key');
  }

  /// 打开坐标校准弹窗：粘贴 JSON 校准参数（来自 web/cad_viewer_hybrid.html
  /// 的「复制参数」/「复制链接」），或直接应用内置的 B05 校准（已验证 <2mm）。
  Future<void> _openCalibrationDialog() async {
    final d = widget.d;
    // 弹窗预填优先级：内存态（本次已粘贴/内置）→ 持久化原始 JSON → 空占位。
    final initialText = _isCalibrated
        ? _jsonOfCurrent()
        : (_persistedRawJson ?? '');
    final controller = TextEditingController(text: initialText);
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
                  '粘贴浏览器端校准参数（JSON），获得与浏览器一致的 <2mm 精度。\n'
                  '获取方式：浏览器打开 cad_viewer_hybrid.html → 校准面板 → 「复制参数」。\n'
                  '「应用内置B05」仅为离线演示（假设图纸中心=坐标原点），非真实校准，'
                  '除图纸中心外均会偏移，不可用于验收数据。',
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
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx, 'AXIS');
                      },
                      child: const Text('图上多点校准'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (_isCalibrated)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _clearCalibration();
              },
              child: const Text('清除校准'),
            ),
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

    if (result == 'AXIS') {
      _startAxisCalibration();
      return;
    }

    CadCoordMapper? mapper;
    if (result == 'BUILTIN') {
      // B05 内置校准：与 web/cad_viewer_hybrid.html 的 debugPoint 完全同式，
      // 即 scale=((imgW/1489)+(imgH/844))/2（X/Y 平均法），保证浏览器「调试信息」
      // 输出的坐标与此处一致，便于肉眼对照打点（<2mm）。
      //   a = 1/scale; c = -imgW/2/scale
      //   d = -1/scale; f = +imgH/2/scale
      final scale = ((d.w / 1489) + (d.h / 844)) / 2;
      mapper = CadCoordMapper.fromAffine(
        viewWidth: d.w,
        viewHeight: d.h,
        a: 1 / scale,
        d: -1 / scale,
        c: -d.w / 2 / scale,
        f: d.h / 2 / scale,
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
        AppSnack.show(context, '校准参数格式无效，请检查 JSON',
            kind: AppSnackKind.danger);
        return;
      }
    }
    // 保存校准并登记进校准库；内置演示坐标系传 null（从库中移除）。
    await saveCadCalibration(
      ref,
      d.key,
      mapper,
      result == 'BUILTIN' ? null : result,
    );
    _persistedRawJson = result == 'BUILTIN' ? null : result;
    if (!mounted) return;
    setState(() {});
    AppSnack.show(context, '校准已保存，图纸坐标定位已生效',
        kind: AppSnackKind.success);
  }

  /// 清除本图纸校准，回到内置演示坐标系（校准库同步移除）。
  Future<void> _clearCalibration() async {
    final d = widget.d;
    await deleteCadCalibration(ref, d.key);
    _persistedRawJson = null;
    if (!mounted) return;
    setState(() {});
    AppSnack.show(context, '已清除校准，回到内置演示坐标系',
        kind: AppSnackKind.muted);
  }

  /// 开始"图上多点校准"：进入轴网拾取模式，并异步识别轴线（红线）辅助点选。
  /// 支持 3+ 点最小二乘拟合（含旋转/仿射失真），并自动剔除残差大的点。
  void _startAxisCalibration() {
    setState(() {
      _calibPhase = _CalibPhase.collecting;
      _calibPairs = [];
      _calibResiduals = null;
      _calibMeanResidual = null;
      _axisGrid = null;
    });
    AppSnack.show(
      context,
      '校准模式：点击轴线交点添加点位（≥2 点生效，建议 3~5 点更精准）',
      kind: AppSnackKind.brand,
      actionLabel: '取消',
      onAction: _cancelAxisCalibration,
    );
    _detectAxisLinesAsync();
  }

  /// 异步识别底图轴线：读 asset → 解码 → 扫描长线 → 叠加红色辅助线。
  Future<void> _detectAxisLinesAsync() async {
    final d = widget.d;
    if (_detectingAxis || d.src.isEmpty) return;
    setState(() => _detectingAxis = true);
    try {
      final bytes = await rootBundle.load(d.src);
      final codec = await ui.instantiateImageCodec(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final rgba = await imageToRgba(img);
      img.dispose();
      if (rgba == null || !mounted) return;
      final grid = detectAxisLines(
        rgba,
        d.w.round(),
        d.h.round(),
        sampleW: 700,
        minRatio: 0.5,
        maxGap: 4,
        clusterTol: 8,
        maxLines: 30,
      );
      if (!mounted) return;
      setState(() {
        _axisGrid = grid;
        _detectingAxis = false;
      });
      AppSnack.show(
        context,
        '已识别 ${grid.horizontals.length} 横轴 + ${grid.verticals.length} 纵轴（红色辅助线）',
        kind: AppSnackKind.success,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _detectingAxis = false);
    }
  }

  /// 校准模式下的图纸点击：换算整图像素坐标，弹窗录入真实图纸坐标。
  void _handleCalibTap(
    Offset localPos,
    double dispW,
    double dispH,
    double maxW,
    double maxH,
  ) {
    if (_calibPhase == _CalibPhase.idle) return;
    final originX = (maxW - dispW) / 2;
    final originY = (maxH - dispH) / 2;
    final imgX = localPos.dx - originX;
    final imgY = localPos.dy - originY;
    final relX = (dispW > 0) ? (imgX / dispW).clamp(0.0, 1.0) : 0.0;
    final relY = (dispH > 0) ? (imgY / dispH).clamp(0.0, 1.0) : 0.0;
    final px = Offset(relX * widget.d.w, relY * widget.d.h);
    _promptWorldCoord('第 ${_calibPairs.length + 1} 点', px);
  }

  /// 录入某像素点的真实图纸坐标（mm），并加入点对列表。
  Future<void> _promptWorldCoord(String title, Offset px) async {
    final xCtrl = TextEditingController();
    final yCtrl = TextEditingController();
    // 若图上已有旧校准，可把"当前换算值"预填，用户微调更省事。
    if (_isCalibrated) {
      final w = _coordMapper.screenToWorld(px.dx, px.dy);
      xCtrl.text = w.dx.toStringAsFixed(1);
      yCtrl.text = w.dy.toStringAsFixed(1);
    }
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$title 真实图纸坐标'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '输入该点在图纸坐标系中的真实坐标（mm）\n可从 CAD 轴号查（如轴线交点 ①-Ⓐ）',
              style: TextStyle(fontSize: 12, color: AppTokens.muted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: xCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'X (mm)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: yCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Y (mm)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final x = double.tryParse(xCtrl.text.trim());
              final y = double.tryParse(yCtrl.text.trim());
              if (x == null || y == null) {
                AppSnack.show(ctx, '请输入有效数字', kind: AppSnackKind.danger);
                return;
              }
              Navigator.pop(ctx, (xCtrl.text.trim(), yCtrl.text.trim()));
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result == null) return; // 取消仅忽略本次，仍留在 collecting 继续加点

    final world = Offset(double.parse(result.$1), double.parse(result.$2));
    final pairs = [..._calibPairs, CalibPointPair(pixel: px, world: world)];
    setState(() {
      _calibPairs = pairs;
      _calibResiduals = null;
      _calibMeanResidual = null;
    });
    if (pairs.length >= 2) {
      // 实时预览：2+ 点即可算一次（≥3 点走最小二乘+残差）。
      _tryFitPreview();
    }
    AppSnack.show(
      context,
      '第 ${pairs.length} 点已记 → (${world.dx.toStringAsFixed(1)}, ${world.dy.toStringAsFixed(1)})mm'
      '${pairs.length >= 2 ? ' · 已 ${pairs.length} 点' : ''}'
      '（继续点击可加点，≥3 点最小二乘更精准）',
      kind: AppSnackKind.brand,
      actionLabel: pairs.length >= 3 ? '完成' : null,
      onAction: pairs.length >= 3 ? _finishAxisCalibration : null,
    );
  }

  /// 实时预览拟合结果（仅算不保存），便于用户在图上看到残差分布。
  void _tryFitPreview() {
    if (_calibPairs.length < 2) return;
    final d = widget.d;
    final fit = fitAffineRobust(_calibPairs, d.w, d.h);
    if (fit == null) return;
    if (!mounted) return;
    setState(() {
      _calibResiduals = fit.residuals;
      _calibMeanResidual = fit.meanResidualMm;
    });
  }

  /// 点已收集齐：稳健拟合并保存校准。
  void _finishAxisCalibration() {
    final pairs = _calibPairs;
    if (pairs.length < 2) {
      AppSnack.show(context, '至少需要 2 个点', kind: AppSnackKind.danger);
      return;
    }
    final d = widget.d;
    final fit = fitAffineRobust(pairs, d.w, d.h);
    if (fit == null) {
      AppSnack.show(
          context,
          pairs.length >= 3
              ? '点共线或过少，无法解算，请增加非共线点'
              : '两点坐标无法解算（两点太近/无跨度），请重选',
          kind: AppSnackKind.danger);
      setState(() => _calibPhase = _CalibPhase.collecting);
      return;
    }
    final mapper = fit.mapper;
    // 保存并登记校准库（图上校准无浏览器原始 JSON，传 null）。
    saveCadCalibration(ref, d.key, mapper, null);
    _persistedRawJson = null;
    setState(() {
      _calibPhase = _CalibPhase.idle;
      _calibPairs = [];
      _calibResiduals = null;
      _calibMeanResidual = null;
      _axisGrid = null;
    });
    // 提示质量：多点拟合平均残差越小越好。
    final quality = fit.meanResidualMm <= 1
        ? '优'
        : fit.meanResidualMm <= 5
            ? '良'
            : '一般（建议增加点/检查点选）';
    AppSnack.show(
      context,
      '校准已保存 · ${pairs.length} 点拟合 平均残差 ${fit.meanResidualMm.toStringAsFixed(1)}mm（${quality}）'
      '${fit.maxResidualMm > 50 ? ' · 已剔除偏差大点' : ''}',
      kind: AppSnackKind.success,
    );
  }

  /// 取消/退出校准模式。
  void _cancelAxisCalibration() {
    setState(() {
      _calibPhase = _CalibPhase.idle;
      _calibPairs = [];
      _calibResiduals = null;
      _calibMeanResidual = null;
      _axisGrid = null;
    });
    AppSnack.show(context, '已退出校准', kind: AppSnackKind.muted);
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
      backgroundColor: AppTokens.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
  /// 坐标拾取：点击图纸打点，换算为真实图纸坐标并记录缺陷。
  ///
  /// [localPos] 为点击点在 InteractiveViewer 约束盒子坐标系的位置
  /// （来自盒子层 GestureDetector.localPosition，范围 [0..maxW,0..maxH]）。
  /// 注意：InteractiveViewer 内部用 [Transform]（transformHitTests=true）包裹 child，
  /// 手势回调的 localPosition 已经被自动反变换为「未缩放/平移的盒子坐标」，
  /// 因此**不能再**用变换矩阵二次反算（会双重反变换导致坐标错误）。
  ///
  /// 换算：盒子坐标 - 图片居中偏移（图片按 BoxFit.contain 在盒子内居中）
  /// → 图片显示坐标 → 归一化比例 → 整图像素坐标 → 世界坐标。
  ///
  /// [dispW]/[dispH]：图片在盒子内的显示尺寸（BoxFit.contain 后）。
  /// [maxW]/[maxH]：InteractiveViewer 约束盒子尺寸。
  void _pickAnnotation(
    Offset localPos,
    double dispW,
    double dispH,
    double maxW,
    double maxH,
  ) {
    // 1. 图片显示区域在盒子内的左上角偏移（居中）
    final originX = (maxW - dispW) / 2;
    final originY = (maxH - dispH) / 2;
    // 2. 点击点在图片显示坐标系内的位置
    final imgX = localPos.dx - originX;
    final imgY = localPos.dy - originY;
    // 3. 归一化比例（供图钉标记定位，与 display 尺寸无关）
    final relX = (dispW > 0) ? (imgX / dispW).clamp(0.0, 1.0) : 0.0;
    final relY = (dispH > 0) ? (imgY / dispH).clamp(0.0, 1.0) : 0.0;
    // 4. 整图像素坐标（0..imgW, 0..imgH）
    final px = relX * widget.d.w;
    final py = relY * widget.d.h;
    // 5. 用校准映射换算真实图纸坐标（未校准回退演示坐标系）
    final world = _coordMapper.screenToWorld(px, py);

    // ★ 诊断日志（坐标仍不准时把这段控制台输出截图即可诊断）
    debugPrint(
      '[CAD PICK] drawing=${widget.d.key} '
      'local=(${localPos.dx.toStringAsFixed(1)},${localPos.dy.toStringAsFixed(1)}) '
      'box=($maxW,$maxH) disp=($dispW,$dispH) '
      'origin=(${(maxW - dispW) / 2},${(maxH - dispH) / 2}) '
      'img=(${px.toStringAsFixed(1)},${py.toStringAsFixed(1)}) '
      'world=(${world.dx.toStringAsFixed(2)},${world.dy.toStringAsFixed(2)}) '
      'useAffine=${_coordMapper.useAffine} '
      'a=${_coordMapper.a.toStringAsFixed(6)} '
      'd=${_coordMapper.d.toStringAsFixed(6)} '
      'c=${_coordMapper.c.toStringAsFixed(2)} '
      'f=${_coordMapper.f.toStringAsFixed(2)}',
    );

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

    // 打通巡查记录：新建一条巡场清单记录（带真实图纸坐标 worldX/worldY）
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
      reporter: '现场记录',
      tags: ['CAD定位'],
      note: '从图纸拾取定位，坐标 ${ann.coordText}',
      seed: 'cad_pick',
      drawingKey: widget.d.key,
      worldX: world.dx,
      worldY: world.dy,
    );

    final repo = ref.read(repositoryProvider);
    // 归入当前项目，避免新增缺陷串到另一个项目。
    if (repo is MockRepository) {
      repo.currentIs7 = ref.read(is7DongProjectProvider);
    }
    repo.addDefect(defect);

    final calibrated = _isCalibrated;
    AppSnack.show(
      context,
      calibrated
          ? '已记录缺陷：${ann.coordText} · 点击图钉可拍照记录'
          : '已记录缺陷（未校准演示值）：${ann.coordText} · 先校准再打点',
      kind: calibrated ? AppSnackKind.success : AppSnackKind.danger,
      actionLabel: '拍照',
      onAction: () => _captureAtAnnotation(ann),
    );
    ref.invalidate(defectsProvider);
  }

  /// 渲染当前图纸的坐标标注标记：小图钉 + 序号。
  /// 默认不显示坐标标签，避免遮挡图纸；点击图钉弹窗显示完整坐标。
  List<Widget> _buildAnnotationMarks(double dispW, double dispH) {
    final list =
        ref.watch(cadAnnotationsProvider)[widget.d.key] ?? const <CadAnnotation>[];
    // 小图钉尺寸：随图纸缩放，但基数较小，减少遮挡。
    const pinR = 10.0;
    const tipH = 5.0;
    return List.generate(list.length, (i) {
      final a = list[i];
      final idx = i + 1;
      return Positioned(
        // 尖端对准打点位置：(relX*dispW, relY*dispH)
        left: a.relX * dispW - pinR,
        top: a.relY * dispH - pinR - tipH,
        child: GestureDetector(
          onTap: () => _showAnnotationDetail(a, idx),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 图钉主体（红圆 + 数字序号，白边醒目）
              Container(
                width: pinR * 2,
                height: pinR * 2,
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
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      shadows: [
                        Shadow(
                          color: Colors.black38,
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // 底部尖端（指向精确坐标点）
              Positioned(
                left: pinR - 4,
                top: pinR * 2 - 3,
                child: Transform.rotate(
                  angle: 0.7854, // 45°
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppTokens.danger,
                      borderRadius: BorderRadius.circular(1.5),
                      border: Border.all(color: Colors.white, width: 1.5),
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

  /// 显示标注详情（弹窗：完整坐标 + 诊断 + 关联缺陷 + 拍照记录）。
  void _showAnnotationDetail(CadAnnotation a, int idx) {
    final mapper = _coordMapper;
    final calibInfo = mapper.useAffine
        ? 'a=${mapper.a.toStringAsFixed(4)} '
            'd=${mapper.d.toStringAsFixed(4)} '
            'c=${mapper.c.toStringAsFixed(1)} '
            'f=${mapper.f.toStringAsFixed(1)}'
        : '范围 [${mapper.worldLeft.toStringAsFixed(0)}, '
            '${(mapper.worldLeft + mapper.worldWidth).toStringAsFixed(0)}]×'
            '[${(mapper.worldTop - mapper.worldHeight).toStringAsFixed(0)}, '
            '${mapper.worldTop.toStringAsFixed(0)}] mm';
    final pxImg = (a.relX * widget.d.w).toStringAsFixed(0);
    final pyImg = (a.relY * widget.d.h).toStringAsFixed(0);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('标注 #$idx'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('图纸坐标', a.coordText),
            _detailRow('整图像素', '($pxImg, $pyImg) / '
                '${widget.d.w.toStringAsFixed(0)}×${widget.d.h.toStringAsFixed(0)}'),
            _detailRow('相对位置', '${(a.relX * 100).toStringAsFixed(1)}% · ${(a.relY * 100).toStringAsFixed(1)}%'),
            _detailRow('校准状态', _isCalibrated ? '已校准' : '未校准（演示值）'),
            _detailRow('校准参数', calibInfo),
            _detailRow('记录时间', a.createdAt.toString().substring(0, 19)),
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
            style: TextButton.styleFrom(foregroundColor: AppTokens.danger),
            child: const Text('删除'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _captureAtAnnotation(a);
            },
            style: FilledButton.styleFrom(backgroundColor: AppTokens.accent),
            child: const Text('拍照记录'),
          ),
        ],
      ),
    );
  }

  /// 从图钉直接进入拍照：带图纸坐标写入 CaptureArgs。
  void _captureAtAnnotation(CadAnnotation a) {
    context.push(
      '/capture',
      extra: CaptureArgs(
        floor: widget.d.crumb.replaceAll(' ', ''),
        anchorLabel: '${widget.d.title}·标注',
        x: a.relX,
        y: a.relY,
        drawingKey: a.drawingKey,
        drawPointWorldX: a.worldX,
        drawPointWorldY: a.worldY,
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
                            // CAD/OCF 图纸：有截图底图 src 时渲染（截图底图+矢量坐标方案；
                            // 预置图为 assets，上传图为网络 PNG——DrawingImage 自适应）。
                            Positioned.fill(
                              child: d.src.isNotEmpty
                                  ? DrawingImage(
                                      d.src,
                                      fit: BoxFit.fill,
                                      errorWidget: _CadPlaceholder(
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
                            // 轴网校准叠加层：红线 + 已选点
                            if (_calibPhase != _CalibPhase.idle)
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _AxisOverlayPainter(
                                    grid: _axisGrid,
                                    imgW: widget.d.w,
                                    imgH: widget.d.h,
                                    points: [
                                      for (final p in _calibPairs)
                                        Offset(
                                          p.pixel.dx / widget.d.w * dispW,
                                          p.pixel.dy / widget.d.h * dispH,
                                        )
                                    ],
                                    residuals: _calibResiduals,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    // 校准模式提示条
                    if (_calibPhase != _CalibPhase.idle)
                      Positioned(
                        left: 12,
                        right: 12,
                        top: 10,
                        child: _CalibHintBar(
                          phase: _calibPhase,
                          detecting: _detectingAxis,
                          pointCount: _calibPairs.length,
                          meanResidual: _calibMeanResidual,
                          onCancel: _cancelAxisCalibration,
                          onFinish: _calibPairs.length >= 3
                              ? _finishAxisCalibration
                              : null,
                        ),
                      ),
                    // 盒子层打点/锚定：覆盖全盒子，拾取/校准模式下点击
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onLongPress: _anchor,
                        onTapUp: _calibPhase != _CalibPhase.idle
                            ? (details) {
                                // 校准模式：优先响应（避免与坐标拾取冲突）
                                final local = details.localPosition;
                                _handleCalibTap(local, dispW, dispH, maxW, maxH);
                              }
                            : ref.watch(cadPickModeProvider)
                                ? (details) {
                                    // 盒子坐标系点击（localPosition 已被 Transform 自动反变换，
                                    // 不能再乘变换矩阵）。传图片显示尺寸与盒子尺寸。
                                    final local = details.localPosition;
                                    _pickAnnotation(local, dispW, dispH, maxW, maxH);
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
                  icon: MingCuteIcons.boxLine,
                  label: '专业看图',
                  onTap: onCad,
                  accent: true),
              _ToolBtn(icon: MingCuteIcons.zoomInLine, label: '放大', onTap: onZoomIn),
              _ToolBtn(icon: MingCuteIcons.zoomOutLine, label: '缩小', onTap: onZoomOut),
              _ToolBtn(
                  icon: MingCuteIcons.layersLine,
                  label: '图层',
                  onTap: onLayers,
                  active: true),
              _ToolBtn(
                  icon: MingCuteIcons.rulerLine,
                  label: '校准',
                  onTap: onCalibrate,
                  active: isCalibrated),
              _ToolBtn(
                  icon: MingCuteIcons.mapPinLine,
                  label: '坐标',
                  onTap: onPick,
                  active: pickActive),
              _ToolBtn(icon: MingCuteIcons.documentLine, label: 'PDF原稿', onTap: onPdf),
              _ToolBtn(icon: MingCuteIcons.fullscreenLine, label: '复位', onTap: onReset),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        decoration: accent
            ? BoxDecoration(
                color: AppTokens.fg.withValues(alpha: 0.12),
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
            Icon(icon,
                size: 18,
                color: accent
                    ? AppTokens.fg
                    : active
                        ? AppTokens.brand
                        : AppTokens.muted),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: accent
                        ? AppTokens.fg
                        : active
                            ? AppTokens.brand
                            : AppTokens.muted)),
          ],
        ),
      ),
    );
  }
}

/// 轴网校准叠加层：检测到的红线 + 已选点标记（显示坐标 = 图片显示像素）。
/// 已选点按序号标号，若有拟合残差则标在点旁（红色 = 残差偏大，便于复校）。
class _AxisOverlayPainter extends CustomPainter {
  final AxisGrid? grid;
  final List<Offset> points; // 已选点（图片显示坐标）
  final List<double>? residuals; // 拟合残差（mm），与 points 一一对应
  final double imgW; // 整图原始像素宽（AxisLine 坐标基准）
  final double imgH;
  const _AxisOverlayPainter({
    this.grid,
    this.points = const [],
    this.residuals,
    required this.imgW,
    required this.imgH,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 红线：半透明红色虚线，辅助对齐轴线交点（原图坐标 → 显示坐标）
    if (grid != null && imgW > 0 && imgH > 0) {
      final paint = Paint()
        ..color = const Color(0xFFFF3B30).withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      for (final h in grid!.horizontals) {
        canvas.drawLine(
            Offset(h.a.dx / imgW * size.width, h.a.dy / imgH * size.height),
            Offset(h.b.dx / imgW * size.width, h.b.dy / imgH * size.height),
            paint);
      }
      for (final v in grid!.verticals) {
        canvas.drawLine(
            Offset(v.a.dx / imgW * size.width, v.a.dy / imgH * size.height),
            Offset(v.b.dx / imgW * size.width, v.b.dy / imgH * size.height),
            paint);
      }
    }
    // 已选点：按序号标号；残差大（>50mm）的显示为红色警示
    for (var i = 0; i < points.length; i++) {
      final r = residuals != null && i < residuals!.length
          ? residuals![i]
          : null;
      final bad = r != null && r > 50;
      _drawPoint(canvas, points[i], '${i + 1}', bad: bad, residual: r);
    }
  }

  void _drawPoint(Canvas canvas, Offset p, String label,
      {bool bad = false, double? residual}) {
    final c = bad ? const Color(0xFFDC2626) : const Color(0xFF16A34A);
    canvas.drawCircle(p, 7, Paint()..color = c.withValues(alpha: 0.3));
    canvas.drawCircle(
      p,
      5,
      Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final tp = TextPainter(
      text: TextSpan(
          text: label,
          style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: Colors.white)),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.drawCircle(p, 5, Paint()..color = c);
    tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    // 残差标注（>0 时画在点右下）
    if (residual != null) {
      final rp = TextPainter(
        text: TextSpan(
            text: '${residual.toStringAsFixed(0)}mm',
            style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w600,
                color: bad ? const Color(0xFFDC2626) : AppTokens.patrolFg)),
        textDirection: TextDirection.ltr,
      )..layout();
      rp.paint(canvas, p + const Offset(7, 6));
    }
  }

  @override
  bool shouldRepaint(covariant _AxisOverlayPainter oldDelegate) =>
      oldDelegate.grid != grid ||
      oldDelegate.points.length != points.length ||
      oldDelegate.residuals != residuals;
}

/// 校准模式顶部提示条：显示当前点数/残差质量，≥3 点时显示"完成"。
class _CalibHintBar extends StatelessWidget {
  final _CalibPhase phase;
  final bool detecting;
  final int pointCount;
  final double? meanResidual;
  final VoidCallback onCancel;
  final VoidCallback? onFinish;
  const _CalibHintBar({
    required this.phase,
    required this.detecting,
    required this.pointCount,
    required this.meanResidual,
    required this.onCancel,
    this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    String label;
    if (detecting) {
      label = '正在识别轴线红线…';
    } else if (pointCount == 0) {
      label = '点击轴线交点添加点位（≥2 生效，3~5 点更精准）';
    } else if (pointCount < 2) {
      label = '已 $pointCount 点 · 继续点击添加（建议 ≥3 点）';
    } else {
      final q = meanResidual == null
          ? ''
          : meanResidual! <= 1
              ? ' · 均差 ${meanResidual!.toStringAsFixed(1)}mm 优'
              : meanResidual! <= 5
                  ? ' · 均差 ${meanResidual!.toStringAsFixed(1)}mm 良'
                  : ' · 均差 ${meanResidual!.toStringAsFixed(1)}mm 一般';
      label = '已 $pointCount 点$q · 点击可继续加点';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTokens.bg.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        border: Border.all(color: AppTokens.border),
        boxShadow: AppTokens.elevationRaised,
      ),
      child: Row(
        children: [
          Icon(
            detecting
                ? MingCuteIcons.loadingLine
                : MingCuteIcons.mapPinLine,
            size: 14,
            color: AppTokens.brand,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12,
                    color: AppTokens.fg,
                    fontWeight: FontWeight.w500)),
          ),
          if (onFinish != null)
            InkWell(
              onTap: onFinish,
              borderRadius: BorderRadius.circular(AppTokens.radiusPill),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTokens.brand.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                ),
                child: const Text('完成',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppTokens.brand,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          InkWell(
            onTap: onCancel,
            borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: const Text('取消',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppTokens.danger,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ],
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
                        backgroundColor: AppTokens.fg,
                        radius: 10,
                        child: Text('${h.num}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12)),
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
              child: const Icon(MingCuteIcons.documentLine,
                  size: 30, color: AppTokens.brand),
            ),
            const SizedBox(height: AppTokens.space4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTokens.space6),
              child: Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
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
                color: AppTokens.warningTint,
                borderRadius: BorderRadius.circular(AppTokens.radiusPill),
              ),
              child: const Text('矢量渲染待 GStarSDK 接入',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AppTokens.warning)),
            ),
          ],
        ),
      );
}
