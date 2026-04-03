# Baiti App — Changelog & Feature Summary

Version **1.0.0** · Build **1** · Released 2026

---

## Overview

Baiti App is a Flutter-based room and guesthouse management application backed by Google Apps Script and Google Sheets. It is designed for small accommodation owners who need a simple, fast, and free solution without a dedicated server.

---

## Version 1.0.0 — Initial Release

### Authentication
- Google Sign-In via `google_sign_in`
- ID token verified server-side on every API request (stateless, secure)
- Session stored locally with `shared_preferences`
- Auto-redirect: unauthenticated users → Login; authenticated → Dashboard

### Dashboard
- Greeting card showing the logged-in user's name
- Feature grid with navigation to: Transactions, Calendar, Customers, Rooms, Reports
- Settings and logout actions in the app bar

### Room Management (`/rooms`)
- List all rooms with status badges (available / occupied / maintenance)
- Add new room: name, price per night, capacity, description, status
- Edit existing room
- Delete room (with confirmation)

### Customer (Guest) Management (`/customers`)
- List customers with search by name, phone, or NIK
- Add new customer: NIK, name, phone, birth date, address
- Edit existing customer
- **KTP OCR scan** — camera or gallery pick, on-device text recognition via Google ML Kit (Latin script), auto-fills NIK, name, birth date, and address fields
- OCR character correction for common misreads (O→0, I→1, S→5, B→8, etc.)

### Booking / Transaction Management (`/transactions`)
- List all bookings with status badges (unpaid / partial / paid)
- Transaction detail screen: booking info, payment summary, payment history
- **Booking form**:
  - Customer picker — search existing customers OR add a new one (with KTP scan) directly from the form, without leaving the screen
  - Room picker with price display
  - Check-in / check-out date selection, nights auto-calculated
  - DP (down payment) amount field
  - Notes field
- Google Calendar event created automatically on each new booking

### Payment Tracking
- Add payment to a transaction: amount, method (Cash / Bank Transfer / QRIS), date, notes
- Payment history list on the transaction detail screen
- Payment status auto-updated: `unpaid` → `partial` → `paid` based on total paid vs. total price
- PDF invoice and kwitansi (receipt) generation and sharing via `pdf` + `printing`

### Calendar (`/calendar`)
- Monthly calendar view (`table_calendar`) showing check-in dates
- Tap a date to see bookings for that day

### Reports (`/reports`)
- Summary report filtered by date range
- CSV export via `share_plus`

### Settings (`/setup`)
- Input field for Google Apps Script Web App URL (saved locally, never sent to third parties)
- Optional Google Calendar ID field (defaults to primary calendar)
- Accessible from Dashboard (settings icon) — shows back button when pushed; proceeds to Login on first-time setup
- **About** link → dedicated About screen

### About Screen (`/about`)
- App icon, name, tagline
- Version and build number badge
- Developer, Package ID, and copyright information

---

## Technical Changes (build-related)

| Area | Change |
|------|--------|
| Package ID | Changed from `com.example.catat_app` → `app.maloka.catat` |
| `MainActivity.kt` | Moved to `kotlin/app/maloka/catat/` with updated package declaration |
| `google-services.json` | Updated `package_name` to `app.maloka.catat` |
| `compileSdk` | Upgraded to 36 (required by latest plugin dependencies) |
| `printing` plugin | Patched `compileSdkVersion` to 36 in pub-cache |
| ProGuard rules | Added `-dontwarn` for unused ML Kit script models (Chinese, Japanese, Korean, Devanagari) |
| App icon | Custom 1024×1024 PNG (house icon on blue gradient) replacing default Flutter icon |
| `flutter_launcher_icons` | Generates all Android mipmap density variants from `assets/images/icon.png` |
| `AppInfo` constants | Centralised in `setup_screen.dart`: app name, version, developer, copyright, package ID |

---

## Architecture

```
Flutter (Android)
    │
    ├── Riverpod 2.x — state management
    ├── GoRouter — navigation / deep links
    ├── Clean Architecture per feature (data / domain / presentation)
    │
    └── HTTP POST ──► Google Apps Script Web App
                          │
                          ├── Google Sheets  (database)
                          ├── Google Calendar (booking events)
                          └── Google Drive   (KTP file storage, future)
```

### Key files

| Path | Purpose |
|------|---------|
| `lib/core/router/app_router.dart` | All named routes and auth redirect logic |
| `lib/core/api/api_service.dart` | HTTP client — POST to Apps Script |
| `lib/core/storage/local_storage.dart` | SharedPreferences wrapper (URL, calendar ID, user) |
| `lib/core/services/ktp_ocr_service.dart` | KTP OCR parser (ML Kit + regex) |
| `lib/core/services/pdf_service.dart` | PDF invoice / kwitansi generation |
| `apps-script/main.js` | Apps Script entry point (`doPost`) |
| `apps-script/config.js` | Spreadsheet ID and sheet name constants |
| `apps-script/setup.js` | One-time `setupSheets()` initialisation |

---

## Known Limitations

- No offline mode — all data reads/writes require an internet connection to Apps Script
- Google Sheets has a practical row limit (~50 000 rows per sheet before performance degrades)
- Apps Script cold-start can add 1–3 seconds to the first request after inactivity
- Concurrent writes are protected by `LockService` — the app retries up to 3× on a 423 response
- KTP OCR accuracy depends on image quality; fields can be manually corrected before saving
