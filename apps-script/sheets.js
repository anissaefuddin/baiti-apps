// ── Spreadsheet access ────────────────────────────────────────────────────────
// Cache the Spreadsheet instance for the lifetime of a single script execution.
// Each doPost() call is a fresh execution, so this is safe.

let _spreadsheet = null;

function getSpreadsheet() {
  if (!_spreadsheet) {
    _spreadsheet = SpreadsheetApp.openById(SPREADSHEET_ID);
  }
  return _spreadsheet;
}

/**
 * Get a sheet by name. Throws if not found.
 * @param {string} name - One of the SHEET.* constants.
 * @returns {GoogleAppsScript.Spreadsheet.Sheet}
 */
function getSheet(name) {
  const sheet = getSpreadsheet().getSheetByName(name);
  if (!sheet) {
    throw new Error(`Sheet "${name}" not found. Run setupSheets() first.`);
  }
  return sheet;
}

// ── Read ──────────────────────────────────────────────────────────────────────

/**
 * Return all data rows (excluding the header row) as a 2D array.
 * Returns [] if the sheet has only a header row or is empty.
 */
function getAllRows(sheet) {
  const lastRow = sheet.getLastRow();
  if (lastRow < 2) return [];
  const lastCol = sheet.getLastColumn();
  if (lastCol < 1) return [];
  return sheet.getRange(2, 1, lastRow - 1, lastCol).getValues();
}

/**
 * Find the first row where column[colIndex] === value.
 * Returns the row array, or null if not found.
 * @param {GoogleAppsScript.Spreadsheet.Sheet} sheet
 * @param {number} colIndex - 0-based column index.
 * @param {*} value
 */
function findRowByColumn(sheet, colIndex, value) {
  const rows = getAllRows(sheet);
  return rows.find(row => String(row[colIndex]) === String(value)) ?? null;
}

/**
 * Find the 1-based sheet row number for the first matching row.
 * Returns -1 if not found. (+2 = 1-based index + header row offset)
 */
function findRowNumberByColumn(sheet, colIndex, value) {
  const rows = getAllRows(sheet);
  const idx = rows.findIndex(row => String(row[colIndex]) === String(value));
  return idx === -1 ? -1 : idx + 2;
}

// ── Write ─────────────────────────────────────────────────────────────────────

/**
 * Append a new row to the sheet.
 * @param {GoogleAppsScript.Spreadsheet.Sheet} sheet
 * @param {Array} values - Ordered values matching the sheet's column layout.
 */
function appendRow(sheet, values) {
  sheet.appendRow(values);
}

/**
 * Overwrite an existing row by its 1-based sheet row number.
 * @param {GoogleAppsScript.Spreadsheet.Sheet} sheet
 * @param {number} rowNumber - 1-based row number (2 = first data row).
 * @param {Array} values
 */
function updateRow(sheet, rowNumber, values) {
  sheet.getRange(rowNumber, 1, 1, values.length).setValues([values]);
}

/**
 * Soft-delete a row by setting a `deleted` flag in the UPDATED_AT column area.
 * For now this does a hard-delete by clearing the row content.
 * Full soft-delete (status = 'deleted') will be added when transactions are implemented.
 * @param {GoogleAppsScript.Spreadsheet.Sheet} sheet
 * @param {number} rowNumber - 1-based row number.
 */
function deleteRow(sheet, rowNumber) {
  sheet.deleteRow(rowNumber);
}

// ── Convenience: get all rows as objects ──────────────────────────────────────

/**
 * Return all data rows mapped through a transform function.
 * @param {GoogleAppsScript.Spreadsheet.Sheet} sheet
 * @param {function(Array): Object} mapper - Converts row array to domain object.
 */
function getAllAs(sheet, mapper) {
  return getAllRows(sheet).map(mapper);
}
