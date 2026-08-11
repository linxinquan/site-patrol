import '../models.dart';

/// 数据仓库抽象接口。UI 只依赖此接口。
/// 当前实现：MockRepository（dev）。后端就绪后实现 RemoteRepository（prod）。
abstract class Repository {
  Future<Project> getProject();
  Future<List<Floor>> getFloors();
  Future<Map<String, Drawing>> getDrawings();
  Future<Drawing?> getDrawing(String key);
  Future<List<PhotoAnchor>> getAnchors(String floor);
  Future<List<Defect>> getDefects({DefectStatus? status});
  Future<List<TimelinePhoto>> getTimeline(String anchor);
}
