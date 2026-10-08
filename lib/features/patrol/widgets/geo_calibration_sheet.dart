import 'package:flutter/material.dart';

import '../../../core/cad/geo_calibration.dart';
import '../../../core/utils/geo_calib_solver.dart';
import '../../../core/utils/geo_project.dart';

/// 图纸**地理配准**表单：把现场 GPS 经纬度落到这张图纸的像素上。
///
/// 两种填法：
/// - **自动校准（零输入，推荐先试）**：走完一圈巡场后，用「规划路线 + 本次 GPS
///   轨迹」自动反解出比例与锚点。精度受 GPS 民用精度限制（比例误差 1~4%），
///   适合判断路线走向，**不能用来量尺寸**。
/// - **手工填（更准）**：填图纸左上角的真实经纬度 + 选幅面/比例尺。
///   比例尺来自图纸本身，精度高于自动估算。
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

  /// 自动校准用的规划路线（图纸**像素**坐标）。为空则不显示「自动校准」。
  List<PixelPoint> autoRoute = const [],

  /// 自动校准用的 GPS 轨迹（经纬度，时间顺序）。为空则不显示「自动校准」。
  List<GeoPoint> autoFixes = const [],
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
      autoRoute: autoRoute,
      autoFixes: autoFixes,
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
    this.autoRoute = const [],
    this.autoFixes = const [],
  });

  final GeoCalibrationLibrary library;
  final String drawingKey;
  final String drawingVersionId;
  final double pixelWidth;
  final String drawingTitle;
  final GeoCalibration? current;

  /// 自动校准用的规划路线（图纸像素坐标）与 GPS 轨迹（经纬度）。
  final List<PixelPoint> autoRoute;
  final List<GeoPoint> autoFixes;

  @override
  State<_GeoCalibrationSheet> createState() => _GeoCalibrationSheetState();
}

class _GeoCalibrationSheetState extends State<_GeoCalibrationSheet> {
  late final TextEditingController _latCtl;
  late final TextEditingController _lngCtl;
  String _paper = 'A0';
  int _scale = 100;
  String? _error;

  /// 自动校准的解算结果（非空 = 已算出，可一键采用）。
  GeoCalibSolution? _auto;

  /// 自动校准的失败原因（数据不足 / 残差过大）。
  String? _autoHint;

  /// 由规划路线 + GPS 轨迹反解配准。
  ///
  /// 精度受 GPS 民用精度限制，比例误差通常 1~4%；残差超过 8m 视为不可信，
  /// 提示改用手工填（比例尺来自图纸，更准）。
  void _runAuto() {
    final sol = solveGeoCalibrationFromRoute(
      route: widget.autoRoute,
      fixes: widget.autoFixes,
    );
    if (sol == null) {
      setState(() {
        _auto = null;
        _autoHint = '自动校准失败：轨迹点太少，或路线/GPS 几乎没有位移'
            '（请走完一圈、路线不要太短）';
      });
      return;
    }
    if (!sol.reliable) {
      setState(() {
        _auto = null;
        _autoHint = '自动校准可信度不足'
            '（匹配 ${sol.matched} 点 / 残差 ${sol.residualM.toStringAsFixed(1)}m）'
            '，建议改用下方手工填';
      });
      return;
    }
    setState(() {
      _auto = sol;
      _autoHint = null;
      // 把解算值回填进表单，让用户能直接看到并微调
      _latCtl.text = sol.originLat.toStringAsFixed(6);
      _lngCtl.text = sol.originLng.toStringAsFixed(6);
    });
  }

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
              // —— 自动校准（零输入）：走完一圈后由规划路线 + GPS 轨迹反解 ——
              if (widget.autoRoute.length >= 3 && widget.autoFixes.length >= 3)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _auto == null ? const Color(0xFFEFF6FF) : const Color(0xFFEAF7EE),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text('自动校准（推荐先试）',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600)),
                          ),
                          if (_auto == null)
                            TextButton(
                              onPressed: _runAuto,
                              child: const Text('一键反解'),
                            )
                          else
                            TextButton(
                              onPressed: _runAuto,
                              child: const Text('重新反解'),
                            ),
                        ],
                      ),
                      if (_auto == null && _autoHint == null)
                        const Text(
                          '用本次巡场的「规划路线 + GPS 轨迹」自动算出比例与锚点，'
                          '无需手填。精度受 GPS 影响（比例误差约 1~4%）。',
                          style: TextStyle(fontSize: 11, height: 1.4, color: Colors.black54),
                        ),
                      if (_auto != null)
                        Text(
                          '已反解：米/像素 ≈ ${_auto!.metersPerPixel.toStringAsExponential(3)}，'
                          '匹配 ${_auto!.matched} 点，残差 ${_auto!.residualM.toStringAsFixed(1)}m。'
                          '已回填到下方，可直接保存或微调。',
                          style: const TextStyle(fontSize: 11, height: 1.4),
                        ),
                      if (_autoHint != null)
                        Text(_autoHint!,
                            style: const TextStyle(
                                fontSize: 11, height: 1.4, color: Color(0xFFB26A00))),
                    ],
                  ),
                ),
              if (widget.autoRoute.length >= 3 && widget.autoFixes.length >= 3)
                const SizedBox(height: 14),
              const Text('手工填写（或用上方自动校准结果）',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 10),
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
