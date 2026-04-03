// ── Entry Points ──────────────────────────────────────────────────────────────
//
// This is the Apps Script Web App entry point.
// Deploy as: Execute as = Me, Access = Anyone.
//
// All Flutter requests arrive as POST with body:
//   { "action": "...", "token": "...", "data": { ... } }
//
// All responses are JSON:
//   { "success": true|false, "data": ..., "error": ..., "error_code": ..., "timestamp": "..." }
//
// HTTP status is always 200 (Apps Script limitation).
// The Flutter client checks `success` and `error_code`, not the HTTP status.

/**
 * Handle POST requests from the Flutter app.
 * @param {GoogleAppsScript.Events.DoPost} e
 */
function doPost(e) {
  try {
    // Guard: missing or empty body
    if (!e || !e.postData || !e.postData.contents) {
      return respondError('Invalid request: empty body', ERROR_CODE.VALIDATION);
    }

    let body;
    try {
      body = JSON.parse(e.postData.contents);
    } catch (_) {
      return respondError('Invalid request: body is not valid JSON', ERROR_CODE.VALIDATION);
    }

    const { action, token, data } = body;

    if (!action || typeof action !== 'string') {
      return respondError('Missing required field: action', ERROR_CODE.VALIDATION);
    }

    const result = _route(action, token, data);
    return respondOk(result);

  } catch (err) {
    Logger.log('[doPost] Unhandled error: ' + err.message + '\n' + (err.stack || ''));

    const errorCode = err.errorCode || ERROR_CODE.INTERNAL;

    // Don't leak internal stack traces to the client.
    const clientMessage = errorCode === ERROR_CODE.INTERNAL
      ? 'An internal error occurred. Please try again.'
      : err.message;

    return respondError(clientMessage, errorCode);
  }
}

/**
 * Health check endpoint — returns app status and timestamp.
 * Useful for verifying the deployment is alive before configuring the Flutter app.
 */
function doGet() {
  return ContentService
    .createTextOutput(JSON.stringify({
      status: 'ok',
      app: 'catat-app',
      version: '1.0.0',
      timestamp: new Date().toISOString(),
    }))
    .setMimeType(ContentService.MimeType.JSON);
}

// ── Router ────────────────────────────────────────────────────────────────────

/**
 * Route an action string to the appropriate handler function.
 * Actions are namespaced: "resource.verb" (e.g. "auth.login", "rooms.list").
 *
 * Public actions (no auth required):
 *   - auth.login
 *
 * Protected actions require a valid token → call requireAuth(token) first.
 * Protected routes will be added here as features are implemented.
 *
 * @param {string} action
 * @param {string|undefined} token - Google ID token (required for protected routes).
 * @param {Object|undefined} data  - Action-specific payload.
 * @returns {*} Handler return value (will be wrapped in respondOk).
 */
function _route(action, token, data) {
  switch (action) {

    // ── Auth (public) ──────────────────────────────────────────────────────
    case 'auth.login':
      return handleAuthLogin(token);

    // ── Rooms ──────────────────────────────────────────────────────────────
    case 'rooms.list':   return handleRoomsList(requireAuth(token));
    case 'rooms.create': return handleRoomsCreate(requireAuth(token), data);
    case 'rooms.update': return handleRoomsUpdate(requireAuth(token), data);
    case 'rooms.delete': return handleRoomsDelete(requireAuth(token), data);
    //
    case 'customers.list':         return handleCustomersList(requireAuth(token));
    case 'customers.getByNIK':     return handleCustomersGetByNIK(requireAuth(token), data);
    case 'customers.create':       return handleCustomersCreate(requireAuth(token), data);
    case 'customers.update':       return handleCustomersUpdate(requireAuth(token), data);
    case 'customers.delete':       return handleCustomersDelete(requireAuth(token), data);
    //
    case 'transactions.list':              return handleTransactionsList(requireAuth(token));
    case 'transactions.create':            return handleTransactionsCreate(requireAuth(token), data);
    case 'transactions.checkAvailability': return handleTransactionsCheckAvailability(requireAuth(token), data);
    // case 'transactions.getById':           return handleTransactionsGetById(requireAuth(token), data);
    // case 'transactions.update':            return handleTransactionsUpdate(requireAuth(token), data);
    // case 'transactions.delete':            return handleTransactionsDelete(requireAuth(token), data);
    //
    case 'payments.create':            return handlePaymentsCreate(requireAuth(token), data);
    case 'payments.listByTransaction': return handlePaymentsListByTransaction(requireAuth(token), data);
    // case 'payments.delete':            return handlePaymentsDelete(requireAuth(token), data);
    //
    case 'reports.summary': return handleReportsSummary(requireAuth(token), data);
    case 'reports.export':  return handleReportsExport(requireAuth(token), data);

    default: {
      const err = new Error('Unknown action: ' + action);
      err.errorCode = ERROR_CODE.VALIDATION;
      throw err;
    }
  }
}

// ── Auth guard for protected routes ───────────────────────────────────────────

/**
 * Verify the token and return the authenticated user record.
 * Throws UNAUTHORIZED if token is invalid or user not registered.
 * Call this at the top of every protected route handler.
 *
 * @param {string} token - Google ID token.
 * @returns {Object} User record from the users sheet.
 */
function requireAuth(token) {
  if (!token) {
    const err = new Error('Authentication required.');
    err.errorCode = ERROR_CODE.UNAUTHORIZED;
    throw err;
  }

  const payload = verifyGoogleToken(token);
  if (!payload) {
    const err = new Error('Invalid or expired token. Please sign in again.');
    err.errorCode = ERROR_CODE.UNAUTHORIZED;
    throw err;
  }

  const userRow = findRowByColumn(
    getSheet(SHEET.USERS),
    COL.USERS.GOOGLE_ID,
    String(payload.sub),
  );

  if (!userRow) {
    // Token is valid but user hasn't been registered — shouldn't normally happen
    // since auth.login creates users on first sign-in.
    const err = new Error('User not found. Please sign in again.');
    err.errorCode = ERROR_CODE.UNAUTHORIZED;
    throw err;
  }

  // Re-use the _rowToUser mapper from auth.js (all .js files share global scope).
  return _rowToUser(userRow);
}
