// ── Customer handlers ──────────────────────────────────────────────────────────
//
// All handlers receive the authenticated `user` object from requireAuth()
// in main.js. Write operations acquire a script lock before touching the sheet.
//
// NIK (Nomor Induk Kependudukan) is the Indonesian national ID number — 16 digits,
// unique per customer, and used as a human-readable identifier in search.

/**
 * Return all customers ordered as stored.
 * @param {Object} user - Authenticated user from requireAuth().
 */
function handleCustomersList(user) {
  const customers = getAllAs(getSheet(SHEET.CUSTOMERS), _rowToCustomer);
  Logger.log('customers.list: ' + customers.length + ' customers returned to ' + user.email);
  return customers;
}

/**
 * Find a single customer by NIK (exact match).
 * Used for duplicate-check on the form and NIK-based lookup during booking.
 * @param {Object} user
 * @param {{ nik }} data
 */
function handleCustomersGetByNIK(user, data) {
  requireFields(data, ['nik']);

  const row = findRowByColumn(
    getSheet(SHEET.CUSTOMERS),
    COL.CUSTOMERS.NIK,
    String(data.nik).trim(),
  );

  if (!row) throwNotFound('Tamu');
  return _rowToCustomer(row);
}

/**
 * Create a new customer.
 * NIK must be unique — returns CONFLICT if another customer with the same NIK exists.
 * @param {Object} user
 * @param {{ nik, name, phone?, address?, birth_date? }} data
 */
function handleCustomersCreate(user, data) {
  requireFields(data, ['nik', 'name']);

  const nik  = String(data.nik).trim();
  const name = String(data.name).trim();

  if (!/^\d{16}$/.test(nik)) {
    throwValidation('NIK harus terdiri dari 16 digit angka');
  }
  if (name === '') {
    throwValidation('Nama tamu tidak boleh kosong');
  }

  const lock = LockService.getScriptLock();
  if (!lock.tryLock(LOCK_TIMEOUT_MS)) throwLock();

  try {
    // Check NIK uniqueness while holding the lock.
    const existing = findRowByColumn(getSheet(SHEET.CUSTOMERS), COL.CUSTOMERS.NIK, nik);
    if (existing) {
      const err = new Error('NIK ' + nik + ' sudah terdaftar');
      err.errorCode = ERROR_CODE.CONFLICT;
      throw err;
    }

    const customer = {
      id:         generateUUID(),
      nik:        nik,
      name:       name,
      phone:      String(data.phone || '').trim(),
      address:    String(data.address || '').trim(),
      birth_date: String(data.birth_date || '').trim(),
      ktp_url:    '',
      created_at: now(),
      updated_at: now(),
    };

    appendRow(getSheet(SHEET.CUSTOMERS), _customerToRow(customer));
    Logger.log('customers.create: NIK=' + nik + ' by ' + user.email);
    return customer;
  } finally {
    lock.releaseLock();
  }
}

/**
 * Update one or more fields of an existing customer.
 * NIK cannot be changed after creation (it is the permanent identifier).
 * @param {Object} user
 * @param {{ id, name?, phone?, address?, birth_date? }} data
 */
function handleCustomersUpdate(user, data) {
  requireFields(data, ['id']);

  const lock = LockService.getScriptLock();
  if (!lock.tryLock(LOCK_TIMEOUT_MS)) throwLock();

  try {
    const sheet  = getSheet(SHEET.CUSTOMERS);
    const rowNum = findRowNumberByColumn(sheet, COL.CUSTOMERS.ID, data.id);
    if (rowNum === -1) throwNotFound('Tamu');

    const existing = _rowToCustomer(findRowByColumn(sheet, COL.CUSTOMERS.ID, data.id));

    const updated = {
      id:         existing.id,
      nik:        existing.nik,  // NIK is immutable after creation
      name:       data.name      !== undefined ? String(data.name).trim()       : existing.name,
      phone:      data.phone     !== undefined ? String(data.phone).trim()      : existing.phone,
      address:    data.address   !== undefined ? String(data.address).trim()    : existing.address,
      birth_date: data.birth_date !== undefined ? String(data.birth_date).trim() : existing.birth_date,
      ktp_url:    existing.ktp_url,
      created_at: existing.created_at,
      updated_at: now(),
    };

    updateRow(sheet, rowNum, _customerToRow(updated));
    Logger.log('customers.update: id=' + data.id + ' by ' + user.email);
    return updated;
  } finally {
    lock.releaseLock();
  }
}

/**
 * Delete a customer by ID.
 * Phase 3 will add a guard: blocked if customer has any transaction.
 * @param {Object} user
 * @param {{ id }} data
 */
function handleCustomersDelete(user, data) {
  requireFields(data, ['id']);

  const lock = LockService.getScriptLock();
  if (!lock.tryLock(LOCK_TIMEOUT_MS)) throwLock();

  try {
    const sheet  = getSheet(SHEET.CUSTOMERS);
    const rowNum = findRowNumberByColumn(sheet, COL.CUSTOMERS.ID, data.id);
    if (rowNum === -1) throwNotFound('Tamu');

    // Block delete if the customer has any transaction (historical or future).
    // Deleting would orphan booking records.
    const txnsForCustomer = getAllRows(getSheet(SHEET.TRANSACTIONS))
      .filter(r => String(r[COL.TRANSACTIONS.CUSTOMER_ID]) === String(data.id));
    if (txnsForCustomer.length > 0) {
      throwConflict(
        'Tamu tidak dapat dihapus karena memiliki riwayat transaksi (' +
        txnsForCustomer.length + ' pemesanan).',
      );
    }

    deleteRow(sheet, rowNum);
    Logger.log('customers.delete: id=' + data.id + ' by ' + user.email);
    return { deleted: true, id: data.id };
  } finally {
    lock.releaseLock();
  }
}

// ── Row ↔ Object converters ───────────────────────────────────────────────────

function _customerToRow(c) {
  return [
    c.id,
    c.nik,
    c.name,
    c.phone,
    c.address,
    c.birth_date,
    c.ktp_url,
    c.created_at,
    c.updated_at,
  ];
}

function _rowToCustomer(row) {
  return {
    id:         String(row[COL.CUSTOMERS.ID]),
    nik:        String(row[COL.CUSTOMERS.NIK]),
    name:       String(row[COL.CUSTOMERS.NAME]),
    phone:      String(row[COL.CUSTOMERS.PHONE]      || ''),
    address:    String(row[COL.CUSTOMERS.ADDRESS]    || ''),
    birth_date: String(row[COL.CUSTOMERS.BIRTH_DATE] || ''),
    ktp_url:    String(row[COL.CUSTOMERS.KTP_URL]    || ''),
    created_at: toISOString(row[COL.CUSTOMERS.CREATED_AT]),
    updated_at: toISOString(row[COL.CUSTOMERS.UPDATED_AT]),
  };
}

// Error helpers are in utils.js: throwValidation, throwNotFound, throwLock, throwConflict
