import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/di/providers.dart';
import '../../data/models.dart';

/// CAD 信息面板：图层开关 + 布局切换。
/// 通过 [dwgFileUrl] / [dwgBase64] 触发 getDwgInfo 解析；
/// 未提供时展示当前已解析的 CAD 信息或提示接入。
class CadInfoPanel extends ConsumerStatefulWidget {
  final String drawingKey;
  final String? dwgFileUrl;
  final String? dwgBase64;
  const CadInfoPanel({
    super.key,
    required this.drawingKey,
    this.dwgFileUrl,
    this.dwgBase64,
  });

  @override
  ConsumerState<CadInfoPanel> createState() => _CadInfoPanelState();
}

class _CadInfoPanelState extends ConsumerState<CadInfoPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _layerToggle = <String, bool>{}; // layer name -> visible
  DwgInfo? _info;
  String? _loadingError;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      DwgInfo? info;
      final cached = ref.read(cadInfoProvider(widget.drawingKey));
      if (cached.hasValue) {
        info = cached.value;
      }
      if (info != null) {
        setState(() {
          _info = info;
          _loading = false;
          _initToggles();
        });
        return;
      }
      // 无缓存且提供了 DWG 源，走真实解析（getDwgInfo 不扣次）
      if (widget.dwgFileUrl != null || widget.dwgBase64 != null) {
        final cad = ref.read(cadServiceProvider);
        info = await cad.fetchDwgInfo(
          fileName: '${widget.drawingKey.replaceAll('_', ' ')}.dwg',
          fileUrl: widget.dwgFileUrl,
          fileBase64: widget.dwgBase64,
        );
        setState(() {
          _info = info;
          _loading = false;
          _initToggles();
        });
        return;
      }
      setState(() {
        _loading = false;
        _loadingError = '当前图纸未关联 DWG 数据源';
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _loadingError = 'CAD 解析失败：$e';
      });
    }
  }

  void _initToggles() {
    _layerToggle.clear();
    if (_info != null) {
      for (final l in _info!.layers) {
        _layerToggle[l.name] = !l.isOff;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.space4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text('专业看图',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTokens.fg)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close,
                      size: 20, color: AppTokens.muted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            TabBar(
              controller: _tab,
              labelColor: AppTokens.brand,
              unselectedLabelColor: AppTokens.muted,
              indicatorColor: AppTokens.brand,
              tabs: const [
                Tab(text: '图层', icon: Icon(LucideIcons.layers, size: 16)),
                Tab(text: '布局', icon: Icon(LucideIcons.layoutTemplate, size: 16)),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 300,
              child: TabBarView(
                controller: _tab,
                children: [
                  _buildLayers(),
                  _buildLayouts(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: CircularProgressIndicator(color: AppTokens.brand),
        ),
      );

  Widget _buildError() => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(_loadingError ?? '未知错误',
              style: const TextStyle(color: AppTokens.muted)),
        ),
      );

  Widget _buildLayers() {
    if (_loading) return _buildLoading();
    if (_loadingError != null) return _buildError();
    if (_info == null || _info!.layers.isEmpty) {
      return const Center(
          child: Text('暂无图层数据', style: TextStyle(color: AppTokens.muted)));
    }
    final layers = _info!.layers;
    return ListView.builder(
      itemCount: layers.length,
      itemBuilder: (context, i) {
        final l = layers[i];
        final on = _layerToggle[l.name] ?? true;
        return CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: AppTokens.brand,
          title: Text(l.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppTokens.fg)),
          subtitle: l.isFrozen
              ? const Text('已冻结', style: TextStyle(fontSize: 11))
              : (l.isLock
                  ? const Text('已锁定', style: TextStyle(fontSize: 11))
                  : null),
          value: on,
          onChanged: (v) =>
              setState(() => _layerToggle[l.name] = v ?? true),
        );
      },
    );
  }

  Widget _buildLayouts() {
    if (_loading) return _buildLoading();
    if (_loadingError != null) return _buildError();
    if (_info == null || _info!.layouts.isEmpty) {
      return const Center(
          child: Text('暂无布局数据', style: TextStyle(color: AppTokens.muted)));
    }
    final current = ref.watch(cadCurrentLayoutProvider);
    final layouts = _info!.layouts;
    return ListView.builder(
      itemCount: layouts.length,
      itemBuilder: (context, i) {
        final lay = layouts[i];
        final selected = current == lay.name;
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            selected ? LucideIcons.checkCircle : LucideIcons.circle,
            color: selected ? AppTokens.brand : AppTokens.muted,
            size: 20,
          ),
          title: Text(lay.name,
              style: const TextStyle(fontSize: 13, color: AppTokens.fg)),
          subtitle: lay.handle != null
              ? Text('句柄 ${lay.handle}',
                  style: const TextStyle(fontSize: 11))
              : null,
          onTap: () {
            ref.read(cadCurrentLayoutProvider.notifier).state = lay.name;
            setState(() {});
          },
        );
      },
    );
  }
}
