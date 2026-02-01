# Loading Animation - Xcode Setup Instructions

## ✅ Files Already Created

All Swift files and the Lottie animation are ready:

1. ✅ **Animation File**: `/Lottie/Just Flow - Teal.json` (already added by you)
2. ✅ **LoadingAnimationView.swift**: `Views/LoadingAnimationView.swift`
3. ✅ **AppSessionManager.swift**: `Services/AppSessionManager.swift`
4. ✅ **ContentView.swift**: Updated with loading animation logic

---

## 🔧 Xcode Setup Steps

### Step 1: Add New Swift Files to Xcode Project

**LoadingAnimationView.swift**:
1. In Xcode, right-click on `Views` folder
2. Select "Add Files to StudyAI..."
3. Navigate to: `StudyAI/StudyAI/Views/LoadingAnimationView.swift`
4. ✅ Check "Copy items if needed" (if not already in Views)
5. ✅ Check target "StudyAI"
6. Click "Add"

**AppSessionManager.swift**:
1. In Xcode, right-click on `Services` folder
2. Select "Add Files to StudyAI..."
3. Navigate to: `StudyAI/StudyAI/Services/AppSessionManager.swift`
4. ✅ Check "Copy items if needed" (if not already in Services)
5. ✅ Check target "StudyAI"
6. Click "Add"

---

### Step 2: Verify Lottie Animation File

The file `Just Flow - Teal.json` is already in your `Lottie` folder. Verify it's added to Xcode:

1. In Xcode, navigate to `Lottie` folder
2. You should see `Just Flow - Teal.json` listed
3. Click on the file
4. In File Inspector (right panel), verify:
   - ✅ Target Membership: `StudyAI` is checked
   - ✅ Type: "Default - JSON Text"

**If the file is NOT in Xcode**:
1. Right-click on `Lottie` folder in Xcode
2. Select "Add Files to StudyAI..."
3. Navigate to: `StudyAI/Lottie/Just Flow - Teal.json`
4. ✅ Check "Copy items if needed" is UNCHECKED (file is already there)
5. ✅ Check target "StudyAI"
6. Click "Add"

---

### Step 3: Build the Project

1. Clean build folder: **Product → Clean Build Folder** (Shift+Cmd+K)
2. Build: **Product → Build** (Cmd+B)
3. Check for any errors in the Issue Navigator

**Expected Result**: Build should succeed with 0 errors

---

### Step 4: Test the Loading Animation

#### Test 1: First Launch (Should Show Animation)

1. **Delete the app from simulator**:
   - Long press app icon in simulator
   - Select "Delete App"
   - Confirm deletion

2. **Run the app** (Cmd+R)

3. **Expected Behavior**:
   - ✅ Teal gradient background appears
   - ✅ "Just Flow - Teal" animation plays (wavy teal animation)
   - ✅ "StudyMates" text appears
   - ✅ "Loading..." text at bottom
   - ✅ Animation plays for ~3.5 seconds
   - ✅ Screen fades out smoothly
   - ✅ Login screen appears

4. **Check Console Logs**:
   ```
   🎬 [AppSession] First app launch - showing loading animation
   ```

#### Test 2: Continuous Session (Should Skip Animation)

1. **With app running**, press Home button (Cmd+Shift+H)
2. **Wait 5 seconds**
3. **Return to app** (click app icon in simulator)

4. **Expected Behavior**:
   - ✅ NO loading animation
   - ✅ App shows immediately (last screen you were on)

5. **Check Console Logs**:
   ```
   🎬 [AppSession] App entered background at [timestamp]
   🔐 [ContentView] App entering background...
   🔐 [ContentView] App returning to foreground...
   🎬 [AppSession] App became active
   🎬 [AppSession] Continuous session (5 sec) - skipping loading animation
   ```

#### Test 3: New Session After Timeout (Should Show Animation)

**Option A: Wait 31 minutes** (not practical for testing)

**Option B: Debug Trick (Recommended)**:
1. With app running, press Home button
2. Stop the app in Xcode (Stop button or Cmd+.)
3. In Xcode debug console, run:
   ```swift
   // Set background time to 31 minutes ago
   let oldTime = Date().timeIntervalSince1970 - (31 * 60)
   UserDefaults.standard.set(oldTime, forKey: "lastAppBackgroundTime")
   ```
4. Run the app again (Cmd+R)

5. **Expected Behavior**:
   - ✅ Loading animation shows again (treated as new session)

6. **Check Console Logs**:
   ```
   🎬 [AppSession] Session expired (31 min) - showing loading animation
   ```

**Option C: Modify Session Timeout (for testing)**:

Edit `AppSessionManager.swift` line 19:
```swift
// Change from 30 minutes to 10 seconds (for testing)
private let sessionTimeout: TimeInterval = 10  // 10 seconds instead of 30 * 60

// Don't forget to change back after testing!
```

Then:
1. Build and run
2. Background the app (Cmd+Shift+H)
3. Wait 11 seconds
4. Return to app
5. ✅ Should show loading animation

---

## 🐛 Troubleshooting

### Issue: Build errors about LottieView

**Error**: `Cannot find 'LottieView' in scope`

**Solution**: The project already has a custom `LottieView` wrapper in `Views/Components/LottieView.swift`. Make sure:
1. That file exists
2. It's added to the Xcode project
3. Target membership includes "StudyAI"

### Issue: Animation file not found

**Error**: Console shows "Could not find animation named 'Just Flow - Teal'"

**Solutions**:
1. **Check file is in bundle**:
   - Select "Just Flow - Teal.json" in Xcode
   - Verify Target Membership checkbox is checked for "StudyAI"

2. **Check Build Phases**:
   - Select StudyAI target
   - Go to "Build Phases"
   - Expand "Copy Bundle Resources"
   - Verify "Just Flow - Teal.json" is listed
   - If not, click "+" and add it

3. **Clean and rebuild**:
   - Product → Clean Build Folder (Shift+Cmd+K)
   - Product → Build (Cmd+B)

### Issue: Animation doesn't show at all

**Check**:
1. Console logs - look for `🎬 [AppSession]` messages
2. If you see "Continuous session - skipping loading animation", delete the app and try again

**Force show animation**:
In Xcode debug console:
```swift
UserDefaults.standard.removeObject(forKey: "lastAppBackgroundTime")
```
Then relaunch the app.

### Issue: App crashes on launch

**Check**:
1. Make sure both new Swift files are added to Xcode project
2. Check for any build errors
3. Look at crash logs in Console

---

## 🎨 Customization (Optional)

### Change Session Timeout

**File**: `AppSessionManager.swift:19`
```swift
private let sessionTimeout: TimeInterval = 30 * 60  // 30 minutes

// Examples:
// 10 minutes: 10 * 60
// 1 hour: 60 * 60
// 5 minutes (testing): 5 * 60
```

### Change Animation Duration

**File**: `LoadingAnimationView.swift:60`
```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
    // Change 3.5 to your desired duration (seconds)
}
```

### Change Background Colors

**File**: `LoadingAnimationView.swift:21-24`
```swift
LinearGradient(
    colors: [
        Color(red: 0, green: 0.803, blue: 0.839),  // Top color
        Color(red: 0.180, green: 0.514, blue: 0.541)  // Bottom color
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)
```

### Change App Name Text

**File**: `LoadingAnimationView.swift:42`
```swift
Text("StudyMates")  // Change to your preferred text
```

---

## ✅ Verification Checklist

Before considering this complete, verify:

- [ ] LoadingAnimationView.swift added to Xcode project (Views folder)
- [ ] AppSessionManager.swift added to Xcode project (Services folder)
- [ ] "Just Flow - Teal.json" is in Xcode project (Lottie folder) with target membership
- [ ] Project builds with 0 errors (Cmd+B)
- [ ] First launch shows loading animation (~3.5 seconds)
- [ ] Quick return to foreground skips animation
- [ ] Console shows appropriate `🎬 [AppSession]` logs
- [ ] Animation plays smoothly (teal wave effect)
- [ ] Fade-out transition is smooth
- [ ] Login screen appears after animation

---

## 📝 Summary

**What was implemented**:
1. ✅ Full-screen Lottie loading animation
2. ✅ Session tracking (30-minute timeout)
3. ✅ Smart skip for continuous sessions
4. ✅ One full animation cycle guaranteed on new sessions
5. ✅ Smooth fade transitions

**User Experience**:
- **First launch**: Beautiful teal animation (~3.5 sec)
- **Quick return** (<30 min): Instant access, no animation
- **New session** (>30 min): Fresh animation experience

**Architecture**:
- `AppSessionManager`: Tracks session state using UserDefaults
- `LoadingAnimationView`: Full-screen view with Lottie animation
- `ContentView`: Orchestrates animation display with ZStack overlay

---

## 🚀 Next Steps

1. Add the two new Swift files to Xcode (if not already done)
2. Verify Lottie animation file has target membership
3. Build the project (Cmd+B)
4. Run and test all three scenarios
5. Enjoy your beautiful loading animation! 🎉

---

**Questions?** Check the main documentation: `LOADING_ANIMATION_IMPLEMENTATION.md`
