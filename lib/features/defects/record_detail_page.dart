import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/status_badge.dart';

/// 记录详情页（静态版）。
/// 数据来源：当前缺陷工单 mock（按 defectId 取）。
/// 待 P3 接真实后端后改为 record 资源。
class RecordDetailPage extends ConsumerWidget {
  final String defectId;
  const RecordDetailPage({super.key, required this.defectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final defects = ref.watch(defectsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('记录详情')),
      body: defects.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
            child: Text('加载失败：$e',
                style: const TextStyle(color: AppTokens.danger))),
        data: (list) {
          final d = list.where((x) => x.id == defectId).cast<dynamic>().firstOrNull;
          if (d == null) {
            return const Center(child: Text('未找到该记录'));
          }
          return _Body(d);
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final dynamic d;
  const _Body(this.d);

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(AppTokens.space4),
        children: [
          // 水印照片占位
          _WatermarkPhoto(seed: d.seed as String),
          const SizedBox(height: AppTokens.space4),
          // 缺陷块
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusBadge(
                        text: d.status.label as String,
                        color: d.status.color,
                        bg: d.status.soft),
                    const SizedBox(width: 8),
                    StatusBadge(
                        text: d.severity.label as String,
                        color: d.severity.color,
                        bg: d.severity.color.withValues(alpha: 0.12)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(d.part as String,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTokens.fg)),
                const SizedBox(height: 6),
                Text('${d.type} · ${d.anchor}',
                    style: const TextStyle(
                        fontSize: 13, color: AppTokens.muted)),
                const SizedBox(height: 6),
                Text(d.note as String,
                    style: const TextStyle(
                        fontSize: 13, color: AppTokens.mutedA11y)),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.space3),
          // 元信息
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MetaRow(icon: LucideIcons.clock, label: '时间', value: d.ts as String),
                _MetaRow(icon: LucideIcons.mapPin, label: 'GPS', value: d.gps as String),
                _MetaRow(icon: LucideIcons.compass, label: '海拔', value: d.alt as String),
                _MetaRow(icon: LucideIcons.user, label: '责任人', value: d.resp as String),
                _MetaRow(icon: LucideIcons.layers, label: '楼层', value: d.floor as String),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.space3),
          // 时间轴入口
          AppCard(
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('时间轴对比（P3 实现）'))),
            child: const Row(
              children: [
                Icon(LucideIcons.calendarClock,
                    color: AppTokens.brand, size: 18),
                SizedBox(width: 10),
                Expanded(
                    child: Text('查看同部位时间轴对比',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTokens.fg))),
                Icon(LucideIcons.chevronRight,
                    color: AppTokens.muted, size: 18),
              ],
            ),
          ),
        ],
      );
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _MetaRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 14, color: AppTokens.muted),
            const SizedBox(width: 8),
            SizedBox(
                width: 56,
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 12, color: AppTokens.muted))),
            Expanded(
                child: Text(value,
                    style: const TextStyle(
                        fontSize: 13, color: AppTokens.fg))),
          ],
        ),
      );
}

/// 水印照片占位：颜色块 + 大字水印「南方科技大学附属医院 · 校本部」+ 时间戳。
/// 真实场景应渲染真实照片 + 服务端水印。
class _WatermarkPhoto extends StatelessWidget {
  final String seed;
  const _WatermarkPhoto({required this.seed});
  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: HSLColor.fromAHSL(1.0, seed.codeUnitAt(0) * 7 % 360, 0.4,
                      0.5)
                  .toColor(),
            ),
            Center(
              child: Text(
                '现场照片 $seed',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700),
              ),
            ),
            // 水印
            Center(
              child: Transform.rotate(
                angle: -0.3,
                child: Text(
                  '南方科技大学附属医院 · 校本部\n${DateTime.now().toIso8601String().substring(0, 10)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
            // 防篡改角标
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.badgeCheck,
                        color: AppTokens.success, size: 12),
                    SizedBox(width: 4),
                    Text('已校验',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppTokens.success,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension _IterableFirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}