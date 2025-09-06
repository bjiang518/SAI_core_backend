# 🚀 Google Sign-In Setup - Step by Step Guide

Follow these steps **in order** to enable Google Sign-In in your StudyAI app.

## ✅ **Step 1: Add GoogleSignIn SDK (In Xcode)**

1. **Open StudyAI.xcodeproj in Xcode**
2. **File → Add Package Dependencies**
3. **Paste this URL:** `https://github.com/google/GoogleSignIn-iOS`
4. **Click "Add Package"**
5. **Select "GoogleSignIn" → Click "Add Package"**
6. **Ensure it's added to "StudyAI" target**

---

## 🌐 **Step 2: Create Google Cloud OAuth Client**

1. **Go to [Google Cloud Console](https://console.cloud.google.com/)**
2. **Create new project or select existing**
3. **Configure OAuth consent screen (if needed):**
   - Go to "APIs & Services" → "OAuth consent screen"  
   - Choose "External" user type
   - Fill in required fields:
     - App name: **StudyAI**
     - User support email: your email
     - Developer contact information: your email
   - Click "Save and Continue"
   - Skip scopes (click "Save and Continue")
   - Add test users: add your email address
   - Click "Save and Continue"
4. **Create OAuth 2.0 Client ID:**
   - Go to "APIs & Services" → "Credentials"
   - Click "Create Credentials" → "OAuth 2.0 Client IDs"
   - Application type: **"iOS"**
   - Name: **"StudyAI iOS"**
   - Bundle ID: **`com.bo-jiang-StudyAI`** (exact match!)
   - Click "Create"
5. **Download GoogleService-Info.plist:**
   - Click the download button or "Download JSON"
   - Save the `GoogleService-Info.plist` file

---

## 📱 **Step 3: Add Configuration File (In Xcode)**

1. **Drag `GoogleService-Info.plist` into Xcode**
2. **Drop it in the StudyAI folder (next to other .swift files)**
3. **✅ Check "Add to target: StudyAI"**
4. **Click "Finish"**
5. **Verify it appears in Project Navigator**

---

## 🔗 **Step 4: Configure URL Schemes (In Xcode)**

1. **Select StudyAI project (blue icon at top)**
2. **Select StudyAI target → Info tab**
3. **Scroll down to "URL Types"**
4. **Click "+" to add new URL Type**
5. **Open your GoogleService-Info.plist file**
6. **Copy the value for `REVERSED_CLIENT_ID`** (looks like `com.googleusercontent.apps.123456789`)
7. **Paste it in "URL Schemes" field**
8. **Identifier: `GoogleSignIn`**

**Example:**
```
URL Schemes: com.googleusercontent.apps.123456789-abcdef123456.apps.googleusercontent.com
Identifier: GoogleSignIn
```

---

## 🔧 **Step 5: Enable Production Code**

1. **Open `AuthenticationService.swift`**
2. **Line 16:** Uncomment the import:
   ```swift
   import GoogleSignIn  // Remove the //
   ```
3. **Lines 614-650:** Uncomment the entire production code block
   - Remove the `/*` at line 614
   - Remove the `*/` at line 650
4. **Save the file**

---

## 🧪 **Step 6: Test the Setup**

1. **Build the project (⌘+B)**
2. **Run the app (⌘+R)**
3. **Go to login screen**
4. **Tap "Continue with Google"**
5. **Should show Google Sign-In flow**

---

## ✅ **Verification Checklist**

- [ ] GoogleSignIn SDK added via Package Manager
- [ ] Google Cloud Console OAuth client created
- [ ] Bundle ID matches exactly: `com.bo-jiang-StudyAI`
- [ ] GoogleService-Info.plist added to Xcode project
- [ ] URL scheme configured with REVERSED_CLIENT_ID
- [ ] Production code uncommented
- [ ] App builds without errors
- [ ] Google Sign-In button appears and works

---

## 🚨 **Troubleshooting**

**Build Errors:**
- Make sure GoogleSignIn import is uncommented
- Verify SDK was added to StudyAI target

**"Configuration not found" error:**
- Check GoogleService-Info.plist is in project
- Verify it's added to StudyAI target

**"Invalid client" error:**
- Bundle ID must match exactly: `com.bo-jiang-StudyAI`
- Check OAuth client configuration in Google Cloud Console

**URL scheme errors:**
- REVERSED_CLIENT_ID must be exact copy from plist
- Format: `com.googleusercontent.apps.XXXXXXXXX`

---

## 🎉 **What Happens Next**

Once setup is complete:
1. **Google Sign-In button will work**
2. **Users can authenticate with their Google account**
3. **User data will be securely stored in Keychain**
4. **Subsequent launches can use biometric authentication**

Ready to set up? Start with Step 1! 🚀