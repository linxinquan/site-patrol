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

/// 项目列表（多项目切换）。
final projectsProvider = FutureProvider<List<Project>>(
    (ref) => ref.watch(repositoryProvider).getProjects());

/// 当前选中的项目 id。默认取项目列表第一个；切换时写入。
final currentProjectIdProvider = StateProvider<String?>((ref) => null);

/// 当前项目（依赖 currentProjectIdProvider 选择）。
final projectProvider = FutureProvider<Project>((ref) async {
  final projects = await ref.watch(projectsProvider.future);
  final id = ref.watch(currentProjectIdProvider);
  if (id == null) return projects.first;
  return projects.firstWhere((p) => p.id == id, orElse: () => projects.first);
});

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

/// Web 调试专用：标记当前是否为「手机尺寸模拟」模式。
/// DeviceFrame 切换时写入；App 的 MaterialApp.router builder 读取后
/// 显式注入 MediaQueryData(size: Size(390, 844))，避免 FittedBox 推断尺寸
/// 触发 web release 下的边界问题。
final devicePhoneModeProvider = StateProvider<bool>((ref) => true);

/// 用户列表（头像切换用）。
final usersProvider = Provider<List<User>>((ref) => users);

/// 当前登录用户 id。默认第一个；点击头像切换时写入。
final currentUserIdProvider = StateProvider<String?>((ref) => null);

/// 当前登录用户（依赖 currentUserIdProvider）。
final currentUserProvider = Provider<User>((ref) {
  final id = ref.watch(currentUserIdProvider);
  if (id == null) return users.first;
  return users.firstWhere((u) => u.id == id, orElse: () => users.first);
});
