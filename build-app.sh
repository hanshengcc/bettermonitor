#!/bin/bash
# 构建 BetterMonitor.app（菜单栏应用）
set -e
cd "$(dirname "$0")"

swift build -c release

# build.noindex：Spotlight 不索引，避免“应用程序”里出现第二个 BetterMonitor
APP=build.noindex/BetterMonitor.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/BetterMonitor "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"

# 图标：Icon Composer 源文件 -> Assets.car（新版玻璃图标）+ AppIcon.icns（旧系统兜底）
ICON_OUT=build.noindex/icon
rm -rf "$ICON_OUT" && mkdir -p "$ICON_OUT" "$APP/Contents/Resources"
xcrun actool Resources/AppIcon.icon --compile "$ICON_OUT" --platform macosx \
  --minimum-deployment-target 13.0 --app-icon AppIcon \
  --output-partial-info-plist "$ICON_OUT/partial.plist" >/dev/null
cp "$ICON_OUT/Assets.car" "$ICON_OUT/AppIcon.icns" "$APP/Contents/Resources/"
codesign --force --sign - "$APP"

echo "✅ 已生成 $APP"
