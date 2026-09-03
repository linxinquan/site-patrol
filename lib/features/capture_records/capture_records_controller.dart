import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/local_storage.dart';
import '../../core/di/providers.dart';
import '../../data/models.dart';

/// 验收记录筛选：时间窗口 + 楼层 + AI 状态。
///
/// `time` 默认 [RecordTimeRange.all]；`floor` 与 `aiOnly` 默认空（不过滤）。
/// 复制时使用 [copyWith]；清空楼层请传 `clearFloor: true`。
class CaptureRecordsFilter {
  const CaptureRecordsFilter({
    this.time = RecordTimeRange.all,
    this.floor,
    this.aiOnly = false,
  });

  final RecordTimeRange time;
  final String? floor;

  /// 是否仅展示「识别到 AI 缺陷」的记录（defects.length > 0）。
  final bool aiOnly;

  CaptureRecordsFilter copyWith({
    RecordTimeRange? time,
    String? floor,
    bool? aiOnly,
    bool clearFloor = false,
  }) {
    return CaptureRecordsFilter(
      time: time ?? this.time,
      floor: clearFloor ? null : (floor ?? this.floor),
      aiOnly: aiOnly ?? this.aiOnly,
    );
  }
}

enum RecordTimeRange { all, today, week }

/// 验收记录仓库：写真实来源是 [LocalStorage] 的 `stored_vision_results` 文档。
///
/// 内存态约定：
/// - `_all` 始终为「当前项目」过滤 + ts 倒序后的全量数据；
/// - 切换项目（[is7DongProjectProvider]）通过 `ref.listen` 自动重过滤；
/// - 删除/转工单只对 `_all` 操作，写回 LocalStorage 时按 id 精确删除（保留
///   其他项目/其他记录的 entry），避免误删；
/// - 时间/楼层/AI 筛选为纯函数 [applyFilter]，由页面消费时即时计算。
class CaptureRecordsNotifier
    extends StateNotifier<List<Map<String, dynamic>>> {
  CaptureRecordsNotifier(this.ref, {LocalStorage? storage})
      : _storage = storage ?? LocalStorage.instance,
        super(const []) {
    _load();
    ref.listen<bool>(is7DongProjectProvider, (_, __) => _load());
  }

  final Ref ref;
  final LocalStorage _storage;

  /// 与 `capture_page.dart` 的 `_storageKey` 保持一致。
  static const String storageKey = 'stored_vision_results';

  Future<void> reload() async {
    await _load();
  }

  /// 按 id 删除一条记录：清理照片文件 + 写回文档 + 更新 state。
  /// 写回时按全文档重新移除匹配 id，确保不丢失其他项目/其他记录的 entry。
  Future<void> deleteById(String id) async {
    final raw = await _storage.readDoc(storageKey);
    if (raw == null || raw.isEmpty) {
      state = const [];
      return;
    }
    List<dynamic> decoded;
    try {
      final v = jsonDecode(raw);
      if (v is! List) {
        state = const [];
        return;
      }
      decoded = v;
    } catch (_) {
      state = const [];
      return;
    }

    Map<String, dynamic>? target;
    for (final e in decoded) {
      if (e is Map && e['id']?.toString() == id) {
        target = e.cast<String, dynamic>();
        break;
      }
    }
    final remaining = decoded
        .where((e) => e is! Map || e['id']?.toString() != id)
        .toList();

    // 写回：必须先写文档，再清理照片（写失败时不删照片，可恢复）。
    try {
      await _storage.writeDoc(storageKey, jsonEncode(remaining));
    } catch (_) {
      // 写失败时跳过照片清理，保证数据完整性优先。
      return;
    }

    final photo = target?['photo']?.toString();
    if (photo != null && photo.isNotEmpty) {
      try {
        await _storage.deleteFile(photo);
      } catch (_) {/* 文件可能不存在，忽略 */}
    }

    state = state.where((e) => e['id']?.toString() != id).toList();
  }

  /// 就地回写指定记录的 `defects[idx].status` 为 `'converted'`
  /// （验收转工单成功时调用）；同时持久化到 LocalStorage。
  /// 返回是否成功（id 命中且原本 status 不是 converted）。
  Future<bool> markDefectConverted(String captureId, int idx) async {
    final raw = await _storage.readDoc(storageKey);
    if (raw == null || raw.isEmpty) return false;
    List<dynamic> decoded;
    try {
      final v = jsonDecode(raw);
      if (v is! List) return false;
      decoded = v;
    } catch (_) {
      return false;
    }

    bool changed = false;
    for (final e in decoded) {
      if (e is! Map) continue;
      if (e['id']?.toString() != captureId) continue;
      final defects = e['defects'];
      if (defects is! List || idx < 0 || idx >= defects.length) return false;
      final target = defects[idx];
      if (target is! Map) return false;
      if (target['status']?.toString() == 'converted') return false;
      target['status'] = 'converted';
      changed = true;
      break;
    }
    if (!changed) return false;

    await _storage.writeDoc(storageKey, jsonEncode(decoded));
    // 更新 state（按 id 找到对应 entry 后深拷贝 defects）。
    state = [
      for (final e in state)
        if (e['id']?.toString() == captureId)
          _withDefectStatus(e, idx, 'converted')
        else
          e,
    ];
    return true;
  }

  Map<String, dynamic> _withDefectStatus(
    Map<String, dynamic> src,
    int idx,
    String status,
  ) {
    final next = Map<String, dynamic>.from(src);
    final ds = src['defects'];
    if (ds is List) {
      next['defects'] = [
        for (var i = 0; i < ds.length; i++)
          if (i == idx && ds[i] is Map)
            (Map<String, dynamic>.from(ds[i] as Map))..['status'] = status
          else
            ds[i],
      ];
    }
    return next;
  }

  Future<void> _load() async {
    final raw = await _storage.readDoc(storageKey);
    if (raw == null || raw.isEmpty) {
      state = const [];
      return;
    }
    List<dynamic> decoded;
    try {
      final v = jsonDecode(raw);
      if (v is! List) {
        state = const [];
        return;
      }
      decoded = v;
    } catch (_) {
      state = const [];
      return;
    }
    final list = decoded
        .whereType<Map>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
    final filtered = _applyProjectFilter(list);
    filtered.sort((a, b) => _tsOf(b).compareTo(_tsOf(a)));
    state = filtered;
  }

  List<Map<String, dynamic>> _applyProjectFilter(
    List<Map<String, dynamic>> all,
  ) {
    final drawings = ref.read(drawingsProvider);
    // 异步未就绪时不过滤，避免误丢；下次项目切换再纠正。
    if (!drawings.hasValue) return all;
    final keys = drawings.requireValue.keys.toSet();
    if (keys.isEmpty) return all;
    return all.where((e) {
      final k = e['drawingKey']?.toString() ?? '';
      // 无 drawingKey 的记录视为未关联，保留（兼容历史数据）。
      return k.isEmpty || keys.contains(k);
    }).toList();
  }
}

/// ts 转毫秒：`capture_page.dart` 写入的 ts 形如 `YYYY-MM-DD HH:mm:ss`，
/// 替换首空格为 `T` 后 `DateTime.parse`。
int recordTsMillis(Map<String, dynamic> e) {
  final t = e['ts']?.toString() ?? '';
  if (t.isEmpty) return 0;
  final iso = t.contains('T') ? t : t.replaceFirst(' ', 'T');
  return DateTime.tryParse(iso)?.millisecondsSinceEpoch ?? 0;
}

/// 纯函数：按 [CaptureRecordsFilter] 二次过滤。
List<Map<String, dynamic>> applyRecordsFilter(
  List<Map<String, dynamic>> records,
  CaptureRecordsFilter f,
) {
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final weekStart = todayStart.subtract(const Duration(days: 6));
  return records.where((e) {
    final ts = recordTsMillis(e);
    if (ts > 0) {
      final dt = DateTime.fromMillisecondsSinceEpoch(ts);
      switch (f.time) {
        case RecordTimeRange.today:
          if (dt.isBefore(todayStart)) return false;
          break;
        case RecordTimeRange.week:
          if (dt.isBefore(weekStart)) return false;
          break;
        case RecordTimeRange.all:
          break;
      }
    }
    if (f.floor != null && f.floor!.isNotEmpty) {
      if ((e['floor']?.toString() ?? '') != f.floor) return false;
    }
    if (f.aiOnly) {
      final ds = e['defects'];
      if (ds is! List || ds.isEmpty) return false;
    }
    return true;
  }).toList();
}

/// 内部使用：Notifier 私有。
  int _tsOf(Map<String, dynamic> e) => recordTsMillis(e);

/// 转工单 Defect 构造：从一条拍照验收 entry + 其 AI 缺陷条目，构造可写入缺陷库的 Defect。
///
/// - `id` = `${captureId}#$idx`（保证唯一 + 可追溯回验收记录）
/// - `type` 取 `vlDefect.name`；`severity` 从字符串解析，解析失败回落到 orange
/// - `status` = draft，`seed` = 'capture_convert'
/// - `reporter` = '验收记录'；`tags` = ['验收转工单', '验收#${captureId}']
/// - `photos` = `[capture.photo]`（如非空），`sourceCaptureId` = capture.id
/// - `note` 拼接 `${capture.note}｜${vlDefect.desc ?? ''}`
/// - `drawingKey/worldX/worldY` 透传（用于图纸回溯）
/// - `gps/alt/resp` 置空串（验收记录无 GPS / 责任信息，由 /defects 后续录入）
Defect buildDefectFromCaptureDefect({
  required Map<String, dynamic> capture,
  required Map<String, dynamic> vlDefect,
  required int idx,
  String? captureIdOverride,
}) {
  final captureId = captureIdOverride ?? capture['id']?.toString() ?? '';
  final anchor = capture['anchor']?.toString() ?? '';
  final floor = capture['floor']?.toString() ?? '';
  final ts = capture['ts']?.toString() ?? '';
  final note = capture['note']?.toString() ?? '';
  final photo = capture['photo']?.toString();
  final desc = vlDefect['desc']?.toString();
  final drawingKey = capture['drawingKey']?.toString();
  final worldX = (capture['worldX'] as num?)?.toDouble();
  final worldY = (capture['worldY'] as num?)?.toDouble();

  return Defect(
    id: '$captureId#$idx',
    part: anchor.isEmpty ? '验收点' : anchor,
    type: vlDefect['name']?.toString() ?? '未分类',
    category: DefectCategory.other,
    severity: _parseSeverityString(vlDefect['severity']?.toString()),
    status: DefectStatus.draft,
    anchor: anchor,
    floor: floor,
    ts: ts,
    gps: '',
    alt: '',
    resp: '',
    reporter: '验收记录',
    tags: ['验收转工单', '验收#$captureId'],
    note: desc == null || desc.isEmpty ? note : '$note｜$desc',
    seed: 'capture_convert',
    drawingKey: drawingKey,
    worldX: worldX,
    worldY: worldY,
    photos: photo == null || photo.isEmpty ? const [] : [photo],
    sourceCaptureId: captureId,
  );
}

/// 解析 severity 字符串（'red'/'orange'/'yellow'/'green'）为枚举；解析失败回落到 orange。
DefectSeverity _parseSeverityString(String? s) {
  if (s == null) return DefectSeverity.orange;
  return DefectSeverity.values.firstWhere(
    (v) => v.name == s,
    orElse: () => DefectSeverity.orange,
  );
}