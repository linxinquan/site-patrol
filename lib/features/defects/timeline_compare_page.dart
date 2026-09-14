import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../shared/widgets/nav_icon_button.dart';
import '../../core/di/providers.dart';
import '../../core/storage/local_storage.dart';
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
  // 复用本地图片读取 Future，避免拖动滑块时重复读文件。
  final Map<String, Future<Uint8List?>> _photoBytesFutures = {};

  @override
  void initState() {
    super.initState();
    _anchor = widget.anchor ?? _anchor;
    _load();
  }

  Future<void> _load() async {
    final list = await ref.read(repositoryProvider).getTimeline(_anchor);
    if (!mounted) return;
    setState(() {
      _photos = list;
      _leftIdx = list.isNotEmpty ? 0 : null;
      _rightIdx = list.length > 1 ? list.length - 1 : (_leftIdx);
    });
  }

  Future<Uint8List?> _readPhotoBytes(String relativePath) =>
      _photoBytesFutures.putIfAbsent(
        relativePath,
        () => LocalStorage.instance.readFile(relativePath),
      );

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
    final left = _leftIdx != null && _leftIdx! < _photos.length
        ? _photos[_leftIdx!]
        : null;
    final right = _rightIdx != null && _rightIdx! < _photos.length
        ? _photos[_rightIdx!]
        : null;
    return Scaffold(
      backgroundColor: AppTokens.bg,
      appBar: AppBar(
        titleSpacing: 0,
        automaticallyImplyLeading: false,
        toolbarHeight: 48,
        leadingWidth: 0,
        title: const Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: 12),
                child: NavIconButton(icon: MingCuteIcons.leftLine),
              ),
            ),
            // 和图纸详情页一致：标题区两侧预留 48，避免被返回按钮顶偏。
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '时间轴对比',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 24 / 16,
                      color: AppTokens.fg,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'F8 · 滑块前后对比',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      height: 20 / 12,
                      color: AppTokens.fg2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: AppTokens.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        // 页面首块内容与导航栏底部统一保持 12 的间距。
        padding: const EdgeInsets.fromLTRB(AppTokens.space3, AppTokens.space3,
            AppTokens.space3, AppTokens.space3),
        children: [
          _buildAnchorBar(),
          const SizedBox(height: AppTokens.space3),
          _buildWorkbenchCard(left: left, right: right),
        ],
      ),
    );
  }

  Widget _buildAnchorBar() => AppCard(
        padding: const EdgeInsets.all(AppTokens.space3),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 320;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _anchor,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 24 / 16,
                    color: AppTokens.fg,
                  ),
                ),
                const SizedBox(height: 8),
                if (!compact)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_photos.length} 个时点',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            height: 20 / 12,
                            color: AppTokens.fg2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '注：点击照片选择左右对比',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          height: 20 / 12,
                          color: Color(0xFFFF4444),
                        ),
                      ),
                    ],
                  )
                else ...[
                  Text(
                    '${_photos.length} 个时点',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      height: 20 / 12,
                      color: AppTokens.fg2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '注：点击照片选择左右对比',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      height: 20 / 12,
                      color: Color(0xFFFF4444),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      );

  /// 主工作区：上面选照片，下面看滑块前后对比。
  Widget _buildWorkbenchCard({
    required TimelinePhoto? left,
    required TimelinePhoto? right,
  }) =>
      AppCard(
        padding: const EdgeInsets.all(AppTokens.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildThumbRail(),
            const SizedBox(height: 12),
            Container(height: 1, color: AppTokens.border),
            const SizedBox(height: 12),
            if (left != null && right != null)
              _buildCompareCard(left, right)
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppTokens.space4),
                decoration: BoxDecoration(
                  color: AppTokens.surface2,
                  borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                ),
                child: const Row(
                  children: [
                    Icon(MingCuteIcons.forbidCircleLine,
                        size: 16, color: AppTokens.muted),
                    SizedBox(width: AppTokens.space2),
                    Expanded(
                      child: Text(
                        '请从上方照片中至少选择两张进行对比',
                        style: TextStyle(
                          fontSize: 14,
                          height: 22 / 14,
                          color: AppTokens.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );

  Widget _buildThumbRail() {
    if (_photos.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppTokens.space4),
        decoration: BoxDecoration(
          color: AppTokens.surface2,
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        ),
        child: const Center(
          child: Text('该部位暂无时间轴照片',
              style: TextStyle(fontSize: 14, color: AppTokens.muted)),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth < 360 ? 102.0 : 108.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '选择对比照片',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 24 / 16,
                color: AppTokens.fg,
              ),
            ),
            const SizedBox(height: 8),
            // 照片很多时允许横向滑动，避免缩略图被挤窄。
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < _photos.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    SizedBox(width: itemWidth, child: _buildThumb(i)),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildThumb(int i) {
    final p = _photos[i];
    final selected = i == _leftIdx || i == _rightIdx;
    final roleLabel = i == _leftIdx
        ? '左侧'
        : i == _rightIdx
            ? '右侧'
            : null;
    return InkWell(
      onTap: () => _pick(i),
      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: selected ? const Color(0x0D0395FF) : Colors.white,
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          border: Border.all(
            color: selected ? AppTokens.brand : AppTokens.border,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: _buildPhotoContent(p),
                  ),
                ),
                if (p.verified)
                  Positioned(
                    left: 5,
                    top: 5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 0),
                      decoration: BoxDecoration(
                        color: const Color(0xB300B84A),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '已校验',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w400,
                          height: 18 / 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                if (roleLabel != null)
                  Positioned(
                    right: 5,
                    top: 5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 0),
                      decoration: BoxDecoration(
                        color: const Color(0xCC0395FF),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        roleLabel,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          height: 18 / 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              p.date,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 22 / 14,
                color: selected ? AppTokens.brand : AppTokens.fg,
              ),
            ),
            Text(
              _stateLabel(p.state),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                height: 20 / 12,
                color: AppTokens.fg2,
              ),
            ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('前后对比',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 24 / 16,
                    color: AppTokens.fg)),
            const Spacer(),
            InkWell(
              onTap: _swap,
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: Center(
                        child: Icon(MingCuteIcons.transformationLine,
                            size: 16, color: AppTokens.brand),
                      ),
                    ),
                    SizedBox(width: 4),
                    Text('交换照片',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            height: 20 / 12,
                            color: AppTokens.brand)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '拖动下方滑块查看 ${left.date} 到 ${right.date} 的现场变化',
          style: const TextStyle(
              fontSize: 12, height: 20 / 12, color: AppTokens.fg2),
        ),
        const SizedBox(height: 12),
        _buildSwipeView(left, right),
        const SizedBox(height: 12),
        _buildCompareSlider(),
        const SizedBox(height: 12),
        _buildCompareSummary(left, right),
      ],
    );
  }

  /// 自定义滑块外观，贴近设计稿的粗轨道和圆形拖拽点。
  Widget _buildCompareSlider() => SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 6,
          activeTrackColor: AppTokens.border,
          inactiveTrackColor: AppTokens.border,
          overlayShape: SliderComponentShape.noOverlay,
          thumbShape: const _CompareSliderThumbShape(),
          thumbColor: AppTokens.brand,
        ),
        child: Slider(
          value: _slider,
          min: 0,
          max: 1,
          onChanged: (v) => setState(() => _slider = v),
        ),
      );

  /// 底部对比摘要：把两次时点的日期和描述拆开显示，阅读更清晰。
  Widget _buildCompareSummary(TimelinePhoto left, TimelinePhoto right) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTokens.surface2,
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        ),
        child: Column(
          children: [
            _buildSummaryBlock(left),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              height: 1,
              color: AppTokens.border,
            ),
            _buildSummaryBlock(right),
          ],
        ),
      );

  Widget _buildSummaryBlock(TimelinePhoto p) => Column(
        children: [
          Text(
            p.date,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              height: 20 / 12,
              color: AppTokens.muted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            p.caption,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              height: 22 / 14,
              color: AppTokens.fg,
            ),
          ),
        ],
      );

  /// 统一渲染时间轴图片：优先 assets，其次本地存储文件。
  Widget _buildPhotoContent(TimelinePhoto photo) {
    final imagePath = photo.imagePath;
    final contentKey =
        ValueKey('${photo.isAsset}-${photo.imagePath ?? ''}-${photo.date}');
    if (imagePath == null || imagePath.isEmpty) {
      return KeyedSubtree(
        key: contentKey,
        child: _buildPhotoPlaceholder('暂无对比照片'),
      );
    }
    if (photo.isAsset) {
      return KeyedSubtree(
        key: contentKey,
        child: Image.asset(
          imagePath,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => _buildPhotoPlaceholder('图片加载失败'),
        ),
      );
    }
    return KeyedSubtree(
      key: contentKey,
      child: FutureBuilder<Uint8List?>(
        future: _readPhotoBytes(imagePath),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return _buildPhotoPlaceholder('照片加载中');
          }
          final bytes = snap.data;
          if (bytes == null || bytes.isEmpty) {
            return _buildPhotoPlaceholder('照片不存在');
          }
          return Image.memory(
            bytes,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            gaplessPlayback: true,
          );
        },
      ),
    );
  }

  /// 图片缺失时给一个稳定占位，避免整块留白。
  Widget _buildPhotoPlaceholder(String text) => Container(
        color: AppTokens.surface2,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              MingCuteIcons.picLine,
              size: 22,
              color: AppTokens.muted,
            ),
            const SizedBox(height: 6),
            Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                height: 20 / 12,
                color: AppTokens.muted,
              ),
            ),
          ],
        ),
      );

  /// 裁剪对比：底层 right 全幅，上层 left 裁剪到滑块位置。
  Widget _buildSwipeView(TimelinePhoto left, TimelinePhoto right) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          child: AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 底层：右侧照片（全幅）
                Positioned.fill(child: _buildPhotoContent(right)),
                // 上层：左侧照片（裁剪到滑块位置）
                Positioned.fill(
                  child: ClipRect(
                    clipper: _LeftPhotoClipper(_slider),
                    child: _buildPhotoContent(left),
                  ),
                ),
                // 在图片上显示当前拖拽位置，方便直观看到前后分界。
                Positioned(
                  left: (constraints.maxWidth * _slider) - 1,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(
                      width: 2,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 6,
                            offset: Offset(0, 0),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // 日期角标
                Positioned(
                  left: 8,
                  top: 8,
                  child: _CornerTag(
                    label: '前 ${left.date}',
                    bg: Colors.black54,
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: _CornerTag(
                    label: '后 ${right.date}',
                    bg: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 角落状态标签（胶囊），垫底实色 + 白字。标签内文字按全局规范取 W500。
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
            style: const TextStyle(
                fontSize: 10,
                color: Colors.white,
                fontWeight: FontWeight.w500)),
      );
}

/// 只保留左侧一定比例区域，用于前后照片滑块裁切。
class _LeftPhotoClipper extends CustomClipper<Rect> {
  final double fraction;
  const _LeftPhotoClipper(this.fraction);

  @override
  Rect getClip(Size size) {
    final width = (size.width * fraction).clamp(0.0, size.width);
    return Rect.fromLTWH(0, 0, width, size.height);
  }

  @override
  bool shouldReclip(covariant _LeftPhotoClipper oldClipper) =>
      oldClipper.fraction != fraction;
}

/// 下方滑块拖拽圆：蓝底、白描边、阴影，中间带拖拽图标。
class _CompareSliderThumbShape extends SliderComponentShape {
  const _CompareSliderThumbShape();

  static const double _radius = 16;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.fromRadius(_radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    const fillColor = AppTokens.brand;
    const borderColor = Colors.white;
    const shadowColor = Color(0x26012D4D);

    canvas.drawShadow(
      Path()..addOval(Rect.fromCircle(center: center, radius: _radius)),
      shadowColor,
      8,
      true,
    );
    canvas.drawCircle(center, _radius, Paint()..color = fillColor);
    canvas.drawCircle(
      center,
      _radius - 1,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final icon = String.fromCharCode(MingCuteIcons.moveLine.codePoint);
    final iconPainter = TextPainter(
      text: TextSpan(
        text: icon,
        style: TextStyle(
          fontSize: 20,
          fontFamily: MingCuteIcons.moveLine.fontFamily,
          package: MingCuteIcons.moveLine.fontPackage,
          color: Colors.white,
        ),
      ),
      textDirection: textDirection,
    )..layout();
    iconPainter.paint(
      canvas,
      Offset(
        center.dx - (iconPainter.width / 2),
        center.dy - (iconPainter.height / 2),
      ),
    );
  }
}
