// ── Response builders ──────────────────────────────────────────────────────────
// Apps Script Web Apps always return HTTP 200.
// Success/failure is communicated via the `success` field in the JSON body.
// The Flutter client checks `success` — not the HTTP status code.

/**
 * Build a JSON success response.
 * @param {*} data - Payload to return to the client.
 */
function respondOk(data) {
  return ContentService
    .createTextOutput(JSON.stringify({
      success: true,
      data: data ?? null,
      error: null,
      timestamp: new Date().toISOString(),
    }))
    .setMimeType(ContentService.MimeType.JSON);
}

/**
 * Build a JSON error response.
 * @param {string} message - Human-readable error message.
 * @param {string} [errorCode] - Machine-readable code (e.g. 'LOCK_TIMEOUT').
 */
function respondError(message, errorCode) {
  return ContentService
    .createTextOutput(JSON.stringify({
      success: false,
      data: null,
      error: message,
      error_code: errorCode ?? null,
      timestamp: new Date().toISOString(),
    }))
    .setMimeType(ContentService.MimeType.JSON);
}

// ── Error codes (matched by Flutter retry/error logic) ────────────────────────

const ERROR_CODE = {
  LOCK_TIMEOUT:  'LOCK_TIMEOUT',   // LockService couldn't acquire lock → Flutter retries
  UNAUTHORIZED:  'UNAUTHORIZED',   // Bad/expired token → Flutter re-authenticates
  NOT_FOUND:     'NOT_FOUND',      // Resource doesn't exist
  CONFLICT:      'CONFLICT',       // e.g. double booking
  VALIDATION:    'VALIDATION',     // Bad input data
  INTERNAL:      'INTERNAL',       // Unexpected server error
};

// ── Helpers ───────────────────────────────────────────────────────────────────

/**
 * Generate a UUID v4 using Apps Script's built-in utility.
 */
function generateUUID() {
  return Utilities.getUuid();
}

/**
 * Return current time as ISO 8601 string.
 */
function now() {
  return new Date().toISOString();
}

/**
 * Safely convert a Sheets cell value to an ISO date string.
 * Google Sheets returns Date objects for date-formatted cells.
 */
function toISOString(value) {
  if (!value) return '';
  if (value instanceof Date) return value.toISOString();
  return String(value);
}

/**
 * Assert that all required fields exist and are non-empty.
 * Throws a validation error if any are missing.
 * @param {Object} obj
 * @param {string[]} fields
 */
function requireFields(obj, fields) {
  for (const field of fields) {
    if (obj[field] === undefined || obj[field] === null || obj[field] === '') {
      const err = new Error(`Missing required field: ${field}`);
      err.errorCode = ERROR_CODE.VALIDATION;
      throw err;
    }
  }
}

// ── Shared throw helpers (used by all handler files) ──────────────────────────

/**
 * Throw a VALIDATION error.
 * @param {string} msg
 */
function throwValidation(msg) {
  const err = new Error(msg);
  err.errorCode = ERROR_CODE.VALIDATION;
  throw err;
}

/**
 * Throw a NOT_FOUND error for a named entity.
 * @param {string} entity - Human-readable entity name, e.g. 'Kamar'.
 */
function throwNotFound(entity) {
  const err = new Error(entity + ' tidak ditemukan');
  err.errorCode = ERROR_CODE.NOT_FOUND;
  throw err;
}

/**
 * Throw a LOCK_TIMEOUT error.
 */
function throwLock() {
  const err = new Error('Server sibuk, silakan coba lagi');
  err.errorCode = ERROR_CODE.LOCK_TIMEOUT;
  throw err;
}

/**
 * Throw a CONFLICT error.
 * @param {string} msg
 */
function throwConflict(msg) {
  const err = new Error(msg);
  err.errorCode = ERROR_CODE.CONFLICT;
  throw err;
}
