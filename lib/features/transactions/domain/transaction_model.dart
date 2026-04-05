import 'dart:convert';

import 'package:intl/intl.dart';

// ── Payment status ────────────────────────────────────────────────────────────

enum PaymentStatus { unpaid, partial, paid }

extension PaymentStatusX on PaymentStatus {
  String get value => name;

  String get label => switch (this) {
        PaymentStatus.unpaid  => 'Belum Bayar',
        PaymentStatus.partial => 'DP / Sebagian',
        PaymentStatus.paid    => 'Lunas',
      };

  static PaymentStatus fromString(String? s) => switch (s) {
        'partial' => PaymentStatus.partial,
        'paid'    => PaymentStatus.paid,
        _         => PaymentStatus.unpaid,
      };
}

// ── Availability result ───────────────────────────────────────────────────────

class AvailabilityResult {
  const AvailabilityResult({
    required this.available,
    this.conflictCode,
    this.conflictRoomNames,
    this.conflictCheckIn,
    this.conflictCheckOut,
  });

  final bool available;
  final String? conflictCode;
  final List<String>? conflictRoomNames;
  final DateTime? conflictCheckIn;
  final DateTime? conflictCheckOut;
}

// ── Model ─────────────────────────────────────────────────────────────────────

/// Mirrors the `transactions` sheet schema.
///
/// [customerName] and [roomName] are denormalized fields returned by
/// `transactions.list` and `transactions.create` for display purposes.
/// [roomName] is a comma-separated list when multiple rooms are booked.
class TransactionModel {
  const TransactionModel({
    required this.id,
    required this.bookingCode,
    required this.customerId,
    required this.roomIds,
    required this.checkIn,
    required this.checkOut,
    required this.nights,
    required this.totalPrice,
    required this.dpAmount,
    required this.paymentStatus,
    required this.calendarEventId,
    required this.notes,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    required this.customerName,
    required this.roomName,
    this.calendarError,
  });

  final String id;
  final String bookingCode;
  final String customerId;

  /// List of room IDs included in this booking.
  final List<String> roomIds;

  final DateTime checkIn;
  final DateTime checkOut;
  final int nights;
  final double totalPrice;
  final double dpAmount;
  final PaymentStatus paymentStatus;
  final String calendarEventId;
  final String notes;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  // ── Denormalized display fields ──────────────────────────────────────────
  final String customerName;

  /// Comma-separated room names (e.g. "Deluxe, Suite").
  final String roomName;

  /// Non-null when the booking was saved but the Google Calendar event
  /// creation failed. Transient — not persisted, only set from create response.
  final String? calendarError;

  // ── Computed helpers ─────────────────────────────────────────────────────

  bool get hasCalendarEvent => calendarEventId.isNotEmpty;
  double get remaining => totalPrice - dpAmount;

  static final _idr = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );
  static final _dateFmt = DateFormat('d MMM yyyy', 'id_ID');

  String get formattedTotal     => _idr.format(totalPrice);
  String get formattedDp        => _idr.format(dpAmount);
  String get formattedRemaining => _idr.format(remaining);
  String get formattedCheckIn   => _dateFmt.format(checkIn);
  String get formattedCheckOut  => _dateFmt.format(checkOut);

  factory TransactionModel.fromJson(Map<String, dynamic> json,
      {String? calendarError}) {
    return TransactionModel(
      id:              json['id'] as String,
      bookingCode:     json['booking_code'] as String,
      customerId:      json['customer_id'] as String,
      roomIds:         _parseRoomIds(json['room_ids']),
      checkIn:         _parseDate(json['check_in']),
      checkOut:        _parseDate(json['check_out']),
      nights:          (json['nights'] as num).toInt(),
      totalPrice:      (json['total_price'] as num).toDouble(),
      dpAmount:        (json['dp_amount'] as num?)?.toDouble() ?? 0.0,
      paymentStatus:   PaymentStatusX.fromString(json['payment_status'] as String?),
      calendarEventId: (json['calendar_event_id'] as String?) ?? '',
      notes:           (json['notes'] as String?) ?? '',
      createdBy:       (json['created_by'] as String?) ?? '',
      createdAt:       DateTime.tryParse((json['created_at'] as String?) ?? '') ?? DateTime.now(),
      updatedAt:       DateTime.tryParse((json['updated_at'] as String?) ?? '') ?? DateTime.now(),
      customerName:    (json['customer_name'] as String?) ?? '',
      roomName:        (json['room_name'] as String?) ?? '',
      calendarError:   calendarError,
    );
  }

  /// Parse room_ids from the server — handles:
  ///   • List<dynamic> (already decoded JSON array)
  ///   • String JSON array e.g. '["id1","id2"]'
  ///   • Legacy single String ID
  static List<String> _parseRoomIds(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    final s = raw.toString().trim();
    if (s.startsWith('[')) {
      try {
        final decoded = jsonDecode(s) as List;
        return decoded.map((e) => e.toString()).toList();
      } catch (_) {}
    }
    return s.isNotEmpty ? [s] : [];
  }

  /// Parse a 'YYYY-MM-DD' or full ISO string into a local [DateTime].
  static DateTime _parseDate(dynamic raw) {
    final s = (raw as String?) ?? '';
    final datePart = s.length >= 10 ? s.substring(0, 10) : s;
    return DateTime.tryParse(datePart) ?? DateTime.now();
  }

  TransactionModel copyWith({PaymentStatus? paymentStatus, double? dpAmount}) {
    return TransactionModel(
      id: id, bookingCode: bookingCode, customerId: customerId,
      roomIds: roomIds,
      checkIn: checkIn, checkOut: checkOut, nights: nights,
      totalPrice: totalPrice,
      dpAmount: dpAmount ?? this.dpAmount,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      calendarEventId: calendarEventId, notes: notes, createdBy: createdBy,
      createdAt: createdAt, updatedAt: updatedAt,
      customerName: customerName, roomName: roomName,
    );
  }
}
