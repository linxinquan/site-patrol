import 'package:flutter/material.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import 'package:go_router/go_router.dart';
import '../../shared/widgets/nav_icon_button.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/mock/mock_data.dart';

/// 蓝图原稿预览页（P4）：浅色（白底）原稿浏览 + InteractiveViewer 缩放 + 图纸切换。
/// 图纸：assets/drawings 的 PNG 原稿（建施报_06 西楼一层 / 建施报_20 东楼一层 / 建施报_01 总平面图），离线可用、零新依赖。
class BlueprintViewerPage extends StatefulWidget {
  const BlueprintViewerPage({super.key});

  @override
  State<BlueprintViewerPage> createState() => _BlueprintViewerPageState();
}

class _BlueprintViewerPageState extends State<BlueprintViewerPage> {
  final TransformationController _controller = TransformationController();
  int _index = 0;

  Map<String, String> get _drawing => blueprintDrawings[_index];
  String get _src => _drawing['src']!;
  String get _title => _drawing['title']!;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _switchTo(int i) {
    setState(() => _index = i);
    _controller.value = Matrix4.identity();
  }

  void _zoom(double factor) {
    final current = _controller.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(0.5, 4.0);
    _controller.value = Matrix4.identity()..scaleByDouble(next, next, next, 1);
  }

  void _reset() => _controller.value = Matrix4.identity();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.bg,
      appBar: AppBar(
        backgroundColor: AppTokens.bg,
        foregroundColor: AppTokens.fg,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        leadingWidth: 36,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: NavIconButton(
            icon: MingCuteIcons.leftLine,
            color: const Color(0xFF09244B),
            onPressed: () => context.pop(),
          ),
        ),
        title: const Text('蓝图原稿',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTokens.fg)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTokens.surface,
                borderRadius: BorderRadius.circular(AppTokens.radiusLg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTokens.brandTint,
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusSm),
                        ),
                        child: const Icon(
                          MingCuteIcons.documentsLine,
                          size: 18,
                          color: AppTokens.brand,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _title,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                height: 22 / 14,
                                color: AppTokens.fg,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              '保留原图缩放和复位操作，当前页面只优化原稿承载区和图纸切换样式',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                height: 20 / 12,
                                color: AppTokens.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < blueprintDrawings.length; i++)
                        _DrawingSwitchChip(
                          label: blueprintDrawings[i]['label']!,
                          selected: _index == i,
                          onTap: () => _switchTo(i),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTokens.space2),
          Expanded(
            child: Stack(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTokens.surface,
                    borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTokens.surface2,
                      borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InteractiveViewer(
                      transformationController: _controller,
                      minScale: 0.5,
                      maxScale: 4.0,
                      boundaryMargin: const EdgeInsets.all(80),
                      child: Center(
                        child: Image.asset(
                          _src,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    ),
                  ),
                ),
                // 缩放控件保持原逻辑不变，只保留当前位置。
                Positioned(
                  right: 12,
                  bottom: 40,
                  child: _ZoomFab(
                    onZoomIn: () => _zoom(1.3),
                    onZoomOut: () => _zoom(1 / 1.3),
                    onReset: _reset,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 图纸切换按钮：改成轻量按钮式切换，避免默认 ChoiceChip 的系统感。
class _DrawingSwitchChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DrawingSwitchChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? AppTokens.accent : AppTokens.surface2,
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 20 / 12,
              color: selected ? AppTokens.onAccent : AppTokens.fg2,
            ),
          ),
        ),
      );
}

/// 画布右下悬浮的缩放控件（复位 / 放大 / 缩小），白卡药丸，距底 40。
/// 三张独立白卡（40×64，圆角 8），图标 #09244B + 辅文 #60656B，
/// 与图纸详情页 _ZoomFab 完全一致（直接复用）。
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
                  Text(label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12,
                          height: 20 / 12,
                          color: Color(0xFF60656B))),
                ],
              ),
            ),
          ),
        ),
      );
}
