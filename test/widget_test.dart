import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gongdi_app/app.dart';
import 'package:gongdi_app/core/storage/local_storage.dart';
import 'package:gongdi_app/core/storage/session_store.dart';
import 'package:gongdi_app/features/auth/auth_controller.dart';

/// 内存版 LocalStorage，供单测注入（避免真实 secure_storage/Hive 依赖）。
class MemoryStorage implements LocalStorage {
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
  Future<Uint8List?> readFile(String relativePath) async => files[relativePath];
  @override
  Future<void> writeFile(String relativePath, Uint8List bytes) async =>
      files[relativePath] = bytes;
  @override
  Future<void> deleteFile(String relativePath) async =>
      files.remove(relativePath);
  @override
  Future<bool> fileExists(String relativePath) async =>
      files.containsKey(relativePath);
  @override
  Future<void> seedDrawingsIfNeeded() async {}
}

void main() {
  testWidgets('未登录进入登录页，登录后进入主页', (tester) async {
    final storage = MemoryStorage();
    final store = SessionStore(storage: storage);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionStoreProvider.overrideWithValue(store),
      ],
      child: const App(),
    ));
    await tester.pumpAndSettle();

    // 未登录 → 登录守卫重定向到登录页。
    expect(find.text('进入应用'), findsOneWidget);

    // 点击登录 → 进入主页。
    await tester.tap(find.text('进入应用'));
    await tester.pumpAndSettle();

    // 主页可能多处展示项目名，用 findsWidgets。
    expect(find.text('腾讯大铲湾 DY04 · 7栋'), findsWidgets);
  });

  test('已存在有效会话时 initAuthProvider 恢复会话', () async {
    final storage = MemoryStorage();
    await storage.writeKV(
      'session',
      '{"userId":"u1","username":"yang","displayName":"杨工","loginAt":"2026-08-13T00:00:00"}',
    );
    final store = SessionStore(storage: storage);

    final container = ProviderContainer(overrides: [
      sessionStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(container.dispose);

    await container.read(initAuthProvider.future);
    final session = container.read(authStateProvider);
    expect(session, isNotNull);
    expect(session!.username, 'yang');
    expect(session.displayName, '杨工');
  });

  test('无会话时 initAuthProvider 保持未登录', () async {
    final container = ProviderContainer(overrides: [
      sessionStoreProvider.overrideWithValue(
        SessionStore(storage: MemoryStorage()),
      ),
    ]);
    addTearDown(container.dispose);

    await container.read(initAuthProvider.future);
    expect(container.read(authStateProvider), isNull);
  });

  test('已过期会话被清除并返回未登录', () async {
    final storage = MemoryStorage();
    await storage.writeKV(
      'session',
      '{"userId":"u1","username":"yang","displayName":"杨工",'
          '"loginAt":"2026-01-01T00:00:00","expiresAt":"2026-01-02T00:00:00"}',
    );
    final store = SessionStore(storage: storage);

    final container = ProviderContainer(overrides: [
      sessionStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(container.dispose);

    await container.read(initAuthProvider.future);
    expect(container.read(authStateProvider), isNull);
    // 过期会话应已被清除。
    expect(await store.read(), isNull);
  });
}
