import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';

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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 分段切换（Frame 2131330677）：外壳高 34、pad 2、gap 2、#E9EAEB 底圆角 8；
        // 选中片白底圆角 6、14/W500/#202224；未选中透明底、#919499。两片 Expanded 等分自适应。
        AnimatedBuilder(
          animation: _tab,
          builder: (_, __) => Container(
            height: 34,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: const Color(0xFFE9EAEB),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                _segChip('图层', 0),
                const SizedBox(width: 2),
                _segChip('布局', 1),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 内容白卡（Frame 2147228107）：白底圆角 8、高 240、pad 12，内容居中展示。
        Container(
          height: 240,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTokens.surface,
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          ),
          child: SizedBox.expand(
            child: TabBarView(
              controller: _tab,
              children: [
                _buildLayers(),
                _buildLayouts(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoading() => const Center(
        child: CircularProgressIndicator(color: AppTokens.brand),
      );

  /// 空态/错误：白卡内居中提示（Frame 2147228107：14/W400/#B5B9BF）。
  Widget _buildError() => Center(
        child: Text(
          _loadingError ?? '未知错误',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            height: 22 / 14,
            color: Color(0xFFB5B9BF),
          ),
        ),
      );

  Widget _buildLayers() {
    if (_loading) return _buildLoading();
    if (_loadingError != null) return _buildError();
    if (_info == null || _info!.layers.isEmpty) {
      return const Center(
        child: Text('暂无图层数据',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                height: 22 / 14,
                color: Color(0xFFB5B9BF))),
      );
    }
    final layers = _info!.layers;
    return ListView.separated(
      itemCount: layers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final l = layers[i];
        final on = _layerToggle[l.name] ?? true;
        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14,
                          height: 22 / 14,
                          color: AppTokens.fg)),
                  if (l.isFrozen)
                    const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Text('已冻结',
                            style: TextStyle(fontSize: 12, color: AppTokens.muted)))
                  else if (l.isLock)
                    const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Text('已锁定',
                            style: TextStyle(fontSize: 12, color: AppTokens.muted))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _RoundCheckbox(
              value: on,
              onChanged: (v) => setState(() => _layerToggle[l.name] = v ?? true),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLayouts() {
    if (_loading) return _buildLoading();
    if (_loadingError != null) return _buildError();
    if (_info == null || _info!.layouts.isEmpty) {
      return const Center(
        child: Text('暂无布局数据',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                height: 22 / 14,
                color: Color(0xFFB5B9BF))),
      );
    }
    final current = ref.watch(cadCurrentLayoutProvider);
    final layouts = _info!.layouts;
    return ListView.separated(
      itemCount: layouts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final lay = layouts[i];
        final selected = current == lay.name;
        return GestureDetector(
          onTap: () {
            ref.read(cadCurrentLayoutProvider.notifier).state = lay.name;
            setState(() {});
          },
          child: Row(
            children: [
              Icon(
                selected
                    ? MingCuteIcons.checkCircleLine
                    : MingCuteIcons.circleDashLine,
                color: selected ? AppTokens.brand : AppTokens.muted,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(lay.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, height: 22 / 14, color: AppTokens.fg)),
                    if (lay.handle != null)
                      Text('句柄 ${lay.handle}',
                          style:
                              const TextStyle(fontSize: 12, color: AppTokens.muted)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 分段切换胶囊片（Frame 2131330677 小按钮）：高 30、圆角 6；
  /// 选中 = 白底 + 14/W500/#202224；未选中 = 透明底 + #919499。
  Widget _segChip(String label, int i) {
    final sel = _tab.index == i;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          _tab.animateTo(i);
          setState(() {});
        },
        child: Container(
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel ? AppTokens.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 22 / 14,
              color: sel ? AppTokens.fg : AppTokens.muted,
            ),
          ),
        ),
      ),
    );
  }

  /// 自绘圆角勾选框（替代 Material Checkbox）。
  Widget _RoundCheckbox(
      {required bool value, required ValueChanged<bool?> onChanged}) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: value ? AppTokens.brand : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: value ? AppTokens.brand : AppTokens.muted, width: 1.5),
        ),
        child: value
            ? const Icon(MingCuteIcons.checkLine, size: 14, color: Colors.white)
            : null,
      ),
    );
  }
}
