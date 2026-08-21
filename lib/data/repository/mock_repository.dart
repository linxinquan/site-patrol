import '../models.dart';
import '../mock/mock_data.dart';
import 'repository.dart';

/// Mock 实现：直接读本地常量 + assets。带小延迟以演示 loading 态。
class MockRepository implements Repository {
  /// 可变缺陷列表（从 mock 常量浅拷贝，含全部项目），addDefect 写入此处，getDefects 读此处。
  final List<Defect> _defects = List.from([...defects, ...dy7Defects]);

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
  Future<List<Defect>> getDefects({DefectStatus? status}) {
    // 按项目返回：7栋缺陷（dy7Defects + 新增）+ 南科大缺陷（defects + 新增）。
    final is7 = _currentIs7;
    final base = is7 ? dy7Defects : defects;
    final baseIds = base.map((d) => d.id).toSet();
    final list = [
      ...base,
      ..._defects.where((d) => !baseIds.contains(d.id)),
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
  Future<void> addDefect(Defect defect) {
    _defects.add(defect);
    return Future.value();
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
