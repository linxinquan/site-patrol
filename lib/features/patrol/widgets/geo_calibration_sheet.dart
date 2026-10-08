import 'package:flutter/material.dart';

import '../../../core/cad/geo_calibration.dart';
import '../../../core/utils/geo_project.dart';

/// 图纸**地理配准**表单：把现场 GPS 经纬度落到这张图纸的像素上。
///
/// 现场怎么填（方案①）：
/// 1. 拿手机定位（或问总工/BIM）拿到**图纸左上角**那个点的真实经纬度；
/// 2. 选图纸幅面（A0~A4）与比例尺（如 1:100）；
/// 3. 系统按 `米/像素 = 纸面宽(m) × 比例尺分母 / 底图像素宽` 自动换算，
///    并显示这张图覆盖的实地范围，确认量级无误后保存。
///
/// 配准一次长期复用；底图改版（换图纸）后需重新配准。
/// 返回 `true` 表示配准有变更（调用方需刷新轨迹像素化缓存）。
Future<bool?> showGeoCalibrationSheet(
  BuildContext context, {
  required GeoCalibrationLibrary library,
  required String drawingKey,
  required String drawingVersionId,
  required double pixelWidth,
  required String drawingTitle,
  GeoCalibration? current,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _GeoCalibrationSheet(
      library: library,
      drawingKey: drawingKey,
      drawingVersionId: drawingVersionId,
      pixelWidth: pixelWidth,
      drawingTitle: drawingTitle,
      current: current,
    ),
  );
}

class _GeoCalibrationSheet extends StatefulWidget {
  const _GeoCalibrationSheet({
    required this.library,
    required this.drawingKey,
    required this.drawingVersionId,
    required this.pixelWidth,
    required this.drawingTitle,
    this.current,
  });

  final GeoCalibrationLibrary library;
  final String drawingKey;
  final String drawingVersionId;
  final double pixelWidth;
  final String drawingTitle;
  final GeoCalibration? current;

  @override
  State<_GeoCalibrationSheet> createState() => _GeoCalibrationSheetState();
}

class _GeoCalibrationSheetState extends State<_GeoCalibrationSheet> {
  late final TextEditingController _latCtl;
  late final TextEditingController _lngCtl;
  String _paper = 'A0';
  int _scale = 100;
  String? _error;

  @override
  void initState() {
    super.initState();
    final c = widget.current;
    _latCtl = TextEditingController(
      text: c == null ? '' : c.originLat.toStringAsFixed(6),
    );
    _lngCtl = TextEditingController(
      text: c == null ? '' : c.originLng.toStringAsFixed(6),
    );
  }

  @override
  void dispose() {
    _latCtl.dispose();
    _lngCtl.dispose();
    super.dispose();
  }

  /// 幅面 + 比例尺 + 底图像素宽 → 米/像素。
  double? get _mpp => metersPerPixelFromScale(
        paperWidthMeters: kPaperWidthMeters[_paper] ?? 1.189,
        scaleDenominator: _scale.toDouble(),
        pixelWidth: widget.pixelWidth,
      );

  /// 本图覆盖的实地宽度（米）：让人一眼看出量级对不对（差 1000 倍时很明显）。
  double? get _coverM => _mpp == null ? null : _mpp! * widget.pixelWidth;

  Future<void> _save() async {
    final lat = double.tryParse(_latCtl.text.trim());
    final lng = double.tryParse(_lngCtl.text.trim());
    if (lat == null || lat < -90 || lat > 90) {
      setState(() => _error = '纬度不合法（应在 -90 ~ 90）');
      return;
    }
    if (lng == null || lng < -180 || lng > 180) {
      setState(() => _error = '经度不合法（应在 -180 ~ 180）');
      return;
    }
    final mpp = _mpp;
    if (mpp == null) {
      setState(() => _error = '比例尺换算失败，请检查底图像素宽是否有效');
      return;
    }
    await widget.library.upsert(GeoCalibration(
      drawingKey: widget.drawingKey,
      drawingVersionId: widget.drawingVersionId,
      originLat: lat,
      originLng: lng,
      metersPerPixel: mpp,
    ));
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _clear() async {
    await widget.library.remove(widget.drawingKey);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      // 键盘弹起时表单仍可滚动，避免小屏被遮挡
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('图纸地理配准',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                '${widget.drawingTitle}｜填「图纸左上角」那一点的真实经纬度，'
                '巡场采集的 GPS 轨迹才能落到图上。',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _latCtl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                      decoration: const InputDecoration(
                        labelText: '纬度（北正）',
                        hintText: '如 22.543210',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _lngCtl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                      decoration: const InputDecoration(
                        labelText: '经度（东正）',
                        hintText: '如 114.057860',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _paper,
                      decoration: const InputDecoration(
                        labelText: '图纸幅面',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final e in kPaperWidthMeters.entries)
                          DropdownMenuItem(
                            value: e.key,
                            child: Text('${e.key}（${e.value} m）'),
                          ),
                      ],
                      onChanged: (v) => setState(() => _paper = v ?? 'A0'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _scale,
                      decoration: const InputDecoration(
                        labelText: '比例尺',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: 50, child: Text('1:50')),
                        DropdownMenuItem(value: 100, child: Text('1:100')),
                        DropdownMenuItem(value: 200, child: Text('1:200')),
                        DropdownMenuItem(value: 500, child: Text('1:500')),
                        DropdownMenuItem(value: 1000, child: Text('1:1000')),
                      ],
                      onChanged: (v) => setState(() => _scale = v ?? 100),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F7FA),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _mpp == null
                      ? '比例尺换算失败'
                      : '米/像素 ≈ ${_mpp!.toStringAsExponential(3)}\n'
                          '本图覆盖实地宽约 ${_coverM!.toStringAsFixed(1)} m'
                          '${_coverM! > 3000 ? '（偏大，请确认比例尺选对）' : ''}',
                  style: const TextStyle(fontSize: 12, height: 1.5),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: const TextStyle(
                        color: Color(0xFFFF4444), fontSize: 12)),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  if (widget.current != null)
                    TextButton(
                      onPressed: _clear,
                      child: const Text('清除配准',
                          style: TextStyle(color: Color(0xFFFF4444))),
                    ),
                  const Spacer(),
                  SizedBox(
                    width: 96,
                    height: 44,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 118,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('保存配准'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
