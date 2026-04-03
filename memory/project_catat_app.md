---
name: catat-app project context
description: Architecture decisions, patterns, and current state of the catat-app Flutter/Apps Script project
type: project
---

Room/guesthouse booking management app for Indonesian market.

**Why:** Small accommodation owners manage bookings manually (WhatsApp, notebooks). This provides a centralized, zero-hosting-cost solution using Google's free ecosystem.

**How to apply:** Use when suggesting new features or patterns — match the existing architecture.

## Stack
- Flutter (Dart) + Riverpod 2.x (AsyncNotifier) + GoRouter
- Google Apps Script Web App (always returns HTTP 200 — errors in JSON body)
- Google Sheets (database), Google Drive (KTP files), Google Calendar (bookings)
- Google ML Kit (OCR, Phase 2), Flutter pdf package (Phase 4)

## Key architectural decisions

### API transport
- All requests: POST `{ action, token, data }` to Apps Script URL
- Apps Script ALWAYS returns HTTP 200 — success/failure in `{ success, error, error_code }`
- Flutter ApiService checks `error_code == "LOCK_TIMEOUT"` to retry (not HTTP 423)
- Retry: up to 3 attempts with `attempt * 2` second backoff

### Auth flow
- `google_sign_in` → idToken → POST `auth.login` → Apps Script verifies via tokeninfo endpoint
- Session cached in SharedPreferences as JSON string
- `authProvider.future` used (not `ref.read`) to await async notifier on splash screen
- `handleSessionExpiry()` on AuthNotifier for mid-session UNAUTHORIZED responses
- First user in `users` sheet auto-promoted to `admin` role

### Error handling
- `ApiException` has both `statusCode` (HTTP) and `errorCode` (Apps Script body)
- `AuthError` is a typed model with `AuthErrorType` enum — drives icon + copy on login screen
- `AuthNotifier.clearError()` dismisses error banner without changing auth status

### State management pattern
- `AsyncNotifierProvider<AuthNotifier, AuthState>` — Riverpod 2.x style, no code gen
- Loading: `state = const AsyncValue.loading()`
- Error recovery: set `AsyncValue.data(AuthState(unauthenticated, error: ...))` to show error while remaining interactive

### Router
- GoRouter watches `authProvider` for redirects
- Routes: `/splash`, `/login`, `/setup`, `/dashboard`
- `/setup` always accessible (for reconfiguration)
- `authProvider.future` in SplashScreen waits for session resolution

## Phase status
- Phase 1 (Infrastructure): COMPLETE — boilerplate + auth module
- Phase 2 (Room & Customer CRUD + OCR): NOT STARTED
- Phase 3 (Bookings + Calendar + Payments): NOT STARTED
- Phase 4 (Dashboard + Reports + PDF): NOT STARTED
- Phase 5 (Polish): NOT STARTED

## Apps Script files (apps-script/)
- `config.js` — SPREADSHEET_ID constant + all COL/SHEET/ROLE constants
- `utils.js` — respondOk/respondError, ERROR_CODE enum, generateUUID, now
- `sheets.js` — getSheet, getAllRows, findRowByColumn, appendRow, updateRow
- `token.js` — verifyGoogleToken via tokeninfo endpoint
- `auth.js` — handleAuthLogin, _upsertUser, _rowToUser, _userToRow
- `main.js` — doPost, doGet (health), _route, requireAuth
- `setup.js` — setupSheets() run once from editor; validateSheets() for debugging

## Deployment checklist
1. Set SPREADSHEET_ID in apps-script/config.js
2. clasp push → run setupSheets() in editor
3. Deploy as Web App (Execute as: Me, Access: Anyone)
4. Copy /exec URL → paste in Flutter SetupScreen
5. Add google-services.json to android/app/
