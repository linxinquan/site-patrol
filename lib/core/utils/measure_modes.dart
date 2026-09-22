/// 面积 / 体积模式：由已测线性尺寸组合出面积、体积（参考量尺宝的做法）。
///
/// 为什么用"组合已测边"而不是"AR 直接框选面/体"：
/// 1. 面域/体域的**直接测量**依赖原生平面检测与平面填充（须改 `ArMeasureView.swift`，
///    当前环境无法编译验证），而组合法只需已有点到点的读数，**今天就能用**；
/// 2. 工程上量开间/进深本来就是两次量边，再乘出面积——与现场做法一致；
/// 3. 精度可追责：面积误差由各边的误差带**合成**给出，不是凭空给一个数。
///
/// 误差传递规则：各因子**相对误差线性相加**（保守）。
/// 不用平方和：各边同源（同一标定、同一台设备），误差是相关的，
/// 平方和会系统性低估。
library;

import 'dart:math' as math;

import '../../data/models.dart';
import 'mm_format.dart';

/// 面积（㎡）+ 误差带（㎡）：由两条线性边相乘。
/// 任一边非正、或单位不是 mm → 返回 null（调用方提示不可算）。
({double value, double err})? computeArea(MeasureItem a, MeasureItem b) {
  if (a.unit != 'mm' || b.unit != 'mm') return null;
  if (a.photoMm <= 0 || b.photoMm <= 0) return null;
  final m2 = a.photoMm * b.photoMm / 1e6;
  final rel = _rel(a) + _rel(b);
  return (value: m2, err: m2 * rel);
}

/// 体积（m³）+ 误差带（m³）：由三条线性边相乘。
({double value, double err})? computeVolume(
    MeasureItem a, MeasureItem b, MeasureItem c) {
  if (a.unit != 'mm' || b.unit != 'mm' || c.unit != 'mm') return null;
  if (a.photoMm <= 0 || b.photoMm <= 0 || c.photoMm <= 0) return null;
  final m3 = a.photoMm * b.photoMm * c.photoMm / 1e9;
  final rel = _rel(a) + _rel(b) + _rel(c);
  return (value: m3, err: m3 * rel);
}

/// 单边相对误差：无误差带时取 0.5%（AI/标定估计的保守下限）。
double _rel(MeasureItem e) =>
    e.photoMm <= 0 ? 0 : (e.errorMm ?? e.photoMm * 0.005) / e.photoMm;

/// 面积/体积的因子说明，如 `3200 × 4100 mm`（写进记录名与报告备注）。
String factorsText(List<MeasureItem> items) =>
    '${items.map((e) => fmtMm(e.photoMm)).join(' × ')} mm';

/// 构造可入清单的面积/体积记录。
///
/// `drawingMm` 固定为 0：面积/体积**不参与"合格/超差"判定**
/// （没有"图纸面积"对照口径），文案层会显示「未判定」。
MeasureItem buildCalcItem({
  required List<MeasureItem> factors,
  required double value,
  required double err,
  required bool isVolume,
}) {
  final value2 = double.parse(value.toStringAsFixed(2));
  return MeasureItem(
    name: '${isVolume ? '体积' : '面积'} ${value2.toStringAsFixed(2)} '
        '${isVolume ? 'm³' : '㎡'}（${factorsText(factors)}）',
    drawingMm: 0,
    photoMm: value,
    source: 'calc',
    errorMm: err,
    unit: isVolume ? 'm3' : 'm2',
  );
}

/// 面积显示文案：`12.50 ㎡`。
String fmtArea(double m2) => '${m2.toStringAsFixed(2)} ㎡';

/// 体积显示文案：`31.20 m³`。
String fmtVolume(double m3) => '${m3.toStringAsFixed(2)} m³';

/// 面积/体积是否在"合理量级"内（用于挡住明显点错造成的荒谬结果）。
///
/// 经验上限：单房间面积 ≤ 2000 ㎡、体积 ≤ 20000 m³（远超任何民用房间）；
/// 下限：面积 ≥ 0.01 ㎡、体积 ≥ 0.01 m³（避免出现 0.00 的假结果）。
bool plausibleArea(double m2) => m2 >= 0.01 && m2 <= 2000;
bool plausibleVolume(double m3) => m3 >= 0.01 && m3 <= 20000;

/// 因子数量要求：面积 2 条边、体积 3 条边。
int requiredFactors({required bool isVolume}) => isVolume ? 3 : 2;

/// 组合合法性：边数够、都是线性尺寸、都为正。
bool canCombine(List<MeasureItem> factors, {required bool isVolume}) {
  if (factors.length != requiredFactors(isVolume: isVolume)) return false;
  for (final f in factors) {
    if (f.unit != 'mm' || f.photoMm <= 0) return false;
  }
  return true;
}

/// 组合计算（面积/体积统一入口）；不满足条件或量级异常返回 null。
({double value, double err})? combine(
  List<MeasureItem> factors, {
  required bool isVolume,
}) {
  if (!canCombine(factors, isVolume: isVolume)) return null;
  final r = isVolume
      ? computeVolume(factors[0], factors[1], factors[2])
      : computeArea(factors[0], factors[1]);
  if (r == null) return null;
  final ok = isVolume ? plausibleVolume(r.value) : plausibleArea(r.value);
  if (!ok) return null;
  return r;
}

/// 组合结果的显示文案：`面积 12.50 ㎡ ±0.13`。
String combineLabel(
  ({double value, double err}) r, {
  required bool isVolume,
}) {
  final v = isVolume ? fmtVolume(r.value) : fmtArea(r.value);
  final e = isVolume ? fmtVolume(r.err) : fmtArea(r.err);
  return '${isVolume ? '体积' : '面积'} $v ±${e.split(' ').first}';
}

/// 供界面显示的误差带（与主值同单位、2 位小数）。
String combineErrText(({double value, double err}) r) =>
    r.err.toStringAsFixed(2);

/// 从候选里挑默认组合（按读数从大到小），用于"推荐三个最大的面"这类快捷选择。
List<MeasureItem> suggestFactors(
  List<MeasureItem> candidates, {
  required bool isVolume,
}) {
  final linear = [
    for (final c in candidates)
      if (c.unit == 'mm' && c.photoMm > 0) c,
  ]..sort((a, b) => b.photoMm.compareTo(a.photoMm));
  final n = requiredFactors(isVolume: isVolume);
  return linear.length >= n ? linear.sublist(0, math.min(n, linear.length)) : linear;
}

/// AR 量尺的**几何模式**：直线 / 面积 / 体积（对应参考样张的三个功能页）。
///
/// 与 `ArMeasureMode`（斜边/水平/高差，决定"取哪一个值"）是正交的两件事：
/// 前者决定"量出来干什么"，后者决定"读数怎么分解"。
enum ArGeometryMode {
  line('直线', 1),
  area('面积', 2),
  volume('体积', 3);

  const ArGeometryMode(this.label, this.edgeCount);

  final String label;

  /// 该模式需要量几条边（直线 1、面积 2、体积 3）。
  final int edgeCount;

  bool get isVolume => this == ArGeometryMode.volume;

  bool get isFace => this != ArGeometryMode.line;
}

/// 面积/体积模式下每条边的工程叫法（与参考样张的 4.000m / 2.000m / 1.000m 对应）。
const List<String> kAreaEdgeLabels = ['长', '宽'];
const List<String> kVolumeEdgeLabels = ['长', '宽', '高'];

List<String> edgeLabels({required bool isVolume}) =>
    isVolume ? kVolumeEdgeLabels : kAreaEdgeLabels;

/// 面积/体积模式的**连续测量累加器**。
///
/// 为什么要有它：参考样张的模式是「选面积 → 连着量长、宽 → 自动出面域」，
/// 用户不该每量一条边就去弹层里手动挑边。这里把"逐条吃进边长 → 够数即产出"
/// 做成纯逻辑，UI 只负责显示进度与把结果落到清单，便于单测钉住行为。
class FaceBuilder {
  FaceBuilder({required this.isVolume});

  final bool isVolume;

  final List<MeasureItem> _edges = [];

  /// 已吃进的边（顺序即 长/宽[/高]）。
  List<MeasureItem> get edges => List.unmodifiable(_edges);

  int get need => requiredFactors(isVolume: isVolume);
  int get got => _edges.length;
  bool get full => _edges.length >= need;

  /// 当前待量的那条边的叫法（已满时返回最后一条）。
  String get currentLabel => edgeLabels(isVolume: isVolume)
      [got >= need ? need - 1 : got];

  /// 吃进一条边。
  ///
  /// 返回：凑满所需边数时给出**可直接入清单**的面积/体积项及其因子边；
  /// 未满返回 null。量级异常（明显点错）时也返回 null，但会清空已积累的边，
  /// 避免脏数据继续叠加出更离谱的结果。
  ({MeasureItem item, List<MeasureItem> factors})? add(MeasureItem edge) {
    _edges.add(edge);
    if (!full) return null;
    final r = combine(_edges, isVolume: isVolume);
    final factors = List<MeasureItem>.of(_edges);
    _edges.clear();
    if (r == null) return null;
    return (
      item: buildCalcItem(
        factors: factors,
        value: r.value,
        err: r.err,
        isVolume: isVolume,
      ),
      factors: factors,
    );
  }

  void reset() => _edges.clear();

  /// 进度文案：`长 1.400m ✓ · 宽 待测`（文案用 m/3 位小数，与图上标注同口径）。
  String progressText() {
    final labels = edgeLabels(isVolume: isVolume);
    final parts = <String>[];
    for (var i = 0; i < need; i++) {
      if (i < _edges.length) {
        parts.add('${labels[i]} ${(_edges[i].photoMm / 1000).toStringAsFixed(3)}m ✓');
      } else {
        parts.add('${labels[i]} 待测');
      }
    }
    return parts.join(' · ');
  }
}
