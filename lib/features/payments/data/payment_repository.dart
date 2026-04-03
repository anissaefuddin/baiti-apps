import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/api_service.dart';
import '../../auth/data/auth_repository.dart';
import '../../transactions/domain/transaction_model.dart';
import '../domain/payment_model.dart';

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  return PaymentRepository(
    api:  ref.watch(apiServiceProvider),
    auth: ref.watch(authRepositoryProvider),
  );
});

/// Data layer for payment operations.
class PaymentRepository {
  PaymentRepository({required ApiService api, required AuthRepository auth})
      : _api = api,
        _auth = auth;

  final ApiService _api;
  final AuthRepository _auth;

  Future<String> _freshToken() async {
    final token = await _auth.getFreshToken();
    if (token == null) {
      throw const ApiException(
        'Sesi berakhir. Silakan masuk kembali.',
        errorCode: 'UNAUTHORIZED',
      );
    }
    return token;
  }

  /// List all payments for [transactionId], newest first.
  Future<List<PaymentModel>> listByTransaction(String transactionId) async {
    final response = await _api.post(
      action: 'payments.listByTransaction',
      token:  await _freshToken(),
      data:   {'transaction_id': transactionId},
    );
    final data = response['data'];
    if (data == null) return [];
    return (data as List)
        .map((e) => PaymentModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Add a payment to a transaction.
  ///
  /// Returns the created [PaymentModel] and a [TransactionUpdate] containing
  /// the server-recomputed [dpAmount] and [paymentStatus].
  Future<PaymentCreateResult> create({
    required String transactionId,
    required double amount,
    required PaymentMethod method,
    String notes = '',
  }) async {
    final response = await _api.post(
      action: 'payments.create',
      token:  await _freshToken(),
      data: {
        'transaction_id': transactionId,
        'amount':         amount,
        'method':         method.value,
        'notes':          notes,
      },
    );
    final d = response['data'] as Map<String, dynamic>;
    return PaymentCreateResult(
      payment: PaymentModel.fromJson(d['payment'] as Map<String, dynamic>),
      transactionUpdate: TransactionUpdate.fromJson(
        d['transaction_update'] as Map<String, dynamic>,
      ),
    );
  }
}

// ── Result types ──────────────────────────────────────────────────────────────

/// Carries both the new payment and the updated transaction fields returned
/// by a single `payments.create` call.
class PaymentCreateResult {
  const PaymentCreateResult({
    required this.payment,
    required this.transactionUpdate,
  });
  final PaymentModel payment;
  final TransactionUpdate transactionUpdate;
}

/// The fields of a transaction that change after a payment is added.
class TransactionUpdate {
  const TransactionUpdate({
    required this.id,
    required this.dpAmount,
    required this.paymentStatus,
  });

  final String id;
  final double dpAmount;
  final PaymentStatus paymentStatus;

  factory TransactionUpdate.fromJson(Map<String, dynamic> json) {
    return TransactionUpdate(
      id:            json['id'] as String,
      dpAmount:      (json['dp_amount'] as num).toDouble(),
      paymentStatus: PaymentStatusX.fromString(json['payment_status'] as String?),
    );
  }
}
