#!/bin/bash

echo "🚀 Building StudyAI with optimized debugging performance..."

# Clean the project first
echo "🧹 Cleaning project..."
xcodebuild clean -project StudyAI.xcodeproj -scheme StudyAI -configuration Debug

# Build for the simulator first to verify our optimizations work
echo "📱 Building for iOS Simulator..."
xcodebuild build -project StudyAI.xcodeproj -scheme StudyAI \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=latest' \
  -quiet

BUILD_RESULT=$?

if [ $BUILD_RESULT -eq 0 ]; then
    echo "✅ StudyAI built successfully with optimized debugging settings!"
    echo ""
    echo "🔧 Applied optimizations:"
    echo "   • Debug information format: dwarf-with-dsym (faster LLDB loading)"
    echo "   • iOS deployment target: 17.0 (better device compatibility)"
    echo "   • LLDB shared cache optimization enabled"
    echo "   • RPC server stability improvements"
    echo "   • Memory loading optimizations"
    echo ""
    echo "📱 To deploy to your device:"
    echo "   1. Connect your iOS device"
    echo "   2. Open StudyAI.xcodeproj in Xcode"
    echo "   3. Select your device as the destination"
    echo "   4. Build and run (⌘+R)"
    echo ""
    echo "⚡ The app should now launch much faster on your device!"
    echo "   The LLDB shared cache warning should be resolved."
else
    echo "❌ Build failed. Please check the error messages above."
    exit 1
fi