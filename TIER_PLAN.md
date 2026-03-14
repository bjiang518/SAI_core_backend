# Guest Login + Tier/Subscription System — Full Implementation Plan

## Context

StudyAI currently has a flat auth system (email/Google/Apple only, all features open to all
logged-in users). The goal is to:
1. Add **Guest Login** so new users can try the app without registering
2. Add a **3-tier subscription system** (Free / Premium / Premium Plus) to gate features and
   enable monetization
3. Lay groundwork for **StoreKit 2 in-app purchases** (Phase 7, not in scope for this plan)

The database already has COPPA tables (`parental_consents`, `age_verifications`,
`consent_audit_log`) and user restriction flags. The tier system must be **additive** — no
COPPA logic is touched.

---

## Tier Definitions

### Tier 0 — Guest (anonymous backend account)
- `POST /api/auth/anonymous` creates a real DB user (`is_anonymous=true`, `tier='free'`)
- Returns a real JWT token — all AI calls go through normal backend auth
- Limits enforced backend-side (same Redis counter system as Free tier)
- Lifetime limits (not monthly) — no auto-reset; purpose is show value → convert
- Auto-deleted 30 days after last login (cron/cleanup job)

| Feature | Lifetime Limit |
|---------|---------------|
| Homework image analysis | 3 lifetime |
| Session chat messages | 10 lifetime |
| View progress / archives | blocked (no data yet) |
| All other features | blocked |

### Tier 1 — Free (registered, `tier = 'free'`)
- Full account, data synced to backend
- Monthly usage counters reset on the 1st of each month (Redis TTL)

| Feature | Monthly Limit |
|---------|--------------|
| Homework image analysis (single) | 10 |
| Session chat messages | 50 |
| Practice questions — Modes 1+2 combined | 30 questions total |
| Error analysis Pass 2 (deep analysis) | 5 |
| Pomodoro / Tomato Garden | Unlimited (local, zero API cost) |
| View progress & archives | Unlimited (DB reads only) |
| Gemini Live voice chat | blocked |
| Practice questions — Archive-based (Mode 3) | blocked |
| Passive parent reports | blocked |
| Batch homework processing | blocked |

### Tier 2 — Premium ($9.99/month or $79.99/year, `tier = 'premium'`)
Target margin: ~50-60% (avg user utilises ~50% of limits → ~$5-8 actual cost vs $9.99 revenue)

| Feature | Monthly Limit |
|---------|--------------|
| Homework image analysis (single) | 50 |
| Homework batch processing | 20 batches |
| Session chat messages | 500 |
| Practice questions — all 3 modes | 200 questions total |
| Error analysis Pass 2 | Unlimited |
| Gemini Live voice chat | 300 minutes |
| Passive parent reports | 2 batches |
| Pomodoro / Tomato Garden | Unlimited |
| View progress & archives | Unlimited |

### Tier 3 — Premium Plus ($19.99/month or $149.99/year, `tier = 'premium_plus'`)
Target: heavy users & families. All limits removed.

| Feature | Monthly Limit |
|---------|--------------|
| Everything in Premium | Unlimited |
| Gemini Live voice chat | Unlimited |
| Passive parent reports | Unlimited (weekly) |
| (Future) Multi-child accounts | Up to 3 sub-accounts |

---

## Cost Validation

| Scenario | Monthly Cost | Revenue | Gross Margin |
|----------|-------------|---------|-------------|
| Free tier (strict limits) | ~$0.50-1.50/user | $0 | — (acquisition cost) |
| Premium at 50% utilisation | ~$4-8/user | $9.99 | ~$2-6 (20-60%) |
| Premium Plus heavy user | ~$12-18/user | $19.99 | ~$2-8 (10-40%) |

---

## Architecture Overview

```
iOS "Continue as Guest" button
  → POST /api/auth/anonymous
  → DB: users row (is_anonymous=true, tier='free')
  → JWT returned, stored in Keychain (same path as normal login)

All AI requests:
  iOS (tier from Keychain) → UI gate via FeatureGate.swift
  Backend JWT auth → tier-check.js middleware → Redis usage counter
  → 403 UPGRADE_REQUIRED | 429 MONTHLY_LIMIT_REACHED | 200 OK

Redis key format: usage:{userId}:{featureKey}:{YYYY-MM}
  TTL = seconds until midnight on last day of current month
  Fallback: DB JSONB column monthly_usage on users table
```

---

## Files to Create (New)

| File | Purpose |
|------|---------|
| `02_ios_app/StudyAI/StudyAI/Models/UserTier.swift` | `UserTier` enum + `GatedFeature` enum |
| `02_ios_app/StudyAI/StudyAI/Services/FeatureGate.swift` | Central access control (tier + COPPA) |
| `02_ios_app/StudyAI/StudyAI/Services/GuestSessionService.swift` | Guest conversion prompt state |
| `02_ios_app/StudyAI/StudyAI/Services/UsageService.swift` | Reads `X-Usage-Remaining` headers; publishes remaining counts for UI |
| `02_ios_app/StudyAI/StudyAI/Views/UpgradePromptView.swift` | Reusable paywall sheet |
| `01_core_backend/src/gateway/middleware/tier-check.js` | Fastify preHandler: tier + usage enforcement |
| `01_core_backend/src/gateway/routes/ai/utils/usage-tracker.js` | Redis counter helpers |

---

## Files to Modify

| File | Changes |
|------|---------|
| `01_core_backend/src/utils/railway-database.js` | DB migration: `tier`, `tier_expires_at`, `is_anonymous`, `monthly_usage`, `usage_reset_date` columns; `subscriptions` table; `getUserTier()` + `incrementUsage()` helpers |
| `01_core_backend/src/gateway/routes/auth-routes.js` | Add `POST /api/auth/anonymous`; add `tier` + `is_anonymous` to all login/register/google/apple responses |
| `02_ios_app/StudyAI/StudyAI/Services/AuthenticationService.swift` | Add `tier: UserTier` + `isAnonymous: Bool` to `User` struct; add `AuthProvider.anonymous`; add `signInAsGuest()` async method; update response parsing |
| `02_ios_app/StudyAI/StudyAI/Models/UserProfile.swift` | Add `accountRestricted: Bool` field (default `false`); populated from `account_restricted` in profile API response |
| `02_ios_app/StudyAI/StudyAI/Views/ModernLoginView.swift` | Add "Continue as Guest" text button; add `conversionMode` parameter |
| `02_ios_app/StudyAI/StudyAI/ContentView.swift` | No structural change needed (existing `isAuthenticated` gate works for guest) |
| `01_core_backend/src/gateway/routes/ai/modules/homework-processing.js` | Add `tierCheck` preHandler to `processHomeworkImageJSON` and batch endpoint |
| `01_core_backend/src/gateway/routes/ai/modules/gemini-live-v2.js` | Block non-Premium at WS connect (~line 66); track minutes on `ws.close()` |
| `01_core_backend/src/gateway/routes/ai/modules/question-generation-v2.js` | Mode 3 mode-check preHandler before count preHandler; question count `tierCheck` |
| `01_core_backend/src/gateway/routes/ai/modules/session-management.js` | Add `tierCheck` to message endpoint |
| `01_core_backend/src/gateway/routes/ai/modules/error-analysis.js` (or equivalent) | Add `tierCheck({ feature: 'error_analysis' })` — free tier limit=5/mo; currently unenforced |
| `01_core_backend/src/gateway/routes/passive-reports.js` | Add `tierCheck` to `generate-now` endpoint |

---

## Phase 1 — Database Migration

**File**: `01_core_backend/src/utils/railway-database.js`

Add at the end of the `initializeDatabase()` migration block (after existing COPPA migrations):

```sql
-- Tier system (additive, does not touch COPPA columns)
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS tier VARCHAR(20) NOT NULL DEFAULT 'free',
  ADD COLUMN IF NOT EXISTS tier_expires_at TIMESTAMP,
  ADD COLUMN IF NOT EXISTS is_anonymous BOOLEAN NOT NULL DEFAULT false;

-- Monthly usage counters (JSONB map: feature_key -> count, Redis fallback)
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS monthly_usage JSONB NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS usage_reset_date DATE NOT NULL DEFAULT CURRENT_DATE;

-- Subscriptions table (for future StoreKit 2 / Stripe receipts)
CREATE TABLE IF NOT EXISTS subscriptions (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  tier           VARCHAR(20) NOT NULL,
  started_at     TIMESTAMP NOT NULL DEFAULT NOW(),
  expires_at     TIMESTAMP,
  platform       VARCHAR(20),        -- 'ios_iap' | 'stripe'
  transaction_id VARCHAR(255),
  is_active      BOOLEAN NOT NULL DEFAULT true,
  created_at     TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_subscriptions_user_id ON subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_active  ON subscriptions(user_id, is_active);
```

Add two new DB helper functions:

```js
// db.getUserTier(userId)
//   Returns: { tier, tier_expires_at, monthly_usage, usage_reset_date, is_anonymous }
//   Cached in userCache (1hr TTL — already exists in railway-database.js)

// db.incrementUsage(userId, featureKey)
//   Updates JSONB counter in users.monthly_usage
//   Resets counter if users.usage_reset_date < current month
```

---

## Phase 2 — Backend: Guest Endpoint + Tier in Login Response

**File**: `01_core_backend/src/gateway/routes/auth-routes.js`

### 2a. Add `tier` and `is_anonymous` to all existing auth responses

Current login response (auth-routes.js line 545):
```js
user: { id, email, name, profileImageUrl, provider, lastLogin }
```

Updated (apply to login, register, googleLogin, appleLogin handlers):
```js
user: { id, email, name, profileImageUrl, provider, lastLogin,
        tier: user.tier || 'free',
        is_anonymous: user.is_anonymous || false }
```

### 2b. New endpoint: `POST /api/auth/anonymous`

```js
// Rate limit: 10/hour per IP (prevents throwaway account spam)
// Body: {} (no fields required)
// Action:
//   1. Generate a random display name ("Guest_XXXX")
//   2. INSERT INTO users (name, is_anonymous, tier) VALUES (...)
//   3. Create session token via db.createUserSession()
//   4. Return same shape as login response
// Cleanup: cron job deletes users WHERE is_anonymous=true AND last_login_at < NOW() - INTERVAL '30 days'
```

---

## Phase 3 — Backend: Tier Check Middleware + Usage Tracker

### New file: `01_core_backend/src/gateway/routes/ai/utils/usage-tracker.js`

```js
const TIER_LIMITS = {
  guest: {
    homework_single: 3,   // lifetime (Redis key prefix: usage_lifetime:{userId}:{feature})
    chat_messages:   10,  // lifetime
    // All other features explicitly blocked (0) — do NOT rely on undefined → unlimited branch
    // for guests, as that branch is only valid for premium_plus.
    homework_batch:  0,
    questions:       0,
    error_analysis:  0,
    reports:         0,
    voice_minutes:   0,
  },
  free: {
    homework_single: 10,
    homework_batch:  0,   // 0 = blocked entirely
    chat_messages:   50,
    questions:       30,  // Modes 1+2 combined
    error_analysis:  5,
    reports:         0,
    voice_minutes:   0,
  },
  premium: {
    homework_single: 50,
    homework_batch:  20,
    chat_messages:   500,
    questions:       200,
    error_analysis:  Infinity,
    reports:         2,
    voice_minutes:   300,
  },
  premium_plus: {
    // Empty object = all features unlimited for premium_plus.
    // Do NOT rely on implicit undefined behavior — usageTracker.check() must
    // explicitly handle the missing key case (see check() spec below).
  }
};

// CRITICAL: Always determine effectiveTier before looking up limits:
//   const effectiveTier = isAnonymous ? 'guest' : tier;
//   const limits = TIER_LIMITS[effectiveTier] ?? {};  // undefined key = unlimited (premium_plus)

// usageTracker.check() MUST include an explicit unlimited branch:
//   const limit = limits[featureKey];
//   if (limit === undefined) {
//     // premium_plus or unknown future tier — always allowed, no counter incremented
//     return { allowed: true, remaining: Infinity, limit: Infinity, resets_at: null };
//   }
//   if (limit === 0) {
//     return { allowed: false, remaining: 0, limit: 0, resets_at: null };  // feature blocked
//   }
//   // ... normal Redis counter check for finite limits ...

// Redis key strategy:
//   Guest (isAnonymous=true):  "usage_lifetime:{userId}:{featureKey}"  — no TTL
//   Others (monthly):          "usage:{userId}:{featureKey}:{YYYY-MM}" — TTL to end of month

// usageTracker.check(userId, featureKey, tier, isAnonymous)
//   → { allowed: bool, remaining: int, limit: int, resets_at: Date|null }

// usageTracker.increment(userId, featureKey, isAnonymous)
//   → INCR on Redis; fallback to DB JSONB users.monthly_usage if Redis unavailable

// usageTracker.incrementBy(userId, featureKey, amount, isAnonymous)
//   → INCRBY amount on Redis; used for voice_minutes
//   Voice crash recovery:
//     - On WS connect:  redis.set("voice_session_start:{userId}", Date.now(), "EX", 7200)
//     - On WS close:    elapsed = Math.ceil((Date.now() - start) / 60000), incrementBy(elapsed)
//                       (MUST use Math.ceil — Redis INCRBY only accepts integers, not floats)
//                       redis.del("voice_session_start:{userId}")
//     - Crash recovery: cron job checks voice_session_start:* keys, bills remaining minutes
```

### New file: `01_core_backend/src/gateway/middleware/tier-check.js`

```js
// Factory: creates a Fastify preHandler hook
// Usage: tierCheck({ feature: 'homework_single' })
//
// tier-check.js imports auth-helper directly as a module:
//   const { getUserId } = require('../routes/ai/utils/auth-helper');
//   (tier-check.js is at src/gateway/middleware/ — auth-helper is at src/gateway/routes/ai/utils/
//    so '../utils/auth-helper' would be MODULE_NOT_FOUND; must traverse through routes/ai/utils)
// Hook logic:
//   1. getUserId(request) → userId  [functional import, same as question-generation-v2.js]
//      NOTE: homework-processing.js uses class-based this.authHelper.getUserIdFromToken() because
//      it instantiates AuthHelper as a class member. tier-check.js does NOT do this — it requires
//      the module directly and uses the named export.
//   2. db.getUserTier(userId) → { tier, is_anonymous } (1hr userCache)
//   3. effectiveTier = is_anonymous ? 'guest' : tier
//   4. usageTracker.check(userId, feature, effectiveTier, is_anonymous)
//   5a. limit === 0 (feature blocked for this tier):
//       reply.status(403).send({ error: 'UPGRADE_REQUIRED', tier_required: 'premium' })
//   5b. remaining === 0 (limit reached):
//       reply.status(429).send({
//         error: is_anonymous ? 'LIFETIME_LIMIT_REACHED' : 'MONTHLY_LIMIT_REACHED',
//         resets_at, feature
//       })
//   5c. allowed:
//       await usageTracker.increment(userId, feature, is_anonymous)
//       reply.header('X-Usage-Remaining', remaining - 1)
//       done()
```

### CRITICAL: `preHandler` placement (Fastify route options level, NOT inside `config`)

```js
// WRONG — preHandler inside config is silently ignored by Fastify:
this.fastify.post('/api/ai/...', {
  config: { rateLimit: {...}, preHandler: [tierCheck(...)] }  // never executes
}, handler);

// CORRECT — preHandler at route options level:
this.fastify.post('/api/ai/...', {
  config: { rateLimit: { max: 15, timeWindow: '1 hour', keyGenerator: ..., ... } },
  preHandler: [tierCheck({ feature: 'homework_single' })]  // top-level option
}, handler);
```

### Wire into endpoints:

**homework-processing.js** — single image:
```js
this.fastify.post('/api/ai/process-homework-image-json', {
  config: { rateLimit: { max: 15, timeWindow: '1 hour', keyGenerator: ..., ... } },
  preHandler: [tierCheck({ feature: 'homework_single' })]
}, this.processHomeworkImageJSON.bind(this));
```

**homework-processing.js** — batch:
```js
this.fastify.post('/api/ai/process-homework-images-batch', {
  config: { rateLimit: { max: 5, timeWindow: '1 hour', keyGenerator: ..., ... } },
  preHandler: [tierCheck({ feature: 'homework_batch' })]
}, this.processHomeworkImagesBatch.bind(this));
// free tier: limit=0 → instant 403 UPGRADE_REQUIRED before any AI call
```

**question-generation-v2.js** — two preHandlers in ORDER (mode check BEFORE count increment):
```js
// IMPORTANT: Mode 3 check must run BEFORE tierCheck to avoid charging a usage slot
// for a feature the user can't access.
preHandler: [
  // Step 1: Block Mode 3 for non-premium BEFORE any counter is incremented
  async (request, reply) => {
    const { mode } = request.body;
    if (mode === 3) {
      // question-generation-v2.js uses: const { getUserId } = require('../utils/auth-helper')
      // NOT the class-based authHelper pattern from homework-processing.js
      const userId = await getUserId(request);
      const { tier, is_anonymous } = await db.getUserTier(userId);
      const effectiveTier = is_anonymous ? 'guest' : tier;
      if (effectiveTier !== 'premium' && effectiveTier !== 'premium_plus') {
        return reply.status(403).send({ error: 'UPGRADE_REQUIRED', tier_required: 'premium' });
      }
    }
    // Mode 1 and 2 fall through to the count check below
  },
  // Step 2: Only reached if mode is allowed — now check/increment the usage counter
  tierCheck({ feature: 'questions' })
]
```

**gemini-live-v2.js** — after token verify (~line 66):
```js
const { tier, is_anonymous } = await db.getUserTier(userId);
const effectiveTier = is_anonymous ? 'guest' : tier;
if (effectiveTier !== 'premium' && effectiveTier !== 'premium_plus') {
  ws.send(JSON.stringify({ type: 'error', code: 'UPGRADE_REQUIRED' }));
  ws.close(1008, 'Premium required'); return;
}
// Write crash-recovery key before opening Gemini WS:
await redis.set(`voice_session_start:${userId}`, Date.now(), 'EX', 7200);
// On ws.close(): compute elapsed minutes, call usageTracker.incrementBy(...)
// Then: await redis.del(`voice_session_start:${userId}`)
```

**session-management.js** — message endpoint:
```js
preHandler: [tierCheck({ feature: 'chat_messages' })]
```

**error-analysis route** (registered in `ai/index.js` line 90 as `ErrorAnalysisRoutes`):
```js
// Find the endpoint in error-analysis.js that handles Pass 2 analysis requests.
// Add tierCheck to enforce the free tier limit of 5/month.
// Without this, the 5/month limit in TIER_LIMITS is decorative — never enforced.
preHandler: [tierCheck({ feature: 'error_analysis' })]
// free tier: 5/month; premium: Infinity
```

**passive-reports.js** — generate-now:
```js
preHandler: [tierCheck({ feature: 'reports' })]
```

### Cache invalidation on tier upgrade

When a subscription is created or user converts from guest (Phase 7 / conversion flow):
```js
userCache.del(userId);  // bust 1hr tier cache immediately so new tier takes effect at once
```
Without this, a newly upgraded user waits up to 1 hour before Premium features unlock.

---

## Phase 4 — iOS: User Model + Guest Auth

### New file: `02_ios_app/StudyAI/StudyAI/Models/UserTier.swift`

```swift
enum UserTier: String, Codable {
    // NOTE: Backend stores anonymous users with tier='free' and is_anonymous=true.
    // The server NEVER sends "guest" as a tier value.
    // user.tier for a guest is always .free — .guest.displayName is never called at runtime.
    //
    // Decision: REMOVE the .guest case entirely. Guest detection uses user.isAnonymous exclusively.
    // Keeping .guest would mislead developers into checking user.tier == .guest (which never matches).
    case free         = "free"
    case premium      = "premium"
    case premiumPlus  = "premium_plus"

    var displayName: String {
        switch self {
        case .free:        return "Free"
        case .premium:     return "Premium"
        case .premiumPlus: return "Premium Plus"
        }
    }

    var isPaid: Bool { self == .premium || self == .premiumPlus }
}

enum GatedFeature {
    case homeworkAnalysis
    case batchHomework
    case chatMessage
    case voiceChat
    case questionGeneration(mode: Int)   // mode 3 = premium only
    case errorAnalysisDeep
    case parentReport
}
```

### Modify: `02_ios_app/StudyAI/StudyAI/Services/AuthenticationService.swift`

```swift
// 1. Extend User struct (lines 27-35) with BACKWARD-COMPATIBLE Decodable:
// User is stored as JSON in Keychain. Existing users have no tier/isAnonymous keys.
// Non-optional fields with no default will throw on JSONDecoder — logging ALL existing users out.
// Fix: use custom init(from:) with try? fallbacks for new fields.
struct User: Codable {
    let id: String
    let email: String       // empty string "" for anonymous users
    let name: String
    let profileImageURL: String?
    let authProvider: AuthProvider
    let createdAt: Date
    let lastLoginAt: Date
    let tier: UserTier      // NEW
    let isAnonymous: Bool   // NEW

    // Custom Decodable so existing Keychain blobs (no tier/isAnonymous) decode without throwing
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(String.self, forKey: .id)
        email          = try c.decode(String.self, forKey: .email)
        name           = try c.decode(String.self, forKey: .name)
        profileImageURL = try? c.decode(String.self, forKey: .profileImageURL)
        authProvider   = try c.decode(AuthProvider.self, forKey: .authProvider)
        createdAt      = try c.decode(Date.self, forKey: .createdAt)
        lastLoginAt    = try c.decode(Date.self, forKey: .lastLoginAt)
        tier        = (try? c.decode(UserTier.self, forKey: .tier)) ?? .free      // fallback
        isAnonymous = (try? c.decode(Bool.self,     forKey: .isAnonymous)) ?? false // fallback
    }
}

// 2. Add to AuthProvider enum:
case anonymous = "anonymous"

// 3. Add signInAsGuest() after existing sign-in methods:
@MainActor
func signInAsGuest() async {
    isLoading = true
    defer { isLoading = false }
    do {
        let result = await networkService.anonymousLogin()
        // Parse response same as signInWithEmail — tier='free', is_anonymous=true
        // Save token + user to Keychain (identical path to normal login)
        // Set isAuthenticated = true
    } catch {
        errorMessage = error.localizedDescription
    }
}

// 4. Update login/register/google/apple response parsing (lines ~271-279):
// Add: tier: UserTier(rawValue: userData["tier"] as? String ?? "free") ?? .free
//      isAnonymous: userData["is_anonymous"] as? Bool ?? false
```

### Modify: `02_ios_app/StudyAI/StudyAI/Views/ModernLoginView.swift`

Add after the Google Sign-In button (around line 317), before sign-up prompt:

```swift
// "Continue as Guest" — subtle text button, not a prominent CTA
Divider().padding(.vertical, 8)

Button {
    Task { await authService.signInAsGuest() }
} label: {
    Text("Continue as Guest")
        .font(.subheadline)
        .foregroundColor(ThemeManager.shared.secondaryText)
}
.disabled(authService.isLoading)
```

Add optional `conversionMode: Bool = false` init parameter:
- When `true`: header text = "Save Your Progress", hides Guest button, shows Back/dismiss button

### New file: `02_ios_app/StudyAI/StudyAI/Services/FeatureGate.swift`

```swift
struct FeatureGate {

    enum GateResult {
        case allowed
        case blocked(reason: BlockReason)
    }

    enum BlockReason {
        case upgradeRequired(minTier: UserTier)
        case monthlyLimitReached(feature: GatedFeature)
        case coppaRestricted
        case notAuthenticated
    }

    static func check(_ feature: GatedFeature, user: User?) -> GateResult {
        guard let user else { return .blocked(reason: .notAuthenticated) }

        // COPPA restriction overrides tier.
        // accountRestricted is read from UserProfile (see Phase 4 — UserProfile change below).
        // Use a switch (not featureMatches) because GatedFeature has associated values
        // and is NOT Equatable without a custom == implementation.
        if ProfileService.shared.currentProfile?.accountRestricted == true {
            switch feature {
            case .voiceChat, .parentReport:
                return .blocked(reason: .coppaRestricted)
            default:
                break
            }
        }

        // Tier-based access (instant UI gate — backend always re-validates)
        switch feature {
        case .batchHomework:
            if !user.tier.isPaid { return .blocked(reason: .upgradeRequired(minTier: .premium)) }
        case .voiceChat:
            if !user.tier.isPaid { return .blocked(reason: .upgradeRequired(minTier: .premium)) }
        case .questionGeneration(let mode) where mode == 3:
            if !user.tier.isPaid { return .blocked(reason: .upgradeRequired(minTier: .premium)) }
        case .parentReport:
            if !user.tier.isPaid { return .blocked(reason: .upgradeRequired(minTier: .premium)) }
        default:
            break
        }

        return .allowed
    }
}
```

**Note**: `GatedFeature` has associated values (`.questionGeneration(mode: Int)`) so it cannot
use `contains()` with `==`. All comparisons must use `switch` statements. Do NOT add an
`Equatable` conformance unless all associated values are also `Equatable` — the switch approach
is simpler and safer.

### Add `accountRestricted` to `UserProfile`

**File**: `02_ios_app/StudyAI/StudyAI/Models/UserProfile.swift`

`UserProfile` already has a fully **custom** `init(from decoder:)` with an explicit `CodingKeys`
enum (lines 78–86). Adding a non-optional property without updating the custom init causes a
**compile error** — the init body doesn't initialize it. Three steps required:

**Step 1**: Add to `CodingKeys` enum:
```swift
case accountRestricted = "account_restricted"
```

**Step 2**: Add to existing `init(from decoder:)` body (with fallback for old cached responses):
```swift
accountRestricted = (try? container.decodeIfPresent(Bool.self, forKey: .accountRestricted)) ?? false
```

**Step 3**: Add `account_restricted` to the backend profile query in `auth-routes.js`.
Find the `getProfileDetails` handler — it queries the `users` table (or a JOIN with `profiles`).
Add `u.account_restricted` to the SELECT:
```js
// In getProfileDetails SQL query, add:
// u.account_restricted
// Return it in the response object:
account_restricted: user.account_restricted ?? false
```

Without all three steps, either it fails to compile or the `FeatureGate` COPPA check silently
never fires (reads `nil` from `ProfileService`, defaults to `false`, COPPA restriction bypassed).

### New file: `02_ios_app/StudyAI/StudyAI/Services/GuestSessionService.swift`

```swift
// Manages guest-to-account conversion prompt state only.
// All usage limits are enforced backend-side — no local counters.
class GuestSessionService: ObservableObject {
    static let shared = GuestSessionService()
    @Published var showConversionPrompt = false

    // Call from UpgradePromptView and ProfileView when user is anonymous
    func promptConversion() { showConversionPrompt = true }
}
```

### New file: `02_ios_app/StudyAI/StudyAI/Services/UsageService.swift`

```swift
// Reads X-Usage-Remaining response headers from AI endpoints.
// NetworkService calls UsageService.shared.update(feature:remaining:) after each AI response.
// Views observe remainingUsage to display "X uses left" badges.
class UsageService: ObservableObject {
    static let shared = UsageService()
    @Published var remainingUsage: [String: Int] = [:]

    func update(feature: String, remaining: Int) {
        remainingUsage[feature] = remaining
    }
}
```

**Header plumbing in NetworkService**: Add `X-Usage-Remaining` header reading to the
network methods that call counted AI endpoints.

SessionChatView uses the **streaming** path, not `sendSessionMessage`. From the codebase,
there are 4 session message methods — only the streaming ones need this:

| Method | Line | Add header read? |
|--------|------|-----------------|
| `sendSessionMessage` | ~988 | No (non-streaming path, not used by active chat UI) |
| `sendSessionMessageStreamingWithRetry` | ~1167 | **YES** — active chat primary path |
| `sendSessionMessageStreaming` | ~1284 | **YES** — called by retry wrapper |
| `sendSessionMessageInteractive` | ~1594 | No (interactive/diagram, not a counted feature) |

The `tierCheck({ feature: 'chat_messages' })` preHandler fires on the streaming endpoint.
The `X-Usage-Remaining` header is set in that HTTP response. Reading it in `sendSessionMessage`
(wrong method) means the "X uses left" badge in the chat input bar **never updates**.

```swift
// Add to sendSessionMessageStreamingWithRetry and sendSessionMessageStreaming,
// after receiving the initial HTTP response (before consuming the SSE stream):
if let remaining = httpResponse.value(forHTTPHeaderField: "X-Usage-Remaining"),
   let count = Int(remaining) {
    await MainActor.run {
        UsageService.shared.update(feature: "chat_messages", remaining: count)
    }
}
```

For non-streaming methods (homework, questions):
```swift
// After receiving HTTPURLResponse in processHomeworkImage(), generatePracticeQuestions():
if let remaining = httpResponse.value(forHTTPHeaderField: "X-Usage-Remaining"),
   let count = Int(remaining) {
    UsageService.shared.update(feature: featureKey, remaining: count)
}
```

### New file: `02_ios_app/StudyAI/StudyAI/Views/UpgradePromptView.swift`

```swift
struct UpgradePromptView: View {
    let blockedFeature: GatedFeature
    let reason: FeatureGate.BlockReason
    var onDismiss: () -> Void
    @EnvironmentObject var authService: AuthenticationService

    var body: some View {
        // Sheet content:
        // - If reason == .upgradeRequired && user.isAnonymous:
        //     "Create a Free Account" as primary CTA → present ModernLoginView(conversionMode: true)
        // - If reason == .upgradeRequired && !user.isAnonymous:
        //     "Upgrade to Premium" primary CTA + pricing
        //     "Continue with Free" secondary
        // - If reason == .monthlyLimitReached:
        //     "You've used all X this month" + resets_at date + upgrade CTA
        // - If reason == .coppaRestricted:
        //     "Ask a parent to unlock this feature"
        // Uses ThemeManager for colors; DesignTokens.Colors.Cute for accents
    }
}
```

---

## Phase 5 — iOS: Feature Gate Call Sites in Views

Add `@State private var showingUpgradePrompt = false` + `FeatureGate.check()` at each entry point:

| View | Entry Point | Feature | Behavior if blocked |
|------|------------|---------|---------------------|
| `DirectAIHomeworkView` | Camera capture button | `.homeworkAnalysis` | Show remaining count; backend returns 429 after limit |
| `DirectAIHomeworkView` | Batch upload button | `.batchHomework` | Show `UpgradePromptView` immediately (tier gate) |
| `SessionChatView` | Send message button | `.chatMessage` | Backend returns 429; iOS shows "50/50 used" in input bar |
| `SessionChatView` | "Live Talk" in 3-dot menu (line ~273) | `.voiceChat` | Show `UpgradePromptView` before even opening WS |
| `PracticeLibraryView` | Mode 3 (Archive) tab | `.questionGeneration(mode: 3)` | Dim tab + show `UpgradePromptView` on tap |
| `HomeView` | Parent Reports button | `.parentReport` | Show `UpgradePromptView` |

Pattern (example for Live Talk in SessionChatView):
```swift
// In the 3-dot menu action (around line 273 of SessionChatView.swift)
Button("Live Talk") {
    let result = FeatureGate.check(.voiceChat, user: authService.currentUser)
    switch result {
    case .allowed:
        enterLiveMode()
    case .blocked:
        showingUpgradePrompt = true
    }
}
.sheet(isPresented: $showingUpgradePrompt) {
    UpgradePromptView(
        blockedFeature: .voiceChat,
        reason: .upgradeRequired(minTier: .premium),
        onDismiss: { showingUpgradePrompt = false }
    )
}
```

For features with monthly limits (homework, chat): iOS should display remaining count.
Backend includes `X-Usage-Remaining: 7` header on AI responses. NetworkService reads this
header and stores in a `@Published var remainingUsage: [String: Int]` on a new lightweight
`UsageService.shared`.

### 429 handling in NetworkService (REQUIRED — not just a UI detail)

A 429 response from a rate-limited AI endpoint currently falls through as a generic network
error in `NetworkService`, showing a confusing "request failed" toast. Each AI method that
can be rate-limited must detect `MONTHLY_LIMIT_REACHED` / `LIFETIME_LIMIT_REACHED` and
surface it as a distinct result so views can show `UpgradePromptView` instead.

Pattern for `processHomeworkImage()` in NetworkService:

```swift
// After receiving the HTTP response:
if httpResponse.statusCode == 429,
   let body = try? JSONDecoder().decode([String: String].self, from: data),
   let errorCode = body["error"],
   errorCode == "MONTHLY_LIMIT_REACHED" || errorCode == "LIFETIME_LIMIT_REACHED" {
    return .limitReached(resetsAt: body["resets_at"])
}
```

The return type of each affected method should include a `.limitReached` case (or throw a
typed error). `DirectAIHomeworkView`, `SessionChatView`, and `PracticeLibraryView` must handle
this case by setting `showingUpgradePrompt = true` rather than showing a generic error.

Apply this pattern to: `processHomeworkImage()`, `sendSessionMessageStreamingWithRetry()`
(not `sendSessionMessage` — see method table above), `generatePracticeQuestions()`,
`generatePassiveReport()`.

---

## Phase 6 — Guest → Account Conversion

**Entry points for conversion prompt:**
- Any blocked feature tap (UpgradePromptView "Create Free Account" CTA)
- Profile/Settings icon tap when `authService.currentUser?.isAnonymous == true`

**Conversion flow (race-condition safe):**
```
UpgradePromptView (or Profile icon)
  → ModernLoginView(conversionMode: true) as .sheet
      Header: "Save Your Progress"
      No "Continue as Guest" button
      Back/dismiss button shown
  → On successful registration/login:
      1. signInWithEmail() (or Google/Apple) succeeds → new token received
      2. ONLY THEN: discard guest token from Keychain (replace with new token)
      3. authService.currentUser updated to new non-anonymous User
      (guest backend account abandoned in memory; auto-deleted from DB after 30 days)
      (no data migration — guest has limited data, not worth complexity)

      IMPORTANT: Do NOT call signOut() before the new sign-in succeeds.
      If network fails, user must remain authenticated as guest.
      The guest token stays valid in Keychain until overwritten by the new token.
```

Note: Guest's 3 homework analyses and 10 chat messages ARE stored in the backend DB under
their anonymous user ID. After conversion they create a new account; old data is not migrated.
This is intentional — the guest lifetime limits are so small that migration adds no value.

---

## Implementation Order (Safe Deploy Sequence)

Each step is independently deployable without breaking existing users:

1. **Phase 1: DB migration** — purely additive (`ADD COLUMN IF NOT EXISTS`), safe to ship first
2. **Phase 2a: Add `tier` to login responses** — iOS ignores unknown JSON fields; backward compatible
3. **Phase 4 (partial): `UserTier.swift` + extend `User` struct** — compile-safe with `?? .free` defaults
4. **Phase 4 (partial): `FeatureGate.swift` + `GuestSessionService.swift`** — no UI wiring yet
5. **Phase 2b + 4: `POST /api/auth/anonymous` + iOS `signInAsGuest()`** — guest flow end-to-end
6. **Phase 4: `UpgradePromptView.swift`** — UI shell, no StoreKit yet
7. **Phase 3: `usage-tracker.js` + `tier-check.js`** — backend infrastructure
8. **Phase 3: Wire `tierCheck` into backend endpoints** — one endpoint at a time, test each
9. **Phase 5: Wire `FeatureGate` into iOS views** — one view at a time
10. **Phase 6: Guest conversion flow** — add `conversionMode` to ModernLoginView
11. **Phase 7 (future): StoreKit 2 IAP** — not in this plan

---

## Key Design Decisions

**Guest = real backend account**
`POST /api/auth/anonymous` creates `is_anonymous=true` user. Real JWT. Data persists across
reinstalls. Auto-deleted after 30 days. Cost: ~$0.10-0.20/active guest (lifetime limits are
very low). Tradeoff accepted: allows future A/B testing of conversion tactics using real data.

**All limits enforced backend-side**
Redis counters are authoritative. iOS uses stored `tier` only for instant UI gating (no network
call). Backend always re-validates. `X-Usage-Remaining` response header keeps iOS count display
in sync. Jailbreak-proof.

**`tier` stored in Keychain with User struct**
Backend returns `tier` on login. iOS stores it in Keychain as part of the `User` Codable struct.
No separate API call needed to get tier on launch. Backend caches tier in `userCache` (1hr TTL
already in railway-database.js) for fast middleware lookups.

**COPPA compatibility**
`FeatureGate.check()` reads `ProfileService.shared.currentProfile?.accountRestricted`. If `true`
(set by COPPA flow in railway-database.js), voice and report features are blocked regardless of
tier. COPPA tables and columns are NOT modified.

**Pomodoro/Garden: no tier gate**
Zero API cost. Available to all tiers including Guest. Acts as a retention hook even for non-
paying users.

**No tier on read-only analytics**
Progress view, archives, mistake review: these are pure DB reads. Cost is negligible and
restricting them hurts retention. All tiers get full read access.

**Localization**
All new UI strings must be added to all 8 `.strings` files in the iOS project:
`en`, `zh-Hans`, `zh-Hant`, `de`, `es`, `fr`, `ja`, and any others present.
New keys to add: `auth.continueAsGuest`, `upgrade.title`, `upgrade.createFreeAccount`,
`upgrade.upgradeToPremium`, `upgrade.monthlyLimitReached`, `upgrade.coppaRestricted`,
`upgrade.resets_at`. Add keys to `Localizable.strings` (en) first, then propagate.

---

## Testing Plan

Tests use real Railway backend + real iOS device. No mocking. You have multiple accounts that
can be set to different tiers by directly updating the Railway PostgreSQL database.

### Test Account Setup

```sql
-- In Railway PostgreSQL (use Railway dashboard query tool or psql):

-- Account A: Free tier (use your existing free account)
UPDATE users SET tier = 'free',  is_anonymous = false WHERE email = 'your_free@email.com';

-- Account B: Premium tier
UPDATE users SET tier = 'premium', tier_expires_at = NOW() + INTERVAL '1 year' WHERE email = 'your_premium@email.com';

-- Account C: Premium Plus
UPDATE users SET tier = 'premium_plus', tier_expires_at = NOW() + INTERVAL '1 year' WHERE email = 'your_plus@email.com';

-- Flush tier cache after each change (add a /admin/flush-cache endpoint or restart backend):
-- Or just wait up to 1 hour for userCache TTL to expire
-- Better: call userCache.del(userId) in a temporary admin route during testing
```

---

### Group 1 — Backend API Tests (curl / Postman against Railway)

Use these to verify backend enforcement before touching the iOS app.

**T1: Login response includes tier**
```bash
curl -X POST https://sai-backend-production.up.railway.app/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"your_free@email.com","password":"..."}'
# Expected: response.user.tier == "free", response.user.is_anonymous == false
```

**T2: Anonymous endpoint creates guest**
```bash
curl -X POST https://sai-backend-production.up.railway.app/api/auth/anonymous
# Expected: 200, response.user.is_anonymous == true, response.token is a valid JWT
# Verify in DB: SELECT tier, is_anonymous FROM users ORDER BY created_at DESC LIMIT 1;
```

**T3: Free tier blocks batch homework**
```bash
# Login as Account A (free), get token
curl -X POST https://sai-backend-production.up.railway.app/api/ai/process-homework-images-batch \
  -H "Authorization: Bearer FREE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"base64_images":["..."]}'
# Expected: 403 { "error": "UPGRADE_REQUIRED", "tier_required": "premium" }
```

**T4: Free tier homework monthly limit**
```bash
# Reset counter first:
# In Railway Redis (or DB): DEL usage:FREE_USER_ID:homework_single:YYYY-MM

# Make 11 calls as free user (limit = 10):
for i in $(seq 1 11); do
  curl -s -o /dev/null -w "%{http_code}" -X POST .../api/ai/process-homework-image-json \
    -H "Authorization: Bearer FREE_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"base64_image":"..."}'; echo
done
# Expected: calls 1-10 → 200; call 11 → 429 { "error": "MONTHLY_LIMIT_REACHED" }
```

**T5: Mode 3 blocked for free tier, counter NOT incremented**
```bash
# Check Redis counter before:
# REDIS GET usage:FREE_USER_ID:questions:YYYY-MM  →  nil or some number N

curl -X POST .../api/ai/generate-questions/practice \
  -H "Authorization: Bearer FREE_TOKEN" \
  -d '{"mode":3,"conversation_data":[],"question_data":[]}'
# Expected: 403 { "error": "UPGRADE_REQUIRED" }

# Check Redis counter after:
# REDIS GET usage:FREE_USER_ID:questions:YYYY-MM  →  still N (not N+1)
```

**T6: Premium tier unlocks voice chat WebSocket**
```bash
# Using wscat or similar:
wscat -c "wss://sai-backend-production.up.railway.app/api/ai/gemini-live/connect?token=PREMIUM_TOKEN"
# Expected: connection accepted, then { "type": "session_ready" } after sending start_session
# With free token: immediate { "type": "error", "code": "UPGRADE_REQUIRED" } then close
```

**T7: Guest lifetime limit**
```bash
# Get guest token from T2
# Make 4 homework calls (limit = 3):
# Calls 1-3 → 200; call 4 → 429 { "error": "LIFETIME_LIMIT_REACHED" }
# Verify: guest counters use "usage_lifetime:" prefix, not "usage:{YYYY-MM}:"
```

**T8: `preHandler` actually fires (not silently inside config)**
```bash
# Temporarily add: console.log('tierCheck running') at the top of tier-check.js hook
# Make any homework request → check Railway logs for the log line
# If missing: preHandler is incorrectly placed inside config
```

**T9: Cache bust on tier change**
```bash
# Login as Account B (premium), get token
# Check voice works: T6 with PREMIUM_TOKEN

# Downgrade tier in DB:
# UPDATE users SET tier = 'free' WHERE email = 'your_premium@email.com';

# WITHOUT cache bust: voice still works for ~1hr (acceptable during testing)
# WITH cache bust (call userCache.del manually or restart backend):
# Voice immediately returns UPGRADE_REQUIRED
```

---

### Group 2 — iOS Device Tests (on physical iPhone)

Run on device against live Railway backend. Build in DEBUG scheme for full logging.

**T10: Guest login UI and flow**
1. Log out from current account
2. On login screen → tap "Continue as Guest"
3. Expected: app opens, user is in main tab view
4. Open Settings/Profile → should show "Guest" badge and "Create Account" CTA
5. Tap "Live Talk" in SessionChatView menu → `UpgradePromptView` appears immediately (before any network call)
6. Kill app and relaunch → should still be logged in as guest (token persisted in Keychain)

**T11: Free tier UI limits**
1. Log in as Account A (free)
2. Open DirectAIHomeworkView → verify remaining count badge (e.g. "10 remaining") shown
3. Submit homework image → badge updates to "9 remaining"
4. Batch upload button → tap → `UpgradePromptView` appears immediately
5. Open SessionChatView → "Live Talk" menu item → `UpgradePromptView` appears
6. Open PracticeLibraryView → Mode 3 (Archive) tab → tap → `UpgradePromptView` appears

**T12: Existing user not logged out after app update**
1. Log in as any account on the OLD build (pre-tier system)
2. Install the new build (with `tier` + `isAnonymous` in User struct)
3. Launch app → user should remain logged in (no login screen presented)
4. Verify `authService.currentUser?.tier == .free` (default from custom init fallback)

**T13: Premium tier unlocks features**
1. Log in as Account B (premium)
2. Open SessionChatView menu → "Live Talk" → should connect (no UpgradePromptView)
3. Open PracticeLibraryView → Mode 3 tab → should be accessible
4. Open HomeView → Parent Reports → should generate (not blocked)

**T14: Guest → account conversion**
1. Log in as guest (T10)
2. Tap any Premium-locked feature → `UpgradePromptView` appears
3. Tap "Create Free Account" → `ModernLoginView` slides up in conversion mode
   - Header should say "Save Your Progress"
   - No "Continue as Guest" button visible
   - Back/dismiss button present
4. Kill network (airplane mode) mid-registration → user should remain as guest (not logged out)
5. Restore network → complete registration → user now has non-anonymous account

**T15: 429 shows UpgradePromptView, not generic error**
1. Manually set free user's homework counter to 10 in Redis (at limit)
2. On iOS as free user → submit homework image
3. Expected: `UpgradePromptView` slides up with "You've used all 10 this month" message
4. NOT expected: generic "Request failed" or network error toast

**T16: COPPA restriction still works (regression)**
1. Set `account_restricted = true` for a test account in DB
2. Log in as that account on iOS
3. Tap "Live Talk" → should be blocked with COPPA message ("Ask a parent to unlock")
4. Tap Parent Reports → same COPPA message
5. Homework analysis → NOT blocked (COPPA only restricts voice + reports)

---

### Group 3 — Regression Tests (existing features)

Run these after all changes to confirm nothing broke.

**T17: Normal login still works** — email/Google/Apple login all succeed, token stored in Keychain

**T18: Session chat still works** — free user can send up to 50 messages/month, conversations archived normally

**T19: Pomodoro / Garden** — timer starts, tomatoes earned, garden loads — for all tiers including guest

**T20: Progress view loads** — subject breakdown, streak data, all visible for all tiers

**T21: Archives accessible** — question archive, session history load for free + premium tiers



1. **DB columns exist**: `SELECT column_name FROM information_schema.columns WHERE table_name='users' AND column_name IN ('tier','is_anonymous','monthly_usage')`
2. **`account_restricted` column exists** (verify before coding Phase 4): `SELECT column_name FROM information_schema.columns WHERE table_name='users' AND column_name LIKE '%restrict%'` — confirms exact column name before adding to SQL query
2. **Login returns tier**: `curl -X POST .../api/auth/login` → response `user.tier == "free"`
3. **Anonymous endpoint**: `curl -X POST .../api/auth/anonymous` → 200, `user.is_anonymous == true`
4. **Existing users not logged out**: Install app update with new User struct → existing logged-in users remain authenticated (Keychain decode doesn't throw)
5. **Guest iOS flow**: Tap "Continue as Guest" → app loads → tap "Live Talk" → `UpgradePromptView` appears
6. **Guest lifetime limit**: Guest POSTs 4 homework images → 4th returns `{ error: 'LIFETIME_LIMIT_REACHED' }`
7. **Free tier homework limit**: Free user POSTs 11 homework images → 11th returns `{ error: 'MONTHLY_LIMIT_REACHED' }`; iOS shows `UpgradePromptView` (not generic error toast)
8. **Free tier blocks batch**: POST to batch endpoint as free user → 403 `{ error: 'UPGRADE_REQUIRED' }`
9. **Mode 3 no double-charge**: Free user attempts Mode 3 question generation → 403 returned, usage counter NOT incremented (verify Redis key unchanged)
10. **Error analysis limit**: Free user exhausts 5/month error analyses → 6th returns `{ error: 'MONTHLY_LIMIT_REACHED' }`
11. **`preHandler` fires**: Add log line in tierCheck; confirm it appears on homework request (not silently skipped inside `config`)
12. **premium_plus unlimited**: Set `tier='premium_plus'` → all features accessible, usage counters never incremented
13. **Premium unlocks voice**: `UPDATE users SET tier='premium' WHERE id=...` + `userCache.del(userId)` → Gemini Live WS connects immediately (no 1hr wait)
14. **Monthly reset**: Manually expire Redis key `usage:{userId}:homework_single:{YYYY-MM}` → counter = 0
15. **COPPA unchanged**: Existing parental consent flow still works; `account_restricted` users see voice blocked regardless of tier
16. **Conversion safe**: Kill network mid-conversion → user remains authenticated as guest, not logged out
