import '../models.dart';

/// 数据仓库抽象接口。UI 只依赖此接口。
/// 当前实现：MockRepository（dev）。后端就绪后实现 RemoteRepository（prod）。
abstract class Repository {
  Future<List<Project>> getProjects();
  Future<Project> getProject(String id);
  Future<List<Floor>> getFloors();
  Future<Map<String, Drawing>> getDrawings();
  Future<Drawing?> getDrawing(String key);
  Future<List<PhotoAnchor>> getAnchors(String floor);
  Future<List<Defect>> getDefects({DefectStatus? status});
  /// 新增一条巡场清单记录（拍照识别后由 CapturePage 调用）。
  Future<void> addDefect(Defect defect);
  Future<List<TimelinePhoto>> getTimeline(String anchor);

  /// 保存一次拍照量尺校对会话（后端落库）。dev/Mock 下为内存实现。
  Future<void> saveMeasurement(MeasureSession session);
  /// 读取某图纸的测量会话（无则返回 null）。
  Future<MeasureSession?> getMeasurement(String projectKey, String drawingKey);
}
