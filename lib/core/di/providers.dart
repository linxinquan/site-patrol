import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models.dart';
import '../../data/mock/mock_data.dart';
import '../../data/repository/repository.dart';
import '../../data/repository/mock_repository.dart';
import '../../data/repository/remote_repository.dart';
import '../../core/env/env.dart';

/// 数据仓库：dev 用 Mock，prod 用 Remote（后端就绪后实现）。UI 只依赖此 Provider。
final repositoryProvider = Provider<Repository>((ref) {
  return Env.isProd ? RemoteRepository() : MockRepository();
});

final projectProvider =
    FutureProvider<Project>((ref) => ref.watch(repositoryProvider).getProject());

final floorsProvider =
    FutureProvider<List<Floor>>((ref) => ref.watch(repositoryProvider).getFloors());

final drawingsProvider = FutureProvider<Map<String, Drawing>>(
    (ref) => ref.watch(repositoryProvider).getDrawings());

final defectsProvider =
    FutureProvider<List<Defect>>((ref) => ref.watch(repositoryProvider).getDefects());

/// 缺陷列表筛选状态（null = 全部）。
final defectFilterProvider = StateProvider<DefectStatus?>((ref) => null);

/// 图纸缓存进度（key → 0~100）。初始按 mock 数据；未缓存图纸点击后模拟下载递增。
/// P4 接真实后端后改为实际下载/缓存逻辑。
final floorCacheProvider = StateProvider<Map<String, int>>((ref) => {
      for (final f in floors) f.key: f.cached ? 100 : f.progress,
    });
