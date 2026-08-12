import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/mock/mock_data.dart';

/// 蓝图原稿预览页（P4）：深色蓝图氛围 + InteractiveViewer 缩放 + 图纸切换。
/// 图纸：assets/drawings 的 PNG 原稿（西楼1F / 东楼1F / 总平面图），离线可用、零新依赖。
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
      backgroundColor: const Color(0xFF0B1220),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1220),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('蓝图原稿',
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700)),
        centerTitle: false,
      ),
      body: Column(
        children: [
          // 顶部图纸切换
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.space4, vertical: AppTokens.space2),
            child: Row(
              children: [
                for (var i = 0; i < blueprintDrawings.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppTokens.space2),
                  Expanded(
                    child: ChoiceChip(
                      label: Text(blueprintDrawings[i]['label']!,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _index == i
                                  ? AppTokens.onAccent
                                  : Colors.white70)),
                      selected: _index == i,
                      onSelected: (_) => _switchTo(i),
                      backgroundColor: Colors.white.withValues(alpha: 0.06),
                      selectedColor: AppTokens.accent,
                      side: BorderSide(
                        color: _index == i
                            ? AppTokens.accent
                            : Colors.white.withValues(alpha: 0.18),
                      ),
                      showCheckmark: false,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusMd),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // 图纸标题水印
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.space4),
            child: Row(
              children: [
                const Icon(LucideIcons.fileStack,
                    size: 13, color: Colors.white54),
                const SizedBox(width: 6),
                Text(_title,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white70)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius:
                        BorderRadius.circular(AppTokens.radiusPill),
                  ),
                  child: const Text('蓝图原稿 · 离线预览',
                      style: TextStyle(
                          fontSize: 10, color: Colors.white54)),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.space2),
          // 图纸交互区
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: AppTokens.space3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08)),
              ),
              clipBehavior: Clip.antiAlias,
              child: InteractiveViewer(
                transformationController: _controller,
                minScale: 0.5,
                maxScale: 4.0,
                boundaryMargin: const EdgeInsets.all(80),
                child: Center(
                  child: Image.asset(_src,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium),
                ),
              ),
            ),
          ),
          // 底部缩放工具条
          Container(
            color: const Color(0xFF0B1220),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ToolBtn(
                    icon: LucideIcons.zoomOut,
                    label: '缩小',
                    onTap: () => _zoom(0.8)),
                const SizedBox(width: AppTokens.space3),
                _ToolBtn(
                    icon: LucideIcons.maximize,
                    label: '复位',
                    onTap: _reset),
                const SizedBox(width: AppTokens.space3),
                _ToolBtn(
                    icon: LucideIcons.zoomIn,
                    label: '放大',
                    onTap: () => _zoom(1.25)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ToolBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.space4, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ],
          ),
        ),
      );
}
