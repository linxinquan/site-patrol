import 'dart:convert';
import 'dart:typed_data';

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
  const DefectItem({required this.name, required this.desc, this.conf = 0.0});

  Map<String, dynamic> toJson() => {'name': name, 'desc': desc, 'conf': conf};

  factory DefectItem.fromJson(Map<String, dynamic> map) => DefectItem(
        name: map['name']?.toString() ?? '',
        desc: map['desc']?.toString() ?? '',
        conf: (map['conf'] as num?)?.toDouble() ?? 0.0,
      );
}

/// 缺陷识别服务：调本地/云端视觉代理后端，再转千问视觉模型。
/// 本地开发默认 http://localhost:3000，上云后改 --dart-define=VISION_HOST=https://xxx
class VisionService {
  static const String host = String.fromEnvironment(
    'VISION_HOST',
    defaultValue: 'http://localhost:3000',
  );

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
}
