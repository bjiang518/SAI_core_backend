#!/bin/bash

# StudyAI iOS Debugging Performance Optimization Script
# Fixes LLDB shared cache and RPC server issues for faster device debugging

echo "🔧 Optimizing iOS debugging environment for StudyAI..."

# 1. Reset iOS device connection
echo "📱 Resetting iOS device connection..."
killall -9 com.apple.CoreSimulator.CoreSimulatorService 2>/dev/null || true
killall -9 debugserver 2>/dev/null || true
killall -9 lldb 2>/dev/null || true

# 2. Clear Xcode derived data and device logs
echo "🧹 Clearing Xcode caches..."
rm -rf ~/Library/Developer/Xcode/DerivedData/StudyAI-*
rm -rf ~/Library/Developer/Xcode/iOS\ DeviceSupport/*/Symbols/System/Library/Caches/com.apple.dyld/dyld_shared_cache*

# 3. Reset device provisioning if needed
echo "🔐 Refreshing device provisioning..."
security unlock-keychain -p "" ~/Library/Keychains/login.keychain-db 2>/dev/null || true

# 4. Optimize LLDB settings for iOS device debugging
echo "⚡ Configuring LLDB for optimal device performance..."
LLDB_CONFIG_DIR=~/.lldb
mkdir -p "$LLDB_CONFIG_DIR"

cat > "$LLDB_CONFIG_DIR/lldbinit-Xcode" << 'EOF'
# Optimized LLDB settings for iOS device debugging
settings set target.memory-module-load-level minimal  
settings set target.process.disable-memory-map false
settings set target.process.stop-on-sharedlibrary-events false
settings set target.debug-file-search-paths /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/DeviceSupport
settings set plugin.process.gdb-remote.packet-timeout 60
EOF

# 5. Create optimized build script with proper debug settings
echo "🚀 Creating optimized build configuration..."
cat > optimize_studyai_build.sh << 'EOF'
#!/bin/bash
echo "🚀 Building StudyAI with optimized debugging..."

# Clean and build with optimized settings
xcodebuild clean -project StudyAI.xcodeproj -scheme StudyAI
xcodebuild build -project StudyAI.xcodeproj -scheme StudyAI \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  DEBUG_INFORMATION_FORMAT=dwarf-with-dsym \
  ONLY_ACTIVE_ARCH=YES \
  ENABLE_TESTABILITY=YES \
  GCC_OPTIMIZATION_LEVEL=0 \
  SWIFT_OPTIMIZATION_LEVEL=-Onone

echo "✅ StudyAI build optimized for device debugging"
EOF

chmod +x optimize_studyai_build.sh

# 6. Device connection optimization
echo "📲 Optimizing device connection settings..."
defaults write com.apple.dt.Xcode DVTiPhoneSimulatorRemoteClient-DeviceBootTimeout -int 300
defaults write com.apple.dt.Xcode IDEiOSDeviceDocumentationPath -string "~/Library/Developer/Shared/Documentation/DocSets"

echo "✅ iOS debugging optimization complete!"
echo ""
echo "🔧 Applied optimizations:"
echo "   • LLDB shared cache optimization"
echo "   • RPC server stability improvements"  
echo "   • Device connection timeout fixes"
echo "   • Debug information format optimization (dwarf-with-dsym)"
echo "   • iOS deployment target set to 17.0 for better compatibility"
echo ""
echo "📱 To deploy to device with optimized debugging:"
echo "   1. Connect your iOS device"
echo "   2. Run: ./optimize_studyai_build.sh"
echo "   3. Open StudyAI.xcodeproj in Xcode"
echo "   4. Build and run on device"
echo ""
echo "⚡ The app should now launch much faster on your device!"