import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../shared/widgets/nav_icon_button.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/status_badge.dart';
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
      AppSnack.show(context, '转换成功，已加入「我的上传」',
          kind: AppSnackKind.success);
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
        backgroundColor: AppTokens.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        toolbarHeight: 44,
        centerTitle: false,
        titleSpacing: 12,
        title: const Text('图纸',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppTokens.fg,
                height: 28 / 20)),
        actions: [
          NavIconButton(
            onPressed: () => AppSnack.show(context, '按楼层 / 索引号检索图纸',
                kind: AppSnackKind.brand),
            icon: MingCuteIcons.searchLine,
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: const UserSwitcher(),
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
                padding: const EdgeInsets.fromLTRB(
                    AppTokens.space3, AppTokens.space2, AppTokens.space3, AppTokens.space3),
                children: [
                  // 项目卡
                  AsyncState(
                    value: project,
                    builder: (p) => _ProjectCard(p: p, floorCount: fs.length),
                  ),
                  const SizedBox(height: AppTokens.space3),
                  // 楼层图纸板块标题（CSS Frame 2131330676：16/W600 + N个楼层白色徽标）
                  _FloorHeader(floorCount: fs.length),
                  const SizedBox(height: AppTokens.space2),
                  // 导入图纸：楼层图纸板块的第一个卡片（标题下、楼层列表前）
                  _ImportCard(
                      onTap: () => AppSnack.show(
                          context, '已选择 1 份 PDF 图纸，开始解析并生成索引',
                          kind: AppSnackKind.accent)),
                  const SizedBox(height: AppTokens.space2),
                  // 任务3：DWG 自助上传 → OCF 手机查看
                  _UploadDwgCard(uploading: _uploading, onPick: _uploadDwg),
                  const _UploadedDrawingsSection(),
                  const SizedBox(height: AppTokens.space2),
                  // 楼层列表（卡间距统一 8）
                  ...fs.map((f) {
                    final count = drawings.maybeWhen(
                      data: (m) => m[f.key]?.hotspots.length ?? f.index,
                      orElse: () => f.index,
                    );
                    final cached =
                        (cache[f.key] ?? (f.cached ? 100 : f.progress)) >= 100;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppTokens.space2),
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

/// 楼层图纸板块标题（CSS Frame 2131330676）：左「楼层图纸」16/W600/fg，
/// 右「N个楼层」白色徽标（圆角 6、12/W400/fg）。
class _FloorHeader extends StatelessWidget {
  final int floorCount;
  const _FloorHeader({required this.floorCount});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.space1),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text('楼层图纸',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.fg,
                    height: 24 / 16)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTokens.surface,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('$floorCount 个楼层',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AppTokens.fg)),
            ),
          ],
        ),
      );
}

/// 任务3：DWG 自助上传入口卡（含转换中状态）。
class _UploadDwgCard extends StatelessWidget {
  final bool uploading;
  final VoidCallback onPick;
  const _UploadDwgCard({
    required this.uploading,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: AppTokens.space2),
        padding: const EdgeInsets.all(AppTokens.space3),
        decoration: BoxDecoration(
          color: AppTokens.surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        ),
        child: uploading
            ? const Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('DWG 转换中…约 1-2 分钟（消耗浩辰配额），请勿关闭页面',
                        style: TextStyle(fontSize: 13, color: AppTokens.fg2)),
                  ),
                ],
              )
            : Row(
                children: [
                  const Icon(Icons.upload_file,
                      size: 20, color: AppTokens.brand),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('上传 DWG，自动转 OCF 手机查看（图层/测量可用）',
                        style: TextStyle(
                            fontSize: 13, color: AppTokens.fg2)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTokens.brand,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: onPick,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('上传 DWG'),
                  ),
                ],
              ),
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
      padding: const EdgeInsets.only(bottom: AppTokens.space2),
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
                                fontWeight: FontWeight.w600,
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(label,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
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
  bool _useSvg = false; // 默认 PNG；SVG 大文件渲染慢让用户主动切

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(widget.name,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          actions: [
            IconButton(
              tooltip: _useSvg
                  ? '当前：SVG（含文字/标注） · 点击切到 PNG（快）'
                  : '当前：PNG（几何） · 点击切到 SVG（含文字/标注）',
              icon: Icon(_useSvg ? Icons.text_fields : Icons.image),
              onPressed: () => setState(() => _useSvg = !_useSvg),
            ),
          ],
        ),
        body: InteractiveViewer(
          maxScale: 12,
          child: Center(
            child: _useSvg
                ? SvgPicture.network(
                    '${CadService.host}/api/ocf/${widget.ocfKey}.svg',
                    fit: BoxFit.contain,
                    placeholderBuilder: (_) => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('SVG 加载中（约 30-40MB，浏览器需解析…）',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70)),
                      ),
                    ),
                    errorBuilder: (_, __, ___) => Image.network(
                      '${CadService.host}/api/ocf/${widget.ocfKey}.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Text(
                        '底图加载失败：请确认 CAD 服务(8800)已启动',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  )
                : Image.network(
                    '${CadService.host}/api/ocf/${widget.ocfKey}.png',
                    fit: BoxFit.contain,
                    loadingBuilder: (ctx, child, p) => p == null
                        ? child
                        : const Center(
                            child: CircularProgressIndicator(color: Colors.white)),
                    errorBuilder: (_, __, ___) => const Text(
                      '底图加载失败：请确认 CAD 服务(8800)已启动',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
          ),
        ),
      );
}

class _ImportCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ImportCard({required this.onTap});

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(AppTokens.space3),
        onTap: onTap,
        child: Row(
          children: [
            // 导入图标：32x32 灰底（#F4F6F7）圆角 8 + 品牌蓝上传图标
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTokens.surface2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(MingCuteIcons.uploadLine,
                  color: AppTokens.brand, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('导入图纸',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTokens.fg)),
                  const SizedBox(height: 4),
                  const Text('支持 PDF/JPG/PNG,DWG导入即转PDF',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: AppTokens.muted)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(MingCuteIcons.rightLine,
                color: Color(0xFF999999), size: 16),
          ],
        ),
      );
}

/// 楼层图纸行内标签（CSS Frame 2131330663 / 0617 系列）：
/// 实色浅底、圆角 6、12/W400、行高 20。
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
                fontWeight: FontWeight.w400,
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
                          fontWeight: FontWeight.w600,
                          color: AppTokens.fg),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  // 下排：索引 + 楼栋 + 楼层
                  Row(
                    children: [
                      if (indexCount > 0)
                        _Tag(
                            text: '索引 $indexCount',
                            bg: const Color(0xFFF1F7FF),
                            fg: const Color(0xFF428BF7)),
                      if (indexCount > 0) const SizedBox(width: 4),
                      _Tag(
                          text: floor.building,
                          bg: const Color(0xFFF8F8F8),
                          fg: AppTokens.muted),
                      const SizedBox(width: 4),
                      _Tag(
                          text: floor.floor,
                          bg: const Color(0xFFF8F8F8),
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
