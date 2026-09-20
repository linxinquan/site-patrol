/// 图纸与版本域模型（C1 图纸版本 / C2 校准 / C3 热点）。
///
/// **核心约定：底图、尺寸、热点、校准全部随版本走。**
/// [DrawingVersion] 是权威数据；[Drawing] 上的 `src` / `w` / `h` / `hotspots`
/// 是「当前发布版本」的**冗余快照**（由服务端按 `publishedVersionId` 回填），
/// 让渲染端不必改代码。
///
/// 图纸改版走「发布」动作：旧版本置 `archived` 锁只读，**不做自动坐标迁移**，
/// 客户端需提示驻场重新校准。
///
/// 后端对应表：`drawings`（身份）+ `drawing_versions`（底图/尺寸/热点/校准）。
library;

/// 容错取 double（非数值 → 0）。
///
/// 写成**顶层函数**是必要的：类内若存在名为 `num` 的字段（如 [Hotspot]），
/// 会在类作用域内遮蔽 `num` 类型，导致 `as num?` 无法编译。
double _asDouble(dynamic v) => v is num ? v.toDouble() : 0;

/// 图纸热点（底图上的可点区域）。
///
/// **内嵌于 [DrawingVersion.hotspots]**：热点是坐标，必须随版本走。
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

  Map<String, dynamic> toJson() =>
      {'num': num, 'label': label, 'target': target, 'x': x, 'y': y};

  factory Hotspot.fromJson(Map<String, dynamic> m) {
    // 注意：本类有名为 `num` 的字段，会在类作用域内遮蔽 `num` 类型，
    // 因此这里不能写 `as num?`，改用顶层容错取值函数。
    return Hotspot(
      num: _asDouble(m['num']).toInt(),
      label: m['label']?.toString() ?? '',
      target: m['target']?.toString() ?? '',
      x: _asDouble(m['x']),
      y: _asDouble(m['y']),
    );
  }
}

/// 图纸（C1，版本身份）。
///
/// **版本化的核心约定**：本类只承载「图纸身份」与**当前发布版本的冗余快照**；
/// 权威数据在 [DrawingVersion]（底图尺寸、热点、校准都随版本走）。
/// 冗余字段（[src] / [w] / [h] / [hotspots]）由服务端按 `publishedVersionId`
/// join 回填，客户端渲染代码可直接用，不必改。
class Drawing {
  final String key; // 本地业务 key（后台建表时作为 external key）
  final String projectId; // 所属项目（多项目隔离的必要条件）
  final String title;
  final String crumb; // 面包屑，如「7栋 详图」
  final String variant; // 图纸类型，如 detail / plan
  final String discipline; // 专业，如 建筑 / 结构 / 机电（自由文本，可扩展）
  final String src; // 冗余快照：当前发布版本底图（assets 路径或对象存储 key）
  final double w; // 冗余快照：底图像素宽
  final double h; // 冗余快照：底图像素高
  final List<Hotspot> hotspots; // 冗余快照：当前发布版本热点

  /// 当前发布版本（→ [DrawingVersion.id]）。
  /// 空串 = 尚未版本化（预置演示图 / 后台未发布）。
  final String publishedVersionId;
  final int sort; // 列表排序

  /// 若为 CAD/OCF 图纸，标记对应 OCF 缓存 key（如 `dy04_7_B01`）。
  /// ⚠️ CAD 链路已判废案，待整体剥离。
  final String? cadOcfKey;
  const Drawing({
    required this.key,
    this.projectId = '',
    required this.title,
    required this.crumb,
    required this.variant,
    this.discipline = '',
    required this.src,
    required this.w,
    required this.h,
    required this.hotspots,
    this.publishedVersionId = '',
    this.sort = 0,
    this.cadOcfKey,
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'projectId': projectId,
        'title': title,
        'crumb': crumb,
        'variant': variant,
        'discipline': discipline,
        // 冗余快照也一并输出：后端可直接落库，客户端也能脱离版本表渲染。
        'src': src,
        'w': w,
        'h': h,
        'hotspots': hotspots.map((e) => e.toJson()).toList(),
        'publishedVersionId': publishedVersionId,
        'sort': sort,
        'cadOcfKey': cadOcfKey,
      };

  factory Drawing.fromJson(Map<String, dynamic> m) => Drawing(
        key: m['key']?.toString() ?? '',
        projectId: m['projectId']?.toString() ?? '',
        title: m['title']?.toString() ?? '',
        crumb: m['crumb']?.toString() ?? '',
        variant: m['variant']?.toString() ?? '',
        discipline: m['discipline']?.toString() ?? '',
        src: m['src']?.toString() ?? '',
        w: (m['w'] as num?)?.toDouble() ?? 0,
        h: (m['h'] as num?)?.toDouble() ?? 0,
        hotspots: (m['hotspots'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Hotspot.fromJson(e.cast<String, dynamic>()))
            .toList(),
        publishedVersionId: m['publishedVersionId']?.toString() ?? '',
        sort: (m['sort'] as num?)?.toInt() ?? 0,
        cadOcfKey: m['cadOcfKey']?.toString(),
      );
}

/// 图纸版本（C1）——**本次改造的关键**。
///
/// 规则（与需求文档一致）：
/// - 改版走「发布」动作：旧版本 [state] 置 `archived` 并锁只读；
/// - **不做自动坐标迁移**（算法不可靠且不可解释），改版后提示驻场重锚；
/// - 底图、尺寸、热点、校准**全部绑版本**（[Calibration.drawingVersionId]）。
class DrawingVersion {
  /// 版本状态。
  static const String stateDraft = 'draft'; // 已上传未发布
  static const String statePublished = 'published'; // 已发布（当前生效）
  static const String stateArchived = 'archived'; // 已归档（旧版，只读）

  final String id; // ULID
  final String drawingKey; // → Drawing.key
  final String version; // 版本号，**必填**，如 'V1.0'
  final String versionDate; // 版本日期，`yyyy-MM-dd`
  final String state; // 见上方 state* 常量
  final String baseImagePath; // 底图（本地相对路径 / 对象存储 key）
  final double width; // 底图像素宽（权威）
  final double height; // 底图像素高（权威）
  final String? bounds; // CAD 坐标范围 'xmin,ymin,xmax,ymax'（mm）
  final List<Hotspot> hotspots; // 热点随版本走（坐标）
  final int publishedAtMs; // 发布时间（epoch ms）
  final String? publishedBy; // 发布人 → User.id
  const DrawingVersion({
    required this.id,
    required this.drawingKey,
    required this.version,
    this.versionDate = '',
    this.state = stateDraft,
    this.baseImagePath = '',
    this.width = 0,
    this.height = 0,
    this.bounds,
    this.hotspots = const [],
    this.publishedAtMs = 0,
    this.publishedBy,
  });

  bool get isPublished => state == statePublished;

  Map<String, dynamic> toJson() => {
        'id': id,
        'drawingKey': drawingKey,
        'version': version,
        'versionDate': versionDate,
        'state': state,
        'baseImagePath': baseImagePath,
        'width': width,
        'height': height,
        'bounds': bounds,
        'hotspots': hotspots.map((e) => e.toJson()).toList(),
        'publishedAtMs': publishedAtMs,
        'publishedBy': publishedBy,
      };

  factory DrawingVersion.fromJson(Map<String, dynamic> m) => DrawingVersion(
        id: m['id']?.toString() ?? '',
        drawingKey: m['drawingKey']?.toString() ?? '',
        version: m['version']?.toString() ?? '',
        versionDate: m['versionDate']?.toString() ?? '',
        state: m['state']?.toString() ?? stateDraft,
        baseImagePath: m['baseImagePath']?.toString() ?? '',
        width: (m['width'] as num?)?.toDouble() ?? 0,
        height: (m['height'] as num?)?.toDouble() ?? 0,
        bounds: m['bounds']?.toString(),
        hotspots: (m['hotspots'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Hotspot.fromJson(e.cast<String, dynamic>()))
            .toList(),
        publishedAtMs: (m['publishedAtMs'] as num?)?.toInt() ?? 0,
        publishedBy: m['publishedBy']?.toString(),
      );
}

/// 图纸坐标校准（C2）——**必须绑版本**。
///
/// [map] 是仿射系数（`viewWidth` / `viewHeight` / `a`..`f`），
/// 由 `CadCoordMapper.fromCalibrationMap` 解析；[raw] 保留浏览器导出的原始 JSON，
/// 便于下次打开校准弹窗预填。
///
/// ⚠️ 与 [PhotoCalib] 区分：本类是**图纸级**（像素 ↔ 毫米世界坐标），
/// [PhotoCalib] 是**照片级**（照片内参考物标定）。
class Calibration {
  final String drawingKey; // → Drawing.key
  final String drawingVersionId; // ⚠️ 坐标绑版本
  final String? raw; // 浏览器原始校准 JSON（可空）
  final Map<String, dynamic> map; // 仿射系数
  final int updatedAtMs;
  const Calibration({
    required this.drawingKey,
    this.drawingVersionId = '',
    this.raw,
    this.map = const {},
    this.updatedAtMs = 0,
  });

  Map<String, dynamic> toJson() => {
        'drawingKey': drawingKey,
        'drawingVersionId': drawingVersionId,
        'raw': raw,
        'map': map,
        'updatedAtMs': updatedAtMs,
      };

  factory Calibration.fromJson(Map<String, dynamic> m) => Calibration(
        drawingKey: m['drawingKey']?.toString() ?? '',
        drawingVersionId: m['drawingVersionId']?.toString() ?? '',
        raw: m['raw']?.toString(),
        map: (m['map'] as Map?)?.cast<String, dynamic>() ?? const {},
        updatedAtMs: (m['updatedAtMs'] as num?)?.toInt() ?? 0,
      );
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
