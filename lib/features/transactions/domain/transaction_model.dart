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
  const AvailabilityResult({required this.available, this.conflictCode});

  final bool available;

  /// Booking code of the conflicting reservation (when [available] == false).
  final String? conflictCode;
}

// ── Model ─────────────────────────────────────────────────────────────────────

/// Mirrors the `transactions` sheet schema defined in project.me.
///
/// [customerName] and [roomName] are denormalized fields returned by
/// `transactions.list` and `transactions.create` for display purposes.
class TransactionModel {
  const TransactionModel({
    required this.id,
    required this.bookingCode,
    required this.customerId,
    required this.roomId,
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
  });

  final String id;
  final String bookingCode;
  final String customerId;
  final String roomId;
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
  final String roomName;

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

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id:                json['id'] as String,
      bookingCode:       json['booking_code'] as String,
      customerId:        json['customer_id'] as String,
      roomId:            json['room_id'] as String,
      checkIn:           _parseDate(json['check_in']),
      checkOut:          _parseDate(json['check_out']),
      nights:            (json['nights'] as num).toInt(),
      totalPrice:        (json['total_price'] as num).toDouble(),
      dpAmount:          (json['dp_amount'] as num?)?.toDouble() ?? 0.0,
      paymentStatus:     PaymentStatusX.fromString(json['payment_status'] as String?),
      calendarEventId:   (json['calendar_event_id'] as String?) ?? '',
      notes:             (json['notes'] as String?) ?? '',
      createdBy:         (json['created_by'] as String?) ?? '',
      createdAt:         DateTime.tryParse((json['created_at'] as String?) ?? '') ?? DateTime.now(),
      updatedAt:         DateTime.tryParse((json['updated_at'] as String?) ?? '') ?? DateTime.now(),
      customerName:      (json['customer_name'] as String?) ?? '',
      roomName:          (json['room_name'] as String?) ?? '',
    );
  }

  /// Parse a 'YYYY-MM-DD' or full ISO string into a local [DateTime].
  static DateTime _parseDate(dynamic raw) {
    final s = (raw as String?) ?? '';
    // Take only the date portion to avoid UTC-to-local timezone drift.
    final datePart = s.length >= 10 ? s.substring(0, 10) : s;
    return DateTime.tryParse(datePart) ?? DateTime.now();
  }

  TransactionModel copyWith({PaymentStatus? paymentStatus, double? dpAmount}) {
    return TransactionModel(
      id: id, bookingCode: bookingCode, customerId: customerId, roomId: roomId,
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
