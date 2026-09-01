import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../data/models.dart';
import '../../shared/widgets/app_card.dart';
import 'defects_page.dart' show StatusPill;

/// 记录详情页（静态版）。
/// 数据来源：当前问题清单 mock（按 defectId 取）。
/// 待 P3 接真实后端后改为 record 资源。
class RecordDetailPage extends ConsumerWidget {
  final String defectId;
  const RecordDetailPage({super.key, required this.defectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final defects = ref.watch(defectsProvider);
    return Scaffold(
      backgroundColor: AppTokens.bg,
      appBar: AppBar(
        backgroundColor: AppTokens.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(MingCuteIcons.leftLine,
              size: 20, color: AppTokens.fg),
          onPressed: () => context.pop(),
        ),
        title: const Text('记录详情',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTokens.fg)),
      ),
      body: defects.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
            child: Text('加载失败：$e',
                style: const TextStyle(color: AppTokens.danger))),
        data: (list) {
          final d = list.where((x) => x.id == defectId).firstOrNull;
          if (d == null) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 72),
              child: Center(
                child: Text('未找到该记录',
                    style: TextStyle(color: AppTokens.muted)),
              ),
            );
          }
          return _Body(d);
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final Defect d;
  const _Body(this.d);

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(
            AppTokens.space3, AppTokens.space2, AppTokens.space3, AppTokens.space3),
        children: [
          // 水印照片 + 右上校验胶囊 + 底部 3 行水印文字
          _WatermarkPhoto(d: d),
          const SizedBox(height: AppTokens.space3),
          // 缺陷块：左侧三角 + 中部文字 + 右侧状态大胶囊
          AppCard(
            padding: const EdgeInsets.all(AppTokens.space3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppTokens.dangerSoft,
                    borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                  ),
                  child: const Icon(MingCuteIcons.warningLine,
                      size: 16, color: AppTokens.danger),
                ),
                const SizedBox(width: AppTokens.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${d.part} · ${d.severity.label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTokens.fg),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${d.type} · ${d.anchor}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppTokens.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppTokens.space3),
                StatusPill(status: d.status),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.space3),
          // 元信息（grid 2 列）
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                      child: _MetaCell(label: '拍摄时间', value: d.ts)),
                  const SizedBox(width: AppTokens.space3),
                  Expanded(
                      child: _MetaCell(
                          label: 'GPS 坐标', value: d.gps)),
                ]),
                const SizedBox(height: AppTokens.space3),
                Row(children: [
                  Expanded(
                      child: _MetaCell(label: '海拔', value: d.alt)),
                  const SizedBox(width: AppTokens.space3),
                  Expanded(
                      child: _MetaCell(
                          label: '楼层部位',
                          value: '${d.floor} · ${d.part}')),
                ]),
                const SizedBox(height: AppTokens.space3),
                _MetaRow(
                    icon: MingCuteIcons.user1Line, label: '责任人', value: d.resp),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.space3),
          // 时间轴入口
          AppCard(
            onTap: () => context.push('/timeline', extra: d.anchor),
            child: const Row(
              children: [
                Icon(MingCuteIcons.timeLine,
                    color: AppTokens.brand, size: 18),
                SizedBox(width: 10),
                Expanded(
                    child: Text('查看同部位时间轴对比',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTokens.fg))),
                Icon(MingCuteIcons.rightLine,
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
                        fontSize: 14, color: AppTokens.fg))),
          ],
        ),
      );
}

/// 水印照片占位：颜色块 + 大字水印「南方科技大学附属医院 · 校本部」+ 时间戳。
/// 真实场景应渲染真实照片 + 服务端水印。
class _WatermarkPhoto extends StatelessWidget {
  final Defect d;
  const _WatermarkPhoto({required this.d});

  @override
  Widget build(BuildContext context) {
    final verified = d.status != DefectStatus.draft;
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 渐变背景
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    HSLColor.fromAHSL(1.0, d.seed.codeUnitAt(0) * 7 % 360, 0.35,
                            0.6)
                        .toColor(),
                    HSLColor.fromAHSL(
                            1.0, (d.seed.codeUnitAt(0) * 7 + 40) % 360, 0.45, 0.45)
                        .toColor(),
                  ],
                ),
              ),
            ),
            // 中央斜向大水印
            Center(
              child: Transform.rotate(
                angle: -0.3,
                child: Text(
                  '${d.part}\n${d.ts.substring(0, 10)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
            // 右上角校验胶囊（对齐原型 rd__verified）
            Positioned(
              top: AppTokens.space3,
              right: AppTokens.space3,
              child: verified
                  ? const _VerifiedBadge(
                      icon: MingCuteIcons.badgeLine,
                      label: '已校验',
                      bg: AppTokens.success,
                      fg: AppTokens.onAccent,
                    )
                  : const _VerifiedBadge(
                      icon: MingCuteIcons.wifiOffLine,
                      label: '待回网校验',
                      bg: AppTokens.surface,
                      fg: AppTokens.muted,
                      bordered: true,
                    ),
            ),
            // 底部 3 行水印文字（对齐原型 rd__wm-overlay）
            Positioned(
              left: AppTokens.space3,
              right: AppTokens.space3,
              bottom: AppTokens.space3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _wmText(d.ts),
                  const SizedBox(height: 2),
                  _wmText('${d.gps} · ${d.alt}'),
                  const SizedBox(height: 2),
                  _wmText('${d.floor} · ${d.part}'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 单行水印文字（白色 + 阴影，monospace，对齐原型 rd__wm-text）。
  Widget _wmText(String s) => Text(
        s,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontFamily: 'monospace',
          shadows: [
            Shadow(color: Colors.black54, offset: Offset(0, 1), blurRadius: 2),
          ],
        ),
      );
}

/// 右上角校验胶囊（对齐原型 rd__verified / rd__verified--pending）。
class _VerifiedBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color bg;
  final Color fg;
  final bool bordered;
  const _VerifiedBadge({
    required this.icon,
    required this.label,
    required this.bg,
    required this.fg,
    this.bordered = false,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          border: bordered ? Border.all(color: AppTokens.border) : null,
          boxShadow: AppTokens.elevationRaised,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: fg)),
          ],
        ),
      );
}

/// 元信息网格单元（对齐原型 .meta-cell）。
class _MetaCell extends StatelessWidget {
  final String label;
  final String value;
  const _MetaCell({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppTokens.space3),
        decoration: BoxDecoration(
          color: AppTokens.surface2,
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 12, color: AppTokens.muted)),
            const SizedBox(height: 2),
            Text(value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: AppTokens.fg)),
          ],
        ),
      );
}

extension _IterableFirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}