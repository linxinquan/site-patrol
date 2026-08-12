import '../models.dart';
import '../mock/mock_data.dart';
import 'repository.dart';

/// Mock 实现：直接读本地常量 + assets。带小延迟以演示 loading 态。
class MockRepository implements Repository {
  Future<T> _delay<T>(T value) =>
      Future.delayed(const Duration(milliseconds: 350), () => value);

  @override
  Future<Project> getProject() => _delay(project);

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
  Future<List<Defect>> getDefects({DefectStatus? status}) => _delay(
        status == null
            ? defects
            : defects.where((d) => d.status == status).toList(),
      );

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
