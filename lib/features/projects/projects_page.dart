import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/section_title.dart';
import '../../shared/widgets/status_badge.dart';
import '../../shared/widgets/async_state.dart';
import '../../shared/widgets/offline_bar.dart';
import '../../shared/widgets/app_snack.dart';
import '../../shared/widgets/maskable_name.dart';
import '../../data/models.dart';

class ProjectsPage extends ConsumerStatefulWidget {
  const ProjectsPage({super.key});

  @override
  ConsumerState<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends ConsumerState<ProjectsPage> {
  /// 进行中的下载模拟 Timer，key 为楼层图纸 key；页面销毁时统一取消，避免泄漏。
  final Map<String, Timer> _downloadTimers = {};

  @override
  void dispose() {
    for (final t in _downloadTimers.values) {
      t.cancel();
    }
    _downloadTimers.clear();
    super.dispose();
  }

  /// 模拟下载：每 220ms 进度 +20，到 100 视为缓存完成（对齐 HTML 模拟逻辑）。
  void _simulateDownload(String key) {
    // 已有进行中的下载，忽略重复点击
    if (_downloadTimers.containsKey(key)) return;
    var p = ref.read(floorCacheProvider)[key] ?? 0;
    final timer = Timer.periodic(const Duration(milliseconds: 220), (timer) {
      p += 20;
      final done = p >= 100;
      if (done) {
        p = 100;
        timer.cancel();
        _downloadTimers.remove(key);
      }
      // 页面已销毁则停止后续更新，避免跨异步使用 context / state
      if (!mounted) return;
      ref.read(floorCacheProvider.notifier).state = {
        ...ref.read(floorCacheProvider),
        key: p,
      };
      if (done) {
        AppSnack.show(context, '图纸已下载，可离线查看',
            kind: AppSnackKind.success);
      }
    });
    _downloadTimers[key] = timer;
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(projectProvider);
    final floors = ref.watch(floorsProvider);
    final drawings = ref.watch(drawingsProvider);
    final cache = ref.watch(floorCacheProvider);

    return Scaffold(
      backgroundColor: AppTokens.bg,
      appBar: AppBar(
        toolbarHeight: 44,
        backgroundColor: AppTokens.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 12,
        title: project.maybeWhen(
          data: (p) => const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('项目图纸',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTokens.fg)),
              Text('F1 · 图纸文件夹与离线管理',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppTokens.fg2,
                      fontWeight: FontWeight.w400)),
            ],
          ),
          orElse: () => const Text('项目图纸'),
        ),
        actions: [
          IconButton(
            onPressed: () => AppSnack.show(context, '按楼层 / 索引号检索图纸',
                kind: AppSnackKind.brand),
            icon: const Icon(MingCuteIcons.searchLine),
          ),
        ],
      ),
      body: AsyncState(
        value: floors,
        builder: (fs) => Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    AppTokens.space3, AppTokens.space2, AppTokens.space3, AppTokens.space3),
                children: [
                  // 项目卡
                  AsyncState(
                    value: project,
                    builder: (p) => _ProjectCard(p: p, floorCount: fs.length),
                  ),
                  const SizedBox(height: AppTokens.space4),
                  // 楼层图纸板块标题（SectionTitle 规范：16/W600 + 楼层数徽标，自带上下 padding 8）
                  SectionTitle(
                      title: '楼层图纸', subtitle: '${fs.length} 个楼层'),
                  // 导入图纸：楼层图纸板块的第一个卡片（标题下、楼层列表前）
                  _ImportCard(
                      onTap: () => AppSnack.show(
                          context, '已选择 1 份 PDF 图纸，开始解析并生成索引',
                          kind: AppSnackKind.accent)),
                  const SizedBox(height: AppTokens.space2),
                  // 楼层列表（卡间距统一 8）
                  ...fs.map((f) {
                    final count = drawings.maybeWhen(
                      data: (m) => m[f.key]?.hotspots.length ?? f.index,
                      orElse: () => f.index,
                    );
                    final progress =
                        cache[f.key] ?? (f.cached ? 100 : f.progress);
                    final cached = progress >= 100;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppTokens.space2),
                      child: DrawingListItem(
                        floor: f,
                        indexCount: count,
                        progress: progress,
                        cached: cached,
                        onTap: () {
                          if (cached) {
                            context.push('/projects/drawing/${f.key}');
                          } else {
                            AppSnack.show(context, '正在下载离线图纸…',
                                kind: AppSnackKind.muted);
                            _simulateDownload(f.key);
                          }
                        },
                      ),
                    );
                  }),
                  OfflineBar.drawings(fs.length),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final Project p;
  final int floorCount;
  const _ProjectCard({required this.p, required this.floorCount});

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTokens.brandSoft,
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                  ),
                  child:
                      const Icon(MingCuteIcons.folderLine, color: AppTokens.brand),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTokens.fg),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(
                        '${p.client} · ${p.floorArea} · ${p.status}',
                        style: const TextStyle(
                            fontSize: 12, color: AppTokens.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (p.beds > 0)
                  StatusBadge(
                      text: '${p.beds} 床', color: AppTokens.brand),
              ],
            ),
            if (p.parties.isNotEmpty) ...[
              const SizedBox(height: AppTokens.space3),
              const Divider(height: 1, color: AppTokens.border),
              const SizedBox(height: AppTokens.space3),
              for (final party in p.parties)
                Padding(
                  padding:
                      const EdgeInsets.only(bottom: AppTokens.space2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: AppTokens.brandSoft,
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusSm),
                        ),
                        child: const Icon(MingCuteIcons.building1Line,
                            size: 15, color: AppTokens.brand),
                      ),
                      const SizedBox(width: AppTokens.space3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              party.role,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  color: AppTokens.fg2,
                                  height: 20 / 12),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              party.org,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppTokens.fg,
                                  height: 22 / 14),
                            ),
                            const SizedBox(height: 2),
                            Text.rich(
                              TextSpan(
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTokens.muted,
                                    height: 20 / 12),
                                children: [
                                  TextSpan(text: '${party.title} · '),
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.baseline,
                                    baseline: TextBaseline.alphabetic,
                                    child: MaskableName(
                                      name: party.contact,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTokens.muted,
                                          height: 20 / 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      );
}

class _ImportCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ImportCard({required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: AppTokens.surface,
            borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppTokens.radiusLg),
            child: CustomPaint(
              foregroundPainter: const _DashedBorderPainter(),
              child: Padding(
                padding: const EdgeInsets.all(AppTokens.space4),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTokens.surface2,
                        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                      ),
                      child: const Icon(MingCuteIcons.addLine,
                          color: AppTokens.fg),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('导入图纸',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: AppTokens.fg)),
                            SizedBox(height: 2),
                            Text('支持 PDF / JPG / PNG，DWG 导入即转 PDF',
                                style: TextStyle(
                                    fontSize: 12, color: AppTokens.muted)),
                          ],
                        ),
                    ),
                    const Icon(MingCuteIcons.rightLine,
                        color: AppTokens.muted, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

/// 导入图纸虚线边框（设计稿虚线卡：1.5px 虚线描边，圆角 12，边框色 border）。
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTokens.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const dash = 6.0;
    const gap = 4.0;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.75, 0.75, size.width - 1.5, size.height - 1.5),
      const Radius.circular(AppTokens.radiusLg),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = math.min(d + dash, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) => false;
}

class DrawingListItem extends StatelessWidget {
  final Floor floor;
  final int indexCount;
  final VoidCallback onTap;
  final int progress;
  final bool cached;
  const DrawingListItem({
    super.key,
    required this.floor,
    required this.indexCount,
    required this.onTap,
    this.progress = 100,
    this.cached = true,
  });

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTokens.surface2,
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              ),
              child: const Icon(MingCuteIcons.documentLine, color: AppTokens.brand),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(floor.name,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTokens.fg),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      StatusBadge(
                          text: floor.building,
                          color: AppTokens.muted,
                          bg: AppTokens.surface2,
                          fontWeight: FontWeight.w400),
                      const SizedBox(width: 6),
                      StatusBadge(
                          text: floor.floor,
                          color: AppTokens.muted,
                          bg: AppTokens.surface2,
                          fontWeight: FontWeight.w400),
                      const SizedBox(width: 6),
                      if (indexCount > 0)
                        StatusBadge(
                            text: '索引 $indexCount',
                            color: AppTokens.brand,
                            fontWeight: FontWeight.w400),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusBadge(
                    text: cached ? '已下载' : '未下载',
                    color: cached ? AppTokens.success : AppTokens.warning,
                    fontWeight: FontWeight.w400),
                const SizedBox(height: 6),
                SizedBox(
                  width: 72,
                  child: LinearProgressIndicator(
                    value: progress / 100,
                    backgroundColor: AppTokens.surface2,
                    valueColor: const AlwaysStoppedAnimation(AppTokens.fg),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}
