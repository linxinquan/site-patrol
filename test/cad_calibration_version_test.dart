import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:gongdi_app/core/cad/cad_calibration.dart';
import 'package:gongdi_app/core/storage/local_storage.dart';
import 'package:gongdi_app/core/utils/cad_coord.dart';

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

/// 校准「绑版本」的存储约定与**旧数据迁移**。
///
/// 这组测试守的是演示/现场路径：版本化之前已在手机上校准过的图纸
/// （旧 `cad_calib_v3_<key>` 键），升级后必须仍能读到同一套系数，
/// 否则驻场打开图纸会突然变成「未校准」，打点坐标全部失效。
void main() {
  late _MemStorage storage;
  late CadCalibrationStore store;

  final mapperV1 = CadCoordMapper.fromAffine(
    viewWidth: 2400,
    viewHeight: 1698,
    a: 30,
    c: 100,
    d: -30,
    f: 48000,
  );

  setUp(() {
    storage = _MemStorage();
    store = CadCalibrationStore(storage);
  });

  group('CadCalibrationStore 版本分档', () {
    test('保存 v1 后：读 v1 命中，读 v2 为 null（版本隔离）', () async {
      await store.saveCalibration('B05', mapperV1, versionId: 'v1');
      final hit = await store.readCalibration('B05', versionId: 'v1');
      expect(hit, isNotNull);
      expect(hit!.a, 30);
      expect(hit.viewWidth, 2400);

      final miss = await store.readCalibration('B05', versionId: 'v2');
      expect(miss, isNull, reason: '不同版本不得套用同一校准');
    });

    test('未版本化图纸用 __unversioned 档位，读回一致', () async {
      await store.saveCalibration('B05', mapperV1);
      expect(storage.docs.containsKey('cad_calib_v4_B05__unversioned'), isTrue);
      final back = await store.readCalibration('B05');
      expect(back?.a, 30);
    });

    test('删除指定版本不影响其他版本', () async {
      await store.saveCalibration('B05', mapperV1, versionId: 'v1');
      await store.saveCalibration('B05', mapperV1, versionId: 'v2');
      await store.deleteCalibration('B05', versionId: 'v2');
      expect(await store.readCalibration('B05', versionId: 'v1'), isNotNull);
      expect(await store.readCalibration('B05', versionId: 'v2'), isNull);
    });
  });

  group('旧数据（v3）兼容迁移', () {
    test('读到旧键 → 返回同套系数并迁移到 v4 键', () async {
      // 版本化之前的现场数据：按 drawingKey 存，无版本。
      await storage.writeDoc(
        'cad_calib_v3_B05',
        '{"imgW":2400,"imgH":1698,"a":30,"b":0,"c":100,"d":-30,"e":0,"f":48000}',
      );

      final migrated = await store.readCalibration('B05', versionId: 'v1');
      expect(migrated, isNotNull, reason: '旧校准必须仍可读，否则演示/现场会突然未校准');
      expect(migrated!.a, 30);
      expect(migrated.f, 48000);

      // 已迁移到 v4 版本档位；旧键保留（不删，便于回溯与降级）。
      expect(storage.docs.containsKey('cad_calib_v4_B05__v1'), isTrue);
      expect(storage.docs.containsKey('cad_calib_v3_B05'), isTrue);
    });

    test('未版本化图纸也做迁移（落到 __unversioned 档）', () async {
      await storage.writeDoc('cad_calib_v3_B05', '{"imgW":1,"imgH":1,"a":2}');
      final m = await store.readCalibration('B05');
      expect(m?.a, 2);
      expect(storage.docs.containsKey('cad_calib_v4_B05__unversioned'), isTrue);
    });

    test('原始 JSON（弹窗预填）同样兼容迁移', () async {
      await storage.writeDoc('cad_calib_v3_raw_B05', '{"share":"abc"}');
      final raw = await store.readRawJson('B05', versionId: 'v1');
      expect(raw, '{"share":"abc"}');
      expect(storage.docs.containsKey('cad_calib_v4_B05__v1__raw'), isTrue);
    });

    test('未版本化时删除会一并清理旧键（清除校准 = 真清干净）', () async {
      await storage.writeDoc('cad_calib_v3_B05', '{"a":1}');
      await store.deleteCalibration('B05');
      expect(await store.readCalibration('B05'), isNull);
      expect(storage.docs.containsKey('cad_calib_v3_B05'), isFalse);
    });

    test('损坏的旧数据不抛异常，按未校准处理', () async {
      await storage.writeDoc('cad_calib_v3_B05', 'not-json');
      expect(await store.readCalibration('B05', versionId: 'v1'), isNull);
      await storage.writeDoc('cad_calib_v3_B05', '[1,2,3]');
      expect(await store.readCalibration('B05', versionId: 'v1'), isNull);
    });
  });

  group('CalibrationLibrary 版本校验', () {
    test('校准版本与当前版本不一致 → 跳过（需重校）', () async {
      final lib = CalibrationLibrary(storage);
      await lib.upsert('B05', mapperV1, null, drawingVersionId: 'v1');

      final stale = await lib.buildAll(currentVersions: {'B05': 'v2'});
      expect(stale.containsKey('B05'), isFalse);

      final fresh = await lib.buildAll(currentVersions: {'B05': 'v1'});
      expect(fresh['B05']?.a, 30);
    });

    test('未版本化（expected 为空串）不拦截，保证演示图仍自动套用', () async {
      final lib = CalibrationLibrary(storage);
      await lib.upsert('B05', mapperV1, null); // 校准时的版本 = ''

      final all = await lib.buildAll(currentVersions: {'B05': ''});
      expect(all.containsKey('B05'), isTrue);
      expect(all['B05']?.a, 30);
    });

    test('图纸不在当前图纸表（expected 为 null）不拦截', () async {
      final lib = CalibrationLibrary(storage);
      await lib.upsert('B05', mapperV1, null, drawingVersionId: 'v1');
      final all = await lib.buildAll(currentVersions: {'其它图': 'v9'});
      expect(all.containsKey('B05'), isTrue);
    });

    test('传 null 关闭版本校验（旧行为）', () async {
      final lib = CalibrationLibrary(storage);
      await lib.upsert('B05', mapperV1, null, drawingVersionId: 'v1');
      final all = await lib.buildAll();
      expect(all.containsKey('B05'), isTrue);
    });

    test('raw JSON 与版本一起登记，可回填弹窗', () async {
      final lib = CalibrationLibrary(storage);
      await lib.upsert('B05', mapperV1, '{"share":"x"}', drawingVersionId: 'v1');
      expect(await lib.readRaw('B05'), '{"share":"x"}');
    });
  });
}
