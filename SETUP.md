# Baiti App — Setup & Configuration Guide

This guide covers everything needed to run Baiti App from scratch: backend setup, Flutter configuration, and first-time use.

---

## Requirements

### Google Account
- One Google account to own all services (Sheets, Apps Script, Calendar, Firebase)
- The same account must be used to deploy the Apps Script Web App and to create the Firebase project

### Development Machine
- **Flutter SDK** ≥ 3.3.0 — [install guide](https://docs.flutter.dev/get-started/install)
- **Dart SDK** ≥ 3.3.0 (bundled with Flutter)
- **Android SDK** with API level 36 platform installed
- **Java** 17 (required by Gradle)
- **Node.js** ≥ 18 — for the `clasp` CLI used to deploy Apps Script
- **Android device or emulator** with API level 21+ (Android 5.0+)

### Firebase Project
- A Firebase project with Google Sign-In enabled and a registered Android app (`app.maloka.catat`)

---

## Part 1 — Backend (Google Apps Script + Sheets)

### 1.1 Install clasp

```bash
npm install -g @google/clasp
clasp login   # opens browser — sign in with your Google account
```

### 1.2 Create the Google Spreadsheet

1. Go to [sheets.google.com](https://sheets.google.com) and create a **blank** spreadsheet
2. Name it (e.g. `baiti-app-db`)
3. Copy the **Spreadsheet ID** from the URL:
   ```
   https://docs.google.com/spreadsheets/d/<SPREADSHEET_ID>/edit
   ```

### 1.3 Create the Apps Script project

```bash
cd apps-script/
clasp create --title "baiti-app" --type webapp
```

If the project already exists, edit `apps-script/.clasp.json` and set your `scriptId`.

### 1.4 Set the Spreadsheet ID

Open `apps-script/config.js` and replace the placeholder:

```js
const SPREADSHEET_ID = 'YOUR_SPREADSHEET_ID_HERE';
```

### 1.5 Push the code

```bash
cd apps-script/
clasp push
```

Verify with `clasp open` — the editor should show all `.js` files.

### 1.6 Run setupSheets() — one time only

In the Apps Script editor:
1. Select `setupSheets` from the function dropdown (top toolbar)
2. Click ▶ **Run**
3. Grant permissions when prompted (Sheets + Calendar + external requests)
4. You should see: *"✅ Setup complete! All sheets have been created."*

This creates six sheet tabs: `users`, `customers`, `rooms`, `transactions`, `payments`, `reports_cache`.

### 1.7 Deploy as Web App

1. Click **Deploy → New deployment**
2. Select type **Web App**
3. Settings:
   - **Execute as**: Me (your Google account)
   - **Who has access**: Anyone
4. Click **Deploy** and copy the Web App URL:
   ```
   https://script.google.com/macros/s/<ID>/exec
   ```

> After every code change: `clasp push` → Deploy → **Manage deployments** → edit the active deployment → **New version** → Deploy. The URL stays the same.

---

## Part 2 — Firebase (Google Sign-In)

### 2.1 Create Firebase project

1. Go to [console.firebase.google.com](https://console.firebase.google.com)
2. Create a new project (or use an existing one)
3. Enable **Google Sign-In**: Authentication → Sign-in method → Google → Enable

### 2.2 Register the Android app

1. In Firebase Console → Project settings → Add app → Android
2. **Android package name**: `app.maloka.catat`
3. **SHA-1 certificate fingerprint** (debug key):
   ```
   67:16:B0:BB:A4:54:B6:A9:BB:26:B6:26:6B:2F:ED:E2:C7:66:E0:82
   ```
   To get your own debug SHA-1:
   ```bash
   keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
   ```
4. Download `google-services.json` and replace `android/app/google-services.json`

---

## Part 3 — Flutter App

### 3.1 Get dependencies

```bash
flutter pub get
```

### 3.2 Generate app icons (already done for release)

```bash
dart run flutter_launcher_icons
```

Source icon is at `assets/images/icon.png` (1024×1024 PNG). This generates all Android mipmap density variants.

### 3.3 Build

**Debug (for development)**
```bash
flutter run
```

**Release APK**
```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

**Install on connected device**
```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

---

## Part 4 — First-time App Configuration

When the app is opened for the first time (no server URL stored), it redirects to the **Settings** screen automatically.

1. Paste the Apps Script **Web App URL** into the URL field
2. Optionally enter a **Google Calendar ID**:
   - Use `primary` for the main calendar of the deploying Google account
   - Or enter a specific calendar ID: `xxx@group.calendar.google.com`
3. Tap **Simpan**
4. The app proceeds to the **Login** screen
5. Sign in with the Google account that has access to the Spreadsheet

To change settings later: Dashboard → ⚙ (settings icon) → Settings screen → update and save.

---

## Google Calendar Integration

Booking events are automatically created in Google Calendar when a transaction is saved.

- **Event title**: `[Room Name] - [Customer Name]`
- **Date range**: check-in → check-out
- **Description**: booking code, phone, room details

The calendar used is controlled by the **Google Calendar ID** set in Settings.
If no ID is entered, the primary calendar of the Apps Script deployer's account is used.
Failed calendar creation is non-fatal — the booking is saved regardless.

---

## Updating the Backend

After editing any `apps-script/*.js` file:

```bash
cd apps-script/
clasp push
```

Then in the Apps Script editor:
**Deploy → Manage deployments → ✏ Edit → New version → Deploy**

The Web App URL does not change between redeployments.

---

## Troubleshooting

| Error | Solution |
|-------|----------|
| `"Apps Script URL is not configured"` | Open Settings in the app and paste the Web App URL |
| `401 / "Invalid or expired token"` | Sign out and sign in again — ID token expired |
| `"Sheet 'users' not found"` | Run `setupSheets()` in the Apps Script editor (Part 1.6) |
| `"No matching client found for package name"` | Register `app.maloka.catat` in Firebase Console with the correct SHA-1 |
| `ClassNotFoundException: MainActivity` | Check that `MainActivity.kt` is at `kotlin/app/maloka/catat/` with correct package |
| Calendar events not appearing | Check Apps Script **Executions** log for errors; verify Calendar ID in settings |
| Changes not live after push | Create a **new deployment version** in the Apps Script editor |
| `"Server sibuk"` (lock timeout) | Temporary — the app retries automatically up to 3× |
| Build fails: `lStar not found` | Ensure `compileSdk = 36` in `android/app/build.gradle.kts` |

---

## Sheet Schema Reference

| Sheet | Key Columns |
|-------|------------|
| `users` | id, email, name, google_id, role, created_at |
| `customers` | id, nik (unique), name, phone, address, birth_date, created_at, updated_at |
| `rooms` | id, name, price_per_night, capacity, description, status, created_at, updated_at |
| `transactions` | id, booking_code, customer_id, room_id, check_in, check_out, nights, total_price, dp_amount, payment_status, calendar_event_id, notes, created_by, created_at, updated_at |
| `payments` | id, transaction_id, amount, method, paid_at, notes, created_by, created_at |

---

## File Structure Reference

```
catat-app/
├── lib/
│   ├── main.dart
│   ├── core/
│   │   ├── api/           # HTTP client (ApiService)
│   │   ├── router/        # GoRouter + named routes (AppRoutes)
│   │   ├── services/      # KTP OCR, PDF generation
│   │   ├── storage/       # SharedPreferences wrapper
│   │   └── theme/         # Material 3 theme
│   └── features/
│       ├── auth/          # Google Sign-In, splash, login
│       ├── dashboard/     # Home screen
│       ├── customers/     # Guest management + KTP scan
│       ├── rooms/         # Room management
│       ├── transactions/  # Bookings, customer picker, PDF
│       ├── payments/      # Payment entry, history
│       ├── calendar/      # Monthly calendar view
│       ├── reports/       # Summary + CSV export
│       └── settings/      # Setup screen, About screen
├── android/
│   └── app/
│       ├── build.gradle.kts          # compileSdk=36, applicationId
│       ├── google-services.json      # Firebase config
│       ├── proguard-rules.pro        # ML Kit dontwarn rules
│       └── src/main/kotlin/app/maloka/catat/MainActivity.kt
├── assets/
│   └── images/icon.png              # 1024×1024 source icon
└── apps-script/                     # Backend — see DEPLOY.md
