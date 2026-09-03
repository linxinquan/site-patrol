import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gongdi_app/core/di/providers.dart';
import 'package:gongdi_app/core/storage/local_storage.dart';
import 'package:gongdi_app/data/mock/mock_data.dart';
import 'package:gongdi_app/data/models.dart';
import 'package:gongdi_app/features/capture_records/capture_records_controller.dart';

/// 内存版 LocalStorage：仅供单测注入，避开 secure_storage / Hive 平台实现。
class _MemStorage implements LocalStorage {
  final Map<String, String> kv = {};
  final Map<String, String> docs = {};
  final Map<String, Uint8List> files = {};

  @override
  Future<String?> readKV(String key) async => kv[key];
  @override
  Future<void> writeKV(String key, String value) async => kv[key] = value;
  @override
  Future<void> deleteKV(String key) async => kv.remove(key);

  @override
  Future<String?> readDoc(String key) async => docs[key];
  @override
  Future<void> writeDoc(String key, String value) async => docs[key] = value;
  @override
  Future<void> deleteDoc(String key) async => docs.remove(key);

  @override
  Future<Uint8List?> readFile(String p) async => files[p];
  @override
  Future<void> writeFile(String p, Uint8List b) async => files[p] = b;
  @override
  Future<void> deleteFile(String p) async => files.remove(p);
  @override
  Future<bool> fileExists(String p) async => files.containsKey(p);
  @override
  Future<void> seedDrawingsIfNeeded() async {}
}

/// 把记录直接灌进 LocalStorage 文档，便于 Notifier 加载。
Future<void> _seedDoc(_MemStorage s, List<Map<String, dynamic>> records) async {
  await s.writeDoc(
    CaptureRecordsNotifier.storageKey,
    jsonEncode(records),
  );
}

Map<String, dynamic> _entry({
  required String id,
  required String drawingKey,
  required String floor,
  String? ts,
  String anchor = '西楼1F',
  String note = '',
  String? photo,
  List<Map<String, dynamic>>? defects,
}) {
  final tsNow = ts ?? DateTime.now().toIso8601String();
  return {
    'id': id,
    'drawingKey': drawingKey,
    'worldX': 100.0,
    'worldY': 200.0,
    'ts': tsNow,
    'anchor': anchor,
    'floor': floor,
    'count': defects?.length ?? 0,
    'defects': defects ??
        [
          {
            'name': '墙面空鼓',
            'severity': 'orange',
            'conf': 0.91,
            'desc': '空鼓面积约 0.4㎡',
            'status': 'pending',
          },
        ],
    'note': note,
    'photo': photo,
  };
}

ProviderContainer _makeContainer({
  required _MemStorage storage,
  required Map<String, Drawing> drawings,
}) {
  return ProviderContainer(
    overrides: [
      // drawingsProvider 是 FutureProvider，overrideWithValue 让同步读取即可拿到值
      drawingsProvider.overrideWith((ref) async => drawings),
    ],
  );
}

void main() {
  group('applyRecordsFilter 二次筛选', () {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    String todayTs() => DateTime.now().toIso8601String();
    String oldTs(int daysAgo) =>
        todayStart.subtract(Duration(days: daysAgo)).toIso8601String();

    final records = [
      _entry(
          id: 'r1',
          drawingKey: 'dy04_7_B05',
          floor: 'B1',
          ts: todayTs(),
          defects: [
            {'name': 'a', 'severity': 'orange', 'conf': 0.9, 'status': 'pending'},
          ]),
      _entry(
          id: 'r2',
          drawingKey: 'dy04_7_B05',
          floor: 'B1',
          ts: oldTs(2),
          defects: []),
      _entry(
          id: 'r3',
          drawingKey: 'dy04_7_B05',
          floor: '2F',
          ts: todayTs(),
          defects: []),
    ];

    test('全部时间：包含全部 3 条', () {
      final out = applyRecordsFilter(records, const CaptureRecordsFilter());
      expect(out.length, 3);
    });

    test('今日窗口：仅返回今日 ts 的记录', () {
      final out = applyRecordsFilter(
        records,
        const CaptureRecordsFilter(time: RecordTimeRange.today),
      );
      final ids = out.map((e) => e['id']).toList();
      expect(ids, containsAll(['r1', 'r3']));
      expect(ids, isNot(contains('r2')));
    });

    test('本周窗口：包含今日 + 6 天内（r2 在 2 天前）', () {
      final out = applyRecordsFilter(
        records,
        const CaptureRecordsFilter(time: RecordTimeRange.week),
      );
      expect(out.length, 3);
    });

    test('楼层过滤：仅 floor == "2F"', () {
      final out = applyRecordsFilter(
        records,
        const CaptureRecordsFilter(floor: '2F'),
      );
      expect(out.length, 1);
      expect(out.first['id'], 'r3');
    });

    test('AI 仅：defects.length > 0', () {
      final out = applyRecordsFilter(
        records,
        const CaptureRecordsFilter(aiOnly: true),
      );
      expect(out.length, 1);
      expect(out.first['id'], 'r1');
    });

    test('组合：今日 + 2F + AI 仅 → 0 条（r3 无 defects）', () {
      final out = applyRecordsFilter(
        records,
        const CaptureRecordsFilter(
            time: RecordTimeRange.today, floor: '2F', aiOnly: true),
      );
      expect(out, isEmpty);
    });
  });

  group('buildDefectFromCaptureDefect 转工单映射', () {
    final capture = {
      'id': 'cap_001',
      'drawingKey': 'dy04_7_B05',
      'worldX': 100.0,
      'worldY': 200.0,
      'anchor': '西楼1F-左病房翼',
      'floor': '西楼1F',
      'ts': '2026-08-08 14:32',
      'note': '现场观察',
      'photo': 'capture/cap_001.jpg',
    };
    final vl = {
      'name': '墙面空鼓',
      'severity': 'red',
      'conf': 0.92,
      'desc': '空鼓约 0.4㎡',
      'status': 'pending',
    };

    test('字段映射一致（id 拼接 / severity / sourceCaptureId / photos）', () {
      final d = buildDefectFromCaptureDefect(
          capture: capture, vlDefect: vl, idx: 2);
      expect(d.id, 'cap_001#2');
      expect(d.type, '墙面空鼓');
      expect(d.severity, DefectSeverity.red);
      expect(d.status, DefectStatus.draft);
      expect(d.part, '西楼1F-左病房翼');
      expect(d.floor, '西楼1F');
      expect(d.ts, '2026-08-08 14:32');
      expect(d.seed, 'capture_convert');
      expect(d.reporter, '验收记录');
      expect(d.tags, ['验收转工单', '验收#cap_001']);
      expect(d.photos, ['capture/cap_001.jpg']);
      expect(d.sourceCaptureId, 'cap_001');
      expect(d.drawingKey, 'dy04_7_B05');
      expect(d.worldX, 100.0);
      expect(d.worldY, 200.0);
      expect(d.category, DefectCategory.other);
      expect(d.note, '现场观察｜空鼓约 0.4㎡');
    });

    test('severity 解析失败时回落 orange', () {
      final d = buildDefectFromCaptureDefect(
          capture: capture,
          vlDefect: {...vl, 'severity': 'foo'},
          idx: 0);
      expect(d.severity, DefectSeverity.orange);
    });

    test('desc 为空时 note 不拼接分隔符', () {
      final d = buildDefectFromCaptureDefect(
        capture: capture,
        vlDefect: {...vl, 'desc': null},
        idx: 0,
      );
      expect(d.note, '现场观察');
    });

    test('photo 为空时 photos 为空数组', () {
      final d = buildDefectFromCaptureDefect(
        capture: {...capture, 'photo': null},
        vlDefect: vl,
        idx: 0,
      );
      expect(d.photos, isEmpty);
    });
  });

  group('CaptureRecordsNotifier 行为', () {
    late _MemStorage storage;

    setUp(() {
      storage = _MemStorage();
    });

    test('加载：从文档读取 + ts 倒序 + 按当前项目图纸过滤', () async {
      final older = _entry(
        id: 'r1',
        drawingKey: 'dy04_7_B05',
        floor: 'B1',
        ts: DateTime.now()
            .subtract(const Duration(days: 2))
            .toIso8601String(),
      );
      final newer = _entry(
        id: 'r2',
        drawingKey: 'dy04_7_B05',
        floor: 'B1',
        ts: DateTime.now().toIso8601String(),
      );
      // 跨项目记录：drawingKey 不在当前项目图纸集合中，应被过滤掉
      final other = _entry(
        id: 'r3',
        drawingKey: 'B-does-not-exist',
        floor: 'X',
        ts: DateTime.now().toIso8601String(),
      );
      await _seedDoc(storage, [older, newer, other]);

      final container = _makeContainer(
        storage: storage,
        drawings: dy7Drawings,
      );
      addTearDown(container.dispose);

      // 通过容器直接构造 Notifier，注入 storage，绕开 provider override（不暴露 captureRecordsStorageProvider）。
      final notifier =
          CaptureRecordsNotifier(container, storage: storage);
      await Future<void>.delayed(Duration.zero); // 等 _load 完成

      final state = notifier.value;
      // ts 倒序：newer 在前
      expect(state.map((e) => e['id']), ['r2', 'r1']);
      // 跨项目记录被过滤
      expect(state.any((e) => e['id'] == 'r3'), isFalse);
    });

    test('deleteById：从文档移除 + 删除照片 + 更新 state', () async {
      await storage.writeFile('capture/r1.jpg', Uint8List.fromList([1, 2, 3]));
      await _seedDoc(storage, [
        _entry(id: 'r1', drawingKey: 'dy04_7_B05', floor: 'B1',
            photo: 'capture/r1.jpg'),
        _entry(id: 'r2', drawingKey: 'dy04_7_B05', floor: 'B1'),
      ]);

      final container = _makeContainer(
        storage: storage,
        drawings: dy7Drawings,
      );
      addTearDown(container.dispose);
      final notifier =
          CaptureRecordsNotifier(container, storage: storage);
      await Future<void>.delayed(Duration.zero);

      await notifier.deleteById('r1');

      // state 中已无 r1
      expect(notifier.value.any((e) => e['id'] == 'r1'), isFalse);
      // 文档已重写：只剩 r2
      final raw = await storage.readDoc(CaptureRecordsNotifier.storageKey);
      final list = jsonDecode(raw!) as List;
      expect(list.length, 1);
      expect((list.first as Map)['id'], 'r2');
      // 照片文件已删除
      expect(await storage.fileExists('capture/r1.jpg'), isFalse);
    });

    test('markDefectConverted：写回文档 + 更新 state + 第二次调用 false', () async {
      final entry = _entry(id: 'cap_x', drawingKey: 'dy04_7_B05', floor: 'B1');
      await _seedDoc(storage, [entry]);

      final container = _makeContainer(
        storage: storage,
        drawings: dy7Drawings,
      );
      addTearDown(container.dispose);
      final notifier =
          CaptureRecordsNotifier(container, storage: storage);
      await Future<void>.delayed(Duration.zero);

      final ok1 = await notifier.markDefectConverted('cap_x', 0);
      expect(ok1, isTrue);

      // state 中缺陷 status 已变成 converted
      final defects = notifier.value.first['defects'] as List;
      expect(defects.first['status'], 'converted');

      // 第二次调用：已为 converted，返回 false
      final ok2 = await notifier.markDefectConverted('cap_x', 0);
      expect(ok2, isFalse);
    });

    test('markDefectConverted 不存在的 captureId：返回 false 不抛', () async {
      await _seedDoc(storage, [_entry(id: 'cap_x', drawingKey: 'dy04_7_B05', floor: 'B1')]);

      final container = _makeContainer(
        storage: storage,
        drawings: dy7Drawings,
      );
      addTearDown(container.dispose);
      final notifier =
          CaptureRecordsNotifier(container, storage: storage);
      await Future<void>.delayed(Duration.zero);

      final ok = await notifier.markDefectConverted('no_such', 0);
      expect(ok, isFalse);
    });

    test('markDefectConverted 越界 idx：返回 false', () async {
      await _seedDoc(storage, [_entry(id: 'cap_x', drawingKey: 'dy04_7_B05', floor: 'B1')]);

      final container = _makeContainer(
        storage: storage,
        drawings: dy7Drawings,
      );
      addTearDown(container.dispose);
      final notifier =
          CaptureRecordsNotifier(container, storage: storage);
      await Future<void>.delayed(Duration.zero);

      final ok = await notifier.markDefectConverted('cap_x', 99);
      expect(ok, isFalse);
    });
  });
}