import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// ── Payment method ────────────────────────────────────────────────────────────

enum PaymentMethod { cash, transfer, qris }

extension PaymentMethodX on PaymentMethod {
  String get value => name;

  String get label => switch (this) {
        PaymentMethod.cash     => 'Tunai',
        PaymentMethod.transfer => 'Transfer Bank',
        PaymentMethod.qris     => 'QRIS',
      };

  IconLabel get iconLabel => switch (this) {
        PaymentMethod.cash     => const IconLabel(0xe25a, 'Tunai'),
        PaymentMethod.transfer => const IconLabel(0xe004, 'Transfer'),
        PaymentMethod.qris     => const IconLabel(0xef68, 'QRIS'),
      };

  /// Constant [IconData] — safe for tree-shaking in release builds.
  IconData get icon => switch (this) {
        PaymentMethod.cash     => Icons.payments,
        PaymentMethod.transfer => Icons.account_balance,
        PaymentMethod.qris     => Icons.qr_code_scanner,
      };

  static PaymentMethod fromString(String? s) => switch (s) {
        'transfer' => PaymentMethod.transfer,
        'qris'     => PaymentMethod.qris,
        _          => PaymentMethod.cash,
      };
}

/// Tiny helper to carry icon codepoint + label together.
class IconLabel {
  const IconLabel(this.codePoint, this.label);
  final int codePoint;
  final String label;
}

// ── Model ─────────────────────────────────────────────────────────────────────

/// Mirrors the `payments` sheet schema defined in project.me.
class PaymentModel {
  const PaymentModel({
    required this.id,
    required this.transactionId,
    required this.amount,
    required this.method,
    required this.paidAt,
    required this.notes,
    required this.createdBy,
    required this.createdAt,
  });

  final String id;
  final String transactionId;
  final double amount;
  final PaymentMethod method;
  final DateTime paidAt;
  final String notes;
  final String createdBy;
  final DateTime createdAt;

  static final _idr = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );
  static final _dtFmt = DateFormat('d MMM yyyy, HH:mm', 'id_ID');

  String get formattedAmount => _idr.format(amount);
  String get formattedPaidAt => _dtFmt.format(paidAt);

  factory PaymentModel.fromJson(Map<String, dynamic> json) {
    return PaymentModel(
      id:            json['id'] as String,
      transactionId: json['transaction_id'] as String,
      amount:        (json['amount'] as num).toDouble(),
      method:        PaymentMethodX.fromString(json['method'] as String?),
      paidAt:        DateTime.tryParse((json['paid_at'] as String?) ?? '') ?? DateTime.now(),
      notes:         (json['notes'] as String?) ?? '',
      createdBy:     (json['created_by'] as String?) ?? '',
      createdAt:     DateTime.tryParse((json['created_at'] as String?) ?? '') ?? DateTime.now(),
    );
  }
}
