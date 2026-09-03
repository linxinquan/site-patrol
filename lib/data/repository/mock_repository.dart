import 'dart:convert';

import '../../core/storage/local_storage.dart';
import '../models.dart';
import '../mock/mock_data.dart';
import 'repository.dart';

/// Mock 实现：直接读本地常量 + assets。带小延迟以演示 loading 态。
class MockRepository implements Repository {
  MockRepository() {
    // 启动即异步恢复「运行期新增」缺陷（Web 刷新 / 移动端重启后不丢记录）。
    _restored = _restoreAdded();
  }

  /// 运行期新增的缺陷及其所属项目标记（true = 7栋）。
  ///
  /// 单独存放（而非混入 `_defects` 常量）以避免跨项目污染：
  /// 每个项目只看到「本项目的预置 mock + 本项目新增」。
  final List<(Defect defect, bool is7)> _added = [];

  /// 本地持久化 key 与恢复完成信号（getDefects 前必须等待）。
  static const String _addedKey = 'added_defects_v1';
  late Future<void> _restored;

  Future<void> _restoreAdded() async {
    try {
      final raw = await LocalStorage.instance.readDoc(_addedKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _added
        ..clear()
        ..addAll([
          for (final m in decoded.whereType<Map>())
            (
              Defect.fromJson(Map<String, dynamic>.from(m['defect'] as Map)),
              (m['is7'] as bool?) ?? false,
            ),
        ]);
    } catch (_) {
      // 恢复失败（数据损坏等）不阻断主流程，视作无新增记录。
    }
  }

  Future<void> _persistAdded() async {
    try {
      await LocalStorage.instance.writeDoc(
        _addedKey,
        jsonEncode([
          for (final (d, is7) in _added)
            {'is7': is7, 'defect': d.toJson()},
        ]),
      );
    } catch (_) {
      // Web 存储配额满等场景静默失败，不影响内存态可用。
    }
  }

  Future<T> _delay<T>(T value) =>
      Future.delayed(const Duration(milliseconds: 350), () => value);

  @override
  Future<List<Project>> getProjects() => _delay(allProjects);

  @override
  Future<Project> getProject(String id) =>
      _delay(allProjects.firstWhere((p) => p.id == id,
          orElse: () => allProjects.first));

  @override
  Future<List<Floor>> getFloors() => _delay(floors);

  @override
  Future<Map<String, Drawing>> getDrawings() => _delay(drawings);

  @override
  Future<Drawing?> getDrawing(String key) => _delay(drawings[key]);

  @override
  Future<List<PhotoAnchor>> getAnchors(String floor) =>
      _delay(photoAnchors[floor] ?? const []);

  @override
  Future<List<Defect>> getDefects({DefectStatus? status}) async {
    // 等待本地恢复完成，避免启动瞬间 getDefects 拿到空的新增列表。
    await _restored;
    // 按项目返回：当前项目的预置 mock + 本项目运行期新增的缺陷。
    final is7 = _currentIs7;
    final base = is7 ? dy7Defects : defects;
    final list = [
      ...base,
      ..._added.where((e) => e.$2 == is7).map((e) => e.$1),
    ];
    final filtered =
        status == null ? list : list.where((d) => d.status == status).toList();
    return _delay(filtered);
  }

  /// 当前项目是否 7栋（由 UI 侧在写入前设置，影响 getDefects 的分组）。
  bool _currentIs7 = false;
  set currentIs7(bool v) => _currentIs7 = v;

  /// 拍照量尺校对会话（内存态，按 项目+图纸 唯一）。
  final Map<String, MeasureSession> _measurements = {};

  @override
  Future<void> saveMeasurement(MeasureSession session) {
    _measurements['${session.projectKey}|${session.drawingKey}'] = session;
    return Future.value();
  }

  @override
  Future<MeasureSession?> getMeasurement(String projectKey, String drawingKey) =>
      Future.value(_measurements['$projectKey|$drawingKey']);

  @override
  Future<void> addDefect(Defect defect) async {
    // 归入「新增时的当前项目」，避免跨项目串数据。
    _added.add((defect, _currentIs7));
    await _persistAdded();
  }

  @override
  Future<List<TimelinePhoto>> getTimeline(String anchor) {
    // 兼容：从缺陷详情页跳过来时传入的可能是 defect.part（缺陷描述），
    // 而 timeline map 的 key 是 anchor（如"西楼1F-左病房翼"）。
    // 先精确查；查不到时回退到默认 anchor（保证 demo 数据可见）。
    final exact = timeline[anchor];
    if (exact != null) return _delay(exact);
    return _delay(timeline['西楼1F-左病房翼'] ?? const []);
  }
}
