// ── Spreadsheet ───────────────────────────────────────────────────────────────
// Replace with your Google Sheets document ID.
// Found in the URL: https://docs.google.com/spreadsheets/d/{SPREADSHEET_ID}/edit
const SPREADSHEET_ID = '1u_3B33D5JwUsdUbkAq0qRVwHki8pGaUxwQWYYkdxHjg';

// ── Sheet names (must match tab names exactly) ────────────────────────────────
const SHEET = {
  USERS:        'users',
  CUSTOMERS:    'customers',
  ROOMS:        'rooms',
  TRANSACTIONS: 'transactions',
  PAYMENTS:     'payments',
};

// ── Column indices (0-based) ──────────────────────────────────────────────────
// These must match the header order defined in setup.js.

const COL = {
  USERS: {
    ID:         0,
    GOOGLE_ID:  1,
    EMAIL:      2,
    NAME:       3,
    ROLE:       4,
    CREATED_AT: 5,
    UPDATED_AT: 6,
  },

  CUSTOMERS: {
    ID:         0,
    NIK:        1,
    NAME:       2,
    PHONE:      3,
    ADDRESS:    4,
    BIRTH_DATE: 5,
    KTP_URL:    6,
    CREATED_AT: 7,
    UPDATED_AT: 8,
  },

  ROOMS: {
    ID:          0,
    NAME:        1,
    PRICE:       2,
    CAPACITY:    3,
    DESCRIPTION: 4,
    STATUS:      5,
    CREATED_AT:  6,
    UPDATED_AT:  7,
  },

  TRANSACTIONS: {
    ID:                0,
    BOOKING_CODE:      1,
    CUSTOMER_ID:       2,
    ROOM_IDS:          3, // JSON array string, e.g. '["id1","id2"]'
    CHECK_IN:          4,
    CHECK_OUT:         5,
    NIGHTS:            6,
    TOTAL_PRICE:       7,
    DP_AMOUNT:         8,
    PAYMENT_STATUS:    9,
    CALENDAR_EVENT_ID: 10,
    NOTES:             11,
    CREATED_BY:        12,
    CREATED_AT:        13,
    UPDATED_AT:        14,
  },

  PAYMENTS: {
    ID:             0,
    TRANSACTION_ID: 1,
    AMOUNT:         2,
    METHOD:         3,
    PAID_AT:        4,
    NOTES:          5,
    CREATED_BY:     6,
    CREATED_AT:     7,
  },
};

// ── Domain constants ──────────────────────────────────────────────────────────

const ROLE = {
  ADMIN: 'admin',
  STAFF: 'staff',
};

const PAYMENT_STATUS = {
  UNPAID:  'unpaid',
  PARTIAL: 'partial',
  PAID:    'paid',
};

const ROOM_STATUS = {
  AVAILABLE:   'available',
  UNAVAILABLE: 'unavailable',
};

const PAYMENT_METHOD = {
  CASH:     'cash',
  TRANSFER: 'transfer',
  QRIS:     'qris',
};

// ── LockService ───────────────────────────────────────────────────────────────
// Max milliseconds to wait for a script lock before giving up.
const LOCK_TIMEOUT_MS = 10000;
