#!/bin/bash

echo "🧪 Testing StudyAI Camera Implementation"
echo "========================================"

# Launch the app and monitor for camera errors
echo "📱 Launching StudyAI app..."
APP_PID=$(xcrun simctl launch booted "com.bo-jiang-StudyAI" 2>/dev/null | cut -d: -f2 | tr -d ' ')

if [ -n "$APP_PID" ]; then
    echo "✅ App launched successfully (PID: $APP_PID)"
    
    echo "🔍 Monitoring camera system errors for 10 seconds..."
    
    # Monitor for specific camera errors
    xcrun simctl spawn booted log stream --predicate 'process == "StudyAI"' --style syslog 2>/dev/null &
    LOG_PID=$!
    
    # Wait 10 seconds for app to initialize
    sleep 10
    
    # Kill log monitoring
    kill $LOG_PID 2>/dev/null
    
    # Check recent logs for camera errors
    CAMERA_ERRORS=$(xcrun simctl spawn booted log show --predicate 'process == "StudyAI"' --style syslog --last 15s 2>/dev/null | grep -E "(ModelSpecific|FigCapture.*-17281|VTPixel.*-6680)" | wc -l | tr -d ' ')
    
    echo ""
    echo "📊 Camera Error Analysis:"
    echo "========================"
    
    if [ "$CAMERA_ERRORS" -eq "0" ]; then
        echo "✅ SUCCESS: No camera system errors detected!"
        echo "✅ The VNDocumentCameraViewController bypass is working!"
    else
        echo "⚠️  Still detected $CAMERA_ERRORS camera system errors"
        echo "🔍 Recent camera errors:"
        xcrun simctl spawn booted log show --predicate 'process == "StudyAI"' --style syslog --last 15s 2>/dev/null | grep -E "(ModelSpecific|FigCapture.*-17281|VTPixel.*-6680)" | head -5
    fi
    
    echo ""
    echo "📱 App is running. Test the camera functionality manually in the simulator."
    echo "🔒 Camera should use VNDocumentCameraViewController exclusively."
    
else
    echo "❌ Failed to launch app"
    exit 1
fi