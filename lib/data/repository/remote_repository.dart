import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';
import 'repository.dart';

/// 真实后端实现。后端就绪后由 DI（ENV=prod）注入。
///
/// 测量落库走轻量 Python 服务（`server/measure_server.py`）：
///   POST /api/measurements  ·  GET /api/measurements?projectKey=&drawingKey=
///
/// host 解析顺序（原先注释写"默认端口 8820"但代码是 3000，容易误导维护者）：
/// - 线上默认 = 云服务器 **:3000**（与视觉服务同端口），可用 `MEASURE_HOST` 覆盖；
/// - 本地跑 `measure_server.py` 时它监听 **:8820**，必须显式传
///   `--dart-define=MEASURE_HOST=http://localhost:8820`。
/// 注意：该服务目前尚未上线，线上调用会失败（见 FEATURE_INVENTORY 10.7）。
class RemoteRepository implements Repository {
  static const String host = String.fromEnvironment(
    'MEASURE_HOST',
    defaultValue: 'http://120.24.240.129:3000',
  );

  Future<Map<String, dynamic>> _postJson(
      String path, Map<String, dynamic> body) async {
    final resp = await http.post(
      Uri.parse('$host$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode >= 400 || data['ok'] == false) {
      throw Exception(data['err']?.toString() ?? '请求失败: $path');
    }
    return data;
  }

  @override
  Future<void> saveMeasurement(MeasureSession session) =>
      _postJson('/api/measurements', session.toJson());

  @override
  Future<MeasureSession?> getMeasurement(
      String projectKey, String drawingKey) async {
    final resp = await http.get(
      Uri.parse(
          '$host/api/measurements?projectKey=${Uri.encodeComponent(projectKey)}&drawingKey=${Uri.encodeComponent(drawingKey)}'),
      headers: {'Content-Type': 'application/json'},
    );
    if (resp.statusCode >= 400) return null;
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['found'] != true || data['session'] == null) return null;
    return MeasureSession.fromJson(data['session'] as Map<String, dynamic>);
  }

  // —— 以下为其它接口占位（后端未提供时保持未实现）——
  @override
  Future<List<Project>> getProjects() =>
      throw UnimplementedError('RemoteRepository.getProjects 待实现');

  @override
  Future<Project> getProject(String id) =>
      throw UnimplementedError('RemoteRepository.getProject 待实现');

  @override
  Future<List<Floor>> getFloors() =>
      throw UnimplementedError('RemoteRepository.getFloors 待实现');

  @override
  Future<Map<String, Drawing>> getDrawings() =>
      throw UnimplementedError('RemoteRepository.getDrawings 待实现');

  @override
  Future<Drawing?> getDrawing(String key) =>
      throw UnimplementedError('RemoteRepository.getDrawing 待实现');

  @override
  Future<List<PhotoAnchor>> getAnchors(String floor) =>
      throw UnimplementedError('RemoteRepository.getAnchors 待实现');

  @override
  Future<List<Defect>> getDefects({DefectStatus? status}) =>
      throw UnimplementedError('RemoteRepository.getDefects 待实现');

  @override
  Future<void> addDefect(Defect defect) =>
      throw UnimplementedError('RemoteRepository.addDefect 待实现');

  @override
  Future<void> updateDefect(Defect updated) =>
      throw UnimplementedError('RemoteRepository.updateDefect 待实现');

  @override
  Future<List<TimelinePhoto>> getTimeline(String anchor) =>
      throw UnimplementedError('RemoteRepository.getTimeline 待实现');
}
