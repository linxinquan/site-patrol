import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:http/http.dart' as http;

/// 视觉模型缺陷识别结果。
class VisionResult {
  final int count;
  final List<DefectItem> defects;

  const VisionResult({required this.count, required this.defects});

  factory VisionResult.fromContent(String content) {
    // 模型可能返回带 markdown 代码块或多余文字，提取第一个 JSON 对象
    final start = content.indexOf('{');
    final end = content.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) {
      return const VisionResult(count: 0, defects: []);
    }
    try {
      final map = jsonDecode(content.substring(start, end + 1));
      final items = (map['defects'] as List? ?? [])
          .map((e) => DefectItem(
                name: e['name']?.toString() ?? '',
                desc: e['desc']?.toString() ?? '',
                conf: (e['conf'] as num?)?.toDouble() ?? 0.0,
                suggestion: e['suggestion']?.toString(),
              ))
          .toList();
      return VisionResult(count: map['count'] as int? ?? items.length, defects: items);
    } catch (_) {
      return const VisionResult(count: 0, defects: []);
    }
  }

  /// 序列化为可存储的 JSON（暂存用）。
  Map<String, dynamic> toJson() =>
      {'count': count, 'defects': defects.map((d) => d.toJson()).toList()};

  /// 从 JSON 恢复（容错：字段缺失时给空值）。
  factory VisionResult.fromJson(Map<String, dynamic> map) {
    final items = (map['defects'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(DefectItem.fromJson)
        .toList();
    return VisionResult(
      count: map['count'] as int? ?? items.length,
      defects: items,
    );
  }
}

class DefectItem {
  final String name;
  final String desc;

  /// 置信度 0.0~1.0：1.0 确定无需人工复核，0.0 判断错误/无法判断。
  final double conf;

  /// AI 整改建议（给施工单位；后端模型未返回时为空，客户端用本地建议库兜底）。
  final String? suggestion;
  const DefectItem({
    required this.name,
    required this.desc,
    this.conf = 0.0,
    this.suggestion,
  });

  Map<String, dynamic> toJson() =>
      {'name': name, 'desc': desc, 'conf': conf, 'suggestion': suggestion};

  factory DefectItem.fromJson(Map<String, dynamic> map) => DefectItem(
        name: map['name']?.toString() ?? '',
        desc: map['desc']?.toString() ?? '',
        conf: (map['conf'] as num?)?.toDouble() ?? 0.0,
        suggestion: map['suggestion']?.toString(),
      );
}

/// 缺陷识别服务：调本地/云端视觉代理后端，再转千问视觉模型。
/// 默认指向已部署的云服务器；本地调试可覆盖：--dart-define=VISION_HOST=http://localhost:3000
class VisionService {
  static const String host = String.fromEnvironment(
    'VISION_HOST',
    defaultValue: 'http://120.24.240.129:3000',
  );

  /// 联网预检：地下室/无信号时快速失败，避免用户白等识别超时。
  ///
  /// 只要收到任意 HTTP 响应（含 404/500）即视为网络可达；
  /// 连接失败或超时视为不可达。Web 端跨域被拦也会返回 false
  /// （此时真实识别调用同样会失败，结论一致，且手动标定不受影响）。
  static Future<bool> isReachable({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      await http.get(Uri.parse(host)).timeout(timeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 识别图片中的施工缺陷。
  /// [imageBytes] 压缩后的图片字节，[prompt] 可覆盖默认指令。
  Future<VisionResult> recognizeDefects(
    Uint8List imageBytes, {
    String? prompt,
  }) async {
    final resp = await http
        .post(
          Uri.parse('$host/api/vision'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'image': 'data:image/jpeg;base64,${base64Encode(imageBytes)}',
            if (prompt != null) 'prompt': prompt,
          }),
        )
        .timeout(const Duration(seconds: 180));

    if (resp.statusCode != 200) {
      throw Exception('视觉识别失败(${resp.statusCode}): ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return VisionResult.fromContent(data['content']?.toString() ?? '');
  }

  /// 识别照片中可用于自动标定的已知尺寸标准件。
  ///
  /// 返回**最优的一个**锚物（按 置信度×框面积 取最大）；没有合格标准件时
  /// 返回 null（不抛异常），由调用方走手动标定兜底。
  /// 网络失败/解析失败会抛异常，调用方需自行 try/catch 降级。
  Future<AnchorDetection?> detectAnchor(Uint8List imageBytes) async {
    final resp = await http
        .post(
          Uri.parse('$host/api/vision'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'image': 'data:image/jpeg;base64,${base64Encode(imageBytes)}',
            'prompt': _anchorPrompt,
          }),
        )
        .timeout(const Duration(seconds: 120));

    if (resp.statusCode != 200) {
      throw Exception('锚物识别失败(${resp.statusCode}): ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return AnchorDetection.bestFromContent(data['content']?.toString() ?? '');
  }

  /// 识别画面中「同一平面上的等距模数网格」（瓷砖缝 / 地砖 / 吊顶扣板 / 幕墙分格），
  /// 返回网格交点与格距——**这是照片量尺的主标定来源**：
  /// 网格给出几十个已知间距的控制点，比单个锚物稳得多，且把斜拍透视一并解出。
  ///
  /// 返回 null 表示画面里没有可用网格（不抛异常）；网络/解析失败抛异常，
  /// 调用方需 try/catch 并回退手动点选网格。
  Future<GridDetection?> detectGrid(Uint8List imageBytes) async {
    final resp = await http
        .post(
          Uri.parse('$host/api/vision'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'image': 'data:image/jpeg;base64,${base64Encode(imageBytes)}',
            'prompt': _gridPrompt,
          }),
        )
        .timeout(const Duration(seconds: 120));

    if (resp.statusCode != 200) {
      throw Exception('网格识别失败(${resp.statusCode}): ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return GridDetection.fromContent(data['content']?.toString() ?? '');
  }
}

/// AI 识别到的等距模数网格。
///
/// [points] 为归一化 0~1 的网格交点坐标，**行优先**（从左到右、从上到下）；
/// [cols]/[rows] 是**交点的列数/行数**，故 `points.length == cols × rows`；
/// [gridMm] 为相邻交点的真实间距（模型无法判断时为 0）。
class GridDetection {
  final String name;
  final double gridMm;
  final int cols;
  final int rows;
  final List<Offset> points;
  final double conf;

  const GridDetection({
    required this.name,
    required this.gridMm,
    required this.cols,
    required this.rows,
    required this.points,
    this.conf = 0,
  });

  /// 是否可用于标定：至少 4 个交点、格距为正、行列数合理、有一定置信度。
  bool get isValid =>
      points.length >= 4 &&
      points.length >= cols * rows &&
      cols >= 2 &&
      rows >= 2 &&
      gridMm > 0 &&
      conf >= 0.3;

  /// 从模型文本提取网格；无合格结果返回 null（不抛异常）。
  static GridDetection? fromContent(String content) {
    final start = content.indexOf('{');
    final end = content.lastIndexOf('}');
    if (start == -1 || end <= start) return null;
    try {
      final map = jsonDecode(content.substring(start, end + 1));
      final g = map['grid'];
      if (g is! Map) return null;
      double n(dynamic v) => (v as num?)?.toDouble() ?? 0;
      final pts = <Offset>[];
      for (final p in (g['points'] as List? ?? [])) {
        if (p is List && p.length >= 2) {
          pts.add(Offset(n(p[0]), n(p[1])));
        }
      }
      final det = GridDetection(
        name: g['name']?.toString() ?? '模数网格',
        gridMm: n(g['gridMm']),
        cols: (g['cols'] as num?)?.toInt() ?? 0,
        rows: (g['rows'] as num?)?.toInt() ?? 0,
        points: pts,
        conf: n(g['conf']),
      );
      return det.isValid ? det : null;
    } catch (_) {
      return null;
    }
  }
}

/// 网格识别提示词：要求返回**行优先**的归一化交点数组与真实格距。
const String _gridPrompt =
    '你是施工测量助手。请在照片中找出【一个】同一平面上的等距网格'
    '（瓷砖缝/地砖缝、吊顶扣板、幕墙分格、石膏板拼缝等），并给出其交点。\n'
    '要求：\n'
    '1) 网格必须位于同一平面、尽量完整入画，交点清晰可辨；\n'
    '2) name 为网格类型描述（如「瓷砖缝」「吊顶扣板」）；\n'
    '3) gridMm 为相邻两条缝的真实间距（mm）：瓷砖常见 300/600/800，'
    '扣板常见 300/600，石膏板 1200；无法判断时给 0；\n'
    '4) cols/rows 为**交点的列数、行数**（交点数 = cols×rows），'
    '每向至少 2 个交点，最多取 5×5（务必只给清晰可辨的交点）；\n'
    '5) points 为网格交点坐标，归一化 0~1，**按行优先排列**'
    '（先从左到右走完一行，再进入下一行），个数须等于 cols×rows；\n'
    '6) conf 为置信度 0~1；画面里没有可用网格时返回 {"grid":null}。\n'
    '只输出 JSON，不要任何多余文字：\n'
    '{"grid":{"name":"瓷砖缝","gridMm":600,"cols":4,"rows":4,"conf":0.9,'
    '"points":[[0.10,0.20],[0.35,0.19],[0.58,0.18],[0.80,0.17],'
    '[0.11,0.45],[0.36,0.44],[0.59,0.43],[0.81,0.42],'
    '[0.12,0.70],[0.37,0.69],[0.60,0.68],[0.82,0.67],[0.13,0.95],'
    '[0.38,0.94],[0.61,0.93],[0.83,0.92]]}}';

/// 自动标定锚物识别结果。
///
/// [left]/[top]/[right]/[bottom] 为归一化 0~1 的图像外接矩形；
/// [realWmm]/[realHmm] 是框宽、高各自对应的**真实长度**（模型按物体在画面
/// 中的实际朝向换算——横放的 A4 纸框宽对应 297 而不是 210）。
class AnchorDetection {
  final String name;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final double realWmm;
  final double realHmm;
  final double conf;

  const AnchorDetection({
    required this.name,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.realWmm,
    required this.realHmm,
    this.conf = 0,
  });

  /// 是否可用于标定（框有效 + 尺寸为正 + 有一定置信度）。
  bool get isValid =>
      right > left &&
      bottom > top &&
      realWmm > 0 &&
      realHmm > 0 &&
      conf >= 0.3;

  /// 归一化框面积（多候选时优先取大而可信的）。
  double get area => (right - left) * (bottom - top);

  /// 从模型文本里提取最优锚物；无合格结果返回 null。
  static AnchorDetection? bestFromContent(String content) {
    final start = content.indexOf('{');
    final end = content.lastIndexOf('}');
    if (start == -1 || end <= start) return null;
    try {
      final map = jsonDecode(content.substring(start, end + 1));
      final list = (map['anchors'] as List? ?? []);
      final dets = list
          .whereType<Map>()
          .map((e) {
            final box = (e['box'] as List? ?? []);
            double n(dynamic v) => (v as num?)?.toDouble() ?? 0;
            return AnchorDetection(
              name: e['name']?.toString() ?? '',
              left: box.isNotEmpty ? n(box[0]) : 0,
              top: box.length > 1 ? n(box[1]) : 0,
              right: box.length > 2 ? n(box[2]) : 0,
              bottom: box.length > 3 ? n(box[3]) : 0,
              realWmm: n(e['realWmm']),
              realHmm: n(e['realHmm']),
              conf: n(e['conf']),
            );
          })
          .where((d) => d.isValid)
          .toList();
      if (dets.isEmpty) return null;
      dets.sort((a, b) => (b.conf * b.area).compareTo(a.conf * a.area));
      return dets.first;
    } catch (_) {
      return null;
    }
  }
}

/// 锚物识别提示词（与 `kAnchorObjects` 尺寸库保持一致，改尺寸需同步）。
const String _anchorPrompt =
    '你是施工测量助手。请在照片中找出【一个】可用于长度标定的已知尺寸标准件。\n'
    '只认这些（名称→真实尺寸 mm）：\n'
    '- 86型开关/插座面板：86×86\n'
    '- A4纸：210×297\n'
    '- 身份证/银行卡：85.6×54\n'
    '- 标准砖（烧结普通砖）：240×115×53\n'
    '- 瓷砖：300×300 / 600×600 / 800×800\n'
    '- 纸面石膏板：1200×2400\n'
    '要求：\n'
    '1) 物体须完整入画、无遮挡、无明显透视倾斜；\n'
    '2) box 为该物体在图中的外接矩形 [x1,y1,x2,y2]，坐标归一化 0~1；\n'
    '3) realWmm/realHmm = 框的宽、高各自对应的真实长度，按物体在画面中的'
    '实际朝向换算（横放的 A4 纸框宽对应 297，竖放对应 210）；\n'
    '4) conf 为置信度 0~1，拿不准就给低分；\n'
    '5) 没有合格标准件时返回 {"anchors":[]}。\n'
    '只输出 JSON，不要任何多余文字：\n'
    '{"anchors":[{"name":"86型开关面板","box":[0.1,0.2,0.3,0.4],'
    '"realWmm":86,"realHmm":86,"conf":0.9}]}';
