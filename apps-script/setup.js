// ── One-time Sheet Initialization ─────────────────────────────────────────────
//
// Run setupSheets() ONCE from the Apps Script editor (not via web app) to
// create all required sheets with proper headers.
//
// How to run:
//   1. Open the Apps Script project in the editor
//   2. Select the function "setupSheets" from the function dropdown
//   3. Click ▶ Run
//   4. Grant permissions when prompted
//
// Safe to re-run: existing sheets with correct headers are left untouched.
// Only missing sheets are created.

/**
 * Create all required sheets with header rows.
 * Existing sheets are not modified.
 */
function setupSheets() {
  const ss = getSpreadsheet();

  _ensureSheet(ss, SHEET.USERS, [
    'id', 'google_id', 'email', 'name', 'role', 'created_at', 'updated_at',
  ]);

  _ensureSheet(ss, SHEET.CUSTOMERS, [
    'id', 'nik', 'name', 'phone', 'address', 'birth_date',
    'ktp_drive_url', 'created_at', 'updated_at',
  ]);

  _ensureSheet(ss, SHEET.ROOMS, [
    'id', 'name', 'price_per_night', 'capacity', 'description',
    'status', 'created_at', 'updated_at',
  ]);

  _ensureSheet(ss, SHEET.TRANSACTIONS, [
    'id', 'booking_code', 'customer_id', 'room_ids',
    'check_in', 'check_out', 'nights', 'total_price',
    'dp_amount', 'payment_status', 'calendar_event_id',
    'notes', 'created_by', 'created_at', 'updated_at',
  ]);

  _ensureSheet(ss, SHEET.PAYMENTS, [
    'id', 'transaction_id', 'amount', 'method',
    'paid_at', 'notes', 'created_by', 'created_at',
  ]);

  // Remove the default "Sheet1" tab if it was auto-created and is empty.
  _removeDefaultSheet(ss);

  Logger.log('setupSheets() complete. All sheets are ready.');
  SpreadsheetApp.getUi().alert('✅ Setup complete! All sheets have been created.');
}

/**
 * Validate that every sheet exists and has the right number of columns.
 * Useful to run after manually editing the spreadsheet.
 */
function validateSheets() {
  const issues = [];

  const expected = {
    [SHEET.USERS]:        7,
    [SHEET.CUSTOMERS]:    9,
    [SHEET.ROOMS]:        8,
    [SHEET.TRANSACTIONS]: 15,
    [SHEET.PAYMENTS]:     8,
  };

  for (const [name, colCount] of Object.entries(expected)) {
    const sheet = getSpreadsheet().getSheetByName(name);
    if (!sheet) {
      issues.push('Missing sheet: ' + name);
      continue;
    }
    const actual = sheet.getLastColumn();
    if (actual !== colCount) {
      issues.push(name + ': expected ' + colCount + ' columns, found ' + actual);
    }
  }

  if (issues.length === 0) {
    Logger.log('validateSheets(): all sheets OK.');
    SpreadsheetApp.getUi().alert('✅ All sheets are valid.');
  } else {
    const msg = 'Sheet issues found:\n' + issues.join('\n');
    Logger.log(msg);
    SpreadsheetApp.getUi().alert('⚠️ ' + msg);
  }
}

// ── Internal ──────────────────────────────────────────────────────────────────

/**
 * Create a sheet with header row if it doesn't already exist.
 * @param {GoogleAppsScript.Spreadsheet.Spreadsheet} ss
 * @param {string} name
 * @param {string[]} headers
 */
function _ensureSheet(ss, name, headers) {
  let sheet = ss.getSheetByName(name);

  if (!sheet) {
    sheet = ss.insertSheet(name);
    Logger.log('Created sheet: ' + name);
  } else {
    Logger.log('Sheet already exists, skipping: ' + name);
    return;
  }

  // Write headers in row 1, freeze it so data scrolling leaves headers visible.
  sheet.getRange(1, 1, 1, headers.length).setValues([headers]);
  sheet.setFrozenRows(1);

  // Style the header row for readability.
  const headerRange = sheet.getRange(1, 1, 1, headers.length);
  headerRange.setBackground('#1565C0');
  headerRange.setFontColor('#FFFFFF');
  headerRange.setFontWeight('bold');

  // Auto-resize columns.
  sheet.autoResizeColumns(1, headers.length);
}

/**
 * Remove the auto-created "Sheet1" tab if it exists and is completely empty.
 */
function _removeDefaultSheet(ss) {
  const defaultSheet = ss.getSheetByName('Sheet1');
  if (!defaultSheet) return;

  const hasData = defaultSheet.getLastRow() > 0 || defaultSheet.getLastColumn() > 0;
  if (hasData) return; // Don't delete if user has put data there

  try {
    ss.deleteSheet(defaultSheet);
    Logger.log('Removed default Sheet1.');
  } catch (_) {
    // Ignore if it's the only sheet (can't delete the last sheet)
  }
}
