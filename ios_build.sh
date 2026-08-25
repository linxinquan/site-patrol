#!/usr/bin/env bash
# iOS 真机调试一键脚本（site-patrol）
# 用法：在你自己的 Mac 终端执行  bash ios_build.sh
# 前置：1) 已装 CocoaPods（sudo gem install cocoapods 或 brew install cocoapods）
#       2) iPhone 已用数据线连上 Mac 并「信任此电脑」
#       3) Xcode 里登录过你的 Apple ID（Signing 选 Team）
set -euo pipefail
cd "$(dirname "$0")"

FLUTTER=$(command -v flutter)

# 0. 检查 Flutter
if [ -z "$FLUTTER" ]; then
  echo "❌ 未检测到 Flutter，请先安装 Flutter 并确保 flutter 命令可用"
  echo "   参考：https://docs.flutter.dev/get-started/install/macos"
  exit 1
fi

# 0. 检查 CocoaPods
if ! command -v pod >/dev/null 2>&1; then
  echo "❌ 未检测到 CocoaPods，请先安装其一："
  echo "   sudo gem install cocoapods"
  echo "   或  brew install cocoapods"
  exit 1
fi

# 1. 安装 iOS 依赖
echo "📦 pod install ..."
(cd ios && pod install)

# 2. 列出已连接设备
echo "📱 已连接设备："
"$FLUTTER" devices

# 3. 签名提示（仅需首次）
echo ""
echo "⚠️  若 Xcode 尚未配置签名 Team（仅需首次）："
echo "   1) open ios/Runner.xcworkspace"
echo "   2) Signing & Capabilities → Team 选你的 Apple ID"
echo "   3) Bundle Identifier 改成你自己的（如 com.yourname.gongdiApp，避免 com.example 占位）"
echo "   4) iPhone 上：设置 → 通用 → VPN与设备管理 → 信任你的 Apple ID"
echo ""

# 4. 等待用户确认设备已连
read -rp "配置好后按回车开始运行（确保 iPhone 已连接并在 Xcode 已选为运行设备）... "

# 5. 运行（自动选已连接的 iPhone；多设备时用 flutter run --device-id <udid>）
echo "🚀 flutter run ..."
"$FLUTTER" run
