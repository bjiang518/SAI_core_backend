# Authentication Setup Guide

This guide explains the current authentication state and how to enable additional features.

## Current Authentication Status

### ✅ **Working Now (Personal Development Account)**
- **Email Authentication**: Full email/password sign-in with secure keychain storage
- **Biometric Authentication**: Face ID/Touch ID login after initial setup
- **Modern UI**: Complete redesign with gradient backgrounds and modern iOS patterns

### 🔶 **Apple Sign-In (Requires Paid Developer Account)**
- **Current State**: Disabled due to personal development team limitation
- **Code Ready**: Full implementation exists but Apple Sign-In capability is removed from entitlements
- **To Enable**: Upgrade to paid Apple Developer Program ($99/year), then restore capability

### 🔶 **Google Sign-In (Requires SDK Setup)**
- **Current State**: Shows setup instructions when attempted
- **Code Ready**: Full production implementation prepared
- **To Enable**: Follow steps below to add GoogleSignIn SDK

---

## Enable Google Sign-In

### Step 1: Add GoogleSignIn SDK

1. Open your Xcode project
2. Go to **File → Add Package Dependencies**
3. Enter the URL: `https://github.com/google/GoogleSignIn-iOS`
4. Click **Add Package**
5. Select **GoogleSignIn** and click **Add Package**

### Step 2: Create OAuth 2.0 Client

1. Visit [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing project
3. Go to **APIs & Services → Credentials**
4. Click **Create Credentials → OAuth 2.0 Client IDs**
5. Select **iOS** as application type
6. Set bundle ID to: `com.bo-jiang-StudyAI`
7. Download the `GoogleService-Info.plist` file

### Step 3: Add Configuration File

1. Drag `GoogleService-Info.plist` into your Xcode project
2. Make sure it's added to the StudyAI target
3. Verify the file is in the project navigator

### Step 4: Configure URL Scheme

1. Open `Info.plist` in Xcode
2. Add a new item with key `CFBundleURLTypes`
3. Set it as an Array
4. Add a new item (Dictionary) to the array
5. Add `CFBundleURLName` with value `com.bo-jiang-StudyAI`
6. Add `CFBundleURLSchemes` as an Array
7. Add the `REVERSED_CLIENT_ID` from your `GoogleService-Info.plist`

Example Info.plist structure:
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>com.bo-jiang-StudyAI</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>YOUR_REVERSED_CLIENT_ID_HERE</string>
        </array>
    </dict>
</array>
```

### Step 5: Enable Real Google Sign-In

Once you've completed steps 1-4, the app will automatically detect the GoogleSignIn SDK and enable real Google Sign-In functionality. The implementation in `AuthenticationService.swift` is already prepared to work with the SDK.

### Step 6: Uncomment Production Code

In `AuthenticationService.swift`, find the `performRealGoogleSignIn` method and uncomment the production code block (lines 581-624) after adding the SDK.

---

## Enable Apple Sign-In (Optional)

### Requirements
- **Paid Apple Developer Program** membership ($99/year)
- Cannot be enabled with personal development teams

### Steps to Enable
1. Upgrade to paid Apple Developer Program
2. Restore Apple Sign-In capability in `StudyAI.entitlements`:
   ```xml
   <key>com.apple.developer.applesignin</key>
   <array>
       <string>Default</string>
   </array>
   ```
3. The app will automatically show Apple Sign-In button

---

## Current Features

### ✅ **Email Authentication**
- Secure registration and login
- Password validation
- Account management

### ✅ **Biometric Authentication** 
- Face ID/Touch ID support
- Secure credential storage
- Automatic availability detection

### ✅ **Modern UI/UX**
- Gradient backgrounds
- iOS 17.0+ features
- Responsive design
- Error handling with user-friendly messages

### ✅ **Security**
- iOS Keychain integration
- Encrypted credential storage
- Proper permission handling

## Troubleshooting

### Google Sign-In Issues
- Make sure the bundle ID matches exactly: `com.bo-jiang-StudyAI`
- Verify the `GoogleService-Info.plist` is in the project root
- Check that the `REVERSED_CLIENT_ID` is correctly added to URL schemes
- Ensure GoogleSignIn SDK is properly linked to the target

### Apple Sign-In Issues
- Apple Sign-In requires paid developer account
- Personal development teams cannot use this capability
- The feature is customer-facing, not developer-only

### Build Issues
- All authentication features work with personal development account except Apple Sign-In
- Project builds successfully without Apple Sign-In capability
- Email and biometric authentication are fully functional