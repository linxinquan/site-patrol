import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../shared/widgets/nav_icon_button.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../data/models.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_bottom_sheet.dart';
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
        leadingWidth: 36,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: NavIconButton(
            icon: MingCuteIcons.leftLine,
            color: const Color(0xFF000000),
            onPressed: () => context.pop(),
          ),
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
                child: Text('未找到该记录', style: TextStyle(color: AppTokens.muted)),
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

class _Body extends StatefulWidget {
  final Defect d;
  final String byName;
  final Future<void> Function(Defect nu) onUpdate;
  const _Body(this.d, {required this.byName, required this.onUpdate});

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  bool _busy = false;
  late final TextEditingController _replyCtl =
      TextEditingController(text: widget.d.reply ?? '');

  @override
  void didUpdateWidget(covariant _Body oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.d.reply != widget.d.reply &&
        _replyCtl.text != (widget.d.reply ?? '')) {
      _replyCtl.text = widget.d.reply ?? '';
    }
  }

  @override
  void dispose() {
    _replyCtl.dispose();
    super.dispose();
  }

  Future<void> _editReply() async {
    final text = await AppBottomSheet.show<String>(
      context: context,
      title: '整改回复',
      isScrollControlled: true,
      body: (ctx) => _ReplyActionSheet(
        initialText: _replyCtl.text,
        helper: '填写整改回复内容后确认保存',
        hintText: '填写整改回复内容',
        accent: AppTokens.brand,
        icon: MingCuteIcons.editLine,
      ),
    );
    if (!mounted || text == null) return;
    _replyCtl.text = text;
    setState(() => _busy = true);
    await widget.onUpdate(widget.d.copyWith(
      reply: text,
      replyBy: widget.byName,
      replyTs: _fmtNow(),
    ));
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _submitRecordAction({required bool closeNow}) async {
    final text = _replyCtl.text.trim();
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
  Widget build(BuildContext context) => Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppTokens.space3, AppTokens.space2, AppTokens.space3, 96),
              children: [
                // 水印照片（保留水印）+ 右上校验胶囊
                _WatermarkPhoto(widget.d),
                const SizedBox(height: AppTokens.space3),
                // 缺陷信息卡：标题 + 状态胶囊 / 红色说明框 / 责任人
                _InfoCard(widget.d),
                const SizedBox(height: AppTokens.space3),
                // 时间轴入口
                _TimelineCard(widget.d),
                const SizedBox(height: AppTokens.space3),
                // 参数卡：拍摄时间 / 海拔 / GPS 坐标 / 楼层部位
                _ParamsCard(widget.d),
                const SizedBox(height: AppTokens.space3),
                // 任务4：设计师远程处置卡
                _DesignerCard(
                    d: widget.d,
                    byName: widget.byName,
                    onUpdate: widget.onUpdate),
                const SizedBox(height: AppTokens.space3),
                // 任务5：施工方整改回复卡（在卡片内直接输入）
                _ReplyCard(
                  d: widget.d,
                  onTap: _busy ? null : _editReply,
                ),
              ],
            ),
          ),
          // 底部固定操作栏用于整条记录的保存和销项操作。
          _RecordActionBar(
            busy: _busy,
            onSave: () => _submitRecordAction(closeNow: false),
            onSubmit: () => _submitRecordAction(closeNow: true),
          ),
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
                        // 卡片主标题统一使用 W500。
                        fontWeight: FontWeight.w500,
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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(MingCuteIcons.eyeLine, color: AppTokens.brand, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text('查看同部位时间轴对比',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 22 / 14,
                    leadingDistribution: TextLeadingDistribution.even,
                    color: AppTokens.brand,
                  )),
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
                    HSLColor.fromAHSL(
                            1.0, d.seed.codeUnitAt(0) * 7 % 360, 0.35, 0.6)
                        .toColor(),
                    HSLColor.fromAHSL(1.0,
                            (d.seed.codeUnitAt(0) * 7 + 40) % 360, 0.45, 0.45)
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
                      bg: Color(0xB300B84A),
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

  // 设计师处置动作采用浅底色块，颜色和底部弹窗中的身份/状态色体系一致。
  (Color fg, Color bg, IconData icon, String title, String hint, bool required)
      _actionMeta(String action) {
    switch (action) {
      case 'remoteFix':
        return (
          const Color(0xFF00B84A),
          const Color(0x0D00B84A),
          MingCuteIcons.checkCircleLine,
          '远程已解决',
          '填写处理说明后提交并同步更新记录状态',
          true,
        );
      case 'remoteConfirm':
        return (
          const Color(0xFFFF4444),
          const Color(0x0DFF4444),
          MingCuteIcons.phoneSuccessLine,
          '远程已答复',
          '填写远程答复内容后提交给施工方查看',
          false,
        );
      default:
        return (
          const Color(0xFFFF9500),
          const Color(0x0DFF9500),
          MingCuteIcons.location2Line,
          '需要到现场',
          '补充到场说明或准备事项后再提交',
          false,
        );
    }
  }

  Future<void> _act(BuildContext context, String action) async {
    final isFix = action == 'remoteFix';
    final meta = _actionMeta(action);
    final note = await AppBottomSheet.show<String>(
      context: context,
      title: meta.$4,
      isScrollControlled: true,
      body: (ctx) => _DesignerActionSheet(
        actionLabel: meta.$4,
        helper: meta.$5,
        requiredNote: meta.$6,
        accent: meta.$1,
        icon: meta.$3,
        hintText: isFix ? '填写处置说明（必填）' : '填写处置说明（选填）',
      ),
    );
    if (!context.mounted) return;
    if (note == null) return; // 取消
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
    final resultMeta = _actionMeta(d.designerAction ?? 'remoteConfirm');
    final resultFg = resultMeta.$1;
    return AppCard(
      padding: const EdgeInsets.all(AppTokens.space3),
      radius: AppTokens.radiusSm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (acted)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 已提交后的展示态按设计稿拆成标题区和灰底内容区，避免整块染色过重。
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Expanded(
                      child: Text('设计师处置',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              height: 22 / 14,
                              color: AppTokens.fg)),
                    ),
                    Container(
                      constraints: const BoxConstraints(minHeight: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: resultFg.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        d.designerActionLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 20 / 12,
                          color: resultFg,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F6F7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 280;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (d.designerNote ?? '').trim().isEmpty
                                ? '暂无处置说明'
                                : d.designerNote!.trim(),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              height: 22 / 14,
                              color: AppTokens.fg2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (compact) ...[
                            Text('处置人：${d.designerBy ?? ''}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  height: 20 / 12,
                                  color: AppTokens.muted,
                                )),
                            const SizedBox(height: 2),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(d.designerTs ?? '',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                    height: 20 / 12,
                                    color: AppTokens.muted,
                                  )),
                            ),
                          ] else
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text('处置人：${d.designerBy ?? ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w400,
                                        height: 20 / 12,
                                        color: AppTokens.muted,
                                      )),
                                ),
                                const SizedBox(width: 8),
                                Text(d.designerTs ?? '',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      height: 20 / 12,
                                      color: AppTokens.muted,
                                    )),
                              ],
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('设计师处置',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 22 / 14,
                        color: AppTokens.fg)),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 336;
                    final buttons = [
                      _ActBtn(
                        label: '远程已解决',
                        icon: MingCuteIcons.checkCircleLine,
                        fg: const Color(0xFF00B84A),
                        bg: const Color(0x0D00B84A),
                        onTap: () => _act(context, 'remoteFix'),
                      ),
                      _ActBtn(
                        label: '远程已答复',
                        icon: MingCuteIcons.phoneSuccessLine,
                        fg: const Color(0xFFFF4444),
                        bg: const Color(0x0DFF4444),
                        onTap: () => _act(context, 'remoteConfirm'),
                      ),
                      _ActBtn(
                        label: '需要到现场',
                        icon: MingCuteIcons.location2Line,
                        fg: const Color(0xFFFF9500),
                        bg: const Color(0x0DFF9500),
                        onTap: () => _act(context, 'onsite'),
                      ),
                    ];
                    if (compact) {
                      return Wrap(
                        spacing: 13,
                        runSpacing: 13,
                        children: buttons
                            .map((btn) => SizedBox(
                                  width: (constraints.maxWidth - 13) / 2,
                                  child: btn,
                                ))
                            .toList(),
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: buttons[0]),
                        const SizedBox(width: 13),
                        Expanded(child: buttons[1]),
                        const SizedBox(width: 13),
                        Expanded(child: buttons[2]),
                      ],
                    );
                  },
                ),
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
  final Color fg;
  final Color bg;
  final VoidCallback onTap;
  const _ActBtn({
    required this.label,
    required this.icon,
    required this.fg,
    required this.bg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 4),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 22 / 14,
                    color: fg,
                  )),
            ],
          ),
        ),
      );
}

class _DesignerActionSheet extends StatefulWidget {
  final String actionLabel;
  final String helper;
  final bool requiredNote;
  final Color accent;
  final IconData icon;
  final String hintText;

  const _DesignerActionSheet({
    required this.actionLabel,
    required this.helper,
    required this.requiredNote,
    required this.accent,
    required this.icon,
    required this.hintText,
  });

  @override
  State<_DesignerActionSheet> createState() => _DesignerActionSheetState();
}

class _DesignerActionSheetState extends State<_DesignerActionSheet> {
  late final TextEditingController _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      // 键盘弹出时允许内容整体上移并滚动，避免输入框被遮挡。
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: widget.accent.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(widget.icon, size: 20, color: widget.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.helper,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          AppBottomSheet.helperStyle(const Color(0xFF60656B)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctl,
              autofocus: true,
              maxLines: 4,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                height: 22 / 14,
                color: AppTokens.fg,
              ),
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: AppBottomSheet.helperStyle(),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      BorderSide(color: widget.accent.withValues(alpha: 0.2)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            AppSheetFooter.cancelSave(
              onCancel: () => Navigator.of(context).pop(),
              onSave: () {
                final text = _ctl.text.trim();
                if (widget.requiredNote && text.isEmpty) {
                  AppSnack.show(context, '请先填写处置说明', kind: AppSnackKind.muted);
                  return;
                }
                Navigator.of(context).pop(text);
              },
              saveLabel: '确认提交',
            ),
          ],
        ),
      ),
    );
  }
}

/// 回复区底部操作按钮：左侧中性浅底，右侧品牌主按钮。
class _ReplyActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final double height;
  final FontWeight fontWeight;
  const _ReplyActionButton({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.height = 36,
    this.fontWeight = FontWeight.w500,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.5 : 1,
          child: Container(
            height: height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: primary ? AppTokens.accent : const Color(0xFFF4F6F7),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: height >= 48 ? 16 : 14,
                // 底部固定主操作使用 48 高按钮，字重统一为 W600。
                fontWeight: fontWeight,
                height: height >= 48 ? 24 / 16 : 22 / 14,
                color: primary ? AppTokens.onAccent : const Color(0xFF60656B),
              ),
            ),
          ),
        ),
      );
}

// ==================== 任务5：施工方整改回复 ====================

class _ReplyCard extends StatelessWidget {
  final Defect d;
  final VoidCallback? onTap;
  const _ReplyCard({
    required this.d,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(AppTokens.space3),
        radius: AppTokens.radiusSm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('整改回复（施工方）',
                style: TextStyle(
                    fontSize: 14,
                    // 卡片区块标题统一使用 W500。
                    fontWeight: FontWeight.w500,
                    height: 22 / 14,
                    color: AppTokens.fg)),
            const SizedBox(height: 8),
            if ((d.reply ?? '').trim().isEmpty)
              Semantics(
                button: true,
                enabled: onTap != null,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  child: Opacity(
                    opacity: onTap == null ? 0.5 : 1,
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 38),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0x0D0395FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      // 空状态是浅蓝按钮，图标和文案整体居中。
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(MingCuteIcons.editLine,
                              size: 20, color: AppTokens.brand),
                          SizedBox(width: 4),
                          Text(
                            '填写回复',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              height: 22 / 14,
                              color: AppTokens.brand,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F6F7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 280;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.reply!.trim(),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            height: 22 / 14,
                            color: AppTokens.fg2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (compact) ...[
                          Text('回复人：${d.replyBy ?? ''}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                height: 20 / 12,
                                color: AppTokens.muted,
                              )),
                          const SizedBox(height: 2),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              d.replyTs ?? '',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                height: 20 / 12,
                                color: AppTokens.muted,
                              ),
                            ),
                          ),
                        ] else
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  '回复人：${d.replyBy ?? ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                    height: 20 / 12,
                                    color: AppTokens.muted,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                d.replyTs ?? '',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  height: 20 / 12,
                                  color: AppTokens.muted,
                                ),
                              ),
                            ],
                          ),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      );
}

/// 整改回复底部弹窗：交互和设计师处置保持一致，确认后返回填写内容。
class _ReplyActionSheet extends StatefulWidget {
  final String initialText;
  final String helper;
  final String hintText;
  final Color accent;
  final IconData icon;

  const _ReplyActionSheet({
    required this.initialText,
    required this.helper,
    required this.hintText,
    required this.accent,
    required this.icon,
  });

  @override
  State<_ReplyActionSheet> createState() => _ReplyActionSheetState();
}

class _ReplyActionSheetState extends State<_ReplyActionSheet> {
  late final TextEditingController _ctl =
      TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      // 键盘弹出时允许内容整体上移并滚动，避免输入框被遮挡。
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: widget.accent.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(widget.icon, size: 20, color: widget.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.helper,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          AppBottomSheet.helperStyle(const Color(0xFF60656B)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctl,
              autofocus: true,
              maxLines: 4,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                height: 22 / 14,
                color: AppTokens.fg,
              ),
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: AppBottomSheet.helperStyle(),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      BorderSide(color: widget.accent.withValues(alpha: 0.2)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            AppSheetFooter.cancelSave(
              onCancel: () => Navigator.of(context).pop(),
              onSave: () {
                final text = _ctl.text.trim();
                if (text.isEmpty) {
                  AppSnack.show(context, '请先填写整改回复内容',
                      kind: AppSnackKind.muted);
                  return;
                }
                Navigator.of(context).pop(text);
              },
              saveLabel: '确认提交',
            ),
          ],
        ),
      ),
    );
  }
}

/// 记录详情页底部固定操作栏：承载整条记录的保存和销项操作。
class _RecordActionBar extends StatelessWidget {
  final bool busy;
  final VoidCallback onSave;
  final VoidCallback onSubmit;

  const _RecordActionBar({
    required this.busy,
    required this.onSave,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) => Container(
        color: AppTokens.surface,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: _ReplyActionButton(
                  onTap: busy ? null : onSave,
                  label: '仅保存，待复核',
                  height: 48,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ReplyActionButton(
                  primary: true,
                  onTap: busy ? null : onSubmit,
                  label: '提交并销项',
                  height: 48,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
}

extension _IterableFirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
