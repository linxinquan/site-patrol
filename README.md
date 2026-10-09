# 蓝图落地

设计院视角的现场数据闭环 App（Flutter，iOS / Android / Web 三端）。

四步闭环：现场拍照 → AI 自动分类、关联图纸和规范 → 判断责任（设计缺陷 / 施工问题）→ 沉淀缺陷知识库，反哺设计。

## 版本号规则

`pubspec.yaml` 的 `version` 是版本唯一来源，例如 `1.1.0+173`。

- `1.1.0` 是 Device Hub / Installed Apps 可见版本，App 首页显示 `v1.1.0`；`173` 仅是内部构建号。
- 本机构建脚本默认自动递增修订号及内部构建号：`1.1.0+173 → 1.1.1+174 → 1.1.2+175`。成功后更新会保留在 `pubspec.yaml` 中，供后续提交 Git。
- 仅重新签名或为新增设备构建时使用 `--keep-version`，版本号保持不变。
- 功能升级或重大升级时可先手动设置版本（例如 `1.2.0+176`），再用 `--keep-version` 构建该指定版本。
- 构建失败或签名校验失败时，脚本恢复原版本及上一次可用的 `Runner.app`。若构建期间有人修改 `pubspec.yaml`，脚本保留该修改并报错。

## iOS 一键构建与手动安装

本机直接运行：

```sh
../build_site_patrol_ios.sh
```

这个本机入口默认使用 georgehu-iPhone 和已配置的签名团队，并调用仓库内的 `scripts/build_ios.sh`。脚本构建当前工作区，不自动拉取、重置或推送 Git；自动递增版本后构建 Release，校验签名、版本、目标设备名单及签名有效期，最后在 Finder 中定位 `build/ios/iphoneos/Runner.app`。不生成 IPA，默认不执行设备安装。

连接并解锁 iPhone 后，在 Xcode → Window → Devices and Simulators → Devices → 选择 iPhone → Installed Apps → `+` 中选择整个 `Runner.app` 安装。Finder 隐藏扩展名时可能显示为 `Runner`。

常用参数：

```sh
# 保持版本，只重新构建/签名
../build_site_patrol_ios.sh --keep-version

# 为新增 iPhone 授权，保持版本
../build_site_patrol_ios.sh --device '<iPhone 的 UDID>' --keep-version

# 明确要求构建后自动安装到指定设备
../build_site_patrol_ios.sh --install

# 仅在终端构建，不打开 Finder
../build_site_patrol_ios.sh --no-open
```

当前描述文件内的多台 iPhone 可使用同一个 `.app`。新增设备需要先连接 Mac，再为它构建一次以更新授权；直接在 Installed Apps 中安装现有文件不会自动添加设备。设备名单及签名有效期仍适用于 `.app`。

构建信息、安装说明和日志分别位于 `build/ios/BUILD_INFO.json`、`build/ios/安装说明.md` 和 `build/ios/build-ios-*.log`。并发构建会被拒绝，避免版本及产物相互覆盖。

仓库外的本机入口保留个人团队和设备设置，不提交 Git；共享构建逻辑及回归测试位于 `scripts/`。其他机器配置 Flutter、Xcode 自动签名后，可运行：

```sh
./scripts/build_ios.sh --device '<iPhone 的 UDID>'
# 如需指定团队：PATROL_IOS_TEAM=<Team ID> ./scripts/build_ios.sh --device '<UDID>'
```

构建流程回归测试（使用隔离的模拟工具，不会安装到设备）：

```sh
python3 scripts/test_build_ios.py -v
```

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
