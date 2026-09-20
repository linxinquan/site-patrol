/// ⚠️ **CAD 归档域（待剥离）**。
///
/// 浩辰云图 OCF 转换链路已判为废案并整体移交独立项目，
/// 本文件仅作历史兼容保留：**后端不必为其建表**，
/// 待 CAD 迁移完成后本文件整体删除。
///
/// [UploadedDrawing] 也属该链路（DWG 自助上传登记）。
library;

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
    if (v is String) {
      return CadLayer(name: v, isOff: false, isFrozen: false, isLock: false);
    }
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
      layouts:
          ((biz?['layouts'] as List?) ?? []).map(CadLayout.fromJson).toList(),
      blocks:
          ((biz?['blocks'] as List?) ?? []).map((e) => e.toString()).toList(),
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
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ??
            DateTime.now(),
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

/// 用户上传 DWG 转换登记（任务3：DWG 自助上传 → OCF 手机查看）。
class UploadedDrawing {
  final String key; // drawingKey / OCF 缓存 key
  final String name; // 展示名（原始文件名去 .dwg）
  final String fileName; // 原始文件名（含扩展）
  final int sizeBytes;
  final int tsMs;

  /// 底图 PNG 像素宽/高（后端渲染时返回；0 = 旧数据未记录）。
  final int width;
  final int height;

  /// CAD 坐标范围 "xmin,ymin,xmax,ymax"（mm，供后续自动校准）。
  final String? bounds;

  /// 'converting'（转换中）/ 'done'（已转换）/ 'failed'（失败）。
  final String status;
  final String? error; // failed 时给可读错误
  const UploadedDrawing({
    required this.key,
    required this.name,
    required this.fileName,
    this.sizeBytes = 0,
    this.tsMs = 0,
    this.width = 0,
    this.height = 0,
    this.bounds,
    this.status = 'converting',
    this.error,
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'fileName': fileName,
        'sizeBytes': sizeBytes,
        'tsMs': tsMs,
        'width': width,
        'height': height,
        'bounds': bounds,
        'status': status,
        'error': error,
      };

  /// 旧数据读取缺字段一律给默认值。
  factory UploadedDrawing.fromJson(Map<String, dynamic> m) => UploadedDrawing(
        key: m['key']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        fileName: m['fileName']?.toString() ?? '',
        sizeBytes: (m['sizeBytes'] as num? ?? 0).toInt(),
        tsMs: (m['tsMs'] as num? ?? 0).toInt(),
        width: (m['width'] as num? ?? 0).toInt(),
        height: (m['height'] as num? ?? 0).toInt(),
        bounds: m['bounds']?.toString(),
        status: m['status']?.toString() ?? 'done',
        error: m['error']?.toString(),
      );
}
