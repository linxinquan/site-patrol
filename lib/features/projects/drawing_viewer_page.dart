import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html show window;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../core/utils/cad_coord.dart';
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
  /// OCF 已缓存于本地服务，渲染不消耗浩辰解析次数。
  void _openCadViewer() {
    if (!kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('专业看图仅支持 Web 端'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final key = widget.d.cadOcfKey ?? widget.d.key;
    html.window.open('/cad_viewer.html?key=$key', '_blank');
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

  /// 演示坐标系（GStarSDK.js 接入前的兜底换算）。
  /// 真实接入后改为从 getPixelImage 的 viewsize 构建。
  CadCoordMapper get _demoMapper => CadCoordMapper(
        viewWidth: widget.d.w,
        viewHeight: widget.d.h,
        worldLeft: 0,
        worldTop: 50000, // 假设 50m 范围
        worldWidth: 50000,
        worldHeight: 50000,
      );

  /// 坐标拾取：点击图纸打点，换算为图纸坐标并记录。
  void _pickAnnotation(
    Offset localPos,
    Matrix4 matrix,
    Size containedSize,
    double dispW,
    double dispH,
  ) {
    // 将点击位置换算为整图像素坐标
    final px = localPos.dx;
    final py = localPos.dy;
    // 整图在屏幕的显示范围（BoxFit.contain 后）已由 dispW/dispH 给出，
    // 点击相对整图左上角：(localPos - 图中原点)。图中原点即 (0,0)。
    // 相对坐标（0~1）
    final relX = (px / dispW).clamp(0.0, 1.0);
    final relY = (py / dispH).clamp(0.0, 1.0);
    // 整图像素坐标（乘图宽高）
    final world = _demoMapper.screenToWorld(
      relX * widget.d.w,
      relY * widget.d.h,
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

    // 存入 provider
    final map = ref.read(cadAnnotationsProvider);
    final list = [...(map[widget.d.key] ?? const <CadAnnotation>[]), ann];
    ref.read(cadAnnotationsProvider.notifier).state = {
      ...map,
      widget.d.key: list,
    };

    // 退出拾取模式，提示坐标
    ref.read(cadPickModeProvider.notifier).state = false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已记录标注：${ann.coordText}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 渲染当前图纸的坐标标注标记。
  List<Widget> _buildAnnotationMarks(double dispW, double dispH) {
    final list =
        ref.watch(cadAnnotationsProvider)[widget.d.key] ?? const <CadAnnotation>[];
    return list
        .map(
          (a) => Positioned(
            left: a.relX * dispW - 12,
            top: a.relY * dispH - 12,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: AppTokens.danger.withValues(alpha: 0.9),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: AppTokens.elevationRaised,
              ),
              child: const Center(
                child: Icon(Icons.push_pin,
                    size: 12, color: Colors.white),
              ),
            ),
          ),
        )
        .toList();
  }

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
                return Center(
                  child: SizedBox(
                    width: dispW,
                    height: dispH,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // 底图：按 contain 自然尺寸显示。
                        // CAD/OCF 图纸（cadOcfKey 非空）显示待渲染占位（GStarSDK 接入后矢量渲染）。
                        Positioned.fill(
                          child: d.cadOcfKey != null
                              ? _CadPlaceholder(
                                  ocfKey: d.cadOcfKey!,
                                  title: d.title,
                                )
                              : Image.asset(
                                  d.src,
                                  fit: BoxFit.fill,
                                  errorBuilder: (_, __, ___) => _CadPlaceholder(
                                    ocfKey: d.key,
                                    title: d.title,
                                  ),
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
                                crossAxisAlignment: CrossAxisAlignment.center,
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
                        // 长按底图任意处也可锚定；拾取模式下点击打点
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onLongPress: _anchor,
                            onTapUp: ref.watch(cadPickModeProvider)
                                ? (details) {
                                    // 局部坐标需要减去图中原点（居中偏移）
                                    final local = details.localPosition;
                                    _pickAnnotation(
                                        local,
                                        _controller.value,
                                        Size(dispW, dispH),
                                        dispW,
                                        dispH);
                                  }
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
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
          onPick: () {
            final cur = ref.read(cadPickModeProvider);
            ref.read(cadPickModeProvider.notifier).state = !cur;
          },
          pickActive: ref.watch(cadPickModeProvider),
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
  final VoidCallback onPick;
  final bool pickActive;
  const _Toolbar({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
    required this.onPdf,
    required this.onLayers,
    required this.onCad,
    required this.onPick,
    required this.pickActive,
  });

  @override
  Widget build(BuildContext context) => Container(
        color: AppTokens.surface,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
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
                icon: LucideIcons.mapPin,
                label: '坐标',
                onTap: onPick,
                active: pickActive),
            _ToolBtn(icon: LucideIcons.fileText, label: 'PDF原稿', onTap: onPdf),
            _ToolBtn(icon: LucideIcons.maximize, label: '复位', onTap: onReset),
          ],
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
