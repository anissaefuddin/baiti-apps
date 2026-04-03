// ── Payment handlers ───────────────────────────────────────────────────────────
//
// A payment records money received against a transaction.
// After each payment the transaction's `dp_amount` and `payment_status` are
// recomputed from the full payment history and written back atomically.
//
// Status logic (server-authoritative):
//   sum == 0              → 'unpaid'
//   0 < sum < total_price → 'partial'
//   sum >= total_price    → 'paid'
//
// Both the new payment record AND the updated transaction summary are returned
// from payments.create so the Flutter client can update both local caches in
// a single round-trip.

/**
 * List all payments for a given transaction, newest first.
 * @param {Object} user
 * @param {{ transaction_id }} data
 */
function handlePaymentsListByTransaction(user, data) {
  requireFields(data, ['transaction_id']);

  const txnId   = String(data.transaction_id);
  const txnRow  = findRowByColumn(
    getSheet(SHEET.TRANSACTIONS), COL.TRANSACTIONS.ID, txnId,
  );
  if (!txnRow) {
    const err = new Error('Transaksi tidak ditemukan');
    err.errorCode = ERROR_CODE.NOT_FOUND;
    throw err;
  }

  const payments = getAllRows(getSheet(SHEET.PAYMENTS))
    .filter(row => String(row[COL.PAYMENTS.TRANSACTION_ID]) === txnId)
    .map(_rowToPayment)
    .sort((a, b) => b.created_at.localeCompare(a.created_at));

  Logger.log(
    'payments.listByTransaction: ' + payments.length +
    ' payments for ' + txnId + ' to ' + user.email,
  );

  return payments;
}

/**
 * Add a payment to a transaction.
 *
 * Steps (all under a single script lock):
 *   1. Verify transaction exists and is not already fully paid.
 *   2. Validate amount > 0 and does not exceed remaining balance.
 *   3. Append payment row.
 *   4. Recompute dp_amount (sum of all payments) and payment_status.
 *   5. Update transaction row.
 *
 * Returns { payment, transaction } so the client can update both caches.
 *
 * @param {Object} user
 * @param {{ transaction_id, amount, method, notes? }} data
 */
function handlePaymentsCreate(user, data) {
  requireFields(data, ['transaction_id', 'amount', 'method']);

  const txnId  = String(data.transaction_id);
  const amount = Number(data.amount);

  if (isNaN(amount) || amount <= 0) {
    throwValidation('Jumlah pembayaran harus lebih dari 0');
  }

  const validMethods = [
    PAYMENT_METHOD.CASH,
    PAYMENT_METHOD.TRANSFER,
    PAYMENT_METHOD.QRIS,
  ];
  if (!validMethods.includes(String(data.method))) {
    throwValidation('Metode pembayaran tidak valid');
  }

  const lock = LockService.getScriptLock();
  if (!lock.tryLock(LOCK_TIMEOUT_MS)) throwLock();

  try {
    const txnsSheet = getSheet(SHEET.TRANSACTIONS);
    const txnRowNum = findRowNumberByColumn(txnsSheet, COL.TRANSACTIONS.ID, txnId);
    if (txnRowNum === -1) {
      const err = new Error('Transaksi tidak ditemukan');
      err.errorCode = ERROR_CODE.NOT_FOUND;
      throw err;
    }
    const txnRow    = findRowByColumn(txnsSheet, COL.TRANSACTIONS.ID, txnId);
    const txn       = _rowToTxnForPayment(txnRow);

    if (txn.payment_status === PAYMENT_STATUS.PAID) {
      throwValidation('Transaksi ini sudah lunas');
    }

    const remaining = txn.total_price - txn.dp_amount;
    if (amount > remaining + 0.01) {  // 0.01 tolerance for floating-point
      throwValidation(
        'Jumlah melebihi sisa tagihan (Rp ' +
        remaining.toLocaleString('id-ID') + ')',
      );
    }

    // ── Persist payment ──────────────────────────────────────────────────────
    const payment = {
      id:             generateUUID(),
      transaction_id: txnId,
      amount:         amount,
      method:         String(data.method),
      paid_at:        now(),
      notes:          String(data.notes || '').trim(),
      created_by:     user.id,
      created_at:     now(),
    };
    appendRow(getSheet(SHEET.PAYMENTS), _paymentToRow(payment));

    // ── Recompute dp_amount and payment_status from full payment history ─────
    const allPayments = getAllRows(getSheet(SHEET.PAYMENTS))
      .filter(r => String(r[COL.PAYMENTS.TRANSACTION_ID]) === txnId);
    const newDp = allPayments.reduce((sum, r) => sum + Number(r[COL.PAYMENTS.AMOUNT]), 0);

    const newStatus = newDp <= 0
      ? PAYMENT_STATUS.UNPAID
      : newDp >= txn.total_price
        ? PAYMENT_STATUS.PAID
        : PAYMENT_STATUS.PARTIAL;

    // Only update the three fields that changed; reconstruct full row.
    const updatedTxnRow = [...txnRow];
    updatedTxnRow[COL.TRANSACTIONS.DP_AMOUNT]      = newDp;
    updatedTxnRow[COL.TRANSACTIONS.PAYMENT_STATUS] = newStatus;
    updatedTxnRow[COL.TRANSACTIONS.UPDATED_AT]     = now();
    updateRow(txnsSheet, txnRowNum, updatedTxnRow);

    Logger.log(
      'payments.create: Rp ' + amount + ' via ' + payment.method +
      ' for ' + txnId + ' by ' + user.email +
      ' → status=' + newStatus,
    );

    return {
      payment,
      transaction_update: {
        id:             txnId,
        dp_amount:      newDp,
        payment_status: newStatus,
      },
    };
  } finally {
    lock.releaseLock();
  }
}

// ── Row ↔ Object converters ───────────────────────────────────────────────────

function _paymentToRow(p) {
  return [
    p.id,
    p.transaction_id,
    p.amount,
    p.method,
    p.paid_at,
    p.notes,
    p.created_by,
    p.created_at,
  ];
}

function _rowToPayment(row) {
  return {
    id:             String(row[COL.PAYMENTS.ID]),
    transaction_id: String(row[COL.PAYMENTS.TRANSACTION_ID]),
    amount:         Number(row[COL.PAYMENTS.AMOUNT]),
    method:         String(row[COL.PAYMENTS.METHOD]),
    paid_at:        toISOString(row[COL.PAYMENTS.PAID_AT]),
    notes:          String(row[COL.PAYMENTS.NOTES] || ''),
    created_by:     String(row[COL.PAYMENTS.CREATED_BY] || ''),
    created_at:     toISOString(row[COL.PAYMENTS.CREATED_AT]),
  };
}

/** Minimal transaction fields needed for payment validation. */
function _rowToTxnForPayment(row) {
  return {
    id:             String(row[COL.TRANSACTIONS.ID]),
    total_price:    Number(row[COL.TRANSACTIONS.TOTAL_PRICE]),
    dp_amount:      Number(row[COL.TRANSACTIONS.DP_AMOUNT] || 0),
    payment_status: String(row[COL.TRANSACTIONS.PAYMENT_STATUS] || PAYMENT_STATUS.UNPAID),
  };
}

// Error helpers are in utils.js: throwValidation, throwNotFound, throwLock, throwConflict
