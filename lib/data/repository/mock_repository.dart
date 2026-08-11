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
  Future<List<TimelinePhoto>> getTimeline(String anchor) =>
      _delay(timeline[anchor] ?? const []);
}
