# Loading Animation - Quick Reference

## ✅ What's Ready

All code is written and ready. You just need to add files to Xcode.

### Files Created:
1. ✅ `Views/LoadingAnimationView.swift` - Full-screen loading view
2. ✅ `Services/AppSessionManager.swift` - Session tracking logic
3. ✅ `ContentView.swift` - Updated with animation integration
4. ✅ `Lottie/Just Flow - Teal.json` - Animation file (you added this)

---

## 🎯 In Xcode, Do This:

### Step 1: Add LoadingAnimationView.swift
1. Right-click `Views` folder in Xcode
2. "Add Files to StudyAI..."
3. Select: `StudyAI/StudyAI/Views/LoadingAnimationView.swift`
4. ✅ Target: StudyAI
5. Click Add

### Step 2: Add AppSessionManager.swift
1. Right-click `Services` folder in Xcode
2. "Add Files to StudyAI..."
3. Select: `StudyAI/StudyAI/Services/AppSessionManager.swift`
4. ✅ Target: StudyAI
5. Click Add

### Step 3: Verify Lottie File
1. Check that `Lottie/Just Flow - Teal.json` appears in Xcode
2. Click the file, check Target Membership: ✅ StudyAI

### Step 4: Build
Press **Cmd+B**

---

## 🧪 Testing

### Test 1: First Launch (Shows Animation)
1. Delete app from simulator
2. Run (Cmd+R)
3. ✅ Should see teal animation for ~3.5 seconds

### Test 2: Quick Return (Skips Animation)
1. Background app (Cmd+Shift+H)
2. Wait 5 seconds
3. Open app again
4. ✅ Should see app immediately (no animation)

### Test 3: After 30 Minutes (Shows Animation)
**Quick Test Method**:
1. Background app
2. Stop app in Xcode
3. In debug console:
   ```swift
   UserDefaults.standard.set(Date().timeIntervalSince1970 - (31 * 60), forKey: "lastAppBackgroundTime")
   ```
4. Run app again (Cmd+R)
5. ✅ Should see animation (treated as new session)

---

## 🐛 Troubleshooting

### Build Error: "Cannot find 'LottieView'"
**Solution**: Make sure `Views/Components/LottieView.swift` is in the project with target membership checked.

### Animation File Not Found
**Solution**:
1. Select "Just Flow - Teal.json" in Xcode
2. Check Target Membership: ✅ StudyAI
3. Build Phases → Copy Bundle Resources → Verify file is listed

### Animation Doesn't Show
**Solution**: Delete app and reinstall (first launch always shows animation)

---

## 📖 Documentation

- **Complete Details**: `LOADING_ANIMATION_IMPLEMENTATION.md`
- **Step-by-Step Xcode Setup**: `XCODE_SETUP_INSTRUCTIONS.md`
- **This Quick Reference**: `LOADING_ANIMATION_QUICK_REF.md`

---

## ⚙️ How It Works

**Session Tracking**:
- First launch: No previous session → **Show animation**
- Quick return (<30 min): Continuous session → **Skip animation**
- Long absence (>30 min): New session → **Show animation**

**User Experience**:
- Beautiful teal wave animation on fresh starts
- Instant access when quickly returning to app
- Smart detection of continuous vs new sessions

---

## 🎨 Customization

**Change timeout** (AppSessionManager.swift:19):
```swift
private let sessionTimeout: TimeInterval = 30 * 60  // Change 30 to desired minutes
```

**Change animation duration** (LoadingAnimationView.swift:60):
```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {  // Change 3.5 to desired seconds
```

---

**That's it!** Just add the two Swift files to Xcode and build. 🚀
