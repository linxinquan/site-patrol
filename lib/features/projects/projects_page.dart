import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/status_badge.dart';
import '../../shared/widgets/async_state.dart';
import '../../shared/widgets/offline_bar.dart';
import '../../shared/widgets/app_snack.dart';
import '../../data/models.dart';

class ProjectsPage extends ConsumerWidget {
  const ProjectsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(projectProvider);
    final floors = ref.watch(floorsProvider);
    final drawings = ref.watch(drawingsProvider);
    final cache = ref.watch(floorCacheProvider);

    return Scaffold(
      appBar: AppBar(
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
                      color: AppTokens.muted,
                      fontWeight: FontWeight.normal)),
            ],
          ),
          orElse: () => const Text('项目图纸'),
        ),
        actions: [
          IconButton(
            onPressed: () => AppSnack.show(context, '按楼层 / 索引号检索图纸',
                kind: AppSnackKind.brand),
            icon: const Icon(LucideIcons.search),
          ),
        ],
      ),
      body: AsyncState(
        value: floors,
        builder: (fs) => Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppTokens.space4),
                children: [
                  // 项目卡
                  AsyncState(
                    value: project,
                    builder: (p) => _ProjectCard(p: p, floorCount: fs.length),
                  ),
                  const SizedBox(height: AppTokens.space4),
                  const Padding(
                    padding: EdgeInsets.only(left: 2, bottom: AppTokens.space2),
                    child: Row(
                      children: [
                        Icon(LucideIcons.layers,
                            size: 14, color: AppTokens.muted),
                        SizedBox(width: 4),
                        Text('楼层图纸',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTokens.muted)),
                      ],
                    ),
                  ),
                  // 楼层列表
                  ...fs.map((f) {
                    final count = drawings.maybeWhen(
                      data: (m) => m[f.key]?.hotspots.length ?? f.index,
                      orElse: () => f.index,
                    );
                    final progress =
                        cache[f.key] ?? (f.cached ? 100 : f.progress);
                    final cached = progress >= 100;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppTokens.space3),
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
                            _simulateDownload(context, ref, f.key);
                          }
                        },
                      ),
                    );
                  }),
                  // 导入图纸（虚线卡）
                  _ImportCard(
                      onTap: () => AppSnack.show(
                          context, '已选择 1 份 PDF 图纸，开始解析并生成索引',
                          kind: AppSnackKind.accent)),
                  const SizedBox(height: AppTokens.space3),
                  OfflineBar.drawings(fs.length),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 模拟下载：每 220ms 进度 +20，到 100 视为缓存完成（对齐 HTML 模拟逻辑）。
  void _simulateDownload(BuildContext context, WidgetRef ref, String key) {
    var p = ref.read(floorCacheProvider)[key] ?? 0;
    Timer.periodic(const Duration(milliseconds: 220), (timer) {
      p += 20;
      if (p >= 100) {
        p = 100;
        timer.cancel();
      }
      ref.read(floorCacheProvider.notifier).state = {
        ...ref.read(floorCacheProvider),
        key: p,
      };
      if (p >= 100) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('图纸已缓存，可离线查看')));
      }
    });
  }
}

class _ProjectCard extends StatelessWidget {
  final Project p;
  final int floorCount;
  const _ProjectCard({required this.p, required this.floorCount});

  @override
  Widget build(BuildContext context) => AppCard(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTokens.brandSoft,
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              ),
              child: const Icon(LucideIcons.folder, color: AppTokens.brand),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTokens.fg),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    '${p.client} · ${p.floorArea} · ${p.status}',
                    style:
                        const TextStyle(fontSize: 12, color: AppTokens.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            StatusBadge(
                text: '${p.beds} 床',
                color: AppTokens.brand,
                bg: AppTokens.brandSoft),
          ],
        ),
      );
}

class _ImportCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ImportCard({required this.onTap});

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTokens.accentSoft,
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                ),
                child: const Icon(LucideIcons.plus, color: AppTokens.accent),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('导入图纸',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppTokens.fg)),
                    SizedBox(height: 2),
                    Text('支持 PDF / JPG / PNG，DWG 导入即转 PDF',
                        style: TextStyle(fontSize: 12, color: AppTokens.muted)),
                  ],
                ),
              ),
              const Icon(LucideIcons.chevronRight,
                  color: AppTokens.muted, size: 18),
            ],
          ),
        ),
      );
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
              child: const Icon(LucideIcons.fileText, color: AppTokens.brand),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(floor.name,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppTokens.fg),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      StatusBadge(
                          text: floor.building,
                          color: AppTokens.mutedA11y,
                          bg: AppTokens.surface2),
                      const SizedBox(width: 6),
                      StatusBadge(
                          text: floor.floor,
                          color: AppTokens.mutedA11y,
                          bg: AppTokens.surface2),
                      const SizedBox(width: 6),
                      if (indexCount > 0)
                        StatusBadge(
                            text: '索引 $indexCount',
                            color: AppTokens.brand,
                            bg: AppTokens.brandSoft),
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
                    text: cached ? '已缓存' : '未缓存',
                    color: cached ? AppTokens.success : AppTokens.warning,
                    bg: cached ? AppTokens.successSoft : AppTokens.warningSoft),
                const SizedBox(height: 6),
                SizedBox(
                  width: 72,
                  child: LinearProgressIndicator(
                    value: progress / 100,
                    backgroundColor: AppTokens.surface2,
                    valueColor: const AlwaysStoppedAnimation(AppTokens.accent),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}
