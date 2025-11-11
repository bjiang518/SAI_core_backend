#!/bin/bash
# 重新构建并安装应用到模拟器

echo "🧹 清理旧构建..."
xcodebuild -project StudyAI.xcodeproj -scheme StudyAI clean

echo "🔨 构建新版本..."
xcodebuild -project StudyAI.xcodeproj -scheme StudyAI -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

echo "📱 启动模拟器..."
xcrun simctl boot "iPhone 16 Pro" 2>/dev/null || echo "模拟器已在运行"

echo "🚀 安装应用..."
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/StudyAI-*/Build/Products/Debug-iphonesimulator -name "StudyAI.app" | head -1)
if [ -n "$APP_PATH" ]; then
    xcrun simctl install "iPhone 16 Pro" "$APP_PATH"
    echo "✅ 应用安装成功！"
    echo "💡 建议：清除之前的番茄数据，重新测试生成功能"
else
    echo "❌ 未找到应用"
fi
