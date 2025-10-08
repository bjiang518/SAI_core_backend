# Parent Mode & Password Management System

## Overview

The Parent Mode system provides a secure way to restrict access to sensitive features in the StudyAI app. Parents can set a 6-digit PIN that must be entered to access protected features.

## Files Created

### 1. **ParentModeManager.swift** (`Services/ParentModeManager.swift`)
Singleton service that manages parent mode authentication and password storage.

**Key Features:**
- Set/change/remove 6-digit parent password
- Verify parent authentication
- Track authentication session
- Check if parent authentication is required

### 2. **PasswordManagementView.swift** (`Views/PasswordManagementView.swift`)
Complete UI for password management including:
- Change account password (placeholder)
- Set parent password
- Change parent password
- Remove parent password

### 3. **ParentAuthenticationView.swift** (`Views/ParentAuthenticationView.swift`)
Reusable authentication modal for protecting features.

**Features:**
- 6-digit PIN entry
- Auto-verify on 6-digit input
- Failed attempt tracking (3 attempts max)
- Account lockout after 3 failures
- Haptic feedback

### 4. **ContentView.swift** (Modified)
Connected Password Manager button to open PasswordManagementView.

---

## How to Use

### For Settings (Already Implemented)

1. User taps **Settings** (gear icon) → **Security** → **Password Manager**
2. Opens `PasswordManagementView` with options:
   - **Set Parent Password** (if not set)
   - **Change Parent Password** (if already set)
   - **Remove Parent Password** (if already set)
   - **Change Account Password** (placeholder for now)

### For Protecting Features (Implementation Guide)

There are **two ways** to protect a feature with parent authentication:

---

## Method 1: Using the `.parentProtected()` Modifier

**Best for:** Buttons, list items, or any tappable view

```swift
import SwiftUI

struct MyView: View {
    var body: some View {
        Button("Delete All Data") {
            // This won't be called unless authenticated
            deleteAllData()
        }
        .parentProtected(
            title: "Delete Data",
            message: "This action requires parent permission",
            action: {
                // Code runs ONLY after successful authentication
                deleteAllData()
            }
        )
    }
}
```

---

## Method 2: Manual Authentication Check

**Best for:** Complex navigation flows or conditional logic

```swift
import SwiftUI

struct MyView: View {
    @StateObject private var parentModeManager = ParentModeManager.shared
    @State private var showingAuthView = false
    @State private var showingProtectedView = false

    var body: some View {
        Button("Access Protected Feature") {
            if parentModeManager.requiresParentAuthentication() {
                // Show auth modal if parent mode is enabled
                showingAuthView = true
            } else {
                // Direct access if parent mode is disabled
                showingProtectedView = true
            }
        }
        .sheet(isPresented: $showingAuthView) {
            ParentAuthenticationView(
                title: "Parent Verification",
                message: "This feature requires parent permission",
                onSuccess: {
                    // Authentication successful - show protected view
                    showingProtectedView = true
                }
            )
        }
        .sheet(isPresented: $showingProtectedView) {
            ProtectedFeatureView()
        }
    }
}
```

---

## Example: Protecting Parent Reports

Here's how you would protect the "Parent Reports" feature in `HomeView.swift`:

### Before (Unprotected):
```swift
HorizontalActionButton(
    icon: "doc.text.fill",
    title: "Parent Reports",
    subtitle: "Study progress & insights",
    color: DesignTokens.Colors.analyticsPlum,
    action: { showingParentReports = true }
)
```

### After (Protected):
```swift
HorizontalActionButton(
    icon: "doc.text.fill",
    title: "Parent Reports",
    subtitle: "Study progress & insights",
    color: DesignTokens.Colors.analyticsPlum,
    action: {
        if parentModeManager.requiresParentAuthentication() {
            showingParentAuth = true
        } else {
            showingParentReports = true
        }
    }
)
.sheet(isPresented: $showingParentAuth) {
    ParentAuthenticationView(
        title: "Parent Reports Access",
        message: "View detailed progress reports",
        onSuccess: { showingParentReports = true }
    )
}
```

---

## ParentModeManager API

### Check Authentication Status
```swift
let parentModeManager = ParentModeManager.shared

// Check if parent mode is enabled
if parentModeManager.isParentModeEnabled {
    print("Parent mode is active")
}

// Check if authentication is required
if parentModeManager.requiresParentAuthentication() {
    // Show authentication modal
}

// Check if currently authenticated
if parentModeManager.isParentAuthenticated {
    print("Parent is authenticated")
}
```

### Password Management
```swift
// Set password (first time)
let success = parentModeManager.setParentPassword("123456")

// Verify password
let isValid = parentModeManager.verifyParentPassword("123456")

// Change password
let result = parentModeManager.changeParentPassword(
    currentPassword: "123456",
    newPassword: "654321"
)

// Remove password
let removed = parentModeManager.removeParentPassword(password: "123456")
```

### Session Management
```swift
// Sign out from parent mode (require re-authentication)
parentModeManager.signOutParentMode()
```

---

## Security Features

### Current Implementation:
- ✅ 6-digit numeric PIN
- ✅ Password stored in UserDefaults (local device only)
- ✅ Failed attempt tracking (3 attempts max)
- ✅ Account lockout after failures
- ✅ Session-based authentication (stays authenticated)

### Future Enhancements:
- 🔐 **Move to Keychain** - For production, store password in iOS Keychain instead of UserDefaults
- ⏱️ **Timeout-based sessions** - Auto sign-out after inactivity
- 🔔 **Notification on failed attempts** - Alert parents of unauthorized access attempts
- 📧 **Email/SMS recovery** - Password recovery via parent email
- 🔑 **Biometric unlock** - Allow Face ID/Touch ID for parent authentication

---

## User Flow Examples

### First-Time Setup:
1. User opens **Settings → Security → Password Manager**
2. Taps **"Set Parent Password"**
3. Enters 6-digit PIN twice
4. Parent mode is now **enabled**
5. Protected features now require this PIN

### Accessing Protected Feature:
1. User taps protected feature (e.g., "Parent Reports")
2. If parent mode is enabled → **Authentication modal appears**
3. Enter 6-digit PIN
4. If correct → **Feature opens**
5. If incorrect → **Error message, 2 attempts remaining**
6. After 3 failed attempts → **Account locked** (temporary)

### Changing Password:
1. User opens **Settings → Security → Password Manager**
2. Taps **"Change Parent Password"**
3. Enters **current PIN**
4. Enters **new PIN** twice
5. Password updated successfully

### Removing Parent Mode:
1. User opens **Settings → Security → Password Manager**
2. Taps **"Remove Parent Password"**
3. Sees warning about disabling restrictions
4. Enters **current PIN** to confirm
5. Parent mode is now **disabled**
6. All features are now accessible without PIN

---

## Testing Checklist

- [ ] Set parent password for first time
- [ ] Verify password works
- [ ] Try incorrect password (should fail)
- [ ] Try 3 incorrect passwords (should lock)
- [ ] Change password successfully
- [ ] Remove password successfully
- [ ] Protect a feature with `.parentProtected()` modifier
- [ ] Protect a feature with manual check
- [ ] Test authentication session persistence

---

## Next Steps

To protect a specific feature:

1. **Import ParentModeManager**:
   ```swift
   @StateObject private var parentModeManager = ParentModeManager.shared
   @State private var showingAuthView = false
   ```

2. **Add authentication check**:
   ```swift
   action: {
       if parentModeManager.requiresParentAuthentication() {
           showingAuthView = true
       } else {
           // Direct access
       }
   }
   ```

3. **Add authentication sheet**:
   ```swift
   .sheet(isPresented: $showingAuthView) {
       ParentAuthenticationView(
           title: "Feature Name",
           message: "Reason for protection",
           onSuccess: { /* Grant access */ }
       )
   }
   ```

---

## Summary

✅ **Password Manager** - Complete UI for setting/changing/removing passwords
✅ **Parent Mode Service** - Secure authentication management
✅ **Authentication Modal** - Reusable UI component
✅ **Easy Integration** - Simple API for protecting features
✅ **Security Features** - Failed attempt tracking, lockout, session management

**Status**: Ready to use! 🎉

To protect any feature, just add the parent authentication check before granting access.