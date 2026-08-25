import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../core/di/providers.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/models.dart';
import '../../shared/widgets/app_card.dart';

/// 时间轴对比页（F8）：同一部位多时点照片选两张，滑块裁剪前后对比。
/// 数据：timeline mock（anchor → 3 张 before/mid/after 照片）。
/// 照片：CustomPainter 模拟（对齐 HTML mockPhotoSVG，避免 SVG 依赖）。
class TimelineComparePage extends ConsumerStatefulWidget {
  final String? anchor;
  const TimelineComparePage({super.key, this.anchor});

  @override
  ConsumerState<TimelineComparePage> createState() =>
      _TimelineComparePageState();
}

class _TimelineComparePageState extends ConsumerState<TimelineComparePage> {
  String _anchor = '西楼1F-左病房翼';
  List<TimelinePhoto> _photos = const [];
  int? _leftIdx;
  int? _rightIdx;
  double _slider = 0.5;

  @override
  void initState() {
    super.initState();
    _anchor = widget.anchor ?? _anchor;
    _load();
  }

  Future<void> _load() async {
    final list =
        await ref.read(repositoryProvider).getTimeline(_anchor);
    if (!mounted) return;
    setState(() {
      _photos = list;
      _leftIdx = list.isNotEmpty ? 0 : null;
      _rightIdx = list.length > 1 ? list.length - 1 : (_leftIdx);
    });
  }

  void _pick(int idx) {
    setState(() {
      if (_leftIdx == null) {
        _leftIdx = idx;
      } else if (_rightIdx == null || _rightIdx == idx) {
        _rightIdx = idx;
      } else if (_leftIdx == idx) {
        _leftIdx = null;
      } else {
        _rightIdx = idx;
      }
    });
  }

  void _swap() {
    setState(() {
      final t = _leftIdx;
      _leftIdx = _rightIdx;
      _rightIdx = t;
    });
  }

  @override
  Widget build(BuildContext context) {
    final left =
        _leftIdx != null && _leftIdx! < _photos.length ? _photos[_leftIdx!] : null;
    final right = _rightIdx != null && _rightIdx! < _photos.length
        ? _photos[_rightIdx!]
        : null;
    return Scaffold(
      backgroundColor: AppTokens.bg,
      appBar: AppBar(
        toolbarHeight: 44,
        titleSpacing: 12,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('时间轴对比',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.fg)),
            Text('F8 · 滑块前后对比',
                style: TextStyle(
                    fontSize: 12,
                    color: AppTokens.fg2,
                    fontWeight: FontWeight.w400)),
          ],
        ),
        centerTitle: false,
        backgroundColor: AppTokens.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppTokens.space3, AppTokens.space2, AppTokens.space3, AppTokens.space3),
        children: [
          _buildAnchorBar(),
          const SizedBox(height: AppTokens.space3),
          _buildThumbGrid(),
          const SizedBox(height: AppTokens.space3),
          if (left != null && right != null) ...[
            _buildCompareCard(left, right),
            const SizedBox(height: AppTokens.space3),
          ],
          if (left == null || right == null)
            const AppCard(
              padding: EdgeInsets.all(AppTokens.space4),
              child: Row(
                children: [
                  Icon(MingCuteIcons.forbidCircleLine,
                      size: 16, color: AppTokens.muted),
                  SizedBox(width: AppTokens.space2),
                  Expanded(
                    child: Text('请从上方照片中至少选择两张进行对比',
                        style: TextStyle(
                            fontSize: 14, color: AppTokens.muted)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAnchorBar() => AppCard(
        padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.space4, vertical: AppTokens.space3),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTokens.brandSoft,
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              ),
              child: const Icon(MingCuteIcons.timeLine,
                  size: 16, color: AppTokens.brand),
            ),
            const SizedBox(width: AppTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_anchor,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTokens.fg)),
                  const SizedBox(height: 2),
                  Text('${_photos.length} 个时点 · 点击照片选择左右对比',
                      style: const TextStyle(
                          fontSize: 12, color: AppTokens.muted)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _buildThumbGrid() {
    if (_photos.isEmpty) {
      return const AppCard(
        padding: EdgeInsets.all(AppTokens.space4),
        child: Center(
          child: Text('该部位暂无时间轴照片',
              style: TextStyle(fontSize: 14, color: AppTokens.muted)),
        ),
      );
    }
    return Row(
      children: [
        for (var i = 0; i < _photos.length; i++) ...[
          if (i > 0) const SizedBox(width: AppTokens.space3),
          Expanded(child: _buildThumb(i)),
        ],
      ],
    );
  }

  Widget _buildThumb(int i) {
    final p = _photos[i];
    final selected = i == _leftIdx || i == _rightIdx;
    return InkWell(
      onTap: () => _pick(i),
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppTokens.surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          border: Border.all(
            color: selected ? AppTokens.fg : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: CustomPaint(
                  painter: _MockPhotoPainter(
                    state: p.state,
                    date: p.date,
                    seed: i + 1,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(p.date,
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppTokens.fg)),
                ),
                if (p.verified)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppTokens.brandTint,
                      borderRadius:
                          BorderRadius.circular(AppTokens.radiusPill),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(MingCuteIcons.checkLine,
                            size: 9, color: AppTokens.brand),
                        SizedBox(width: 2),
                        Text('已校验',
                            style: TextStyle(
                                fontSize: 10,
                                color: AppTokens.brand,
                                fontWeight: FontWeight.w400)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(_stateLabel(p.state),
                style: const TextStyle(
                    fontSize: 10, color: AppTokens.muted)),
          ],
        ),
      ),
    );
  }

  String _stateLabel(String s) => switch (s) {
        'before' => '前期',
        'mid' => '中期',
        'after' => '后期',
        _ => s,
      };

  Widget _buildCompareCard(TimelinePhoto left, TimelinePhoto right) {
    return AppCard(
      padding: const EdgeInsets.all(AppTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(MingCuteIcons.columns2Line,
                  size: 14, color: AppTokens.fg),
              const SizedBox(width: 6),
              const Text('前后对比',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTokens.fg)),
              const Spacer(),
              InkWell(
                onTap: _swap,
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                child: const Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(MingCuteIcons.unfoldHorizontalLine,
                          size: 12, color: AppTokens.muted),
                      SizedBox(width: 4),
                      Text('交换',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: AppTokens.muted)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.space3),
          _buildSwipeView(left, right),
          const SizedBox(height: AppTokens.space3),
          Slider(
            value: _slider,
            activeColor: AppTokens.fg,
            inactiveColor: AppTokens.border,
            onChanged: (v) => setState(() => _slider = v),
          ),
          Row(
            children: [
              _buildDateTag(left, alignLeft: true),
              const Spacer(),
              _buildDateTag(right, alignLeft: false),
            ],
          ),
          const SizedBox(height: AppTokens.space3),
          Text(
            '${left.date}（${left.caption}） → ${right.date}（${right.caption}）',
            style: const TextStyle(
                fontSize: 12, color: AppTokens.muted, height: 20 / 12),
          ),
        ],
      ),
    );
  }

  /// 裁剪对比：底层 right 全幅，上层 left 裁剪到滑块位置。
  Widget _buildSwipeView(TimelinePhoto left, TimelinePhoto right) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 底层：右侧照片（全幅）
                CustomPaint(
                  painter: _MockPhotoPainter(
                    state: right.state,
                    date: right.date,
                    seed: _rightIdx! + 1,
                  ),
                ),
                // 上层：左侧照片（裁剪到滑块位置）
                ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: _slider,
                    child: SizedBox(
                      width: w,
                      child: CustomPaint(
                        painter: _MockPhotoPainter(
                          state: left.state,
                          date: left.date,
                          seed: _leftIdx! + 1,
                        ),
                      ),
                    ),
                  ),
                ),
                // 分隔线
                Positioned(
                  left: w * _slider - 1.5,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 3, color: AppTokens.fg),
                ),
                // 日期角标
                Positioned(
                  left: 8,
                  top: 8,
                  child: _CornerTag(
                    label: '前 ${left.date}',
                    bg: AppTokens.fg,
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: _CornerTag(
                    label: '后 ${right.date}',
                    bg: const Color(0xFF0B1220),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDateTag(TimelinePhoto p, {required bool alignLeft}) => Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment:
            alignLeft ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          Icon(
            alignLeft ? MingCuteIcons.arrowLeftLine : MingCuteIcons.arrowRightLine,
            size: 12,
            color: AppTokens.muted,
          ),
          const SizedBox(width: 4),
          Text(p.date,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.fg)),
        ],
      );
}

class _CornerTag extends StatelessWidget {
  final String label;
  final Color bg;
  const _CornerTag({required this.label, required this.bg});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 10, color: Colors.white)),
      );
}

/// 模拟照片：墙面 + 缺陷痕迹（对齐 HTML mockPhotoSVG）。
class _MockPhotoPainter extends CustomPainter {
  final String state; // before / mid / after
  final String date;
  final int seed;
  const _MockPhotoPainter({
    required this.state,
    required this.date,
    required this.seed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 墙面底色（不同时点色温不同）
    final baseColor = switch (state) {
      'before' => const Color(0xFFE7E3DA),
      'mid' => const Color(0xFFD8D3C6),
      _ => const Color(0xFFF2EEE6),
    };
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            baseColor.withValues(alpha: 1),
            Color.lerp(baseColor, const Color(0xFFB8B2A4), 0.35)!,
          ],
        ).createShader(rect),
    );

    // 顶部光带
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 2),
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );

    final cx = size.width * (0.32 + (seed % 3) * 0.18);
    final cy = size.height * 0.55;

    switch (state) {
      case 'before':
        // 空鼓斑块 + 裂缝
        canvas.drawOval(
          Rect.fromCenter(
              center: Offset(cx, cy), width: size.width * 0.34, height: size.height * 0.4),
          Paint()..color = const Color(0xFFC9C2B2).withValues(alpha: 0.75),
        );
        _drawCrack(canvas, size, Offset(cx - size.width * 0.08, cy),
            Offset(cx + size.width * 0.12, cy + size.height * 0.12),
            const Color(0xFF6B6355));
        _drawCrack(canvas, size, Offset(cx, cy),
            Offset(cx + size.width * 0.05, cy + size.height * 0.22),
            const Color(0xFF7A7163));
        break;
      case 'mid':
        // 注浆补丁
        canvas.drawOval(
          Rect.fromCenter(
              center: Offset(cx, cy),
              width: size.width * 0.3,
              height: size.height * 0.36),
          Paint()..color = const Color(0xFF8E8578).withValues(alpha: 0.8),
        );
        canvas.drawOval(
          Rect.fromCenter(
              center: Offset(cx - size.width * 0.05, cy - size.height * 0.05),
              width: size.width * 0.16,
              height: size.height * 0.2),
          Paint()..color = const Color(0xFF5E574C).withValues(alpha: 0.7),
        );
        _drawCrack(canvas, size, Offset(cx, cy),
            Offset(cx + size.width * 0.1, cy + size.height * 0.12),
            const Color(0xFF3E3A33));
        break;
      default:
        // 修复后：仅淡痕
        canvas.drawOval(
          Rect.fromCenter(
              center: Offset(cx, cy),
              width: size.width * 0.3,
              height: size.height * 0.36),
          Paint()
            ..color = const Color(0xFFCFC8B8).withValues(alpha: 0.4),
        );
        _drawCrack(canvas, size, Offset(cx, cy),
            Offset(cx + size.width * 0.1, cy + size.height * 0.12),
            const Color(0xFFB5AC9C).withValues(alpha: 0.5));
    }

    // 底部水印
    final tsPaint = Paint()..color = Colors.black.withValues(alpha: 0.45);
    canvas.drawRect(
        Rect.fromLTWH(0, size.height - 18, size.width, 18), tsPaint);
    final tb = TextPainter(
      text: TextSpan(
        text: '现场照片 $date  ·  验收留证',
        style: const TextStyle(
            fontSize: 10, color: Colors.white, letterSpacing: 0),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tb.paint(canvas, Offset(8, size.height - 15.5));
  }

  void _drawCrack(Canvas canvas, Size size, Offset a, Offset b, Color color) {
    final path = Path()..moveTo(a.dx, a.dy);
    final mid = Offset((a.dx + b.dx) / 2 + size.width * 0.015,
        (a.dy + b.dy) / 2 - size.height * 0.01);
    path.quadraticBezierTo(mid.dx, mid.dy, b.dx, b.dy);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
    // 小分叉
    canvas.drawLine(
      Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2),
      Offset((a.dx + b.dx) / 2 - size.width * 0.03,
          (a.dy + b.dy) / 2 + size.height * 0.06),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _MockPhotoPainter oldDelegate) =>
      oldDelegate.state != state ||
      oldDelegate.date != date ||
      oldDelegate.seed != seed;
}
