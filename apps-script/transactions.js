// ── Transaction (Booking) handlers ────────────────────────────────────────────
//
// A "transaction" in this system represents a confirmed room booking.
// Bookings are linked to one customer and one room, with a date range.
//
// Business rules:
//   • A room cannot be double-booked (overlap check under lock before insert).
//   • A Google Calendar event is created on success (non-fatal if it fails).
//   • Booking codes are auto-generated: BK-YYYYMMDD-NNN (sequence resets per day).
//   • payment_status starts as 'unpaid'; updated by the payments module (Phase 4).

/**
 * Return all transactions, enriched with customer_name and room_name.
 * Builds lookup maps over customers/rooms sheets to avoid O(n²) scans.
 * @param {Object} user - Authenticated user.
 */
function handleTransactionsList(user) {
  const txns = getAllAs(getSheet(SHEET.TRANSACTIONS), _rowToTransaction);

  // Build O(1) lookup maps
  const customerNames = {};
  getAllRows(getSheet(SHEET.CUSTOMERS)).forEach(r => {
    customerNames[String(r[COL.CUSTOMERS.ID])] = String(r[COL.CUSTOMERS.NAME]);
  });

  const roomNames = {};
  getAllRows(getSheet(SHEET.ROOMS)).forEach(r => {
    roomNames[String(r[COL.ROOMS.ID])] = String(r[COL.ROOMS.NAME]);
  });

  Logger.log('transactions.list: ' + txns.length + ' records to ' + user.email);

  return txns.map(txn => ({
    ...txn,
    customer_name: customerNames[txn.customer_id] || '',
    room_name:     roomNames[txn.room_id]         || '',
  }));
}

/**
 * Check whether a room is available for the requested date range.
 * Returns { available: true } or { available: false, conflict: { booking_code, check_in, check_out } }.
 *
 * Pass `exclude_id` when re-checking for an existing booking (update flow).
 *
 * @param {Object} user
 * @param {{ room_id, check_in, check_out, exclude_id? }} data
 */
function handleTransactionsCheckAvailability(user, data) {
  requireFields(data, ['room_id', 'check_in', 'check_out']);

  const checkIn  = new Date(data.check_in);
  const checkOut = new Date(data.check_out);

  if (isNaN(checkIn.getTime()))  throwValidation('Tanggal check-in tidak valid');
  if (isNaN(checkOut.getTime())) throwValidation('Tanggal check-out tidak valid');
  if (checkOut <= checkIn)       throwValidation('Tanggal check-out harus setelah check-in');

  const conflict = _findConflict(
    getAllAs(getSheet(SHEET.TRANSACTIONS), _rowToTransaction),
    String(data.room_id),
    checkIn,
    checkOut,
    data.exclude_id ? String(data.exclude_id) : null,
  );

  if (conflict) {
    return {
      available: false,
      conflict: {
        booking_code: conflict.booking_code,
        check_in:     conflict.check_in,
        check_out:    conflict.check_out,
      },
    };
  }

  return { available: true };
}

/**
 * Create a new booking.
 *
 * Steps (all under a single script lock):
 *   1. Validate customer + room exist.
 *   2. Re-check availability (prevents race conditions).
 *   3. Calculate nights and total price.
 *   4. Generate booking code.
 *   5. Create Google Calendar event (non-fatal).
 *   6. Persist to sheet.
 *
 * @param {Object} user
 * @param {{ customer_id, room_id, check_in, check_out, notes? }} data
 */
function handleTransactionsCreate(user, data) {
  requireFields(data, ['customer_id', 'room_id', 'check_in', 'check_out']);

  const checkIn  = new Date(data.check_in);
  const checkOut = new Date(data.check_out);

  if (isNaN(checkIn.getTime()))  throwValidation('Tanggal check-in tidak valid');
  if (isNaN(checkOut.getTime())) throwValidation('Tanggal check-out tidak valid');
  if (checkOut <= checkIn)       throwValidation('Tanggal check-out harus setelah check-in');

  // Validate date is not in the past (allow today)
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  if (checkIn < today) throwValidation('Tanggal check-in tidak boleh di masa lalu');

  const lock = LockService.getScriptLock();
  if (!lock.tryLock(LOCK_TIMEOUT_MS)) throwLock();

  try {
    // ── Verify foreign keys ──────────────────────────────────────────────────
    const customerRow = findRowByColumn(
      getSheet(SHEET.CUSTOMERS), COL.CUSTOMERS.ID, String(data.customer_id),
    );
    if (!customerRow) throwValidation('Tamu tidak ditemukan');

    const roomRow = findRowByColumn(
      getSheet(SHEET.ROOMS), COL.ROOMS.ID, String(data.room_id),
    );
    if (!roomRow) throwValidation('Kamar tidak ditemukan');

    // ── Availability check (inside lock — prevents race condition) ───────────
    const txnsSheet = getSheet(SHEET.TRANSACTIONS);
    const allTxns   = getAllAs(txnsSheet, _rowToTransaction);

    const conflict = _findConflict(allTxns, String(data.room_id), checkIn, checkOut, null);
    if (conflict) {
      const err = new Error(
        'Kamar sudah dipesan pada tanggal tersebut (booking: ' + conflict.booking_code + ')',
      );
      err.errorCode = ERROR_CODE.CONFLICT;
      throw err;
    }

    // ── Calculate stay ───────────────────────────────────────────────────────
    const nights     = Math.round((checkOut - checkIn) / 86400000); // ms per day
    const pricePerNight = Number(roomRow[COL.ROOMS.PRICE]);
    const totalPrice    = nights * pricePerNight;

    // ── Generate booking code ────────────────────────────────────────────────
    const bookingCode = _generateBookingCode(allTxns);

    // ── Calendar event (non-fatal) ───────────────────────────────────────────
    const customerName = String(customerRow[COL.CUSTOMERS.NAME]);
    const roomName     = String(roomRow[COL.ROOMS.NAME]);
    let calendarEventId = '';
    try {
      calendarEventId = _createCalendarEvent(
        bookingCode, customerName, roomName,
        checkIn, checkOut, String(data.notes || ''),
      );
    } catch (calErr) {
      Logger.log('[transactions.create] Calendar event failed (non-fatal): ' + calErr.message);
    }

    // ── Persist ──────────────────────────────────────────────────────────────
    const txn = {
      id:                generateUUID(),
      booking_code:      bookingCode,
      customer_id:       String(data.customer_id),
      room_id:           String(data.room_id),
      check_in:          _formatDate(checkIn),
      check_out:         _formatDate(checkOut),
      nights:            nights,
      total_price:       totalPrice,
      dp_amount:         0,
      payment_status:    PAYMENT_STATUS.UNPAID,
      calendar_event_id: calendarEventId,
      notes:             String(data.notes || '').trim(),
      created_by:        user.id,
      created_at:        now(),
      updated_at:        now(),
    };

    appendRow(txnsSheet, _transactionToRow(txn));
    Logger.log('transactions.create: ' + bookingCode + ' by ' + user.email);

    return {
      ...txn,
      customer_name: customerName,
      room_name:     roomName,
    };
  } finally {
    lock.releaseLock();
  }
}

// ── Availability helper ───────────────────────────────────────────────────────

/**
 * Find the first transaction that overlaps [checkIn, checkOut) for the given room.
 * Overlap: existing.check_in < requested.check_out AND existing.check_out > requested.check_in
 *
 * @param {Object[]} txns    - All existing transactions.
 * @param {string}   roomId
 * @param {Date}     checkIn
 * @param {Date}     checkOut
 * @param {string|null} excludeId - Transaction ID to ignore (for updates).
 * @returns {Object|null}
 */
function _findConflict(txns, roomId, checkIn, checkOut, excludeId) {
  return txns.find(txn => {
    if (txn.room_id !== roomId) return false;
    if (excludeId && txn.id === excludeId) return false;

    const existIn  = new Date(txn.check_in);
    const existOut = new Date(txn.check_out);

    return existIn < checkOut && existOut > checkIn;
  }) || null;
}

// ── Booking code generator ────────────────────────────────────────────────────

/**
 * Generate the next sequential booking code for today: BK-YYYYMMDD-NNN.
 * Sequence is 1-based and resets at midnight.
 * @param {Object[]} allTxns - All existing transactions (for sequence scan).
 */
function _generateBookingCode(allTxns) {
  const d = new Date();
  const dateStr = d.getFullYear().toString()
    + String(d.getMonth() + 1).padStart(2, '0')
    + String(d.getDate()).padStart(2, '0');

  const prefix = 'BK-' + dateStr + '-';

  let maxSeq = 0;
  allTxns.forEach(txn => {
    const code = String(txn.booking_code || '');
    if (code.startsWith(prefix)) {
      const seq = parseInt(code.substring(prefix.length), 10);
      if (!isNaN(seq) && seq > maxSeq) maxSeq = seq;
    }
  });

  return prefix + String(maxSeq + 1).padStart(3, '0');
}

// ── Google Calendar ───────────────────────────────────────────────────────────

/**
 * Create an all-day Google Calendar event spanning the booking stay.
 * Uses the default calendar of the script owner's account.
 *
 * @returns {string} The event ID stored for future edits/deletes.
 */
function _createCalendarEvent(bookingCode, customerName, roomName, checkIn, checkOut, notes) {
  const calendar = CalendarApp.getDefaultCalendar();
  const title    = '[' + roomName + '] ' + customerName;
  const desc     = bookingCode + (notes ? '\n\nCatatan: ' + notes : '');

  // createAllDayEvent(title, startDate, endDate) — endDate is exclusive
  const event = calendar.createAllDayEvent(title, checkIn, checkOut, {
    description: desc,
  });

  return event.getId();
}

// ── Date helper ───────────────────────────────────────────────────────────────

/**
 * Format a Date object as 'YYYY-MM-DD' string (locale-independent).
 * Avoids timezone shift issues from toISOString() which outputs UTC.
 */
function _formatDate(d) {
  if (!(d instanceof Date)) {
    // Already a string — normalise to date-only portion
    return String(d).substring(0, 10);
  }
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return y + '-' + m + '-' + day;
}

// ── Row ↔ Object converters ───────────────────────────────────────────────────

function _transactionToRow(txn) {
  return [
    txn.id,
    txn.booking_code,
    txn.customer_id,
    txn.room_id,
    txn.check_in,           // 'YYYY-MM-DD' string
    txn.check_out,          // 'YYYY-MM-DD' string
    txn.nights,
    txn.total_price,
    txn.dp_amount,
    txn.payment_status,
    txn.calendar_event_id,
    txn.notes,
    txn.created_by,
    txn.created_at,
    txn.updated_at,
  ];
}

function _rowToTransaction(row) {
  return {
    id:                String(row[COL.TRANSACTIONS.ID]),
    booking_code:      String(row[COL.TRANSACTIONS.BOOKING_CODE]),
    customer_id:       String(row[COL.TRANSACTIONS.CUSTOMER_ID]),
    room_id:           String(row[COL.TRANSACTIONS.ROOM_ID]),
    check_in:          _rowDateToString(row[COL.TRANSACTIONS.CHECK_IN]),
    check_out:         _rowDateToString(row[COL.TRANSACTIONS.CHECK_OUT]),
    nights:            Number(row[COL.TRANSACTIONS.NIGHTS]),
    total_price:       Number(row[COL.TRANSACTIONS.TOTAL_PRICE]),
    dp_amount:         Number(row[COL.TRANSACTIONS.DP_AMOUNT] || 0),
    payment_status:    String(row[COL.TRANSACTIONS.PAYMENT_STATUS] || PAYMENT_STATUS.UNPAID),
    calendar_event_id: String(row[COL.TRANSACTIONS.CALENDAR_EVENT_ID] || ''),
    notes:             String(row[COL.TRANSACTIONS.NOTES] || ''),
    created_by:        String(row[COL.TRANSACTIONS.CREATED_BY] || ''),
    created_at:        toISOString(row[COL.TRANSACTIONS.CREATED_AT]),
    updated_at:        toISOString(row[COL.TRANSACTIONS.UPDATED_AT]),
  };
}

/**
 * Convert a Sheets cell date value to a 'YYYY-MM-DD' string.
 * Handles both Date objects (Sheets auto-converts date cells) and plain strings.
 */
function _rowDateToString(value) {
  if (!value) return '';
  if (value instanceof Date) return _formatDate(value);
  // String: take just the date portion
  return String(value).substring(0, 10);
}

// Error helpers are in utils.js: throwValidation, throwNotFound, throwLock, throwConflict
