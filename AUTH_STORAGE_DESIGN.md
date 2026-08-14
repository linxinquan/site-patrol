# 工地验收 App · 登录与本地存储方案设计

> 状态：**S1/S2 已实施，S3–S5 待实施**。最后更新 2026-08-13。
> 对应工程：`D:\code\gongdi\flutter_app`（南方科技大学附属医院/校本部 · 工地验收）。

---

## 0. 决策摘要（已与用户确认）

| # | 议题 | 结论 |
|---|---|---|
| 1 | 存储位置 | **全本地存储优先**，暂不依赖后端 |
| 2 | 目标平台 | **iOS 为主**，Android 同构；**Web 兼容**（预览降级） |
| 3 | 登录实现 | **S2 已建会话层与登录守卫**；S3 补预置用户校验（本文件） |
| 4 | 测试规模 | 3 个用户内测 |
| 5 | 项目图纸 | 提前准备好，**随包预置**（assets → 首次启动拷贝本地，S1 已实现） |
| 6 | 数据形态 | 登录信息 / 图纸大文件 / 标记数据 / 拍照图片 / AI 生成文字 |

---

## 1. 存储层总体架构

```
┌─────────────────────────────────────────────┐
│            业务层（页面 / Provider）           │
│      只依赖 Repository 抽象接口，平台无感      │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────▼──────────────────────────┐
│            LocalStorage 抽象接口              │
│   readKV / writeKV / deleteKV / readFile /   │
│   writeFile / deleteFile                     │
└──────┬──────────────────────────┬───────────┘
       │ 条件导入                    │ 条件导入
┌──────▼───────────┐   ┌──────────▼───────────┐
│ 移动端 iOS/Android │   │      Web（降级）       │
│ · secure_storage  │   │ · WebCrypto 加密 KV   │
│ · Hive（结构化）   │   │ · IndexedDB（KV+Blob） │
│ · path_provider   │   │ · 无文件系统           │
│   （大文件）        │   │                      │
└──────────────────┘   └──────────────────────┘
```

- **业务代码零平台分支**：用 Dart 条件导入（`app_storage_io.dart` / `app_storage_web.dart`）在编译期选定实现。
- iOS 是主力，全量功能本地存储；Web 仅预览，同一接口降级实现。

---

## 2. 存储选型映射

| 数据 | 移动端（iOS/Android） | Web（兼容/预览） |
|---|---|---|
| 登录会话（token/用户信息） | flutter_secure_storage（Keychain/Keystore 加密） | WebCrypto 加密后存 Web Storage（容量小，仅会话级） |
| 标记数据（锚点/缺陷/识别结果） | **Hive**（本地 DB 文件，JSON 直接存） | Hive 的 IndexedDB 后端（或 IndexedDB 直存） |
| 项目图纸（大文件） | path_provider + File（Documents/drawings/） | IndexedDB 存 Blob（预览降级，不保证大图纸） |
| 拍照图片 | path_provider + File（Documents/photos/，压缩后存） | IndexedDB 存 Blob（容量受限，仅演示） |
| AI 生成文字 | Hive（复用 VisionResult.toJson/fromJson） | IndexedDB（同上） |

> 选型理由：Hive 是纯 Dart 嵌入式数据库，跑在 App 进程内、数据在设备本地，**不是后端数据库**——没有网络接口、不支持多用户并发；个人设备数据放本地，账号/同步/多端一致性才属于后端。当前单设备离线验收场景天然是本地存储。

---

## 3. 登录方案设计

### 3.1 登录模式演进

| 阶段 | 模式 | 说明 |
|---|---|---|
| 测试期（当前） | **本地登录（预置用户）** | 内置 3 个测试账号，输入用户名/密码校验通过后生成本地会话 |
| 正式期（后端就绪） | **后端认证（JWT）** | `POST /auth/login` 换取 access/refresh token，本地只存 token |

设计上**按正式期模式建模**：本地登录只是"校验来源"不同，会话模型、存储、守卫完全一致，后端就绪后只替换校验逻辑。

### 3.2 会话数据模型（建议）

```dart
class UserSession {
  final String userId;      // 唯一标识（测试期固定 id，正式期后端下发）
  final String username;    // 登录名
  final String displayName; // 显示名（如「杨工」）
  final String? token;      // 测试期可为空/固定串；正式期 access token
  final String? refreshToken; // 正式期用于续期
  final DateTime loginAt;
  final DateTime? expiresAt;  // 过期时间（null = 长期有效）
}
```

### 3.3 登录流程

```
App 启动
  ├─ 读取本地会话（移动端 secure_storage / Web 加密 KV）
  │    ├─ 有且未过期 → 直接进入 /home（免登录）
  │    └─ 无 / 已过期 → 进入 /login
  └─ /login 输入用户名+密码
       ├─ 本地校验（测试期：比对预置 3 用户）
       └─ 校验通过 → 生成 UserSession → 写入本地存储 → 跳转 /home
```

### 3.4 登出流程

```
用户点击登出
  ├─ 清除本地会话（secure_storage / Web KV）
  ├─ 清除内存中的 Riverpod 会话状态（authStateProvider 置 null）
  └─ GoRouter redirect 自动回到 /login
```

> 登出**不清除**图纸、标记、照片等业务数据，仅清会话；后续可加"清除所有本地数据"按钮（含图纸拷贝目录）。

### 3.5 会话状态管理（Riverpod + GoRouter）

```dart
// 会话状态：null = 未登录；UserSession = 已登录
final authStateProvider = StateProvider<UserSession?>((ref) => null);

// 初始化时从本地存储恢复会话（main 里 await 一次）
final initAuthProvider = FutureProvider<void>((ref) async {
  final session = await LocalStorage.instance.readSession();
  ref.read(authStateProvider.notifier).state = session;
});
```

```dart
// GoRouter 登录守卫
redirect: (context, state) {
  final loggedIn = ref.read(authStateProvider) != null;
  final onLogin = state.matchedLocation == '/login';
  if (!loggedIn && !onLogin) return '/login';
  if (loggedIn && onLogin) return '/home';
  return null;
},
```

### 3.6 安全设计

| 项 | 移动端 | Web |
|---|---|---|
| token/密码存储 | flutter_secure_storage（系统级加密） | WebCrypto AES 加密后存储（浏览器无 Keychain 等价物） |
| 明文落盘 | 禁止（密码/refresh token 不入 Hive、不入文件） | 同左 |
| 会话过期 | expiresAt 校验，过期自动登出 | 同左 |
| 生物识别（可选） | iOS 支持 local_auth 二次解锁（P6 可选） | 不支持 |

> ⚠️ 明确边界：**标记数据/图纸/照片是业务数据，可明文本地存储；登录凭证是敏感数据，必须加密存储**。两者物理隔离（不同存储介质/目录）。

---

## 4. 目录与依赖规划

### 4.1 代码目录（S1/S2 已落地）

```
lib/core/storage/
  ├── local_storage.dart        # ✅ 抽象接口（条件导入入口）
  ├── app_storage_io.dart       # ✅ 移动端实现（secure_storage + Hive + path_provider）
  ├── app_storage_web.dart      # ✅ Web 降级实现（localStorage + 内存文件，预览用）
  ├── session_store.dart        # ✅ 会话读写封装（UserSession 模型 + SessionStore）
  └── seed_assets.dart          # 图纸拷贝已并入 app_storage_io.seedDrawingsIfNeeded()

lib/features/auth/
  ├── login_page.dart           # ⚠️ 占位（S2 仅「进入应用」闭环可测，S3 补表单校验）
  └── auth_controller.dart      # ✅ authStateProvider / sessionStoreProvider / initAuthProvider

lib/data/repository/
  └── local_repository.dart     # S4 实现现有 Repository 接口，读写 Hive/文件

lib/core/utils/
  └── web_storage.dart          # ✅ 重构为条件导入（Web 生效，其他平台空实现）
```

### 4.2 pubspec 增量依赖（设计稿）

```yaml
dependencies:
  flutter_secure_storage: ^9.2.0   # 登录会话（移动端加密）
  hive: ^2.2.3                     # 标记数据 / AI 结果（JSON 直存）
  hive_flutter: ^1.1.0
  path_provider: ^2.1.4            # 图纸/照片文件目录
  path: ^1.9.0
  crypto: ^3.0.3                   # Web 端加密辅助（WebCrypto 封装）
  local_auth: ^2.2.0               # 可选：iOS 生物识别（P6）
```

---

## 5. 实施步骤

- [x] **S1 存储层**：LocalStorage 抽象 + 移动端/Web 双实现 + 首次启动图纸拷贝（`seedDrawingsIfNeeded`）
- [x] **S2 会话层**：UserSession 模型 + SessionStore + authStateProvider + 登录守卫（routerProvider + /login 占位页）
- [ ] **S3 登录页**：预置 3 用户本地校验 → 登录/登出全流程（替换占位 LoginPage）
- [ ] **S4 业务持久化**：LocalRepository 接入标记数据/识别结果/照片保存
- [ ] **S5 验证**：`flutter analyze`（已通过）+ Android/iOS 真机 + Web 预览三端跑通

> S1/S2 已完成；`flutter analyze` 通过，`flutter test` 4 用例通过，`flutter build web` 成功。

---

## 6. 待确认事项

- [ ] **测试期 3 个账号**：具体用户名/密码/显示名是什么？（默认建议：yang/yang123、liu/liu123、zhao/zhao123）
- [ ] **登录是否需要"记住我"**：测试期默认长期有效，还是 24h 过期？
- [ ] **Web 端图纸**：仅预览缩略图，还是要求能查看原图（涉及 IndexedDB 容量与加载体验）？
- [ ] **登出时是否保留图纸本地拷贝**：默认保留（省流量），可加手动清除。
- [ ] **iOS 生物识别解锁**：是否在 P6 加入 local_auth（Face ID / Touch ID）？

---

## 7. 参考

- 现有仓库抽象：`lib/data/repository/repository.dart`（UI 只依赖接口，切换实现零改动）
- 现有识别结果序列化：`lib/data/vision_service.dart`（`VisionResult.toJson/fromJson` 已具备）
- 现有 Web 暂存：`lib/core/utils/web_storage.dart`（仅测试用，将被新存储层替换）
- 环境切换：`--dart-define=ENV=dev|prod`（`lib/core/env/env.dart`）
