# Behavioral Signals — what each event means and where it's used

This is the source of truth for behavioral analytics in StudyAI. Every event
the iOS app emits ends up in `app_events`. Each event answers a specific
question — the dashboard endpoints below read those events back into
plain-language summaries.

If you're looking at a dashboard chart and asking **"what does this number
mean and what should I do about it?"** — start here.

---

## How the system fits together

```
iOS              Backend                   Dashboard
─── ──────────── ─────────────────── ─────────────────────────────────────
View
  │
  ▼
JourneyTracker.shared.track(name, props)
  │  (batched, every 30s or on background)
  ▼
POST /api/events/batch  ──►  app_events table  ──►  /api/admin/analytics/*
                              (user_id,                  ▲
                               event_name,               │
                               properties JSONB,         │
                               session_id,               │
                               occurred_at)              │
                                                         │
                              feedback_submissions ──────┘
                              (separate "Report a problem" channel)
```

Every event carries `session_id` (UUID rotated on cold start or after >5min
background) and `app_language` (the user's iOS UI language, BCP-47 e.g.
`en`, `zh-Hans-CN`) — so we can stitch one user's continuous session into a
story and segment any analytics view by language.

---

## Event catalog

### App lifecycle — when and how long users use the app

| Event | Question it answers | Key properties |
|---|---|---|
| `app_open` | When are users opening the app? Cold start vs warm? | `cold_start`, `app_version` |
| `app_background` | What was the user doing right before they left? How long was the session? | `session_duration_sec`, `last_screen`, `last_action` |
| `onboarding_tour_started` | How many new users start the home coach-mark tour? | `total_steps` |
| `onboarding_tour_completed` | How many walk all the way to the end? | `total_steps` |
| `onboarding_tour_skipped` | Where in the tour do users bail? | `at_step` (0-indexed), `at_step_name`, `total_steps` |

**Dashboard:** DAU/WAU/MAU come from distinct `user_id` on `app_open`.
Bounce = `session_duration_sec < 30`. Language distribution comes from the
top-level `app_language` column on every event (see Insights → App Language).
**Where:** `/api/admin/stats/overview`, `/api/admin/analytics/dropoff`,
`/api/admin/insights/overview` (`languageDistribution`).

### Screen telemetry — what users actually look at

| Event | Question it answers | Key properties |
|---|---|---|
| `screen_viewed` | Which screens see traffic? What's the entry point of each session? | `screen`, `source` |
| `screen_exited` | How long do users stay on each screen? | `screen`, `stay_ms` |

**Naming:** screens use the `Screen` enum in `View+TrackScreen.swift` — keep
this list aligned across iOS + dashboard. Inline strings will fragment buckets.
**Dashboard:** `/api/admin/analytics/screen-flow`.

### Auth funnel — signup, login, guest

| Event | Question it answers | Key properties |
|---|---|---|
| `signup_started` | How many people start signing up? | `provider` |
| `signup_completed` | How many of them finish? | `provider` |
| `signup_failed` | Why are people failing to sign up? | `provider`, `status`, `reason` |
| `login_started` / `login_completed` / `login_failed` | Same for returning users | `provider`, `reason` |
| `guest_session_started` / `guest_session_failed` | How attractive is the guest path? | — |

**Dashboard:** `/api/admin/analytics/conversion-funnel` → `authFunnel` and
`providerSplit` show per-provider success rates. A big drop on Apple usually
means an entitlement / provisioning issue.

### Paywall + purchase funnel

| Event | Question it answers | Key properties |
|---|---|---|
| `paywall_viewed` | Which features are gated and how often is the gate hit? | `feature`, `reason` (`feature_blocked` / `limit_reached`) |
| `purchase_started` | How many viewers tap the buy button? | `product_id`, `tier`, `price` |
| `purchase_succeeded` | How many complete the purchase through Apple? | `product_id`, `tier`, `transaction_id` |
| `purchase_pending` | "Ask to Buy" is in flight (kid accounts) | `product_id`, `tier` |
| `purchase_cancelled` | User backed out of Apple's confirm sheet | `product_id`, `tier` |
| `purchase_failed` | What's blocking purchases? | `product_id`, `tier`, `reason` |
| `subscription_cancel_reason` | Why are paying users heading to "Manage Subscription"? | `tier`, `reason` (`too_expensive`, `not_using_enough`, …) |

**Legacy events still emitted for back-compat:** `upgrade_prompt_shown`,
`upgrade_tapped`. New dashboards should use the standardized names above.
**Dashboard:** `/api/admin/analytics/conversion-funnel` → `paywallFunnel`,
`paywallSources`. Cancel reasons go to `/api/admin/analytics/quality`.

### Homework camera funnel

| Event | Question it answers | Key properties |
|---|---|---|
| `camera_opened` | How many users start a homework capture? | `source` (always `homework`) |
| `camera_permission_denied` | Are users blocking camera access? | — |
| `photo_captured` | How many actually take the photo? | `source` (`camera`/`library`), `width`, `height` |
| `photo_cancelled` | Where do users abandon mid-capture? | `source` |
| `homework_submitted` | How many submit for grading? | `subject`, `question_count`, `parsing_mode` |
| `homework_graded` | Single-question grade outcome | `subject`, `is_correct`, `score` |
| `homework_session_graded` | Whole homework session outcome | `subject`, `correct_count`, `total_questions`, `accuracy_pct` |

**Funnel order:** `camera_opened → photo_captured → homework_submitted →
homework_graded`. Drops between any two steps point to a friction source.

### Practice + chat + focus (existing)

| Event | Question it answers |
|---|---|
| `chat_opened` / `chat_message_sent` | Who's using AI chat? |
| `live_mode_started` / `live_mode_ended` | Voice mode adoption + session length |
| `practice_generated` / `practice_completed` / `practice_abandoned` | Are users finishing practice? |
| `focus_session_started` / `focus_session_completed` | Pomodoro adoption |
| `knowledge_tree_viewed` / `tree_lightup_done` | Knowledge tree mastery flow |
| `question_answered` | Per-question accuracy |

### Push notifications

| Event | Question it answers | Key properties |
|---|---|---|
| `push_received` | Was the app open or backgrounded when push arrived? | `kind`, `deep_link`, `in_foreground` |
| `push_tapped` | What kind of push pulls users back? Where do they go? | `kind`, `deep_link` |

`kind` ∈ {`study_reminder`, `daily_challenge`, `parent_report`, `other`}.
**ROI:** compare daily count of `push_tapped` to daily count of `app_open`
within an hour after a push.

### Quality signals — what's hurting users

| Event | Question it answers | Key properties |
|---|---|---|
| `network_request_failed` | Which API endpoints are flaky? | `endpoint`, `method`, `status`, `duration_ms`, `kind`, `reason` |
| `feedback_submitted` | What problems are users reporting? | `category`, `message_len`, `success` |
| `subscription_cancel_reason` | Why are users leaving paid plans? | `tier`, `reason`, `detail_len` |

**Dashboard:** all consolidated in `/api/admin/analytics/quality`.

`feedback_submissions` table holds the actual free-text content and is queried
separately for safety (no full message text in the events stream).

---

## Dashboard endpoints — read these in order

Each endpoint returns `{ question, interpretation, ...data }`. The
`interpretation` block tells you what to look at and what counts as healthy
vs unhealthy. The order below matches the order to investigate when something
looks off.

### 1. `/api/admin/analytics/screen-flow` — what do users look at?
- `firstScreens`: the first screen of each session. If it's not Home, your
  navigation is misrouted.
- `topScreens`: views + median stay. High views + low stay = passthrough screen
  (or users hate it).
- `exitScreens`: where users were when they backgrounded. Frequent exits from
  a non-natural endpoint (Camera, Paywall) = friction.

### 2. `/api/admin/analytics/dropoff` — where do users abandon?
- `shortSessions`: bounces (session <30s), broken down by `(last_action,
  last_screen)`. The biggest bucket is your friction point.
- `silentUsers`: users who haven't returned in 7+ days, grouped by their last
  action. Tells you what they were doing right before they went dark.
- `commonLastActions`: distribution of the last thing users do before
  backgrounding. Healthy: completion events. Worrying: errors, paywalls.

### 3. `/api/admin/analytics/conversion-funnel` — signup → free → paid
- `authFunnel`: signup_started → completed → first login.
- `paywallFunnel`: paywall_viewed → purchase_started → purchase_succeeded.
- `paywallSources`: which feature triggers paywall most.
- `providerSplit`: success rate per auth provider.

### 4. `/api/admin/analytics/quality` — what's making users unhappy?
- `errors`: top failing endpoints, sorted by affected users.
- `cancelReasons`: distribution + percentages.
- `feedbackByCategory`: bug / suggestion / content / praise / other counts.
- `recentFeedback`: 20 most recent free-text submissions, truncated.

---

## Adding a new event — checklist

1. **Pick a stable name.** Format: `verb_noun` or `noun_verbed`. Lowercase
   with underscores. Examples that are good: `paywall_viewed`,
   `purchase_started`. Examples that are bad: `paywall`, `clickedBuy`.
2. **Decide on properties.** Keep it small. Required: anything you'd group
   the count by (`subject`, `provider`, `feature`). Avoid PII — user_id is
   already on the row.
3. **Add a label** in `admin-routes.js → labelFromEvent` so the per-user
   journey timeline reads like a story sentence.
4. **Add a row to the catalog above** with the question it answers.
5. **Decide which dashboard view** consumes it — and either reuse an existing
   endpoint or add a new section. Don't ship a new event without a consumer.
6. **Emit it from one place.** Wrap in a service method if multiple call sites
   need it; resist sprinkling `JourneyTracker.shared.track` widely.

The goal isn't to capture everything — it's to answer specific questions.
Every event should map to a question on this page.
