/// 量尺域模型（D3 量尺会话 + 照片侧标定）。
///
/// 判定口径（贯穿 App 与报告，必须同源）：
/// - 双容差：[MeasureItem.pass]「±mm 且 ±%」同时满足；
/// - 测量不确定度规约：[MeasureItem.canJudge] 误差带 ≤ 容差/3 才允许下结论，
///   否则一律报「需卷尺复核」。
///
/// 门槛值取项目级设置（B7），不硬编码。
/// 后端对应表：`measure_sessions`（`calib` / `items` 以 JSONB 原样落库）。
library;

import 'dart:math' as math;

import '../sync_meta.dart';

/// 拍照量尺校对：一张照片内对某一构件，实测尺寸 vs 图纸标注尺寸的比对。
class ScaleCheck {
  final String name; // 量尺项，如「梁宽」「墙厚」
  final double measuredMm; // 现场量尺实测值（mm）
  final double drawingMm; // 图纸标注值（mm）
  const ScaleCheck({
    required this.name,
    required this.measuredMm,
    required this.drawingMm,
  });

  /// 偏差 = 实测 - 图纸（mm）
  double get deviation => measuredMm - drawingMm;

  /// 偏差率 = 偏差 / 图纸（%）
  double get deviationPct => drawingMm == 0 ? 0 : deviation / drawingMm * 100;

  /// 是否合格：偏差绝对值 <= 容差
  bool pass(double tolMm, double tolPct) =>
      deviation.abs() <= tolMm && deviationPct.abs() <= tolPct;

  ScaleCheck copyWith({String? name, double? measuredMm, double? drawingMm}) =>
      ScaleCheck(
        name: name ?? this.name,
        measuredMm: measuredMm ?? this.measuredMm,
        drawingMm: drawingMm ?? this.drawingMm,
      );
}

// ==================== 半自动标定测量（拍照量尺校对 V2）====================
// 设计见 docs/archive/MEASURE_FEATURE_PLAN.md：图纸侧量距（CAD 校准）+ 照片侧量距（参考物标定）
// + 逐项校对（图纸 mm vs 实测 mm，双容差判定）。

/// 照片侧量距的一次标定：以已知尺寸参考物（卷尺/标准块）标定照片上的像素比例。
/// 存储参考物两端点完整像素坐标（2D），mm/px 用 2D 欧氏距离计算。
class PhotoCalib {
  final double refMm; // 参考物真实尺寸（mm）
  final double ax; // 起点像素 x（整图坐标系，0..imgW）
  final double ay; // 起点像素 y（整图坐标系，0..imgH）
  final double bx; // 终点像素 x
  final double by; // 终点像素 y
  final double imgW; // 照片整图像素宽
  final double imgH; // 照片整图像素高

  /// 平面单应（图像像素 → 被测平面 mm，行主序 9 元素）。
  ///
  /// 由「模数网格 ≥4 点」标定得到：相当于把斜拍画面矫正为正视图后再量距，
  /// 消除两点比例法在斜拍下的透视失真（倾角越大/越远，失真越大）。
  /// null = 未做单应标定，量距回退两点比例法（旧行为，向后兼容旧会话）。
  final List<double>? homography;

  /// 单应标定残差（mm，控制点最大偏差）。
  /// 仅 ≥5 个控制点时才有意义——4 点是精确解，残差恒为 0，不代表精度高。
  final double? homographyResidualMm;

  /// 单应标定的已知网格跨度（mm），仅用于显示（如「600×600 网格 9 点」）。
  final double? calibWidthMm;
  final double? calibHeightMm;

  /// 单应标定所用控制点数（0 = 未做单应标定）。
  final int calibPoints;

  const PhotoCalib({
    required this.refMm,
    required this.ax,
    required this.ay,
    required this.bx,
    required this.by,
    required this.imgW,
    this.imgH = 0,
    this.homography,
    this.homographyResidualMm,
    this.calibWidthMm,
    this.calibHeightMm,
    this.calibPoints = 0,
  });

  /// 是否已做单应（透视校正）标定。
  bool get hasHomography => homography != null && homography!.length == 9;

  /// 参考物像素跨度（2D 欧氏距离，px）。
  double get spanPx => math.sqrt(math.pow(bx - ax, 2) + math.pow(by - ay, 2));

  /// 照片像素比例（mm/px）：参考物尺寸 / 像素跨度（2D）。
  double get mmPerPx => spanPx <= 1e-6 ? 0 : refMm / spanPx;

  PhotoCalib copyWith({
    double? refMm,
    double? ax,
    double? ay,
    double? bx,
    double? by,
    double? imgW,
    double? imgH,
    List<double>? homography,
    double? homographyResidualMm,
    double? calibWidthMm,
    double? calibHeightMm,
    int? calibPoints,
  }) =>
      PhotoCalib(
        refMm: refMm ?? this.refMm,
        ax: ax ?? this.ax,
        ay: ay ?? this.ay,
        bx: bx ?? this.bx,
        by: by ?? this.by,
        imgW: imgW ?? this.imgW,
        imgH: imgH ?? this.imgH,
        homography: homography ?? this.homography,
        homographyResidualMm: homographyResidualMm ?? this.homographyResidualMm,
        calibWidthMm: calibWidthMm ?? this.calibWidthMm,
        calibHeightMm: calibHeightMm ?? this.calibHeightMm,
        calibPoints: calibPoints ?? this.calibPoints,
      );

  /// 新格式序列化。
  Map<String, dynamic> toJson() => {
        'refMm': refMm,
        'ax': ax,
        'ay': ay,
        'bx': bx,
        'by': by,
        'imgW': imgW,
        'imgH': imgH,
        if (homography != null) 'homography': homography,
        if (homographyResidualMm != null) 'hResidualMm': homographyResidualMm,
        if (calibWidthMm != null) 'calibW': calibWidthMm,
        if (calibHeightMm != null) 'calibH': calibHeightMm,
        if (calibPoints > 0) 'calibPts': calibPoints,
      };

  /// 兼容旧格式（仅 {refMm, pixA, pixB, imgW}）：旧数据 ay=by=0，
  /// 退化为水平距离计算，与旧版行为一致，不抛异常。
  factory PhotoCalib.fromJson(Map<String, dynamic> m) {
    final pixA = (m['pixA'] as num?)?.toDouble();
    final pixB = (m['pixB'] as num?)?.toDouble();
    return PhotoCalib(
      refMm: (m['refMm'] as num?)?.toDouble() ?? 0,
      ax: (m['ax'] as num?)?.toDouble() ?? pixA ?? 0,
      ay: (m['ay'] as num?)?.toDouble() ?? 0,
      bx: (m['bx'] as num?)?.toDouble() ?? pixB ?? 0,
      by: (m['by'] as num?)?.toDouble() ?? 0,
      imgW: (m['imgW'] as num?)?.toDouble() ?? 0,
      imgH: (m['imgH'] as num?)?.toDouble() ?? 0,
      homography: _parseHomography(m['homography']),
      homographyResidualMm: (m['hResidualMm'] as num?)?.toDouble(),
      calibWidthMm: (m['calibW'] as num?)?.toDouble(),
      calibHeightMm: (m['calibH'] as num?)?.toDouble(),
      calibPoints: (m['calibPts'] as num?)?.toInt() ?? 0,
    );
  }

  /// 容错解析单应矩阵：非 9 元素 / 含非数值 → 视为未标定（null），不抛异常。
  static List<double>? _parseHomography(dynamic raw) {
    if (raw is! List || raw.length != 9) return null;
    final out = <double>[];
    for (final v in raw) {
      if (v is! num) return null;
      out.add(v.toDouble());
    }
    return out;
  }
}

/// 校对清单中的一项：图纸侧量得值 vs 照片侧量得值。
class MeasureItem {
  final String name; // 量尺项，如「梁宽」「墙厚」
  final double drawingMm; // 图纸侧量得（CAD 校准后，mm）
  final double photoMm; // 照片侧量得（参考物标定后，mm）
  /// 测量来源：'photo' 默认（照片标尺法）| 'ar_lidar'（AR量尺）| 'manual'。
  /// 旧会话数据无该字段时按 'photo' 处理，保证向后兼容。
  final String source;

  /// 测量误差带半宽（±mm）。LiDAR/AR 等有误差来源时填写；
  /// 旧数据 / 手动录入为 null = 误差未知（不参与判定门控，pass() 逻辑不变）。
  final double? errorMm;
  const MeasureItem({
    required this.name,
    required this.drawingMm,
    required this.photoMm,
    this.source = 'photo',
    this.errorMm,
  });

  /// 偏差 = 照片实测 - 图纸（mm）
  double get deviation => photoMm - drawingMm;

  /// 偏差率 = 偏差 / 图纸（%）
  double get deviationPct => drawingMm == 0 ? 0 : deviation / drawingMm * 100;

  /// 是否合格：偏差绝对值 <= 容差
  bool pass(double tolMm, double tolPct) =>
      deviation.abs() <= tolMm && deviationPct.abs() <= tolPct;

  /// 判定可用性（测量不确定度规约）：测量误差带应 ≤ 容差的 1/3，
  /// 否则实测值与容差边界不可分，报"合格/超差"不可信，应提示复核。
  /// 误差未知（null）或误差过大 → 不可判定。
  bool canJudge(double tolMm) =>
      errorMm != null && errorMm! > 0 && errorMm! <= tolMm / 3;

  MeasureItem copyWith(
          {String? name,
          double? drawingMm,
          double? photoMm,
          String? source,
          double? errorMm}) =>
      MeasureItem(
        name: name ?? this.name,
        drawingMm: drawingMm ?? this.drawingMm,
        photoMm: photoMm ?? this.photoMm,
        source: source ?? this.source,
        errorMm: errorMm ?? this.errorMm,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'drawingMm': drawingMm,
        'photoMm': photoMm,
        'source': source,
        if (errorMm != null) 'errorMm': errorMm,
      };

  /// 字段名与 `MeasureSession` 既有内联序列化保持一致（name/drawingMm/photoMm/source），
  /// 新增 `errorMm` 缺省为 null，旧数据不抛异常。
  factory MeasureItem.fromJson(Map<String, dynamic> m) => MeasureItem(
        name: m['name']?.toString() ?? '',
        drawingMm: (m['drawingMm'] as num? ?? 0).toDouble(),
        photoMm: (m['photoMm'] as num? ?? 0).toDouble(),
        source: m['source']?.toString() ?? 'photo',
        errorMm: (m['errorMm'] as num?)?.toDouble(),
      );
}

/// 一次测量会话（可持久化）。
class MeasureSession {
  final String id;
  final String projectKey;
  final String drawingKey;

  /// 所属图纸版本（→ [DrawingVersion.id]）；空串 = 未版本化。
  final String drawingVersionId;
  final String floor;
  final double tolMm; // 容差 mm
  final double tolPct; // 容差 %
  final PhotoCalib? photoCalib; // 照片侧标定（可空）
  final List<MeasureItem> items;
  final int updatedAt; // 毫秒时间戳

  /// 同步元数据（clientId / version / 时间戳 / 软删）。
  final SyncMeta sync;
  const MeasureSession({
    required this.id,
    required this.projectKey,
    required this.drawingKey,
    this.drawingVersionId = '',
    required this.floor,
    this.tolMm = 15,
    this.tolPct = 2,
    this.photoCalib,
    this.items = const [],
    this.updatedAt = 0,
    this.sync = const SyncMeta(),
  });

  MeasureSession copyWith({
    String? projectKey,
    String? drawingKey,
    String? drawingVersionId,
    String? floor,
    double? tolMm,
    double? tolPct,
    PhotoCalib? photoCalib,
    bool clearPhotoCalib = false,
    List<MeasureItem>? items,
    int? updatedAt,
    SyncMeta? sync,
  }) =>
      MeasureSession(
        id: id,
        projectKey: projectKey ?? this.projectKey,
        drawingKey: drawingKey ?? this.drawingKey,
        drawingVersionId: drawingVersionId ?? this.drawingVersionId,
        floor: floor ?? this.floor,
        tolMm: tolMm ?? this.tolMm,
        tolPct: tolPct ?? this.tolPct,
        photoCalib: clearPhotoCalib ? null : (photoCalib ?? this.photoCalib),
        items: items ?? this.items,
        updatedAt: updatedAt ?? this.updatedAt,
        sync: sync ?? this.sync,
      );

  int get passCount => items.where((e) => e.pass(tolMm, tolPct)).length;
  bool get allPass => items.isNotEmpty && passCount == items.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectKey': projectKey,
        'drawingKey': drawingKey,
        'drawingVersionId': drawingVersionId,
        'floor': floor,
        'tolMm': tolMm,
        'tolPct': tolPct,
        'photoCalib': photoCalib?.toJson(),
        'items': items
            .map((e) => {
                  'name': e.name,
                  'drawingMm': e.drawingMm,
                  'photoMm': e.photoMm,
                  'source': e.source,
                  if (e.errorMm != null) 'errorMm': e.errorMm,
                })
            .toList(),
        'updatedAt': updatedAt,
        ...sync.toJson(),
      };

  factory MeasureSession.fromJson(Map<String, dynamic> m) {
    final calib = m['photoCalib'] as Map<String, dynamic>?;
    return MeasureSession(
      id: m['id'] as String? ?? '',
      projectKey: m['projectKey'] as String? ?? '',
      drawingKey: m['drawingKey'] as String? ?? '',
      drawingVersionId: m['drawingVersionId'] as String? ?? '',
      floor: m['floor'] as String? ?? '',
      tolMm: (m['tolMm'] as num? ?? 15).toDouble(),
      tolPct: (m['tolPct'] as num? ?? 2).toDouble(),
      photoCalib: calib == null ? null : PhotoCalib.fromJson(calib),
      items: (m['items'] as List? ?? [])
          .map((e) => (e as Map<String, dynamic>))
          .map((e) => MeasureItem(
                name: e['name'] as String? ?? '',
                drawingMm: (e['drawingMm'] as num? ?? 0).toDouble(),
                photoMm: (e['photoMm'] as num? ?? 0).toDouble(),
                source: e['source'] as String? ?? 'photo', // 旧数据兼容
                errorMm: (e['errorMm'] as num?)?.toDouble(), // 旧数据 null
              ))
          .toList(),
      updatedAt: (m['updatedAt'] as num? ?? 0).toInt(),
      sync: SyncMeta.fromJson(m),
    );
  }
}

/// 拍照量尺校对页路由参数。
class MeasureArgs {
  final String projectKey;
  final String drawingKey;
  final String floor;
  const MeasureArgs({
    required this.projectKey,
    required this.drawingKey,
    this.floor = '',
  });
}

