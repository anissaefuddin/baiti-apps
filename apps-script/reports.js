// ── Reports handlers ───────────────────────────────────────────────────────────
//
// Reports aggregate transaction and payment data for a given date range.
// All aggregation is done server-side to keep the client thin.
//
// Date range filtering uses check_in date of each transaction.
// Preset periods:
//   'daily'   → today only
//   'weekly'  → last 7 days (Mon–Sun of current week)
//   'monthly' → current calendar month
//   'custom'  → caller provides date_from and date_to (inclusive, 'YYYY-MM-DD')

/**
 * Return a summary report for the given period.
 *
 * Response shape:
 * {
 *   period: { from: 'YYYY-MM-DD', to: 'YYYY-MM-DD' },
 *   total_bookings:      number,
 *   total_income:        number,   // sum of total_price for all bookings in range
 *   collected_income:    number,   // sum of dp_amount (cash actually received)
 *   pending_income:      number,   // total_income - collected_income
 *   status_breakdown: {
 *     unpaid:  number,
 *     partial: number,
 *     paid:    number,
 *   },
 *   upcoming_bookings:   object[], // check_in within next 7 days from today
 *   unpaid_transactions: object[], // unpaid or partial, sorted by check_in asc
 * }
 *
 * @param {Object} user
 * @param {{ period, date_from?, date_to? }} data
 */
function handleReportsSummary(user, data) {
  data = data || {};
  const period   = String(data.period || 'monthly');
  const { from, to } = _resolveDateRange(period, data.date_from, data.date_to);

  const allTxns = getAllAs(getSheet(SHEET.TRANSACTIONS), _rowToTxnReport);

  // Build lookup maps for customer/room names
  const customerNames = {};
  getAllRows(getSheet(SHEET.CUSTOMERS)).forEach(r => {
    customerNames[String(r[COL.CUSTOMERS.ID])] = String(r[COL.CUSTOMERS.NAME]);
  });
  const roomNames = {};
  getAllRows(getSheet(SHEET.ROOMS)).forEach(r => {
    roomNames[String(r[COL.ROOMS.ID])] = String(r[COL.ROOMS.NAME]);
  });

  const _enrich = txn => ({
    ...txn,
    customer_name: customerNames[txn.customer_id] || '',
    room_name:     roomNames[txn.room_id]         || '',
  });

  // ── Filter to date range ─────────────────────────────────────────────────
  const inRange = allTxns.filter(t => {
    const d = t.check_in; // 'YYYY-MM-DD'
    return d >= from && d <= to;
  });

  // ── Aggregate ────────────────────────────────────────────────────────────
  let totalIncome     = 0;
  let collectedIncome = 0;
  const breakdown     = { unpaid: 0, partial: 0, paid: 0 };

  inRange.forEach(t => {
    totalIncome     += t.total_price;
    collectedIncome += t.dp_amount;
    if (breakdown[t.payment_status] !== undefined) {
      breakdown[t.payment_status]++;
    }
  });

  // ── Upcoming: check_in in the next 7 days from today ────────────────────
  const today      = _todayStr();
  const sevenDays  = _addDays(today, 7);
  const upcoming   = allTxns
    .filter(t => t.check_in >= today && t.check_in <= sevenDays)
    .map(_enrich)
    .sort((a, b) => a.check_in.localeCompare(b.check_in));

  // ── Unpaid / partial ─────────────────────────────────────────────────────
  const unpaidTxns = allTxns
    .filter(t =>
      t.payment_status === PAYMENT_STATUS.UNPAID ||
      t.payment_status === PAYMENT_STATUS.PARTIAL,
    )
    .map(_enrich)
    .sort((a, b) => a.check_in.localeCompare(b.check_in));

  Logger.log(
    'reports.summary: period=' + period + ' range=' + from + '…' + to +
    ' bookings=' + inRange.length + ' by ' + user.email,
  );

  return {
    period:              { from, to },
    total_bookings:      inRange.length,
    total_income:        totalIncome,
    collected_income:    collectedIncome,
    pending_income:      totalIncome - collectedIncome,
    status_breakdown:    breakdown,
    upcoming_bookings:   upcoming,
    unpaid_transactions: unpaidTxns,
  };
}

/**
 * Export transactions for the given period as a CSV string.
 *
 * Columns: Kode Booking, Tamu, Kamar, Check-in, Check-out, Malam,
 *          Total, Dibayar, Sisa, Status
 *
 * The Flutter client writes this string to a file and shares it.
 *
 * @param {Object} user
 * @param {{ period, date_from?, date_to? }} data
 */
function handleReportsExport(user, data) {
  data = data || {};
  const period   = String(data.period || 'monthly');
  const { from, to } = _resolveDateRange(period, data.date_from, data.date_to);

  const allTxns = getAllAs(getSheet(SHEET.TRANSACTIONS), _rowToTxnReport);

  const customerNames = {};
  getAllRows(getSheet(SHEET.CUSTOMERS)).forEach(r => {
    customerNames[String(r[COL.CUSTOMERS.ID])] = String(r[COL.CUSTOMERS.NAME]);
  });
  const roomNames = {};
  getAllRows(getSheet(SHEET.ROOMS)).forEach(r => {
    roomNames[String(r[COL.ROOMS.ID])] = String(r[COL.ROOMS.NAME]);
  });

  const inRange = allTxns
    .filter(t => t.check_in >= from && t.check_in <= to)
    .sort((a, b) => a.check_in.localeCompare(b.check_in));

  const HEADER = [
    'Kode Booking', 'Tamu', 'Kamar',
    'Check-in', 'Check-out', 'Malam',
    'Total (Rp)', 'Dibayar (Rp)', 'Sisa (Rp)', 'Status Bayar',
  ];

  const rows = inRange.map(t => [
    t.booking_code,
    customerNames[t.customer_id] || t.customer_id,
    roomNames[t.room_id]         || t.room_id,
    t.check_in,
    t.check_out,
    t.nights,
    t.total_price,
    t.dp_amount,
    t.total_price - t.dp_amount,
    _statusLabel(t.payment_status),
  ]);

  const csv = [HEADER, ...rows]
    .map(row => row.map(_csvCell).join(','))
    .join('\n');

  Logger.log(
    'reports.export: period=' + period + ' range=' + from + '…' + to +
    ' rows=' + inRange.length + ' by ' + user.email,
  );

  return {
    filename: 'laporan_' + from + '_' + to + '.csv',
    csv,
    row_count: inRange.length,
    period: { from, to },
  };
}

// ── Date range resolver ───────────────────────────────────────────────────────

/**
 * Resolve a named period or custom range into { from, to } ('YYYY-MM-DD').
 */
function _resolveDateRange(period, dateFrom, dateTo) {
  const today = _todayStr();

  switch (period) {
    case 'daily':
      return { from: today, to: today };

    case 'weekly': {
      // Monday–Sunday of the current ISO week
      const d    = new Date();
      const day  = d.getDay(); // 0=Sun
      const diff = day === 0 ? -6 : 1 - day;
      const mon  = new Date(d);
      mon.setDate(d.getDate() + diff);
      const sun  = new Date(mon);
      sun.setDate(mon.getDate() + 6);
      return { from: _formatDate(mon), to: _formatDate(sun) };
    }

    case 'monthly': {
      const d    = new Date();
      const from = d.getFullYear() + '-' +
                   String(d.getMonth() + 1).padStart(2, '0') + '-01';
      const last = new Date(d.getFullYear(), d.getMonth() + 1, 0);
      return { from, to: _formatDate(last) };
    }

    case 'custom': {
      if (!dateFrom || !dateTo) {
        const err = new Error('date_from and date_to required for custom period');
        err.errorCode = ERROR_CODE.VALIDATION;
        throw err;
      }
      return { from: String(dateFrom).substring(0, 10), to: String(dateTo).substring(0, 10) };
    }

    default: {
      const err = new Error('Invalid period: ' + period);
      err.errorCode = ERROR_CODE.VALIDATION;
      throw err;
    }
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function _todayStr() {
  return _formatDate(new Date());
}

function _formatDate(d) {
  return d.getFullYear() + '-' +
    String(d.getMonth() + 1).padStart(2, '0') + '-' +
    String(d.getDate()).padStart(2, '0');
}

function _addDays(dateStr, days) {
  const d = new Date(dateStr);
  d.setDate(d.getDate() + days);
  return _formatDate(d);
}

function _csvCell(value) {
  const s = String(value == null ? '' : value);
  // Wrap in quotes if contains comma, quote, or newline
  if (s.includes(',') || s.includes('"') || s.includes('\n')) {
    return '"' + s.replace(/"/g, '""') + '"';
  }
  return s;
}

function _statusLabel(status) {
  switch (status) {
    case PAYMENT_STATUS.PAID:    return 'Lunas';
    case PAYMENT_STATUS.PARTIAL: return 'DP / Sebagian';
    default:                     return 'Belum Bayar';
  }
}

function _rowToTxnReport(row) {
  return {
    id:             String(row[COL.TRANSACTIONS.ID]),
    booking_code:   String(row[COL.TRANSACTIONS.BOOKING_CODE]),
    customer_id:    String(row[COL.TRANSACTIONS.CUSTOMER_ID]),
    room_id:        String(row[COL.TRANSACTIONS.ROOM_ID]),
    check_in:       _rowDateToStr(row[COL.TRANSACTIONS.CHECK_IN]),
    check_out:      _rowDateToStr(row[COL.TRANSACTIONS.CHECK_OUT]),
    nights:         Number(row[COL.TRANSACTIONS.NIGHTS]),
    total_price:    Number(row[COL.TRANSACTIONS.TOTAL_PRICE]),
    dp_amount:      Number(row[COL.TRANSACTIONS.DP_AMOUNT] || 0),
    payment_status: String(row[COL.TRANSACTIONS.PAYMENT_STATUS] || PAYMENT_STATUS.UNPAID),
  };
}

function _rowDateToStr(value) {
  if (!value) return '';
  if (value instanceof Date) return _formatDate(value);
  return String(value).substring(0, 10);
}
