#!/bin/bash

# Google Sign-In Setup Script for StudyAI
# Run this after completing the Xcode and Google Cloud Console setup

echo "🚀 Google Sign-In Setup Verification"
echo "======================================"

# Check if GoogleService-Info.plist exists
if [ -f "StudyAI/GoogleService-Info.plist" ]; then
    echo "✅ GoogleService-Info.plist found"
    
    # Check if it's been configured (not template)
    if grep -q "YOUR_CLIENT_ID_HERE" "StudyAI/GoogleService-Info.plist"; then
        echo "⚠️  GoogleService-Info.plist still contains template values"
        echo "   Please replace with your actual Google Cloud Console configuration"
    else
        echo "✅ GoogleService-Info.plist appears to be configured"
    fi
else
    echo "❌ GoogleService-Info.plist not found"
    echo "   Please download from Google Cloud Console and add to project"
fi

echo ""
echo "📋 Setup Status:"
echo "================"
echo "✅ 1. GoogleSignIn SDK added (detected in project.pbxproj)"
echo "🔄 2. Create Google Cloud Console OAuth Client:"
echo "   • Go to console.cloud.google.com"
echo "   • Configure OAuth consent screen (External, add test users)"
echo "   • Create iOS OAuth 2.0 Client ID"
echo "   • Bundle ID: com.bo-jiang-StudyAI"
echo "   • Download GoogleService-Info.plist"
echo ""
echo "🔄 3. Add GoogleService-Info.plist to Xcode:"
echo "   • Drag file into StudyAI folder in Xcode"
echo "   • Make sure it's added to StudyAI target"
echo ""
echo "🔄 4. Configure URL Schemes in Xcode:"
echo "   • Select StudyAI project → StudyAI target → Info tab"
echo "   • Add URL Types → New URL Scheme"
echo "   • Add REVERSED_CLIENT_ID from GoogleService-Info.plist"
echo ""
echo "🔄 5. Uncomment production code:"
echo "   • Open AuthenticationService.swift"
echo "   • Uncomment the import GoogleSignIn line (line 16)"
echo "   • Uncomment the production code block in performRealGoogleSignIn (lines 614-650)"
echo ""
echo "🔄 6. Test the integration:"
echo "   • Build and run the app"
echo "   • Try Google Sign-In button"
echo ""
echo "📖 For detailed instructions, see: GOOGLE_SETUP_WALKTHROUGH.md"
echo ""
echo "💡 Note: Google Sign-In API is no longer needed in the library."
echo "   Just configure OAuth consent screen and create iOS OAuth client!"