// ── Room handlers ─────────────────────────────────────────────────────────────
//
// All handlers receive the authenticated `user` object from requireAuth()
// in main.js. Write operations acquire a script lock before touching the sheet.

/**
 * Return all rooms ordered as stored.
 * @param {Object} user - Authenticated user from requireAuth().
 */
function handleRoomsList(user) {
  const rooms = getAllAs(getSheet(SHEET.ROOMS), _rowToRoom);
  Logger.log('rooms.list: ' + rooms.length + ' rooms returned to ' + user.email);
  return rooms;
}

/**
 * Create a new room. New rooms always start with status = 'available'.
 * @param {Object} user
 * @param {{ name, price_per_night, capacity, description? }} data
 */
function handleRoomsCreate(user, data) {
  requireFields(data, ['name', 'price_per_night', 'capacity']);

  const price = Number(data.price_per_night);
  const capacity = Number(data.capacity);

  if (!data.name || String(data.name).trim() === '') {
    throwValidation('Nama kamar tidak boleh kosong');
  }
  if (isNaN(price) || price <= 0) {
    throwValidation('Harga per malam harus lebih dari 0');
  }
  if (isNaN(capacity) || capacity < 1 || !Number.isInteger(capacity)) {
    throwValidation('Kapasitas minimal 1 orang');
  }

  const lock = LockService.getScriptLock();
  if (!lock.tryLock(LOCK_TIMEOUT_MS)) throwLock();

  try {
    const room = {
      id:              generateUUID(),
      name:            String(data.name).trim(),
      price_per_night: price,
      capacity:        capacity,
      description:     String(data.description || '').trim(),
      status:          ROOM_STATUS.AVAILABLE,
      created_at:      now(),
      updated_at:      now(),
    };
    appendRow(getSheet(SHEET.ROOMS), _roomToRow(room));
    Logger.log('rooms.create: "' + room.name + '" by ' + user.email);
    return room;
  } finally {
    lock.releaseLock();
  }
}

/**
 * Update one or more fields of an existing room.
 * Only fields present in `data` are updated; omitted fields retain their values.
 * @param {Object} user
 * @param {{ id, name?, price_per_night?, capacity?, description?, status? }} data
 */
function handleRoomsUpdate(user, data) {
  requireFields(data, ['id']);

  // Validate any provided numeric fields upfront (before acquiring the lock).
  if (data.price_per_night !== undefined) {
    const price = Number(data.price_per_night);
    if (isNaN(price) || price <= 0) throwValidation('Harga per malam harus lebih dari 0');
  }
  if (data.capacity !== undefined) {
    const capacity = Number(data.capacity);
    if (isNaN(capacity) || capacity < 1) throwValidation('Kapasitas minimal 1 orang');
  }
  if (data.status !== undefined &&
      data.status !== ROOM_STATUS.AVAILABLE &&
      data.status !== ROOM_STATUS.UNAVAILABLE) {
    throwValidation('Status tidak valid: gunakan "available" atau "unavailable"');
  }

  const lock = LockService.getScriptLock();
  if (!lock.tryLock(LOCK_TIMEOUT_MS)) throwLock();

  try {
    const sheet = getSheet(SHEET.ROOMS);
    const rowNum = findRowNumberByColumn(sheet, COL.ROOMS.ID, data.id);
    if (rowNum === -1) throwNotFound('Kamar');

    const existing = _rowToRoom(findRowByColumn(sheet, COL.ROOMS.ID, data.id));

    const updated = {
      id:              existing.id,
      name:            data.name !== undefined ? String(data.name).trim() : existing.name,
      price_per_night: data.price_per_night !== undefined
                         ? Number(data.price_per_night) : existing.price_per_night,
      capacity:        data.capacity !== undefined
                         ? Number(data.capacity) : existing.capacity,
      description:     data.description !== undefined
                         ? String(data.description).trim() : existing.description,
      status:          data.status !== undefined ? data.status : existing.status,
      created_at:      existing.created_at,
      updated_at:      now(),
    };

    updateRow(sheet, rowNum, _roomToRow(updated));
    Logger.log('rooms.update: "' + updated.name + '" by ' + user.email);
    return updated;
  } finally {
    lock.releaseLock();
  }
}

/**
 * Delete a room by ID.
 * Phase 3 will add a guard: blocked if the room has future bookings.
 * @param {Object} user
 * @param {{ id }} data
 */
function handleRoomsDelete(user, data) {
  requireFields(data, ['id']);

  const lock = LockService.getScriptLock();
  if (!lock.tryLock(LOCK_TIMEOUT_MS)) throwLock();

  try {
    const sheet = getSheet(SHEET.ROOMS);
    const rowNum = findRowNumberByColumn(sheet, COL.ROOMS.ID, data.id);
    if (rowNum === -1) throwNotFound('Kamar');

    // Block delete if the room has any transaction (past or future).
    // Deleting a room with history would orphan transaction records.
    const txnsForRoom = getAllRows(getSheet(SHEET.TRANSACTIONS))
      .filter(r => String(r[COL.TRANSACTIONS.ROOM_ID]) === String(data.id));
    if (txnsForRoom.length > 0) {
      throwConflict(
        'Kamar tidak dapat dihapus karena memiliki riwayat pemesanan. ' +
        'Nonaktifkan kamar jika tidak ingin menerima pemesanan baru.',
      );
    }

    deleteRow(sheet, rowNum);
    Logger.log('rooms.delete: id=' + data.id + ' by ' + user.email);
    return { deleted: true, id: data.id };
  } finally {
    lock.releaseLock();
  }
}

// ── Row ↔ Object converters ───────────────────────────────────────────────────

function _roomToRow(room) {
  return [
    room.id,
    room.name,
    room.price_per_night,
    room.capacity,
    room.description,
    room.status,
    room.created_at,
    room.updated_at,
  ];
}

function _rowToRoom(row) {
  return {
    id:              String(row[COL.ROOMS.ID]),
    name:            String(row[COL.ROOMS.NAME]),
    price_per_night: Number(row[COL.ROOMS.PRICE]),
    capacity:        Number(row[COL.ROOMS.CAPACITY]),
    description:     String(row[COL.ROOMS.DESCRIPTION] || ''),
    status:          String(row[COL.ROOMS.STATUS] || ROOM_STATUS.AVAILABLE),
    created_at:      toISOString(row[COL.ROOMS.CREATED_AT]),
    updated_at:      toISOString(row[COL.ROOMS.UPDATED_AT]),
  };
}

// Error helpers are in utils.js: throwValidation, throwNotFound, throwLock, throwConflict
