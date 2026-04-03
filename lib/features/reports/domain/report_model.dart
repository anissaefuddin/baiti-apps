import 'package:intl/intl.dart';

import '../../transactions/domain/transaction_model.dart';

// ── Period enum ───────────────────────────────────────────────────────────────

enum ReportPeriod { daily, weekly, monthly, custom }

extension ReportPeriodX on ReportPeriod {
  String get value => name;

  String get label => switch (this) {
        ReportPeriod.daily   => 'Hari Ini',
        ReportPeriod.weekly  => 'Minggu Ini',
        ReportPeriod.monthly => 'Bulan Ini',
        ReportPeriod.custom  => 'Kustom',
      };
}

// ── Status breakdown ──────────────────────────────────────────────────────────

class StatusBreakdown {
  const StatusBreakdown({
    required this.unpaid,
    required this.partial,
    required this.paid,
  });

  final int unpaid;
  final int partial;
  final int paid;

  int get total => unpaid + partial + paid;

  factory StatusBreakdown.fromJson(Map<String, dynamic> json) {
    return StatusBreakdown(
      unpaid:  (json['unpaid']  as num?)?.toInt() ?? 0,
      partial: (json['partial'] as num?)?.toInt() ?? 0,
      paid:    (json['paid']    as num?)?.toInt() ?? 0,
    );
  }
}

// ── Summary transaction (for lists inside the report) ────────────────────────

class SummaryTransaction {
  const SummaryTransaction({
    required this.id,
    required this.bookingCode,
    required this.customerName,
    required this.roomName,
    required this.checkIn,
    required this.checkOut,
    required this.nights,
    required this.totalPrice,
    required this.dpAmount,
    required this.paymentStatus,
  });

  final String id;
  final String bookingCode;
  final String customerName;
  final String roomName;
  final DateTime checkIn;
  final DateTime checkOut;
  final int nights;
  final double totalPrice;
  final double dpAmount;
  final PaymentStatus paymentStatus;

  double get remaining => totalPrice - dpAmount;

  static final _idr     = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  static final _dateFmt = DateFormat('d MMM yyyy', 'id_ID');

  String get formattedTotal     => _idr.format(totalPrice);
  String get formattedRemaining => _idr.format(remaining);
  String get formattedCheckIn   => _dateFmt.format(checkIn);
  String get formattedCheckOut  => _dateFmt.format(checkOut);

  factory SummaryTransaction.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic raw) {
      final s = (raw as String?) ?? '';
      return DateTime.tryParse(s.length >= 10 ? s.substring(0, 10) : s) ?? DateTime.now();
    }

    return SummaryTransaction(
      id:            json['id'] as String,
      bookingCode:   json['booking_code'] as String,
      customerName:  (json['customer_name'] as String?) ?? '',
      roomName:      (json['room_name'] as String?) ?? '',
      checkIn:       parseDate(json['check_in']),
      checkOut:      parseDate(json['check_out']),
      nights:        (json['nights'] as num).toInt(),
      totalPrice:    (json['total_price'] as num).toDouble(),
      dpAmount:      (json['dp_amount'] as num?)?.toDouble() ?? 0,
      paymentStatus: PaymentStatusX.fromString(json['payment_status'] as String?),
    );
  }
}

// ── Main report model ─────────────────────────────────────────────────────────

class ReportSummary {
  const ReportSummary({
    required this.periodFrom,
    required this.periodTo,
    required this.totalBookings,
    required this.totalIncome,
    required this.collectedIncome,
    required this.pendingIncome,
    required this.statusBreakdown,
    required this.upcomingBookings,
    required this.unpaidTransactions,
  });

  final DateTime periodFrom;
  final DateTime periodTo;
  final int totalBookings;
  final double totalIncome;
  final double collectedIncome;
  final double pendingIncome;
  final StatusBreakdown statusBreakdown;
  final List<SummaryTransaction> upcomingBookings;
  final List<SummaryTransaction> unpaidTransactions;

  static final _idr     = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  static final _dateFmt = DateFormat('d MMM yyyy', 'id_ID');

  String get formattedTotal     => _idr.format(totalIncome);
  String get formattedCollected => _idr.format(collectedIncome);
  String get formattedPending   => _idr.format(pendingIncome);
  String get formattedPeriodFrom => _dateFmt.format(periodFrom);
  String get formattedPeriodTo   => _dateFmt.format(periodTo);

  factory ReportSummary.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(String? s) {
      final str = s ?? '';
      return DateTime.tryParse(str.length >= 10 ? str.substring(0, 10) : str) ?? DateTime.now();
    }

    final period = json['period'] as Map<String, dynamic>;

    return ReportSummary(
      periodFrom:       parseDate(period['from'] as String?),
      periodTo:         parseDate(period['to']   as String?),
      totalBookings:    (json['total_bookings']   as num).toInt(),
      totalIncome:      (json['total_income']     as num).toDouble(),
      collectedIncome:  (json['collected_income'] as num).toDouble(),
      pendingIncome:    (json['pending_income']   as num).toDouble(),
      statusBreakdown:  StatusBreakdown.fromJson(
                          json['status_breakdown'] as Map<String, dynamic>,
                        ),
      upcomingBookings: (json['upcoming_bookings'] as List)
                          .map((e) => SummaryTransaction.fromJson(e as Map<String, dynamic>))
                          .toList(),
      unpaidTransactions: (json['unpaid_transactions'] as List)
                          .map((e) => SummaryTransaction.fromJson(e as Map<String, dynamic>))
                          .toList(),
    );
  }
}

// ── Export result ─────────────────────────────────────────────────────────────

class ExportResult {
  const ExportResult({
    required this.filename,
    required this.csv,
    required this.rowCount,
    required this.periodFrom,
    required this.periodTo,
  });

  final String filename;
  final String csv;
  final int rowCount;
  final DateTime periodFrom;
  final DateTime periodTo;

  factory ExportResult.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(String? s) =>
        DateTime.tryParse(s ?? '') ?? DateTime.now();
    final period = json['period'] as Map<String, dynamic>;
    return ExportResult(
      filename:   json['filename'] as String,
      csv:        json['csv'] as String,
      rowCount:   (json['row_count'] as num).toInt(),
      periodFrom: parseDate(period['from'] as String?),
      periodTo:   parseDate(period['to']   as String?),
    );
  }
}
