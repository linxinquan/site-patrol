import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../shared/widgets/nav_icon_button.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../data/models.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_snack.dart';
import 'defects_page.dart' show StatusPill;

/// 记录详情页（静态版）。
/// 数据来源：当前巡场清单 mock（按 defectId 取）。
/// 待 P3 接真实后端后改为 record 资源。
class RecordDetailPage extends ConsumerWidget {
  final String defectId;
  const RecordDetailPage({super.key, required this.defectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final defects = ref.watch(defectsProvider);
    final currentUser = ref.watch(currentUserProvider);
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
          return _Body(
            d,
            byName: currentUser.name,
            onUpdate: (nu) async {
              await ref.read(repositoryProvider).updateDefect(nu);
              ref.invalidate(defectsProvider);
              if (context.mounted) {
                AppSnack.show(context, '已保存更新', kind: AppSnackKind.success);
              }
            },
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final Defect d;
  final String byName;
  final Future<void> Function(Defect nu) onUpdate;
  const _Body(this.d, {required this.byName, required this.onUpdate});

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
          const SizedBox(height: AppTokens.space3),
          // 任务4：设计师远程处置卡
          _DesignerCard(d: d, byName: byName, onUpdate: onUpdate),
          const SizedBox(height: AppTokens.space3),
          // 任务5：施工方整改回复卡
          _ReplyCard(d: d, byName: byName, onUpdate: onUpdate),
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
                const SizedBox(
                    width: 56,
                    child: Text('严重程度',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: AppTokens.muted))),
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
                const SizedBox(
                    width: 56,
                    child: Text('责任人',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: AppTokens.muted))),
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
                      icon: MingCuteIcons.checkCircleLine,
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

String _fmtNow() {
  final n = DateTime.now();
  String t(int v) => v.toString().padLeft(2, '0');
  return '${n.year}-${t(n.month)}-${t(n.day)} ${t(n.hour)}:${t(n.minute)}';
}

// ==================== 任务4：设计师远程处置 ====================

class _DesignerCard extends StatelessWidget {
  final Defect d;
  final String byName;
  final Future<void> Function(Defect nu) onUpdate;
  const _DesignerCard({
    required this.d,
    required this.byName,
    required this.onUpdate,
  });

  Future<void> _act(BuildContext context, String action) async {
    final isFix = action == 'remoteFix';
    final ctl = TextEditingController();
    final title = switch (action) {
      'remoteFix' => '远程已解决（销项）',
      'remoteConfirm' => '远程已答复',
      _ => '需到场',
    };
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          maxLines: 3,
          autofocus: true,
          decoration: InputDecoration(
            hintText: isFix ? '填写处置说明（必填）…' : '填写说明（可空）…',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
            child: const Text('确认提交'),
          ),
        ],
      ),
    );
    if (note == null) return; // 取消
    if (isFix && note.isEmpty) {
      AppSnack.show(context, '请填写处置说明后再销项', kind: AppSnackKind.muted);
      return;
    }
    await onUpdate(d.copyWith(
      status: isFix ? DefectStatus.done : null,
      completion: isFix ? '已完成（设计师远程销项）' : null,
      designerAction: action,
      designerNote: note,
      designerBy: byName,
      designerTs: _fmtNow(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final acted = d.designerAction != null;
    return AppCard(
      padding: const EdgeInsets.all(AppTokens.space3),
      radius: AppTokens.radiusSm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('设计师处置',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.fg)),
          const SizedBox(height: 10),
          if (acted)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0x120395FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(d.designerActionLabel,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0395FF))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(d.designerTs ?? '',
                            style: const TextStyle(
                                fontSize: 11, color: AppTokens.muted)),
                      ),
                    ],
                  ),
                  if ((d.designerNote ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(d.designerNote!,
                        style: const TextStyle(
                            fontSize: 13, color: AppTokens.fg2)),
                  ],
                  const SizedBox(height: 4),
                  Text('处置人：${d.designerBy ?? ''}',
                      style: const TextStyle(
                          fontSize: 12, color: AppTokens.muted)),
                ],
              ),
            )
          else
            Row(
              children: [
                Expanded(
                    child: _ActBtn(
                        label: '远程已解决',
                        icon: MingCuteIcons.checkCircleLine,
                        bg: const Color(0xFF16A34A),
                        onTap: () => _act(context, 'remoteFix'))),
                const SizedBox(width: 8),
                Expanded(
                    child: _ActBtn(
                        label: '远程已答复',
                        icon: MingCuteIcons.eyeLine,
                        bg: const Color(0xFF0395FF),
                        onTap: () => _act(context, 'remoteConfirm'))),
                const SizedBox(width: 8),
                Expanded(
                    child: _ActBtn(
                        label: '需到场',
                        icon: MingCuteIcons.mapPinLine,
                        bg: const Color(0xFFF59E0B),
                        onTap: () => _act(context, 'onsite'))),
              ],
            ),
        ],
      ),
    );
  }
}

/// 处置动作按钮（圆角色块 + 图标 + 文案）。
class _ActBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color bg;
  final VoidCallback onTap;
  const _ActBtn({
    required this.label,
    required this.icon,
    required this.bg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(height: 4),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: Colors.white)),
            ],
          ),
        ),
      );
}

// ==================== 任务5：施工方整改回复 ====================

class _ReplyCard extends StatefulWidget {
  final Defect d;
  final String byName;
  final Future<void> Function(Defect nu) onUpdate;
  const _ReplyCard({
    required this.d,
    required this.byName,
    required this.onUpdate,
  });

  @override
  State<_ReplyCard> createState() => _ReplyCardState();
}

class _ReplyCardState extends State<_ReplyCard> {
  late final TextEditingController _ctl =
      TextEditingController(text: widget.d.reply ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _submit({bool closeNow = false}) async {
    final text = _ctl.text.trim();
    if (text.isEmpty) {
      AppSnack.show(context, '请先填写整改回复内容', kind: AppSnackKind.muted);
      return;
    }
    setState(() => _busy = true);
    await widget.onUpdate(widget.d.copyWith(
      reply: text,
      replyBy: widget.byName,
      replyTs: _fmtNow(),
      status: closeNow ? DefectStatus.done : null,
      completion: closeNow ? '已完成（整改销项）' : null,
    ));
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final hasReply = (widget.d.reply ?? '').isNotEmpty;
    return AppCard(
      padding: const EdgeInsets.all(AppTokens.space3),
      radius: AppTokens.radiusSm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('整改回复（施工方）',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTokens.fg)),
              const SizedBox(width: 8),
              if (hasReply)
                Text('已于 ${widget.d.replyTs ?? ''} 回复',
                    style: const TextStyle(
                        fontSize: 11, color: AppTokens.muted)),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ctl,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: '填写整改回复内容…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _submit(),
                  child: const Text('仅保存，待复核'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A)),
                  onPressed: _busy ? null : () => _submit(closeNow: true),
                  child: const Text('提交并销项'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

extension _IterableFirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
