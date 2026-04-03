// ── auth.login ────────────────────────────────────────────────────────────────
//
// Flow:
//   1. Verify Google ID token via tokeninfo endpoint
//   2. Acquire script lock (prevent concurrent user creation)
//   3. Look up user by google_id in the users sheet
//   4. If found  → return existing user
//   5. If not found → create new user (first user becomes admin)
//   6. Release lock and return user object

/**
 * Handle the auth.login action.
 * Called by main.js router with the raw idToken from Flutter.
 *
 * @param {string} idToken - Google ID token from Flutter's google_sign_in.
 * @returns {Object} User record matching the users sheet schema.
 */
function handleAuthLogin(idToken) {
  if (!idToken) {
    const err = new Error('ID token is required');
    err.errorCode = ERROR_CODE.VALIDATION;
    throw err;
  }

  // 1. Verify token with Google.
  const payload = verifyGoogleToken(idToken);
  if (!payload) {
    const err = new Error('Invalid or expired Google token. Please sign in again.');
    err.errorCode = ERROR_CODE.UNAUTHORIZED;
    throw err;
  }

  // 2. Acquire lock before touching the sheet.
  const lock = LockService.getScriptLock();
  const acquired = lock.tryLock(LOCK_TIMEOUT_MS);
  if (!acquired) {
    const err = new Error('Server is busy. Please try again.');
    err.errorCode = ERROR_CODE.LOCK_TIMEOUT;
    throw err;
  }

  try {
    return _upsertUser(payload);
  } finally {
    lock.releaseLock();
  }
}

// ── Internal helpers ──────────────────────────────────────────────────────────

/**
 * Find existing user or create a new one based on the Google token payload.
 * Must be called inside a lock.
 *
 * @param {Object} payload - Verified Google token payload.
 * @returns {Object} User record.
 */
function _upsertUser(payload) {
  const sheet = getSheet(SHEET.USERS);
  const googleId = String(payload.sub);

  // Look up by google_id (unique OAuth subject identifier).
  const existingRow = findRowByColumn(sheet, COL.USERS.GOOGLE_ID, googleId);
  if (existingRow) {
    Logger.log('auth.login: returning existing user ' + existingRow[COL.USERS.EMAIL]);
    return _rowToUser(existingRow);
  }

  // First user in the sheet gets the admin role; all subsequent users are staff.
  const isFirstUser = sheet.getLastRow() < 2;

  const user = {
    id:         generateUUID(),
    google_id:  googleId,
    email:      payload.email,
    name:       payload.name || payload.email,
    role:       isFirstUser ? ROLE.ADMIN : ROLE.STAFF,
    created_at: now(),
    updated_at: now(),
  };

  appendRow(sheet, _userToRow(user));
  Logger.log('auth.login: created new user ' + user.email + ' role=' + user.role);

  return user;
}

/**
 * Convert a users sheet row array to a plain user object.
 * @param {Array} row
 * @returns {Object}
 */
function _rowToUser(row) {
  return {
    id:         String(row[COL.USERS.ID]),
    google_id:  String(row[COL.USERS.GOOGLE_ID]),
    email:      String(row[COL.USERS.EMAIL]),
    name:       String(row[COL.USERS.NAME]),
    role:       String(row[COL.USERS.ROLE]),
    created_at: toISOString(row[COL.USERS.CREATED_AT]),
    updated_at: toISOString(row[COL.USERS.UPDATED_AT]),
  };
}

/**
 * Convert a user object to a row array ordered by COL.USERS indices.
 * @param {Object} user
 * @returns {Array}
 */
function _userToRow(user) {
  return [
    user.id,
    user.google_id,
    user.email,
    user.name,
    user.role,
    user.created_at,
    user.updated_at,
  ];
}
