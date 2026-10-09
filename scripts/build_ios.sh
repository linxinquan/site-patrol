#!/bin/bash
# Build a versioned, signed Runner.app from the current checkout. Never creates IPA.
set -euo pipefail

PROJ=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DEVICE="${PATROL_IOS_DEVICE:-}"
TEAM="${PATROL_IOS_TEAM:-}"
INSTALL=0
KEEP_VERSION=0
REVEAL=1
usage() {
  cat <<'EOF'
用法：build_ios.sh --device <iPhone UDID> [选项]

默认：修订号及内部构建号各 +1，构建并校验 Runner.app，在 Finder 中定位。
  --device <UDID>  指定签名设备；也可设置 PATROL_IOS_DEVICE
  --keep-version  保持当前版本，仅重建或为新增设备签名
  --install       构建后安装到指定设备；默认不安装
  --no-open       不在 Finder 中定位产物
  -h, --help      显示帮助

环境：PATROL_IOS_TEAM 可覆盖本机签名团队；PATROL_IOS_ENV_FILE 可指定环境脚本。
构建当前工作区，不拉取、重置、提交或推送 Git，不生成 IPA。
EOF
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)
      [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || { echo "缺少 --device 的 UDID" >&2; exit 2; }
      DEVICE="$2"; shift 2 ;;
    --keep-version) KEEP_VERSION=1; shift ;;
    --install) INSTALL=1; shift ;;
    --no-open) REVEAL=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数：$1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ -n "$DEVICE" ]] || { echo "请用 --device 指定 iPhone 的 UDID。" >&2; exit 2; }
export PATH="$PATH:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
ENV_FILE="${PATROL_IOS_ENV_FILE:-$HOME/.local/share/lantu-build/env.sh}"
if [[ -f "$ENV_FILE" ]]; then source "$ENV_FILE"; fi
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"
export LANG=en_US.UTF-8
for tool in flutter python3 codesign security git xcrun; do
  command -v "$tool" >/dev/null || { echo "缺少构建工具：$tool" >&2; exit 1; }
done
cd "$PROJ"
mkdir -p .dart_tool build/ios
LOCK="$PROJ/.dart_tool/site-patrol-ios-build.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "已有构建在运行。若上次进程被强制终止，请确认无构建进程后移除 $LOCK" >&2
  exit 1
fi
RUN_DIR=""
APP="$PROJ/build/ios/iphoneos/Runner.app"
BUILD_STARTED=0
BUILD_SUCCESS=0
cleanup() {
  local result=$?
  trap - EXIT
  set +e
  if [[ "$BUILD_SUCCESS" == 0 && -n "$RUN_DIR" ]]; then
    python3 - "$PROJ/pubspec.yaml" "$RUN_DIR" <<'PY'
from pathlib import Path
import sys
pubspec, state = map(Path, sys.argv[1:])
original, expected = state / 'pubspec.original', state / 'pubspec.expected'
if original.exists() and expected.exists():
    if pubspec.read_bytes() == expected.read_bytes():
        pubspec.write_bytes(original.read_bytes())
        print('构建未完成，已恢复原版本号。', file=sys.stderr)
    else:
        print('pubspec.yaml 在构建期间被其他操作修改，保留该改动。', file=sys.stderr)
PY
    if [[ "$BUILD_STARTED" == 1 ]]; then
      rm -rf "$APP"
      if [[ -d "$RUN_DIR/Runner.app" ]]; then
        if ! mv "$RUN_DIR/Runner.app" "$APP"; then
          echo "恢复失败，旧产物保留在 $RUN_DIR/Runner.app" >&2
          rmdir "$LOCK"
          exit 1
        fi
        echo "已恢复上一次可用的 Runner.app。" >&2
      fi
    fi
  fi
  if [[ -n "$RUN_DIR" ]]; then rm -rf "$RUN_DIR"; fi
  rmdir "$LOCK"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
RUN_DIR=$(mktemp -d "$PROJ/build/ios/.release-run.XXXXXX")

# Machine-specific signing values remain local to this checkout.
if [[ -n "$TEAM" ]]; then
  python3 - "$PROJ/ios/Runner.xcodeproj/project.pbxproj" "$TEAM" <<'PY'
from pathlib import Path
import re, sys
p, team = Path(sys.argv[1]), sys.argv[2]
if not re.fullmatch(r'[A-Z0-9]{10}', team):
    raise SystemExit('PATROL_IOS_TEAM 必须是 10 位团队 ID')
data = p.read_bytes()
updated, count = re.subn(rb'DEVELOPMENT_TEAM = [^;]*;', f'DEVELOPMENT_TEAM = {team};'.encode(), data)
if not count:
    raise SystemExit('Xcode 工程中没有 DEVELOPMENT_TEAM，请先配置自动签名')
if updated != data:
    p.write_bytes(updated)
PY
fi

python3 - "$PROJ/pubspec.yaml" "$RUN_DIR" "$KEEP_VERSION" <<'PY'
from pathlib import Path
import re, sys
pubspec, state = map(Path, sys.argv[1:3])
original = pubspec.read_bytes()
matches = list(re.finditer(rb'^version:[ \t]*([0-9]+\.[0-9]+\.[0-9]+)\+([1-9][0-9]*)(?=[ \t\r]*(?:#.*)?$)', original, re.M))
if len(matches) != 1:
    raise SystemExit('pubspec.yaml 必须包含唯一的 version: 主版本.次版本.修订号+内部构建号')
m = matches[0]
old_version = m.group(1).decode()
major, minor, patch = map(int, old_version.split('.'))
number = int(m.group(2))
if sys.argv[3] != '1':
    patch += 1
    number += 1
version = f'{major}.{minor}.{patch}'
expected = original[:m.start(1)] + f'{version}+{number}'.encode() + original[m.end(2):]
(state / 'pubspec.original').write_bytes(original)
(state / 'pubspec.expected').write_bytes(expected)
(state / 'version').write_text(f'{version} {number}\n')
pubspec.write_bytes(expected)
print(f'▶ 版本：{old_version}+{m.group(2).decode()} → {version}+{number}')
PY
read -r VER_NAME BUILD_NUMBER < "$RUN_DIR/version"
COMMIT=$(git rev-parse --short HEAD)
BUILD_TIME=$(TZ=Asia/Singapore date '+%Y-%m-%d %H:%M')
LOG_FILE="$PROJ/build/ios/build-ios-${VER_NAME}-$(date '+%Y%m%d-%H%M%S').log"
echo "▶ 构建当前工作区：${COMMIT}，目标设备：${DEVICE}"
mkdir -p "$(dirname "$APP")"
if [[ -d "$APP" ]]; then mv "$APP" "$RUN_DIR/Runner.app"; fi
BUILD_STARTED=1
flutter --device-id "$DEVICE" build ios --release \
  --dart-define="VERSION_NAME=$VER_NAME" \
  --dart-define="GIT_COMMIT=$COMMIT" \
  --dart-define="BUILD_TIME=$BUILD_TIME" 2>&1 | tee "$LOG_FILE"
codesign --verify --deep --strict "$APP"
python3 - "$PROJ" "$APP" "$RUN_DIR" "$VER_NAME" "$BUILD_NUMBER" "$DEVICE" "$TEAM" "$COMMIT" "$BUILD_TIME" "$LOG_FILE" <<'PY'
from pathlib import Path
import datetime, json, plistlib, subprocess, sys
root, app, state = map(Path, sys.argv[1:4])
version, number, device, team, commit, build_time, log = sys.argv[4:]
if (root / 'pubspec.yaml').read_bytes() != (state / 'pubspec.expected').read_bytes():
    raise SystemExit('pubspec.yaml 在构建期间发生变化，本次产物不予交付')
info = plistlib.loads((app / 'Info.plist').read_bytes())
if (info.get('CFBundleShortVersionString'), info.get('CFBundleVersion')) != (version, number):
    raise SystemExit('构建产物版本与 pubspec.yaml 不一致')
profile = plistlib.loads(subprocess.run(
    ['security', 'cms', '-D', '-i', str(app / 'embedded.mobileprovision')],
    check=True, capture_output=True,
).stdout)
devices = profile.get('ProvisionedDevices', [])
if device not in devices:
    raise SystemExit(f'描述文件未授权目标设备 {device}，请检查 Xcode 自动签名')
if team and team not in profile.get('TeamIdentifier', []):
    raise SystemExit('描述文件签名团队与指定团队不一致')
expiry = profile['ExpirationDate'].replace(tzinfo=datetime.timezone.utc)
if expiry <= datetime.datetime.now(datetime.timezone.utc):
    raise SystemExit('签名描述文件已过期，请在 Xcode 中更新签名')
expiry_local = expiry.astimezone(datetime.timezone(datetime.timedelta(hours=8))).isoformat()
manifest = {
    'version': version, 'build_number': number, 'commit': commit,
    'build_time_singapore': build_time, 'target_device': device,
    'provisioned_devices': devices, 'profile_uuid': profile['UUID'],
    'profile_expiration_singapore': expiry_local,
    'bundle_id': info['CFBundleIdentifier'], 'app': str(app), 'build_log': log,
    'validation': 'Release build, code signature, version, target device, profile expiry passed',
}
(root / 'build/ios/BUILD_INFO.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
(root / 'build/ios/BUILD_INFO.txt').write_text(''.join(f'{k}={v}\n' for k, v in manifest.items()))
(root / 'build/ios/安装说明.md').write_text(f'''# 蓝图落地 {version} 手动安装

安装文件：`{app}`（选择整个 Runner.app，Finder 可能显示为 Runner）。

Xcode → Window → Devices and Simulators → 选择 iPhone → Installed Apps → `+` → 选择 Runner.app。

已授权设备：{', '.join(devices)}。

签名到期：{expiry_local}（新加坡时间）。新增设备需通过 `--device <UDID> --keep-version` 重新构建并更新签名。

本地脚本默认修订号及内部构建号各 +1，只生成 Runner.app，不生成 IPA。默认不安装；显式添加 `--install` 才会安装。
''')
print(f'▶ 校验通过：可见版本 {version}，内部构建号 {number}')
print('  同一个 Runner.app 支持：' + ', '.join(devices))
print('  签名有效至：' + expiry_local)
PY
BUILD_SUCCESS=1
echo "✅ Runner.app 已生成：$APP"
echo "   版本：${VER_NAME}；日志：${LOG_FILE}"
echo "   Xcode → Devices and Simulators → 选择 iPhone → Installed Apps → + → Runner.app"
if [[ "$REVEAL" == 1 ]]; then open -R "$APP" || echo "Finder 未打开，请手动访问上述路径。"; fi
if [[ "$INSTALL" == 1 ]]; then
  echo "▶ 安装到 $DEVICE ..."
  xcrun devicectl device install app --device "$DEVICE" "$APP"
fi
