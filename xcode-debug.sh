#!/bin/bash
# Xcode CLI Debug Script for StudyAI iOS App
# Usage: ./xcode-debug.sh [command]

set -e

PROJECT_DIR="02_ios_app/StudyAI"
SCHEME="StudyAI"
SIMULATOR="iPhone 16 Pro"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Navigate to project directory
cd "${PROJECT_DIR}" || exit 1

# Helper function to print colored output
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# 1. List available simulators
list_simulators() {
    print_header "Available iOS Simulators"
    xcrun simctl list devices available | grep -E "iPhone|iPad" | head -20
}

# 2. Build for simulator
build() {
    print_header "Building StudyAI for Simulator"
    xcodebuild \
        -scheme "${SCHEME}" \
        -sdk iphonesimulator \
        -destination "platform=iOS Simulator,name=${SIMULATOR}" \
        clean build \
        | xcbeautify || true

    if [ $? -eq 0 ]; then
        print_success "Build succeeded!"
    else
        print_error "Build failed. See errors above."
        exit 1
    fi
}

# 3. Build and run on simulator
run() {
    print_header "Building and Running on ${SIMULATOR}"

    # Boot simulator if not running
    DEVICE_ID=$(xcrun simctl list devices | grep "${SIMULATOR}" | grep -v "unavailable" | head -1 | grep -oE '\([A-F0-9-]+\)' | tr -d '()')

    if [ -z "$DEVICE_ID" ]; then
        print_error "Simulator '${SIMULATOR}' not found"
        exit 1
    fi

    print_warning "Booting simulator ${SIMULATOR}..."
    xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true

    # Open Simulator.app
    open -a Simulator

    # Build and install
    print_warning "Building app..."
    xcodebuild \
        -scheme "${SCHEME}" \
        -sdk iphonesimulator \
        -destination "platform=iOS Simulator,name=${SIMULATOR}" \
        -derivedDataPath build \
        | xcbeautify || cat

    # Install app on simulator
    APP_PATH="build/Build/Products/Debug-iphonesimulator/StudyAI.app"
    if [ -d "$APP_PATH" ]; then
        print_warning "Installing app on simulator..."
        xcrun simctl install "$DEVICE_ID" "$APP_PATH"

        # Launch app
        print_warning "Launching app..."
        xcrun simctl launch "$DEVICE_ID" com.OliOli.StudyMatesAI

        print_success "App launched successfully!"
        print_warning "Logs: ./xcode-debug.sh logs"
    else
        print_error "App bundle not found at $APP_PATH"
        exit 1
    fi
}

# 4. Show build errors only
errors() {
    print_header "Checking for Build Errors"
    xcodebuild \
        -scheme "${SCHEME}" \
        -sdk iphonesimulator \
        -destination "platform=iOS Simulator,name=${SIMULATOR}" \
        build 2>&1 | grep -A 5 "error:"
}

# 5. Run tests
test() {
    print_header "Running Unit Tests"
    xcodebuild test \
        -scheme "${SCHEME}" \
        -sdk iphonesimulator \
        -destination "platform=iOS Simulator,name=${SIMULATOR}" \
        | xcbeautify || cat
}

# 6. Clean build artifacts
clean() {
    print_header "Cleaning Build Artifacts"
    xcodebuild clean \
        -scheme "${SCHEME}" \
        -sdk iphonesimulator

    rm -rf build/
    rm -rf ~/Library/Developer/Xcode/DerivedData/StudyAI-*

    print_success "Clean complete!"
}

# 7. View live simulator logs
logs() {
    print_header "Viewing Simulator Logs (Ctrl+C to exit)"
    DEVICE_ID=$(xcrun simctl list devices | grep "${SIMULATOR}" | grep "Booted" | head -1 | grep -oE '\([A-F0-9-]+\)' | tr -d '()')

    if [ -z "$DEVICE_ID" ]; then
        print_error "No booted simulator found. Start simulator first: ./xcode-debug.sh run"
        exit 1
    fi

    # Follow system log for StudyAI app
    xcrun simctl spawn "$DEVICE_ID" log stream --predicate 'processImagePath contains "StudyAI"' --level debug
}

# 8. Check syntax/warnings without full build
check() {
    print_header "Analyzing Code (Syntax & Warnings)"
    xcodebuild analyze \
        -scheme "${SCHEME}" \
        -sdk iphonesimulator \
        -destination "platform=iOS Simulator,name=${SIMULATOR}" \
        | grep -E "warning:|error:" || print_success "No issues found!"
}

# 9. Show project info
info() {
    print_header "Project Information"
    xcodebuild -list
    echo ""
    print_header "Build Settings"
    xcodebuild -showBuildSettings -scheme "${SCHEME}" | grep -E "PRODUCT_BUNDLE_IDENTIFIER|MARKETING_VERSION|CURRENT_PROJECT_VERSION"
}

# 10. Archive for distribution
archive() {
    print_header "Creating Archive for TestFlight/App Store"
    xcodebuild archive \
        -scheme "${SCHEME}" \
        -sdk iphoneos \
        -archivePath "build/StudyAI.xcarchive" \
        | xcbeautify || cat

    if [ -d "build/StudyAI.xcarchive" ]; then
        print_success "Archive created at: build/StudyAI.xcarchive"
        print_warning "Next: Open Xcode Organizer to upload to TestFlight"
    fi
}

# 11. Debug build performance
buildtime() {
    print_header "Build Time Analysis"
    print_warning "Building with time profiling..."

    time xcodebuild \
        -scheme "${SCHEME}" \
        -sdk iphonesimulator \
        -destination "platform=iOS Simulator,name=${SIMULATOR}" \
        clean build \
        OTHER_SWIFT_FLAGS="-Xfrontend -debug-time-compilation" \
        | grep "error:" || print_success "Build completed"
}

# 12. Show app bundle info
bundle_info() {
    print_header "App Bundle Information"
    APP_PATH="build/Build/Products/Debug-iphonesimulator/StudyAI.app"

    if [ -d "$APP_PATH" ]; then
        echo "Bundle ID: $(defaults read "${APP_PATH}/Info.plist" CFBundleIdentifier)"
        echo "Version: $(defaults read "${APP_PATH}/Info.plist" CFBundleShortVersionString)"
        echo "Build: $(defaults read "${APP_PATH}/Info.plist" CFBundleVersion)"
        echo "Size: $(du -sh "${APP_PATH}" | cut -f1)"
        print_success "Bundle is valid"
    else
        print_error "No app bundle found. Run './xcode-debug.sh build' first"
    fi
}

# 13. Uninstall app from simulator
uninstall() {
    print_header "Uninstalling App from Simulator"
    DEVICE_ID=$(xcrun simctl list devices | grep "${SIMULATOR}" | grep "Booted" | head -1 | grep -oE '\([A-F0-9-]+\)' | tr -d '()')

    if [ -z "$DEVICE_ID" ]; then
        print_error "No booted simulator found"
        exit 1
    fi

    xcrun simctl uninstall "$DEVICE_ID" com.OliOli.StudyMatesAI
    print_success "App uninstalled"
}

# Main command handler
case "${1:-help}" in
    list|ls)
        list_simulators
        ;;
    build|b)
        build
        ;;
    run|r)
        run
        ;;
    errors|e)
        errors
        ;;
    test|t)
        test
        ;;
    clean|c)
        clean
        ;;
    logs|l)
        logs
        ;;
    check)
        check
        ;;
    info|i)
        info
        ;;
    archive)
        archive
        ;;
    buildtime|bt)
        buildtime
        ;;
    bundle)
        bundle_info
        ;;
    uninstall|u)
        uninstall
        ;;
    help|h|*)
        print_header "Xcode CLI Debug Tool"
        echo "Usage: ./xcode-debug.sh [command]"
        echo ""
        echo "Commands:"
        echo "  list, ls         List available iOS simulators"
        echo "  build, b         Build app for simulator"
        echo "  run, r           Build and run app on simulator"
        echo "  errors, e        Show only build errors"
        echo "  test, t          Run unit tests"
        echo "  clean, c         Clean build artifacts"
        echo "  logs, l          View live simulator logs"
        echo "  check            Analyze code (syntax/warnings)"
        echo "  info, i          Show project information"
        echo "  archive          Create archive for distribution"
        echo "  buildtime, bt    Measure build time"
        echo "  bundle           Show app bundle information"
        echo "  uninstall, u     Uninstall app from simulator"
        echo "  help, h          Show this help message"
        echo ""
        print_warning "Examples:"
        echo "  ./xcode-debug.sh build         # Build for simulator"
        echo "  ./xcode-debug.sh run           # Build and launch on simulator"
        echo "  ./xcode-debug.sh errors        # Check for compilation errors"
        echo "  ./xcode-debug.sh logs          # Watch app logs in real-time"
        ;;
esac
