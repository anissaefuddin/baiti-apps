# Apps Script Deployment Guide

End-to-end steps to get the catat-app backend running on Google Apps Script.

---

## Prerequisites

- A Google account (will own the Sheets, Calendar events, and deployed Web App)
- Node.js installed (for clasp CLI)

```bash
npm install -g @google/clasp
clasp login   # opens browser → sign in with your Google account
```

---

## Step 1 — Create the Google Spreadsheet

1. Go to [sheets.google.com](https://sheets.google.com) and create a **blank** spreadsheet.
2. Name it something like `catat-app-db`.
3. Copy the **Spreadsheet ID** from the URL:
   ```
   https://docs.google.com/spreadsheets/d/SPREADSHEET_ID/edit
   ```

---

## Step 2 — Create the Apps Script project

```bash
# From inside the apps-script/ directory:
cd apps-script/
clasp create --title "catat-app" --type webapp
```

This creates a new Apps Script project and writes the `scriptId` to `.clasp.json`.
If you already have a project, edit `.clasp.json` and paste your `scriptId` manually.

---

## Step 3 — Set your Spreadsheet ID

Open `config.js` and replace the placeholder:

```js
const SPREADSHEET_ID = 'YOUR_SPREADSHEET_ID_HERE';
//                      ↑ paste the ID from Step 1
```

---

## Step 4 — Push the code

```bash
clasp push
```

All `.js` files (and `appsscript.json`) are uploaded to the Apps Script project.

Verify it pushed correctly:
```bash
clasp open   # opens the editor in your browser
```

---

## Step 5 — Run setupSheets()

**Do this once** to create all sheet tabs with headers.

In the Apps Script editor:
1. Select `setupSheets` from the function dropdown (top toolbar)
2. Click ▶ **Run**
3. When prompted, click **Review Permissions** → **Allow**
4. You should see an alert: *"✅ Setup complete! All sheets have been created."*

You can also run `validateSheets()` afterwards to confirm column counts are correct.

---

## Step 6 — Deploy as Web App

In the Apps Script editor:
1. Click **Deploy** → **New deployment**
2. Click the gear icon ⚙ next to "Type" → select **Web app**
3. Set the following:
   - **Description**: `v1` (or any label)
   - **Execute as**: `Me` (runs as the script owner — required to access your Sheets)
   - **Who has access**: `Anyone` (the app handles its own auth via Google ID tokens)
4. Click **Deploy**
5. **Copy the Web App URL** — it looks like:
   ```
   https://script.google.com/macros/s/AKfycb.../exec
   ```

> **Important**: Every time you push code changes and want them live, you must
> create a **New deployment** (or redeploy an existing one). Editing the script
> does not automatically update a deployed version.

---

## Step 7 — Configure the Flutter app

Open the Flutter app → tap **⚙ Konfigurasi Server** (settings icon on the dashboard).

Paste the Web App URL from Step 6. The app will save it to local storage and use it for all API calls.

To verify the backend is reachable, open the Web App URL in a browser — it should return:
```json
{ "status": "ok", "app": "catat-app", "version": "1.0.0", "timestamp": "..." }
```

---

## Updating the backend

Whenever you change Apps Script code:

```bash
clasp push
```

Then in the editor:
- **Deploy** → **Manage deployments** → click the pencil ✏ on the active deployment → **New version** → **Deploy**

The Web App URL stays the same after redeployment.

---

## Google Calendar integration

Calendar events are created in the **default calendar** of the account that deployed the Web App. They are created automatically when a booking is saved. If calendar creation fails, the booking is still saved (non-fatal).

To see the events: open [calendar.google.com](https://calendar.google.com).

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `"Apps Script URL is not configured"` | Open Settings in the Flutter app and paste the Web App URL |
| `401 / "Invalid or expired token"` | The Google ID token expired — sign out and sign in again |
| `"Sheet 'users' not found"` | Run `setupSheets()` from the editor (Step 5) |
| Calendar events not created | Check the Apps Script **Executions** log in the editor for the specific error |
| Changes not reflected after push | Create a new deployment version (Step 6 — updating) |
| `"Server sibuk"` (LOCK_TIMEOUT) | Temporary; the Flutter client retries up to 3× automatically |

---

## File structure

```
apps-script/
├── appsscript.json   ← manifest (timezone, scopes, webapp config)
├── config.js         ← SPREADSHEET_ID, sheet names, column indices
├── utils.js          ← respondOk/respondError, error codes, shared throw helpers
├── sheets.js         ← Spreadsheet read/write helpers
├── token.js          ← Google ID token verification
├── auth.js           ← auth.login handler
├── rooms.js          ← rooms.* handlers
├── customers.js      ← customers.* handlers
├── transactions.js   ← transactions.* handlers
├── payments.js       ← payments.* handlers
├── reports.js        ← reports.* handlers
├── setup.js          ← one-time setupSheets() + validateSheets()
└── main.js           ← doPost() entry point + _route() router
```
