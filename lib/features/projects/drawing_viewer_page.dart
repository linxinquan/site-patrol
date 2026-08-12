import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../shared/widgets/async_state.dart';
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

class _Viewer extends StatefulWidget {
  final Drawing d;
  final Map<String, Drawing> allDrawings;
  const _Viewer({super.key, required this.d, required this.allDrawings});

  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
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
                        // 底图：按 contain 自然尺寸显示
                        Positioned.fill(
                          child: Image.asset(
                            d.src,
                            fit: BoxFit.fill,
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
                        // 长按底图任意处也可锚定
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onLongPress: _anchor,
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
  const _Toolbar({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
    required this.onPdf,
  });

  @override
  Widget build(BuildContext context) => Container(
        color: AppTokens.surface,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _ToolBtn(icon: LucideIcons.zoomIn, label: '放大', onTap: onZoomIn),
            _ToolBtn(icon: LucideIcons.zoomOut, label: '缩小', onTap: onZoomOut),
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
  const _ToolBtn(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: AppTokens.mutedA11y),
              const SizedBox(height: 2),
              Text(label,
                  style: const TextStyle(fontSize: 11, color: AppTokens.muted)),
            ],
          ),
        ),
      );
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
