import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exception.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/transaction_repository.dart';
import '../../domain/transaction_model.dart';

/// Manages the transaction list.
/// Transactions are sorted newest-first.
///
/// Follows the same _guard pattern as rooms/customers providers.
class TransactionsNotifier extends AsyncNotifier<List<TransactionModel>> {
  @override
  Future<List<TransactionModel>> build() async {
    final list = await ref.read(transactionRepositoryProvider).list();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final list = await ref.read(transactionRepositoryProvider).list();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Future<AvailabilityResult> checkAvailability({
    required List<String> roomIds,
    required DateTime checkIn,
    required DateTime checkOut,
  }) =>
      _guard(
        () => ref.read(transactionRepositoryProvider).checkAvailability(
              roomIds:  roomIds,
              checkIn:  checkIn,
              checkOut: checkOut,
            ),
      );

  Future<TransactionModel> create({
    required String customerId,
    required List<String> roomIds,
    required DateTime checkIn,
    required DateTime checkOut,
    String notes = '',
  }) async {
    final txn = await _guard(
      () => ref.read(transactionRepositoryProvider).create(
            customerId: customerId,
            roomIds:    roomIds,
            checkIn:    checkIn,
            checkOut:   checkOut,
            notes:      notes,
          ),
    );

    // Prepend to local list (newest first).
    state.whenData((list) {
      state = AsyncValue.data([txn, ...list]);
    });
    return txn;
  }

  /// Patch dp_amount and payment_status for a single transaction in the local
  /// list. Called by [PaymentsNotifier.create] after a successful payment.
  void applyPaymentUpdate({
    required String id,
    required double dpAmount,
    required PaymentStatus paymentStatus,
  }) {
    state.whenData((list) {
      state = AsyncValue.data(
        list.map((t) => t.id == id
            ? t.copyWith(dpAmount: dpAmount, paymentStatus: paymentStatus)
            : t).toList(),
      );
    });
  }

  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await ref.read(authProvider.notifier).handleSessionExpiry();
      }
      rethrow;
    }
  }
}

final transactionsProvider =
    AsyncNotifierProvider<TransactionsNotifier, List<TransactionModel>>(
  TransactionsNotifier.new,
);
