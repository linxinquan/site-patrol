import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 数据模型（mock 阶段用纯 Dart 类；接真实 API 时再补 freezed / json_serializable）。

enum DefectStatus { draft, doing, done, reject }

extension DefectStatusX on DefectStatus {
  String get label {
    switch (this) {
      case DefectStatus.draft:
        return '待整改';
      case DefectStatus.doing:
        return '整改中';
      case DefectStatus.done:
        return '已销项';
      case DefectStatus.reject:
        return '已拒绝';
    }
  }

  Color get color {
    switch (this) {
      case DefectStatus.draft:
        return const Color(0xFFDC2626);
      case DefectStatus.doing:
        return const Color(0xFFEA580C);
      case DefectStatus.done:
        return const Color(0xFF16A34A);
      case DefectStatus.reject:
        return const Color(0xFF64748B);
    }
  }

  Color get soft {
    switch (this) {
      case DefectStatus.draft:
        return const Color(0xFFFEE2E2);
      case DefectStatus.doing:
        return const Color(0xFFFFEDD5);
      case DefectStatus.done:
        return const Color(0xFFDCFCE7);
      case DefectStatus.reject:
        return const Color(0xFFF1F5F9);
    }
  }
}

/// 缺陷专业分类（7 类）。
enum DefectCategory { architecture, structure, decoration, water, hvac, electric, other }

extension DefectCategoryX on DefectCategory {
  String get label {
    switch (this) {
      case DefectCategory.architecture:
        return '建筑';
      case DefectCategory.structure:
        return '结构';
      case DefectCategory.decoration:
        return '装饰';
      case DefectCategory.water:
        return '给排水';
      case DefectCategory.hvac:
        return '暖通';
      case DefectCategory.electric:
        return '电气';
      case DefectCategory.other:
        return '其他';
    }
  }
}

/// 缺陷紧急/重要程度分级（红/橙/黄/绿 四通道）。
/// 参考《施工阶段紧急重要程度分级》：红区=重要且紧急(停工+上报)、
/// 橙区=重要不紧急(限期整改)、黄区=紧急不重要(即改)、绿区=不重要不紧急(观察)。
enum DefectSeverity { red, orange, yellow, green }

extension DefectSeverityX on DefectSeverity {
  String get label {
    switch (this) {
      case DefectSeverity.red:
        return '红区';
      case DefectSeverity.orange:
        return '橙区';
      case DefectSeverity.yellow:
        return '黄区';
      case DefectSeverity.green:
        return '绿区';
    }
  }

  /// 处置动作（与分级框架对应）。
  String get action {
    switch (this) {
      case DefectSeverity.red:
        return '停工上报';
      case DefectSeverity.orange:
        return '限期整改';
      case DefectSeverity.yellow:
        return '即查即改';
      case DefectSeverity.green:
        return '常规观察';
    }
  }

  Color get color {
    switch (this) {
      case DefectSeverity.red:
        return const Color(0xFFDC2626); // 红
      case DefectSeverity.orange:
        return const Color(0xFFEA580C); // 橙
      case DefectSeverity.yellow:
        return const Color(0xFFCA8A04); // 黄
      case DefectSeverity.green:
        return const Color(0xFF16A34A); // 绿
    }
  }

  /// 软底色（用于徽标/卡片背景）。
  Color get soft {
    switch (this) {
      case DefectSeverity.red:
        return const Color(0xFFFEE2E2);
      case DefectSeverity.orange:
        return const Color(0xFFFFEDD5);
      case DefectSeverity.yellow:
        return const Color(0xFFFEF3C7);
      case DefectSeverity.green:
        return const Color(0xFFDCFCE7);
    }
  }
}

/// 项目参与方（甲方 / 设计院 / 监理 / 咨询 / PMO 等）。
class Party {
  final String role; // 角色，如 "甲方（业主方）"、"设计院（LDI）" 等
  final String org; // 单位全称，如 "腾讯科技（深圳）有限公司"
  final String contact; // 代表/对接人，如 "林心荃"
  final String title; // 代表职务，如 "业主代表"
  const Party({
    required this.role,
    required this.org,
    required this.contact,
    required this.title,
  });
}

/// 系统用户（参与方代表）。头像点击可切换当前用户。
class User {
  final String id;
  final String name; // 姓名，如 "欧阳嘉"
  final String org; // 单位，如 "Arcadis（凯迪思）"
  final String role; // 角色，如 "全过程咨询 / PMO"
  final String avatar; // assets 头像路径
  const User({
    required this.id,
    required this.name,
    required this.org,
    required this.role,
    required this.avatar,
  });
}

/// 项目施工进度节点（关键里程碑）。
/// 用户后续会提供真实进度资料替换 mock 数据。
class Milestone {
  final String name; // 节点名称，如 "主体结构封顶"
  final String date; // 计划/完成日期，如 "2026-05-30"
  final bool done; // 是否已完成
  final bool current; // 是否为当前进行中的节点（高亮）
  const Milestone({
    required this.name,
    required this.date,
    this.done = false,
    this.current = false,
  });
}

class Project {
  final String id; // 项目唯一标识（多项目切换用）
  final String name;
  final String client;
  final String location;
  final String status;
  final String siteArea;
  final String floorArea;
  final int beds;
  final String concept;
  /// 参与方列表（甲方 / 设计院 / 监理 / 咨询 / PMO）。
  final List<Party> parties;
  /// 施工进度里程碑（项目时间轴数据源）。
  final List<Milestone> milestones;
  const Project({
    required this.id,
    required this.name,
    required this.client,
    required this.location,
    required this.status,
    required this.siteArea,
    required this.floorArea,
    required this.beds,
    required this.concept,
    this.parties = const [],
    this.milestones = const [],
  });
}

/// 附近定位点（工程水印相机风格）：项目 / 地标 + 地址 + GPS + 海拔。
/// 用户在拍照前可从附近定位点列表中选择一个作为水印定位信息。
class SiteLocation {
  final String id;
  /// 地点名称（如项目名 / 工地名）。
  final String name;
  /// 详细地址。
  final String address;
  /// 纬度（°N）。
  final double lat;
  /// 经度（°E）。
  final double lng;
  /// 海拔（m）。
  final double altitude;
  /// 关联项目 id（可空）。
  final String? projectId;
  const SiteLocation({
    required this.id,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.altitude,
    this.projectId,
  });

  /// 水印显示用的 GPS 文本（与 CAD/天气模块纬度在前一致）。
  String get gpsText =>
      '${lat.toStringAsFixed(4)}°N ${lng.toStringAsFixed(4)}°E';

  /// 与另一个定位点的粗略距离（km，球面余弦）。用于"附近"排序/提示。
  double distanceKmTo(SiteLocation other) {
    const r = 6371.0;
    final dLat = (other.lat - lat) * 3.141592653589793 / 180;
    final dLng = (other.lng - lng) * 3.141592653589793 / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat * 3.141592653589793 / 180) *
            math.cos(other.lat * 3.141592653589793 / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(a));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'address': address,
        'lat': lat,
        'lng': lng,
        'altitude': altitude,
        'projectId': projectId,
      };

  factory SiteLocation.fromJson(Map<String, dynamic> j) => SiteLocation(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        address: j['address'] as String? ?? '',
        lat: (j['lat'] as num?)?.toDouble() ?? 0,
        lng: (j['lng'] as num?)?.toDouble() ?? 0,
        altitude: (j['altitude'] as num?)?.toDouble() ?? 0,
        projectId: j['projectId'] as String?,
      );
}

class Floor {
  final String key;
  final String name;
  final int index;
  final bool cached;
  final int progress;
  final String building;
  final String floor;
  const Floor({
    required this.key,
    required this.name,
    required this.index,
    required this.cached,
    required this.progress,
    required this.building,
    required this.floor,
  });
}

class Hotspot {
  final int num;
  final String label;
  final String target;
  final double x; // 0~1 相对坐标
  final double y; // 0~1 相对坐标
  const Hotspot({
    required this.num,
    required this.label,
    required this.target,
    required this.x,
    required this.y,
  });
}

class Drawing {
  final String key;
  final String title;
  final String crumb;
  final String variant;
  final String src; // assets 路径（PNG 图）
  final double w;
  final double h;
  final List<Hotspot> hotspots;
  /// 若为 CAD/OCF 图纸，标记对应 OCF 缓存 key（如 `dy04_7_B01`）。
  /// 非空时图纸查看页走 CAD 渲染/占位逻辑，而非 Image.asset。
  final String? cadOcfKey;
  const Drawing({
    required this.key,
    required this.title,
    required this.crumb,
    required this.variant,
    required this.src,
    required this.w,
    required this.h,
    required this.hotspots,
    this.cadOcfKey,
  });
}

class AnchorPhoto {
  final String file;
  final String date;
  final String caption;
  const AnchorPhoto({
    required this.file,
    required this.date,
    required this.caption,
  });
}

class PhotoAnchor {
  final String id;
  final double x;
  final double y;
  final String label;
  final String? labelPos;
  final List<AnchorPhoto> photos;
  const PhotoAnchor({
    required this.id,
    required this.x,
    required this.y,
    required this.label,
    this.labelPos,
    required this.photos,
  });
}

class Defect {
  final String id;
  final String part;
  final String type;
  /// 专业分类（建筑/结构/装饰/给排水/暖通/电气/其他）。
  final DefectCategory category;
  /// 紧急/重要程度（红/橙/黄/绿）。
  final DefectSeverity severity;
  final DefectStatus status;
  final String anchor;
  final String floor;
  final String ts;
  final String gps;
  final String alt;
  /// 责任人（责任单位 + 人），如 "深圳市建工集团 王工"。
  final String resp;
  /// 责任单位（拆分字段，便于单独展示）。
  final String respUnit;
  /// 记录人（谁发现/记录的）。
  final String reporter;
  /// 附加标签（自由标签，如 "二次结构"、"防火重点"、"总包责任"）。
  final List<String> tags;
  final String note;
  final String seed;
  /// 所属图纸 key（CAD 打点来源，可为空）。
  final String? drawingKey;
  /// 图纸坐标 X（mm，CAD 打点换算，用于图纸上回溯定位）。
  final double? worldX;
  /// 图纸坐标 Y（mm，CAD 打点换算，用于图纸上回溯定位）。
  final double? worldY;
  /// 照片 SHA-256 指纹（防篡改留痕：水印照片字节哈希，与原始记录比对）。
  final String? photoHash;
  /// 水印凭证号（拍摄流水，唯一）。
  final String? watermarkSerial;
  const Defect({
    required this.id,
    required this.part,
    required this.type,
    required this.category,
    required this.severity,
    required this.status,
    required this.anchor,
    required this.floor,
    required this.ts,
    required this.gps,
    required this.alt,
    required this.resp,
    this.respUnit = '',
    this.reporter = '现场记录',
    this.tags = const [],
    required this.note,
    required this.seed,
    this.drawingKey,
    this.worldX,
    this.worldY,
    this.photoHash,
    this.watermarkSerial,
  });

  /// 是否有 CAD 图纸坐标（可回溯定位）。
  bool get hasCadCoord => drawingKey != null && worldX != null && worldY != null;

  /// CAD 坐标文本（"X=… Y=…"），无坐标时返回 null。
  String? get coordText =>
      hasCadCoord ? 'X=${worldX!.toStringAsFixed(1)}  Y=${worldY!.toStringAsFixed(1)}' : null;
}

class TimelinePhoto {
  final String date;
  final String state; // before / mid / after
  final String caption;
  final bool verified;
  const TimelinePhoto({
    required this.date,
    required this.state,
    required this.caption,
    required this.verified,
  });
}

/// 拍照验收路由参数：楼层 + 预锚定部位 + 相对坐标（0~1） + 可选图纸坐标。
class CaptureArgs {
  /// 所属项目 ID（无项目时按 currentProjectIdProvider 推断）。
  final String? projectId;
  final String floor;
  final String anchorLabel;
  final double x;
  final double y;
  /// 若从图纸打点跳转：关联的图纸 key；拍照记录时一并写入缺陷
  /// （真实坐标由 drawPointWorldX/drawPointWorldY 提供）。
  final String? drawingKey;
  final double? drawPointWorldX;
  final double? drawPointWorldY;
  const CaptureArgs({
    this.projectId,
    this.floor = '',
    this.anchorLabel = '',
    this.x = 0.5,
    this.y = 0.5,
    this.drawingKey,
    this.drawPointWorldX,
    this.drawPointWorldY,
  });
}

/// VL 识别的缺陷结果。
class VlDefect {
  final String name;
  final DefectSeverity severity;
  final double conf;
  /// 缺陷描述（真实模型返回；mock 阶段为空）。
  final String? desc;
  const VlDefect({
    required this.name,
    required this.severity,
    required this.conf,
    this.desc,
  });
}

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
// 设计见 MEASURE_FEATURE_PLAN.md：图纸侧量距（CAD 校准）+ 照片侧量距（参考物标定）
// + 逐项校对（图纸 mm vs 实测 mm，双容差判定）。

/// 照片侧量距的一次标定：以已知尺寸参考物（卷尺/标准块）标定照片上的像素比例。
class PhotoCalib {
  final double refMm; // 参考物真实尺寸（mm）
  final double pixA; // 起点像素 x（0..imgW）
  final double pixB; // 终点像素 x（0..imgW）
  final double imgW; // 照片整图像素宽
  const PhotoCalib({
    required this.refMm,
    required this.pixA,
    required this.pixB,
    required this.imgW,
  });

  /// 照片像素比例（mm/px）：参考物尺寸 / 像素跨度。
  double get mmPerPx => refMm / (pixB - pixA).abs();

  PhotoCalib copyWith({double? refMm, double? pixA, double? pixB, double? imgW}) =>
      PhotoCalib(
        refMm: refMm ?? this.refMm,
        pixA: pixA ?? this.pixA,
        pixB: pixB ?? this.pixB,
        imgW: imgW ?? this.imgW,
      );
}

/// 校对清单中的一项：图纸侧量得值 vs 照片侧量得值。
class MeasureItem {
  final String name; // 量尺项，如「梁宽」「墙厚」
  final double drawingMm; // 图纸侧量得（CAD 校准后，mm）
  final double photoMm; // 照片侧量得（参考物标定后，mm）
  const MeasureItem({
    required this.name,
    required this.drawingMm,
    required this.photoMm,
  });

  /// 偏差 = 照片实测 - 图纸（mm）
  double get deviation => photoMm - drawingMm;
  /// 偏差率 = 偏差 / 图纸（%）
  double get deviationPct => drawingMm == 0 ? 0 : deviation / drawingMm * 100;
  /// 是否合格：偏差绝对值 <= 容差
  bool pass(double tolMm, double tolPct) =>
      deviation.abs() <= tolMm && deviationPct.abs() <= tolPct;

  MeasureItem copyWith({String? name, double? drawingMm, double? photoMm}) =>
      MeasureItem(
        name: name ?? this.name,
        drawingMm: drawingMm ?? this.drawingMm,
        photoMm: photoMm ?? this.photoMm,
      );
}

/// 一次测量会话（可持久化）。
class MeasureSession {
  final String id;
  final String projectKey;
  final String drawingKey;
  final String floor;
  final double tolMm; // 容差 mm
  final double tolPct; // 容差 %
  final PhotoCalib? photoCalib; // 照片侧标定（可空）
  final List<MeasureItem> items;
  final int updatedAt; // 毫秒时间戳
  const MeasureSession({
    required this.id,
    required this.projectKey,
    required this.drawingKey,
    required this.floor,
    this.tolMm = 5,
    this.tolPct = 2,
    this.photoCalib,
    this.items = const [],
    this.updatedAt = 0,
  });

  MeasureSession copyWith({
    String? projectKey,
    String? drawingKey,
    String? floor,
    double? tolMm,
    double? tolPct,
    PhotoCalib? photoCalib,
    bool clearPhotoCalib = false,
    List<MeasureItem>? items,
    int? updatedAt,
  }) =>
      MeasureSession(
        id: id,
        projectKey: projectKey ?? this.projectKey,
        drawingKey: drawingKey ?? this.drawingKey,
        floor: floor ?? this.floor,
        tolMm: tolMm ?? this.tolMm,
        tolPct: tolPct ?? this.tolPct,
        photoCalib: clearPhotoCalib ? null : (photoCalib ?? this.photoCalib),
        items: items ?? this.items,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  int get passCount => items.where((e) => e.pass(tolMm, tolPct)).length;
  bool get allPass => items.isNotEmpty && passCount == items.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectKey': projectKey,
        'drawingKey': drawingKey,
        'floor': floor,
        'tolMm': tolMm,
        'tolPct': tolPct,
        'photoCalib': photoCalib == null
            ? null
            : {
                'refMm': photoCalib!.refMm,
                'pixA': photoCalib!.pixA,
                'pixB': photoCalib!.pixB,
                'imgW': photoCalib!.imgW,
              },
        'items': items
            .map((e) => {
                  'name': e.name,
                  'drawingMm': e.drawingMm,
                  'photoMm': e.photoMm,
                })
            .toList(),
        'updatedAt': updatedAt,
      };

  factory MeasureSession.fromJson(Map<String, dynamic> m) {
    final calib = m['photoCalib'] as Map<String, dynamic>?;
    return MeasureSession(
      id: m['id'] as String? ?? '',
      projectKey: m['projectKey'] as String? ?? '',
      drawingKey: m['drawingKey'] as String? ?? '',
      floor: m['floor'] as String? ?? '',
      tolMm: (m['tolMm'] as num? ?? 5).toDouble(),
      tolPct: (m['tolPct'] as num? ?? 2).toDouble(),
      photoCalib: calib == null
          ? null
          : PhotoCalib(
              refMm: (calib['refMm'] as num).toDouble(),
              pixA: (calib['pixA'] as num).toDouble(),
              pixB: (calib['pixB'] as num).toDouble(),
              imgW: (calib['imgW'] as num).toDouble(),
            ),
      items: (m['items'] as List? ?? [])
          .map((e) => (e as Map<String, dynamic>))
          .map((e) => MeasureItem(
                name: e['name'] as String? ?? '',
                drawingMm: (e['drawingMm'] as num? ?? 0).toDouble(),
                photoMm: (e['photoMm'] as num? ?? 0).toDouble(),
              ))
          .toList(),
      updatedAt: (m['updatedAt'] as num? ?? 0).toInt(),
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

// ==================== 浩辰云图 CAD 模型 ====================

/// 图层状态信息（来自 getDwgInfo 返回的 layers）。
class CadLayer {
  final String name;
  final bool isOff;
  final bool isFrozen;
  final bool isLock;
  const CadLayer({
    required this.name,
    required this.isOff,
    required this.isFrozen,
    required this.isLock,
  });

  factory CadLayer.fromJson(dynamic v) {
    if (v is String) return CadLayer(name: v, isOff: false, isFrozen: false, isLock: false);
    final j = (v as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    return CadLayer(
      name: j['name']?.toString() ?? '',
      isOff: j['isoff'] == true || j['isOff'] == true,
      isFrozen: j['isfrozen'] == true || j['isFrozen'] == true,
      isLock: j['islock'] == true || j['isLock'] == true,
    );
  }
}

/// 布局信息（模型空间 / 布局 1/2...）。
/// 浩辰返回两种形态：字符串，或 Map（{globalName, handle, nickName} / {name}）。
class CadLayout {
  final String name;
  /// 布局句柄（用于前端切换布局定位）。
  final String? handle;
  const CadLayout({required this.name, this.handle});

  factory CadLayout.fromJson(dynamic v) {
    if (v is String) return CadLayout(name: v);
    if (v is Map<String, dynamic>) {
      return CadLayout(
        name: (v['nickName']?.toString() ??
                v['globalName']?.toString() ??
                v['name']?.toString() ??
                '')
            .trim(),
        handle: v['handle']?.toString(),
      );
    }
    return const CadLayout(name: '');
  }
}

/// DWG 图纸解析结果（getDwgInfo + getTaskStatus 合并）。
class DwgInfo {
  final String requestId;
  final String taskType;
  final int status; // 0 未开始 / 1 执行中 / 2 已完成
  final int resultCode; // 0 成功
  final String? resultMsg;
  final String? deflayout;
  final List<CadLayer> layers;
  final List<CadLayout> layouts;
  final List<String> blocks;
  final List<String> xrefs;
  final String? error;

  const DwgInfo({
    required this.requestId,
    required this.taskType,
    required this.status,
    required this.resultCode,
    this.resultMsg,
    this.deflayout,
    this.layers = const [],
    this.layouts = const [],
    this.blocks = const [],
    this.xrefs = const [],
    this.error,
  });

  bool get isDone => status == 2;
  bool get isOk => isDone && resultCode == 0;

  factory DwgInfo.fromJson(Map<String, dynamic> j) {
    final biz = j['bizData'] as Map<String, dynamic>?;
    return DwgInfo(
      requestId: biz?['requestId']?.toString() ?? '',
      taskType: biz?['taskType']?.toString() ?? '',
      status: (biz?['status'] as num?)?.toInt() ?? 0,
      resultCode: (biz?['resultCode'] as num?)?.toInt() ?? -1,
      resultMsg: biz?['resultMsg']?.toString(),
      deflayout: biz?['deflayout']?.toString(),
      layers: ((biz?['layers'] as List?) ?? []).map(CadLayer.fromJson).toList(),
      layouts: ((biz?['layouts'] as List?) ?? []).map(CadLayout.fromJson).toList(),
      blocks: ((biz?['blocks'] as List?) ?? []).map((e) => e.toString()).toList(),
      xrefs: ((biz?['xrefs'] as List?) ?? []).map((e) => e.toString()).toList(),
      error: j['msg']?.toString(),
    );
  }
}

/// 图纸坐标标注（巡场精度标注）。
/// 用真实 CAD 图纸坐标（mm）记录缺陷位置，配合 CadCoordMapper 实现屏幕坐标自动换算。
class CadAnnotation {
  final String id;
  /// 所属图纸 key。
  final String drawingKey;
  /// 缺陷/标注名称。
  final String label;
  /// 图纸坐标（mm）。
  final double worldX;
  final double worldY;
  /// 屏幕相对坐标（0~1，便于无坐标系时的兜底定位）。
  final double relX;
  final double relY;
  final DateTime createdAt;
  const CadAnnotation({
    required this.id,
    required this.drawingKey,
    required this.label,
    required this.worldX,
    required this.worldY,
    required this.relX,
    required this.relY,
    required this.createdAt,
  });

  String get coordText =>
      'X=${worldX.toStringAsFixed(2)}  Y=${worldY.toStringAsFixed(2)}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'drawingKey': drawingKey,
        'label': label,
        'worldX': worldX,
        'worldY': worldY,
        'relX': relX,
        'relY': relY,
        'createdAt': createdAt.toIso8601String(),
      };

  factory CadAnnotation.fromJson(Map<String, dynamic> j) => CadAnnotation(
        id: j['id']?.toString() ?? '',
        drawingKey: j['drawingKey']?.toString() ?? '',
        label: j['label']?.toString() ?? '',
        worldX: (j['worldX'] as num?)?.toDouble() ?? 0,
        worldY: (j['worldY'] as num?)?.toDouble() ?? 0,
        relX: (j['relX'] as num?)?.toDouble() ?? 0,
        relY: (j['relY'] as num?)?.toDouble() ?? 0,
        createdAt:
            DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
      );
}

/// 异步任务查询结果。
class CadTaskStatus {
  final String requestId;
  final String taskType;
  final int status;
  final int resultCode;
  final String? resultMsg;
  final Map<String, dynamic>? bizData;

  const CadTaskStatus({
    required this.requestId,
    required this.taskType,
    required this.status,
    required this.resultCode,
    this.resultMsg,
    this.bizData,
  });

  bool get isDone => status == 2;
  bool get isOk => isDone && resultCode == 0;

  factory CadTaskStatus.fromJson(Map<String, dynamic> j) {
    final biz = j['bizData'] as Map<String, dynamic>?;
    return CadTaskStatus(
      requestId: biz?['requestId']?.toString() ?? '',
      taskType: biz?['taskType']?.toString() ?? '',
      status: (biz?['status'] as num?)?.toInt() ?? 0,
      resultCode: (biz?['resultCode'] as num?)?.toInt() ?? -1,
      resultMsg: biz?['resultMsg']?.toString(),
      bizData: biz,
    );
  }
}

// ==================== 天气模型 ====================

/// 天气预警（来自和风天气 /v1/warning/now）。
class WeatherWarning {
  final String type; // 预警类型，如 "台风"、"暴雨"、"高温"
  final String level; // 等级，如 "蓝色"、"黄色"
  final String title; // 标题
  final String text; // 详情
  const WeatherWarning({
    required this.type,
    required this.level,
    required this.title,
    this.text = '',
  });

  factory WeatherWarning.fromJson(Map<String, dynamic> j) => WeatherWarning(
        type: j['type']?.toString() ?? '',
        level: j['level']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        text: j['text']?.toString() ?? '',
      );

  /// 预警等级颜色（蓝/黄/橙/红）。
  Color get color {
    final l = level;
    if (l.contains('红')) return const Color(0xFFDC2626);
    if (l.contains('橙')) return const Color(0xFFEA580C);
    if (l.contains('黄')) return const Color(0xFFCA8A04);
    return const Color(0xFF2563EB); // 蓝色
  }
}

/// 工地实时天气（来自本地 /api/weather 代理，底层走和风天气）。
class WeatherInfo {
  final String source; // mock / qweather / error
  final String name;
  final String temp;
  final String text;
  final String humidity;
  final String windDir;
  final String windScale;
  final String? aqi;
  final String? category; // 空气质量等级：优/良/轻度污染...
  final List<WeatherWarning> warnings;
  final String updateTime;
  const WeatherInfo({
    required this.source,
    required this.name,
    required this.temp,
    required this.text,
    required this.humidity,
    required this.windDir,
    required this.windScale,
    this.aqi,
    this.category,
    this.warnings = const [],
    this.updateTime = '',
  });

  factory WeatherInfo.fromJson(Map<String, dynamic> j) => WeatherInfo(
        source: j['source']?.toString() ?? 'mock',
        name: j['name']?.toString() ?? '深圳',
        temp: j['temp']?.toString() ?? '--',
        text: j['text']?.toString() ?? '--',
        humidity: j['humidity']?.toString() ?? '',
        windDir: j['windDir']?.toString() ?? '',
        windScale: j['windScale']?.toString() ?? '',
        aqi: j['aqi']?.toString(),
        category: j['category']?.toString(),
        warnings: (j['warnings'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(WeatherWarning.fromJson)
            .toList(),
        updateTime: j['updateTime']?.toString() ?? '',
      );

  bool get isMock => source == 'mock';

  /// 天气图标名（映射到 LucideIcons）。
  String get iconName {
    final t = text;
    if (t.contains('雷')) return 'cloudLightning';
    if (t.contains('雨')) return 'cloudRain';
    if (t.contains('雪')) return 'cloudSnow';
    if (t.contains('雾') || t.contains('霾')) return 'cloudFog';
    if (t.contains('阴')) return 'cloud';
    if (t.contains('云')) return 'cloudSun';
    return 'sun';
  }
}
