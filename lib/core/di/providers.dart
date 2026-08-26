import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../data/models.dart';
import '../../data/mock/mock_data.dart';
import '../../data/repository/repository.dart';
import '../../data/repository/mock_repository.dart';
import '../../data/repository/remote_repository.dart';
import '../../data/cad_service.dart';
import '../../core/env/env.dart';
import '../../core/cad/cad_calibration.dart';
import '../../core/utils/cad_coord.dart';
import '../../core/utils/speech_recognizer.dart';
import '../../core/storage/local_storage.dart';
import '../../core/storage/session_store.dart';
import '../../core/storage/patrol_plan_store.dart';

/// 数据仓库：dev 用 Mock，prod 用 Remote（后端就绪后实现）。UI 只依赖此 Provider。
final repositoryProvider = Provider<Repository>((ref) {
  return Env.isProd ? RemoteRepository() : MockRepository();
});

/// 引导态与当前选择的本地偏好（重启后保留，避免重复进入 /onboard）。
final userPrefsProvider = Provider<UserPrefs>(
  (ref) => UserPrefs(storage: LocalStorage.instance),
);

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

/// 当前是否 7栋项目（真实 CAD 图纸）。
final is7DongProjectProvider = Provider<bool>((ref) {
  final p = ref.watch(projectProvider).maybeWhen(
        data: (p) => p,
        orElse: () => allProjects.first,
      );
  return p.id == tencentProject.id;
});

/// 当前项目的图纸楼层列表（按项目区分）。
/// 7栋项目 → dy7Floors（真实 CAD）；南科大 → floors（PNG）。
final floorsProvider = FutureProvider<List<Floor>>((ref) {
  final is7 = ref.watch(is7DongProjectProvider);
  return Future.value(is7 ? dy7Floors : floors);
});

/// 当前项目的图纸字典（按项目区分）。
final drawingsProvider = FutureProvider<Map<String, Drawing>>((ref) {
  final is7 = ref.watch(is7DongProjectProvider);
  return Future.value(is7 ? dy7Drawings : drawings);
});

/// 浩辰云图 CAD 服务（图层/布局/OCF 解析）。
final cadServiceProvider = Provider<CadService>((ref) => CadService());

/// 当前图纸选中的 CAD 布局名（默认 Model 空间）。
final cadCurrentLayoutProvider = StateProvider<String?>((ref) => null);

/// 图纸对应 DWG 的 CAD 信息缓存：drawingKey -> DwgInfo。
final cadInfoProvider =
    FutureProvider.family<DwgInfo?, String>((ref, drawingKey) async {
  // 默认无真实 DWG 关联时返回 null；接入真实数据源后在此拉取。
  return null;
});

/// 坐标标注列表（巡场精度标注，按图纸分组）。
final cadAnnotationsProvider =
    StateProvider<Map<String, List<CadAnnotation>>>((ref) => {});

/// 当前是否处于「坐标标注」拾取模式（点击图纸打点）。
final cadPickModeProvider = StateProvider<bool>((ref) => false);

/// 校准参数本地存储服务（离线持久化）。
final cadCalibrationStoreProvider = Provider<CadCalibrationStore>((ref) {
  return CadCalibrationStore(LocalStorage.instance);
});

/// 校准库（多图纸批量套用：已校准图纸 key + 参数清单）。
final calibrationLibraryProvider = Provider<CalibrationLibrary>((ref) {
  return CalibrationLibrary(LocalStorage.instance);
});

/// 各图纸的坐标校准映射（内存缓存，key = drawingKey）。
/// 由图纸页在加载时通过 [loadCadCalibration] 填充；校准后通过 [saveCadCalibration] 更新。
final cadCalibrationMapProvider =
    StateProvider<Map<String, CadCoordMapper>>((ref) => {});

/// 加载指定图纸的校准映射（从本地存储读，供图纸页坐标换算）。
/// 返回 null 表示该图纸尚未校准。
Future<CadCoordMapper?> loadCadCalibration(WidgetRef ref, String drawingKey) async {
  final store = ref.read(cadCalibrationStoreProvider);
  final mapper = await store.readCalibration(drawingKey);
  if (mapper != null) {
    final map = {...ref.read(cadCalibrationMapProvider), drawingKey: mapper};
    ref.read(cadCalibrationMapProvider.notifier).state = map;
  }
  return mapper;
}

/// 保存指定图纸的校准映射（内存 + 本地持久化 + 登记进校准库）。
/// [rawJson] 为浏览器导出的原始 JSON 文本（内置演示坐标系可传 null）。
Future<void> saveCadCalibration(WidgetRef ref, String drawingKey,
    CadCoordMapper mapper, [String? rawJson]) async {
  final map = {...ref.read(cadCalibrationMapProvider), drawingKey: mapper};
  ref.read(cadCalibrationMapProvider.notifier).state = map;
  final store = ref.read(cadCalibrationStoreProvider);
  await store.saveCalibration(drawingKey, mapper);
  if (rawJson != null) {
    await store.saveRawJson(drawingKey, rawJson);
    await ref.read(calibrationLibraryProvider).upsert(drawingKey, mapper, rawJson);
  } else {
    // 内置演示坐标系：从库中移除，避免下次自动套用演示值。
    await store.deleteRawJson(drawingKey);
    await ref.read(calibrationLibraryProvider).remove(drawingKey);
  }
}

/// 删除指定图纸的校准映射（内存 + 本地 + 校准库同步移除）。
Future<void> deleteCadCalibration(WidgetRef ref, String drawingKey) async {
  final map = {...ref.read(cadCalibrationMapProvider)}..remove(drawingKey);
  ref.read(cadCalibrationMapProvider.notifier).state = map;
  final store = ref.read(cadCalibrationStoreProvider);
  await store.deleteCalibration(drawingKey);
  await store.deleteRawJson(drawingKey);
  await ref.read(calibrationLibraryProvider).remove(drawingKey);
}

/// 语音识别服务（设备端离线 ASR，支持中文；无后端/Key 依赖）。
/// UI 通过 [SpeechRecognizer] 控制录音与消费结果。
final speechRecognizerProvider = Provider<SpeechRecognizer>((ref) {
  final r = SpeechRecognizer();
  ref.onDispose(r.dispose);
  return r;
});

/// 启动期调用：把校准库清单中所有已校准图纸的坐标映射一次性灌入内存，
/// 使后续打开任意图纸自动套用，无需逐张加载或手动粘贴。
Future<void> applyCalibrationLibrary(WidgetRef ref) async {
  final all = await ref.read(calibrationLibraryProvider).buildAll();
  final current = {...ref.read(cadCalibrationMapProvider), ...all};
  ref.read(cadCalibrationMapProvider.notifier).state = current;
}

/// 启动期一次性预置：把 B05（地下室夹层组合平面图）的演示校准系数写入本地单图存储，
/// 使测量模块在全新 web 环境下也能直接走通图纸侧量距流程。
///
/// 注意：这是【演示值】——日志(08-18)记录 B05 系数含系统性恒定偏移（X 偏 0.5mm、Y 偏 1.6mm），
/// 真实精度需现场用浏览器校准弹窗重新获取并保存。本 seed 仅在「该图尚未校准」时写入，
/// 不会覆盖用户已保存的真实校准数据。
Future<void> seedDefaultCalibrations(WidgetRef ref) async {
  const b05Key = 'dy04_7_B05';
  final store = ref.read(cadCalibrationStoreProvider);
  final existing = await store.readCalibration(b05Key);
  if (existing != null) return; // 已校准过（可能是真实值），不覆盖
  final mapper = CadCoordMapper.fromAffine(
    viewWidth: 4500,
    viewHeight: 2551,
    a: 0.3308888888888889,
    b: 0,
    c: -359.3091448275862,
    d: -0.3308888888888889,
    e: 0,
    f: 852.4496763746746,
  );
  await store.saveCalibration(b05Key, mapper);
}

/// 启动期初始化 Provider（一次性触发校准 seed + 库灌入）。
final appInitProvider = FutureProvider<void>((ref) async {
  final wref = ref as WidgetRef;
  await seedDefaultCalibrations(wref);
  await applyCalibrationLibrary(wref);
});

/// 当前项目的缺陷列表（按项目区分，走 Repository 以支持新增）。
/// 7栋项目 → dy7Defects（与 7栋图纸对应的真实巡检数据）；
/// 南科大 → defects（原有 6 条）。
/// 打点新增缺陷后需调用 [refreshDefects]（invalidate）刷新。
final defectsProvider = FutureProvider<List<Defect>>((ref) async {
  final is7 = ref.watch(is7DongProjectProvider);
  // 让 MockRepository 按当前项目分组返回缺陷
  final repo = ref.read(repositoryProvider);
  if (repo is MockRepository) repo.currentIs7 = is7;
  return repo.getDefects();
});

/// 刷新缺陷列表（打点/新增缺陷后调用）。
void refreshDefects(Ref ref) {
  ref.invalidate(defectsProvider);
}

/// 缺陷列表筛选状态（null = 全部）。
final defectFilterProvider = StateProvider<DefectStatus?>((ref) => null);

/// 图纸缓存进度（key → 0~100）。初始按 mock 数据；未缓存图纸点击后模拟下载递增。
/// P4 接真实后端后改为实际下载/缓存逻辑。
final floorCacheProvider = StateProvider<Map<String, int>>((ref) => {
      for (final f in [...floors, ...dy7Floors])
        f.key: f.cached ? 100 : f.progress,
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

// ==================== 天气 ====================

/// 工地实时天气。走本地 /api/weather 代理（后端调和风天气，Key 不外泄）。
/// 未配置 Key 时后端返回 mock，前端照常渲染。
final weatherProvider = FutureProvider<WeatherInfo>((ref) async {
  const host = CadService.host;
  final proj = ref.watch(projectProvider).maybeWhen(
        data: (p) => p,
        orElse: () => null,
      );
  // 按项目位置查询天气（7栋大铲湾 / 南科大西丽，默认深圳）
  final lon = proj?.id == 'tencent-dy04-7' ? '113.9799' : '113.9699';
  final lat = proj?.id == 'tencent-dy04-7' ? '22.5936' : '22.5906';
  final name = proj?.location ?? '深圳';
  final url = Uri.parse(
      '$host/api/weather?lon=$lon&lat=$lat&name=${Uri.encodeQueryComponent(name)}');
  try {
    final resp = await http.get(url).timeout(const Duration(seconds: 8));
    if (resp.statusCode == 200) {
      final j = jsonDecode(utf8.decode(resp.bodyBytes));
      if (j is Map<String, dynamic>) {
        final w = WeatherInfo.fromJson(j);
        return WeatherInfo(
          source: w.source,
          name: name,
          temp: w.temp,
          text: w.text,
          humidity: w.humidity,
          windDir: w.windDir,
          windScale: w.windScale,
          aqi: w.aqi,
          category: w.category,
          warnings: w.warnings,
          updateTime: w.updateTime,
        );
      }
    }
  } catch (_) {}
  // 兜底：后端不可达时本地 mock
  return const WeatherInfo(
    source: 'mock',
    name: '深圳',
    temp: '32',
    text: '多云',
    humidity: '58',
    windDir: '东南风',
    windScale: '3级',
    aqi: '52',
    category: '良',
  );
});

// ==================== 巡场 ====================

/// 当前项目的巡场路线列表（持久化优先，首次为空回退项目种子）。
final patrolPlansProvider =
    FutureProvider.family<List<PatrolPlan>, String>(
  (ref, projectId) => PatrolPlanStore.list(projectId),
);

/// 当前项目的巡场历史记录列表（⑦历史用；阶段三接真实存储）。
final patrolRecordsProvider =
    FutureProvider.family<List<PatrolRecord>, String>(
  (ref, projectId) async => const [], // 阶段三实现
);
