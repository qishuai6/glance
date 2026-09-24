#!/bin/bash
# 秒览 Glance —— 构建脚本：xcodegen 生成工程 + xcodebuild 构建
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-Debug}"

command -v xcodegen >/dev/null || { echo "❌ 缺少 xcodegen（brew install xcodegen）"; exit 1; }

echo "▸ 生成 Xcode 工程…"
xcodegen generate

echo "▸ xcodebuild 构建（${CONFIG}）…"
xcodebuild -project Glance.xcodeproj \
  -scheme Glance \
  -configuration "$CONFIG" \
  -derivedDataPath build/DerivedData \
  build CODE_SIGNING_ALLOWED=YES | tail -n 30

APP="build/DerivedData/Build/Products/$CONFIG/Glance.app"
if [ -d "$APP" ]; then
  echo ""
  echo "✅ 构建完成：$APP"
  codesign --verify --deep --strict "$APP" && echo "✅ 签名校验通过"
fi
