// ── Transaction (Booking) handlers ────────────────────────────────────────────
//
// A "transaction" represents a confirmed room booking.
// One booking can include multiple rooms for the same date range.
//
// Business rules:
//   • No room can be double-booked (overlap check under lock before insert).
//   • room_ids is stored as a JSON array string e.g. '["id1","id2"]'.
//   • A Google Calendar event is created on the *user's own calendar* using
//     their OAuth access token (passed from Flutter). Falls back to the
//     deployer's default calendar if no token is provided.
//   • Calendar times: check-in 14:00 (2 PM), check-out 12:00 (noon).
//   • Booking codes: BK-YYYYMMDD-NNN (sequence resets per day).
//   • payment_status starts as 'unpaid'; updated by the payments module.

/**
 * Return all transactions, enriched with customer_name and room_name.
 */
function handleTransactionsList(user) {
  const txns = getAllAs(getSheet(SHEET.TRANSACTIONS), _rowToTransaction);

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
    room_name: txn.room_ids.map(id => roomNames[id] || id).join(', '),
  }));
}

/**
 * Check whether rooms are available for the requested date range.
 * Accepts either room_id (single string) or room_ids (array) from the client.
 */
function handleTransactionsCheckAvailability(user, data) {
  requireFields(data, ['check_in', 'check_out']);
  if (!data.room_id && (!data.room_ids || data.room_ids.length === 0)) {
    throwValidation('room_id atau room_ids wajib diisi');
  }

  const checkIn  = new Date(data.check_in);
  const checkOut = new Date(data.check_out);

  if (isNaN(checkIn.getTime()))  throwValidation('Tanggal check-in tidak valid');
  if (isNaN(checkOut.getTime())) throwValidation('Tanggal check-out tidak valid');
  if (checkOut <= checkIn)       throwValidation('Tanggal check-out harus setelah check-in');

  const roomIds = data.room_ids
    ? data.room_ids.map(String)
    : [String(data.room_id)];

  const allTxns = getAllAs(getSheet(SHEET.TRANSACTIONS), _rowToTransaction);
  const excludeId = data.exclude_id ? String(data.exclude_id) : null;
  const conflict = _findConflict(allTxns, roomIds, checkIn, checkOut, excludeId);

  if (conflict) {
    // Resolve names of the specific rooms that clash
    const roomsSheet = getSheet(SHEET.ROOMS);
    const conflictingIds = _parseRoomIds(conflict.room_ids)
      .filter(id => roomIds.includes(id));
    const conflictRoomNames = conflictingIds.map(id => {
      const row = findRowByColumn(roomsSheet, COL.ROOMS.ID, id);
      return row ? String(row[COL.ROOMS.NAME]) : id;
    });

    return {
      available: false,
      conflict: {
        booking_code: conflict.booking_code,
        check_in:     conflict.check_in,
        check_out:    conflict.check_out,
        room_names:   conflictRoomNames,
      },
    };
  }

  return { available: true };
}

/**
 * Create a new booking (supports multiple rooms).
 *
 * Steps (all under a single script lock):
 *   1. Validate customer + all rooms exist.
 *   2. Re-check availability for each room (prevents race conditions).
 *   3. Calculate nights and total price (sum of all room prices × nights).
 *   4. Generate booking code.
 *   5. Create Google Calendar event on user's own calendar (non-fatal).
 *   6. Persist to sheet.
 *
 * @param {Object} user
 * @param {{ customer_id, room_ids, check_in, check_out, notes?, calendar_access_token? }} data
 */
function handleTransactionsCreate(user, data) {
  requireFields(data, ['customer_id', 'check_in', 'check_out']);
  if (!data.room_ids || data.room_ids.length === 0) {
    throwValidation('room_ids wajib diisi dan tidak boleh kosong');
  }

  const checkIn  = new Date(data.check_in);
  const checkOut = new Date(data.check_out);

  if (isNaN(checkIn.getTime()))  throwValidation('Tanggal check-in tidak valid');
  if (isNaN(checkOut.getTime())) throwValidation('Tanggal check-out tidak valid');
  if (checkOut <= checkIn)       throwValidation('Tanggal check-out harus setelah check-in');

  const today = new Date();
  today.setHours(0, 0, 0, 0);
  if (checkIn < today) throwValidation('Tanggal check-in tidak boleh di masa lalu');

  const roomIds = data.room_ids.map(String);

  const lock = LockService.getScriptLock();
  if (!lock.tryLock(LOCK_TIMEOUT_MS)) throwLock();

  try {
    // ── Verify customer ──────────────────────────────────────────────────
    const customerRow = findRowByColumn(
      getSheet(SHEET.CUSTOMERS), COL.CUSTOMERS.ID, String(data.customer_id),
    );
    if (!customerRow) throwValidation('Tamu tidak ditemukan');

    // ── Verify all rooms & collect data ──────────────────────────────────
    const roomsSheet = getSheet(SHEET.ROOMS);
    const roomRows   = [];
    for (const roomId of roomIds) {
      const row = findRowByColumn(roomsSheet, COL.ROOMS.ID, roomId);
      if (!row) throwValidation('Kamar tidak ditemukan: ' + roomId);
      roomRows.push(row);
    }

    // ── Availability check for every room (inside lock) ──────────────────
    const txnsSheet = getSheet(SHEET.TRANSACTIONS);
    const allTxns   = getAllAs(txnsSheet, _rowToTransaction);

    const conflict = _findConflict(allTxns, roomIds, checkIn, checkOut, null);
    if (conflict) {
      const err = new Error(
        'Kamar sudah dipesan pada tanggal tersebut (booking: ' + conflict.booking_code + ')',
      );
      err.errorCode = ERROR_CODE.CONFLICT;
      throw err;
    }

    // ── Calculate stay & total ────────────────────────────────────────────
    const nights     = Math.round((checkOut - checkIn) / 86400000);
    const totalPrice = roomRows.reduce(
      (sum, row) => sum + Number(row[COL.ROOMS.PRICE]),
      0,
    ) * nights;

    // ── Generate booking code ─────────────────────────────────────────────
    const bookingCode = _generateBookingCode(allTxns);

    // ── Calendar event on user's own calendar (non-fatal) ─────────────────
    const customerName = String(customerRow[COL.CUSTOMERS.NAME]);
    const roomNames    = roomRows.map(r => String(r[COL.ROOMS.NAME])).join(', ');
    let calendarEventId = '';
    let calendarError   = null;
    try {
      calendarEventId = _createCalendarEvent(
        bookingCode, customerName, roomNames,
        checkIn, checkOut,
        String(data.notes || ''),
        data.calendar_access_token || null,
      );
      Logger.log('[transactions.create] Calendar event created: ' + calendarEventId);
    } catch (calErr) {
      calendarError = calErr.message;
      Logger.log('[transactions.create] Calendar event failed (non-fatal): ' + calErr.message);
    }

    // ── Persist ───────────────────────────────────────────────────────────
    const txn = {
      id:                generateUUID(),
      booking_code:      bookingCode,
      customer_id:       String(data.customer_id),
      room_ids:          roomIds,
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
    Logger.log('transactions.create: ' + bookingCode + ' rooms=[' + roomIds.join(',') + '] by ' + user.email);

    return {
      ...txn,
      customer_name:  customerName,
      room_name:      roomNames,
      calendar_error: calendarError, // null if event was created successfully
    };
  } finally {
    lock.releaseLock();
  }
}

// ── Availability helper ───────────────────────────────────────────────────────

/**
 * Find the first transaction where ANY of the requested rooms overlaps
 * the date range.
 */
function _findConflict(txns, roomIds, checkIn, checkOut, excludeId) {
  const requestedSet = new Set(roomIds);

  return txns.find(txn => {
    if (excludeId && txn.id === excludeId) return false;

    const existingIds   = _parseRoomIds(txn.room_ids);
    const hasSharedRoom = existingIds.some(id => requestedSet.has(id));
    if (!hasSharedRoom) return false;

    const existIn  = new Date(txn.check_in);
    const existOut = new Date(txn.check_out);
    return existIn < checkOut && existOut > checkIn;
  }) || null;
}

/**
 * Parse the room_ids field — handles both new JSON array string and legacy
 * single-ID string for backward compatibility with old data.
 */
function _parseRoomIds(value) {
  if (!value) return [];
  const str = String(value).trim();
  if (str.startsWith('[')) {
    try { return JSON.parse(str).map(String); } catch (_) {}
  }
  return str ? [str] : [];
}

// ── Booking code generator ────────────────────────────────────────────────────

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
 * Create a Google Calendar event.
 *
 * Check-in time : 14:00 (2 PM) on the check-in date.
 * Check-out time: 12:00 (noon) on the check-out date.
 *
 * If calendarAccessToken is provided (user's OAuth access token from Flutter),
 * the event is created on the USER's own primary calendar via the REST API.
 * Otherwise falls back to the deployer's default calendar.
 */
function _createCalendarEvent(bookingCode, customerName, roomNames, checkIn, checkOut, notes, calendarAccessToken) {
  const title = '[' + roomNames + '] ' + customerName;
  const desc  = bookingCode + (notes ? '\n\nCatatan: ' + notes : '');

  // Build local-time Date objects so setHours() works in Asia/Jakarta.
  const ci = checkIn instanceof Date ? checkIn : new Date(checkIn);
  const co = checkOut instanceof Date ? checkOut : new Date(checkOut);

  const checkInTime  = new Date(ci.getFullYear(), ci.getMonth(), ci.getDate(), 14, 0, 0);
  const checkOutTime = new Date(co.getFullYear(), co.getMonth(), co.getDate(), 12, 0, 0);

  if (calendarAccessToken) {
    return _createCalendarEventViaApi(title, desc, checkInTime, checkOutTime, calendarAccessToken);
  }

  // Fallback: deployer's default calendar
  const event = CalendarApp.getDefaultCalendar().createEvent(
    title, checkInTime, checkOutTime, { description: desc },
  );
  return event.getId();
}

/**
 * Create a calendar event via the Google Calendar REST API using the user's
 * own OAuth access token — so the event appears on their calendar, not the
 * deployer's.
 */
function _createCalendarEventViaApi(title, description, startTime, endTime, accessToken) {
  const body = {
    summary:     title,
    description: description,
    start: { dateTime: _toIso8601Local(startTime), timeZone: 'Asia/Jakarta' },
    end:   { dateTime: _toIso8601Local(endTime),   timeZone: 'Asia/Jakarta' },
  };

  const response = UrlFetchApp.fetch(
    'https://www.googleapis.com/calendar/v3/calendars/primary/events',
    {
      method:             'post',
      contentType:        'application/json',
      headers:            { Authorization: 'Bearer ' + accessToken },
      payload:            JSON.stringify(body),
      muteHttpExceptions: true,
    },
  );

  const result = JSON.parse(response.getContentText());
  if (!result.id) {
    throw new Error('Calendar API error: ' + (result.error ? result.error.message : response.getContentText()));
  }
  return result.id;
}

/**
 * Format a Date as ISO 8601 with +07:00 offset.
 * Uses local getters (correct only when script timezone = Asia/Jakarta).
 */
function _toIso8601Local(d) {
  const pad = n => String(n).padStart(2, '0');
  return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate())
    + 'T' + pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':00+07:00';
}

// ── Date helper ───────────────────────────────────────────────────────────────

function _formatDate(d) {
  if (!(d instanceof Date)) return String(d).substring(0, 10);
  const y   = d.getFullYear();
  const m   = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return y + '-' + m + '-' + day;
}

// ── Row ↔ Object converters ───────────────────────────────────────────────────

function _transactionToRow(txn) {
  return [
    txn.id,
    txn.booking_code,
    txn.customer_id,
    JSON.stringify(txn.room_ids),  // stored as JSON array string
    txn.check_in,
    txn.check_out,
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
    room_ids:          _parseRoomIds(row[COL.TRANSACTIONS.ROOM_IDS]),
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

function _rowDateToString(value) {
  if (!value) return '';
  if (value instanceof Date) return _formatDate(value);
  return String(value).substring(0, 10);
}
