import '../models.dart';
import 'repository.dart';

/// 真实后端实现（stub）。后端就绪后填充 Dio/retrofit 调用与 DTO 反序列化。
/// 切换方式：用 `--dart-define=ENV=prod` 构建，DI 会自动注入本类。
class RemoteRepository implements Repository {
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
  Future<List<TimelinePhoto>> getTimeline(String anchor) =>
      throw UnimplementedError('RemoteRepository.getTimeline 待实现');
}
