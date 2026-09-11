import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../shared/widgets/app_bottom_sheet.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/async_state.dart';
import '../../shared/widgets/offline_bar.dart';
import '../../shared/widgets/app_snack.dart';
import '../../shared/widgets/maskable_name.dart';
import '../../shared/widgets/user_switcher.dart';
import '../../data/models.dart';
// 选文件：web 端用 dart:html 自实现（file_picker 在 Flutter Web HTML 渲染器下不可用），
// io（Android/iOS）继续用 file_picker。
import '_dwg_picker_io.dart' if (dart.library.html) '_dwg_picker_web.dart'
    as picker;
import '../../data/cad_service.dart';
import '../../core/storage/uploaded_drawing_store.dart';

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

  /// 任务3：上传中状态（转圈 + 防重复点击）。
  bool _uploading = false;

  /// 任务3：选择 .dwg 上传 → 本地 ODA+ezdxf 转 OCF → 登记到「我的上传」。
  Future<void> _uploadDwg() async {
    if (_uploading) return;
    final projectId = ref.read(currentProjectIdProvider) ?? '';
    final picked = await picker.pickerDwg();
    final bytes = picked.bytes;
    final fileName = picked.name;
    if (bytes == null || fileName == null) {
      AppSnack.show(context, '未选择 .dwg 文件', kind: AppSnackKind.muted);
      return;
    }
    setState(() => _uploading = true);
    AppSnack.show(context, '本地转换中（ODA→DXF→底图），不消耗浩辰配额…',
        kind: AppSnackKind.brand);
    try {
      final base =
          fileName.replaceAll(RegExp(r'\.dwg$', caseSensitive: false), '');
      final biz = await CadService().uploadDwgLocal(
        fileName: fileName,
        fileBase64: base64Encode(bytes),
      );
      final ocfKey = (biz['key'] as String?) ?? base;
      final localOk = biz['localOk'] != false;
      if (!localOk) {
        // 本地无法完整转换（天正/自定义代理对象导致 ODA 导出 DXF 损坏）
        if (!mounted) return;
        final note = (biz['note'] as String?) ?? '';
        AppSnack.show(
            context, note.isNotEmpty ? note : '本地无法完整转换该图纸，请使用「专业看图」(云图)',
            kind: AppSnackKind.danger);
        return;
      }
      final existing = await UploadedDrawingStore.list(projectId);
      await UploadedDrawingStore.save(projectId, [
        UploadedDrawing(
          key: ocfKey,
          name: base,
          fileName: fileName,
          sizeBytes: bytes.length,
          tsMs: DateTime.now().millisecondsSinceEpoch,
          width: (biz['png_w'] as num?)?.toInt() ?? 0,
          height: (biz['png_h'] as num?)?.toInt() ?? 0,
          bounds: (biz['bounds'] as List?)?.join(','),
          status: 'done',
        ),
        ...existing,
      ]);
      if (!mounted) return;
      ref.invalidate(uploadedDrawingsProvider(projectId));
      final note = (biz['note'] as String?) ?? '';
      if (note.isNotEmpty) {
        AppSnack.show(context, note, kind: AppSnackKind.warning);
      } else {
        AppSnack.show(context, '转换成功，已加入「我的上传」', kind: AppSnackKind.success);
      }
    } catch (e) {
      if (!mounted) return;
      AppSnack.show(context, '上传失败：$e', kind: AppSnackKind.danger);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
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
        AppSnack.show(context, '图纸已下载，可离线查看', kind: AppSnackKind.success);
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
        backgroundColor: AppTokens.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        toolbarHeight: 48,
        centerTitle: false,
        titleSpacing: 12,
        title: const Text('图纸',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppTokens.fg,
                height: 28 / 20)),
        actions: const [
          Padding(
            padding: EdgeInsets.fromLTRB(0, 0, 12, 0),
            child: UserSwitcher(),
          ),
        ],
      ),
      body: AsyncState(
        value: floors,
        builder: (fs) => Column(
          children: [
            Expanded(
              child: ListView(
                primary: false,
                padding: const EdgeInsets.fromLTRB(AppTokens.space3,
                    AppTokens.space2, AppTokens.space3, AppTokens.space3),
                children: [
                  // 项目卡
                  AsyncState(
                    value: project,
                    builder: (p) => _ProjectCard(p: p),
                  ),
                  const SizedBox(height: 24),
                  // 楼层图纸板块标题（Frame 2147227972：16/W600 + 「楼层图纸 · N」）
                  _FloorHeader(floorCount: fs.length),
                  const SizedBox(height: AppTokens.space2),
                  // 双列入口（Frame 2147228096 自适应）：导入图纸 / 上传 DWG
                  _FloorImportGrid(
                    onImport: () => AppSnack.show(
                        context, '已选择 1 份 PDF 图纸，开始解析并生成索引',
                        kind: AppSnackKind.accent),
                    dwgUploading: _uploading,
                    onPickDwg: _uploadDwg,
                  ),
                  const SizedBox(height: AppTokens.space3),
                  // 我的上传（DWG→OCF）登记（无记录时自动隐藏）
                  const _UploadedDrawingsSection(),
                  // 楼层列表（卡间距统一 12）
                  ...fs.map((f) {
                    final count = drawings.maybeWhen(
                      data: (m) => m[f.key]?.hotspots.length ?? f.index,
                      orElse: () => f.index,
                    );
                    final cached =
                        (cache[f.key] ?? (f.cached ? 100 : f.progress)) >= 100;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppTokens.space3),
                      child: DrawingListItem(
                        floor: f,
                        indexCount: count,
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

/// 图纸页顶部项目信息卡（Frame 2147228103 自适应版）。
///
/// **蓝卡叠白卡**：白色圆角卡（8）托底，品牌蓝圆角卡（8）压在上部（项目名
/// 16/W500/白 + 副标题 + 「查看更多」+ 甲方行），白卡比蓝卡多出的下半截露出
/// **业主代表**常显行（眼睛开关切换姓名脱敏）。两卡共用上缘与宽度、无灰缝、
/// 不写死高度。无参建方（如南科大）只渲染单张蓝卡。
/// 「查看更多」点击弹出**底部弹窗**：标题 = 项目名，下方完整副标题 + 其余参建
/// 单位（设计院 / 监理 / PMO）彩标白卡列表（Frame 2147228009 样式）。
class _ProjectCard extends StatefulWidget {
  final Project p;
  const _ProjectCard({required this.p});

  @override
  State<_ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<_ProjectCard> {
  /// 业主代表姓名是否脱敏（眼睛开关，默认明文）。
  bool _nameHidden = false;

  Project get p => widget.p;

  /// 首参建方 = 甲方（业主方），其 role/org 进蓝卡 footer、title/contact 为业主代表。
  Party? get _owner => p.parties.isEmpty ? null : p.parties.first;

  /// 其余参建单位（多于甲方时显示「查看更多」入口）。
  List<Party> get _more =>
      p.parties.length > 1 ? p.parties.sublist(1) : const <Party>[];

  /// 「查看更多」：底部弹窗 = 项目名标题 + 完整副标题 + 全部参建方彩标白卡
  /// （甲方第一张，随后设计院 / 监理 / PMO 等）。
  void _showMore() {
    final parties = p.parties;
    AppBottomSheet.show(
      context: context,
      isScrollControlled: true,
      title: p.name,
      body: (ctx) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 完整副标题：甲方 · 面积 · 状态，有多少显示多少、不限行数（随宽度自动换行）。
            Text(
              '${p.client} · ${p.floorArea} · ${p.status}',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: AppTokens.fg2,
                  height: 22 / 14),
            ),
            const SizedBox(height: 12),
            // 参建单位白卡列表（含甲方，甲方第一张；Frame 2147228070 起）
            for (var i = 0; i < parties.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _PartyDetailCard(party: parties[i]),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final owner = _owner;
    final more = _more;

    // 品牌蓝圆角卡（8）：项目名 W500/白 + 副标题 + 查看更多 + 甲方行
    final blueCard = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTokens.brand,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 项目名 / 副标题（甲方·面积·状态）
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: AppTokens.onBrand,
                            height: 24 / 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(
                      '${p.client} · ${p.floorArea} · ${p.status}',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTokens.onBrand.withValues(alpha: 0.7),
                          height: 20 / 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (more.isNotEmpty) ...[
                const SizedBox(width: 16),
                // 「查看更多」白底蓝字小按钮 → 弹出底部参建方列表
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _showMore,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTokens.surface,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('查看更多',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppTokens.brand,
                            height: 20 / 12)),
                  ),
                ),
              ],
            ],
          ),
          if (owner != null) ...[
            const SizedBox(height: 8),
            Container(
              height: 1,
              color: AppTokens.onBrand.withValues(alpha: 0.1),
            ),
            const SizedBox(height: 8),
            // 甲方（业主方）｜单位全称（两端各半，超长各自省略）
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(owner.role,
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTokens.onBrand.withValues(alpha: 0.7),
                          height: 20 / 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(owner.org,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTokens.onBrand.withValues(alpha: 0.7),
                          height: 20 / 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    // 无参建方（南科大等）：只有一张蓝卡，不加白卡托底。
    if (owner == null) return blueCard;

    // —— 蓝卡叠白卡：白卡托底（自身比蓝卡高出一个业主代表行的高度），
    //    蓝卡从白卡上缘压入，白卡露出的下半截即业主代表行，中间无灰缝 ——
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          blueCard,
          // 白区：业主代表（常显，眼睛开关切换姓名脱敏）
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: _OwnerRow(
              party: owner,
              hidden: _nameHidden,
              onToggleHide: () => setState(() => _nameHidden = !_nameHidden),
            ),
          ),
        ],
      ),
    );
  }
}

/// 业主代表行：左「职务」右「姓名 + 眼睛开关」。
/// 眼睛图标点击切换姓名脱敏显示（默认明文 + 闭眼图标，点后打码 + 睁眼图标）。
class _OwnerRow extends StatelessWidget {
  final Party party;
  final bool hidden;
  final VoidCallback onToggleHide;
  const _OwnerRow({
    required this.party,
    required this.hidden,
    required this.onToggleHide,
  });

  @override
  Widget build(BuildContext context) {
    final name = party.contact.isEmpty
        ? party.contact
        : (hidden ? MaskableName.mask(party.contact) : party.contact);
    // 底行两端贴齐：职务靠左占满弹性区，姓名+眼睛整体顶到卡片右端。
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(party.title,
              style: const TextStyle(
                  fontSize: 12, color: AppTokens.fg2, height: 20 / 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 16),
        // 姓名用固有宽度（内容短），职务的 Expanded 吸收全部剩余空间，
        // 姓名+眼睛整体顶到卡片右端（两端贴齐）。勿再用 Flexible 与职务平分 50%。
        Text(name,
            style: const TextStyle(
                fontSize: 12, color: AppTokens.fg2, height: 20 / 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        const SizedBox(width: 4),
        // 眼睛开关（16px，可点区域外扩到 24px 方便触控）
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggleHide,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              hidden ? MingCuteIcons.eyeLine : MingCuteIcons.eyeCloseLine,
              size: 16,
              color: AppTokens.fg2,
            ),
          ),
        ),
      ],
    );
  }
}

/// 「查看更多」底部弹窗中的参建单位白卡（Frame 2147228070/74…）：
/// 彩色角色标签（甲方红 / 设计监理蓝 / PMO 绿）+ 单位全称 16/W600
/// + 底行「职务 | 姓名 + 眼睛开关」（姓名点击脱敏，逐卡独立）。
class _PartyDetailCard extends StatefulWidget {
  final Party party;
  const _PartyDetailCard({required this.party});

  @override
  State<_PartyDetailCard> createState() => _PartyDetailCardState();
}

class _PartyDetailCardState extends State<_PartyDetailCard> {
  /// 本卡联系人姓名是否脱敏（眼睛开关，默认明文）。
  bool _hidden = false;

  /// 按角色取标签配色：甲方红 #FF4444、PMO/咨询绿 #00B84A、其余品牌蓝。
  (Color, Color) get _pillColor {
    final role = widget.party.role;
    if (role.contains('甲方')) {
      return (const Color(0xFFFF4444), const Color(0x0DFF4444));
    }
    if (role.contains('PMO') || role.contains('Arcadis')) {
      return (const Color(0xFF00B84A), const Color(0x0D00B84A));
    }
    return (AppTokens.brand, AppTokens.brandTint);
  }

  @override
  Widget build(BuildContext context) {
    final party = widget.party;
    final (pillFg, pillBg) = _pillColor;
    final name = party.contact.isEmpty
        ? party.contact
        : (_hidden ? MaskableName.mask(party.contact) : party.contact);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 彩色角色标签（圆角 6，12/W500；长文本随卡片宽度自动换行、不截断）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: pillBg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              party.role,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: pillFg,
                  height: 20 / 12),
            ),
          ),
          const SizedBox(height: 4),
          // 单位全称（16/W500；长文本自动换行完整显示、不截断）
          Text(party.org,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppTokens.fg,
                  height: 24 / 16)),
          const SizedBox(height: 4),
          // 底行两端贴齐：左「职务」单行省略占满弹性区，右「姓名 + 眼睛」顶到卡右端。
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(party.title,
                    style: const TextStyle(
                        fontSize: 12, color: AppTokens.fg2, height: 20 / 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 16),
              // 姓名用固有宽度（内容短），职务的 Expanded 吸收全部剩余空间，
              // 姓名+眼睛整体顶到卡片右端（两端贴齐）。勿再用 Flexible 与职务平分 50%。
              Text(name,
                  style: const TextStyle(
                      fontSize: 12, color: AppTokens.fg2, height: 20 / 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(width: 4),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _hidden = !_hidden),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    _hidden
                        ? MingCuteIcons.eyeLine
                        : MingCuteIcons.eyeCloseLine,
                    size: 16,
                    color: AppTokens.fg2,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 楼层图纸板块标题（Frame 2147227972）：「楼层图纸 · N 个楼层」16/W600/fg，行高 24。
class _FloorHeader extends StatelessWidget {
  final int floorCount;
  const _FloorHeader({required this.floorCount});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.space1),
        child: Text('楼层图纸 · $floorCount 个楼层',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTokens.fg,
                height: 24 / 16)),
      );
}

/// 任务3：已上传 DWG 登记列表（含转换状态；真实渲染需 CAD 服务 + 配额）。
class _UploadedDrawingsSection extends ConsumerWidget {
  const _UploadedDrawingsSection();

  static String _time(int ms) {
    if (ms <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String t(int v) => v.toString().padLeft(2, '0');
    return '${t(d.month)}-${t(d.day)} ${t(d.hour)}:${t(d.minute)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectId = ref.watch(currentProjectIdProvider) ?? '';
    final items = ref.watch(uploadedDrawingsProvider(projectId)).maybeWhen(
          data: (l) => l,
          orElse: () => const <UploadedDrawing>[],
        );
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('我的上传（DWG→OCF）',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.muted)),
          const SizedBox(height: 6),
          ...items.map((e) {
            final (String label, Color color) = switch (e.status) {
              'done' => ('已转换', const Color(0xFF16A34A)),
              'converting' => ('转换中', AppTokens.brand),
              _ => ('失败', AppTokens.danger),
            };
            return InkWell(
              onTap: e.status == 'done'
                  ? () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            _LocalDwgPreviewPage(ocfKey: e.key, name: e.name),
                      ))
                  : null,
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTokens.surface,
                  borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.description_outlined,
                        size: 18, color: AppTokens.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14,
                                  // 列表卡主标题统一使用 W500。
                                  fontWeight: FontWeight.w500,
                                  color: AppTokens.fg)),
                          Text(
                            'key: ${e.key} · ${_time(e.tsMs)}'
                            '${e.status == 'failed' && e.error != null ? ' · ${e.error}' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11, color: AppTokens.muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(label,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: color)),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// 本地转换 DWG 底图预览：默认 PNG（快、稳），右上角可切到 SVG（含文字/标注，大图较慢）。
class _LocalDwgPreviewPage extends StatefulWidget {
  final String ocfKey;
  final String name;
  const _LocalDwgPreviewPage({required this.ocfKey, required this.name});

  @override
  State<_LocalDwgPreviewPage> createState() => _LocalDwgPreviewPageState();
}

class _LocalDwgPreviewPageState extends State<_LocalDwgPreviewPage> {
  // 默认叠加文字层：PNG(几何) + 轻量 SVG(仅文字，几十 KB)
  bool _showText = true;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          title: Text(widget.name,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          actions: [
            IconButton(
              tooltip: _showText ? '隐藏文字/标注层' : '显示文字/标注层',
              icon: Icon(_showText ? Icons.text_fields : Icons.text_format),
              onPressed: () => setState(() => _showText = !_showText),
            ),
          ],
        ),
        body: InteractiveViewer(
          maxScale: 12,
          child: Center(
            // Stack 大小由 PNG 决定；SVG 文字层同宽高比 contain 填充 → 精确对齐
            child: Stack(
              children: [
                Image.network(
                  '${CadService.host}/api/ocf/${widget.ocfKey}.png',
                  fit: BoxFit.contain,
                  loadingBuilder: (ctx, child, p) => p == null
                      ? child
                      : const Center(
                          child:
                              CircularProgressIndicator(color: Colors.white)),
                  errorBuilder: (_, __, ___) => const Text(
                    '底图加载失败：请确认 CAD 服务(8800)已启动',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                if (_showText)
                  Positioned.fill(
                    child: SvgPicture.network(
                      '${CadService.host}/api/ocf/${widget.ocfKey}.svg',
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      // 文字层缺失时静默忽略（仅显示几何底图）
                      placeholderBuilder: (_) => const SizedBox.shrink(),
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}

/// 楼层图纸板块「导入 / 上传」双列入口（Frame 2147228096）：
/// 两卡等宽等高（Expanded + IntrinsicHeight + stretch），窄屏自动收窄不溢出。
class _FloorImportGrid extends StatelessWidget {
  final VoidCallback onImport;
  final bool dwgUploading;
  final VoidCallback onPickDwg;
  const _FloorImportGrid({
    required this.onImport,
    required this.dwgUploading,
    required this.onPickDwg,
  });

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _ImportTile(
                title: '导入图纸',
                desc: '支持 PDF/JPG/PNG',
                icon: MingCuteIcons.upload2Line,
                onTap: onImport,
              ),
            ),
            const SizedBox(width: AppTokens.space3),
            Expanded(
              child: dwgUploading
                  ? const _DwgLoadingTile()
                  : _ImportTile(
                      title: '上传 DWG',
                      desc: '自动转 OCF 查看',
                      icon: MingCuteIcons.fileImportLine,
                      iconColor: const Color(0xFFFF4444),
                      textGap: 2,
                      onTap: onPickDwg,
                    ),
            ),
          ],
        ),
      );
}

/// 通用横版入口卡（Frame 2131330695 / 2131330697）：白卡圆角 8、pad 8/12、
/// 总高 64；左 24×24 图标（默认品牌色，可传 iconColor 覆盖）+ gap 12 + 右文字列
/// （标题 16/W500/fg 24 行高、说明 12/W400/muted 20 行高，行间距 textGap：
/// 导入卡 4 / 上传 DWG 卡 2）。
/// 文字列 Expanded 弹性收缩（各 maxLines:1 省略），
/// 窄屏自动收窄不溢出；外层 ConstrainedBox 保底高 64，字号放大时可增高不裁切。
class _ImportTile extends StatelessWidget {
  final String title;
  final String desc;
  final IconData icon;
  final Color iconColor;
  final double textGap;
  final VoidCallback onTap;
  const _ImportTile({
    required this.title,
    required this.desc,
    required this.icon,
    this.iconColor = AppTokens.brand,
    this.textGap = 4,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: AppCard(
          radius: AppTokens.radiusSm,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          onTap: onTap,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: AppTokens.fg,
                            height: 24 / 16)),
                    SizedBox(height: textGap),
                    Text(desc,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            height: 20 / 12,
                            color: AppTokens.muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

/// DWG 上传转换中的占位卡（与 _ImportTile 同外壳同横版布局：spinner 占 24px 图标位）。
class _DwgLoadingTile extends StatelessWidget {
  const _DwgLoadingTile();

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: const AppCard(
          radius: AppTokens.radiusSm,
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('DWG 转换中…',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppTokens.fg,
                            height: 22 / 14)),
                    Text('约 1-2 分钟，请勿关闭页面',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            height: 20 / 12,
                            color: AppTokens.muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

/// 楼层图纸行内标签（CSS Frame 2131330663 / 0617 系列）：
/// 实色浅底、圆角 6、12/W500、行高 20（全局标签规范：标签内文字一律 W500）。
class _Tag extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const _Tag({required this.text, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 20 / 12,
                leadingDistribution: TextLeadingDistribution.even,
                color: fg)),
      );
}

class DrawingListItem extends StatelessWidget {
  final Floor floor;
  final int indexCount;
  final VoidCallback onTap;
  const DrawingListItem({
    super.key,
    required this.floor,
    required this.indexCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(AppTokens.space3),
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 图纸图标（图纸.png，无矩形灰底）
            Image.asset('assets/icons/drawings.png',
                width: 32, height: 32, fit: BoxFit.contain),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题
                  Text(floor.name,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: AppTokens.fg,
                          height: 24 / 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  // 下排：索引(品牌浅蓝底) + 楼栋 + 楼层（Wrap 自适应换行，长楼栋名不再顶出）
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (indexCount > 0)
                        _Tag(
                            text: '索引 $indexCount',
                            bg: const Color(0x0D0395FF),
                            fg: AppTokens.brand),
                      _Tag(
                          text: floor.building,
                          bg: AppTokens.surface2,
                          fg: AppTokens.muted),
                      _Tag(
                          text: floor.floor,
                          bg: AppTokens.surface2,
                          fg: AppTokens.muted),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
