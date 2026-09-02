import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../shared/widgets/nav_icon_button.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../data/models.dart';
import '../../shared/widgets/app_card.dart';
import 'defects_page.dart' show StatusPill;

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
      backgroundColor: AppTokens.surface2,
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F8F8),
        foregroundColor: const Color(0xFF000000),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: NavIconButton(
          icon: MingCuteIcons.leftLine,
          color: const Color(0xFF000000),
          onPressed: () => context.pop(),
        ),
        title: const Text('记录详情',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF000000))),
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
          // 水印照片（保留水印）+ 右上校验胶囊
          _WatermarkPhoto(d),
          const SizedBox(height: AppTokens.space3),
          // 缺陷信息卡：标题 + 状态胶囊 / 红色说明框 / 责任人
          _InfoCard(d),
          const SizedBox(height: AppTokens.space3),
          // 时间轴入口
          _TimelineCard(d),
          const SizedBox(height: AppTokens.space3),
          // 参数卡：拍摄时间 / 海拔 / GPS 坐标 / 楼层部位
          _ParamsCard(d),
        ],
      );
}

/// 缺陷信息卡（对齐 Frame 2131330688，height 154 / padding 12 / gap 8）。
/// Row1：标题（部位）+ 状态胶囊
/// Row2：红色说明框（居中，类型·锚点）
/// Row3：严重程度 label + value（黄）
/// Row4：责任人 label + value
class _InfoCard extends StatelessWidget {
  final Defect d;
  const _InfoCard(this.d);

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(AppTokens.space3),
        radius: AppTokens.radiusSm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    d.part,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTokens.fg),
                  ),
                ),
                const SizedBox(width: AppTokens.space3),
                StatusPill(status: d.status),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0x0DFF4444),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${d.type} · ${d.anchor}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFFFF4444)),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text('严重程度',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: AppTokens.muted)),
                const SizedBox(width: AppTokens.space4),
                Text(d.severity.label,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: AppTokens.warning)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text('责任人',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: AppTokens.muted)),
                const SizedBox(width: AppTokens.space4),
                Expanded(
                  child: Text(d.resp,
                      textAlign: TextAlign.left,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: AppTokens.fg2)),
                ),
              ],
            ),
          ],
        ),
      );
}

/// 时间轴入口（对齐 Frame 2147228022，height 46 / padding 12 / radius 8）。
class _TimelineCard extends StatelessWidget {
  final Defect d;
  const _TimelineCard(this.d);

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(AppTokens.space3),
        radius: AppTokens.radiusSm,
        onTap: () => context.push('/timeline', extra: d.anchor),
        child: const Row(
          children: [
            Icon(MingCuteIcons.eyeLine, color: AppTokens.brand, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text('查看同部位时间轴对比',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTokens.brand)),
            ),
            SizedBox(width: 8),
            Icon(MingCuteIcons.rightLine, color: AppTokens.muted, size: 16),
          ],
        ),
      );
}

/// 参数卡（对齐 Frame 2147228021，height 148 / padding 12 / gap 12）：单列 4 行键值对。
class _ParamsCard extends StatelessWidget {
  final Defect d;
  const _ParamsCard(this.d);

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(AppTokens.space3),
        radius: AppTokens.radiusSm,
        child: Column(
          children: [
            _ParamRow(label: '拍摄时间', value: d.ts),
            const SizedBox(height: AppTokens.space3),
            _ParamRow(label: '海拔', value: d.alt),
            const SizedBox(height: AppTokens.space3),
            _ParamRow(label: 'GPS坐标', value: d.gps),
            const SizedBox(height: AppTokens.space3),
            _ParamRow(label: '楼层部位', value: '${d.floor} · ${d.part}'),
          ],
        ),
      );
}

/// 单行键值对：label 左（辅助灰），value 右对齐（正文辅文 #60656B）。
class _ParamRow extends StatelessWidget {
  final String label;
  final String value;
  const _ParamRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: AppTokens.muted)),
          const SizedBox(width: 2),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: AppTokens.fg2)),
          ),
        ],
      );
}

/// 水印照片占位：颜色块 + 大字水印 + 时间戳。
/// 真实场景应渲染真实照片 + 服务端水印（本稿要求保留图片区域水印）。
class _WatermarkPhoto extends StatelessWidget {
  final Defect d;
  const _WatermarkPhoto(this.d);

  @override
  Widget build(BuildContext context) {
    final verified = d.status != DefectStatus.draft;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      child: SizedBox(
        height: 366,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 渐变背景（占位真实照片）
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
            // 右上角校验胶囊（对齐大按钮：白透底 + 深色文字）
            Positioned(
              top: 12,
              right: 12,
              child: verified
                  ? const _VerifiedBadge(
                      icon: MingCuteIcons.radioboxLine,
                      label: '已效验',
                      bg: const Color(0xB300B84A),
                      fg: AppTokens.onAccent,
                    )
                  : const _VerifiedBadge(
                      icon: MingCuteIcons.wifiOffLine,
                      label: '待回网校验',
                      bg: Color(0x80FFFFFF),
                      fg: Color(0xFF202224),
                    ),
            ),
            // 底部 3 行水印文字（保留）
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
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

  /// 单行水印文字（白色 + 阴影，对齐设计稿水印层）。
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

/// 右上角校验胶囊（对齐大按钮 / 待回网校验）。
class _VerifiedBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color bg;
  final Color fg;
  const _VerifiedBadge({
    required this.icon,
    required this.label,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: fg,
                    height: 20 / 12,
                    leadingDistribution: TextLeadingDistribution.even)),
          ],
        ),
      );
}

extension _IterableFirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
