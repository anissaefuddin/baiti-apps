import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exception.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../transactions/presentation/providers/transactions_provider.dart';
import '../../data/payment_repository.dart';
import '../../domain/payment_model.dart';

/// Payments are scoped per transaction.
/// Use `ref.watch(paymentsProvider(transactionId))` in the detail screen.
class PaymentsNotifier
    extends FamilyAsyncNotifier<List<PaymentModel>, String> {
  @override
  Future<List<PaymentModel>> build(String transactionId) =>
      ref.read(paymentRepositoryProvider).listByTransaction(transactionId);

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(paymentRepositoryProvider).listByTransaction(arg),
    );
  }

  /// Add a payment. On success:
  ///   • Prepends the new [PaymentModel] to the local list.
  ///   • Patches `transactionsProvider` so the list + detail reflect the new
  ///     dp_amount and payment_status without a full re-fetch.
  Future<PaymentModel> create({
    required double amount,
    required PaymentMethod method,
    String notes = '',
  }) async {
    final result = await _guard(
      () => ref.read(paymentRepositoryProvider).create(
            transactionId: arg,
            amount:        amount,
            method:        method,
            notes:         notes,
          ),
    );

    // Prepend to local payments list.
    state.whenData((list) {
      state = AsyncValue.data([result.payment, ...list]);
    });

    // Patch the transaction in the global transactions list.
    final update = result.transactionUpdate;
    ref.read(transactionsProvider.notifier).applyPaymentUpdate(
      id:            update.id,
      dpAmount:      update.dpAmount,
      paymentStatus: update.paymentStatus,
    );

    return result.payment;
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

final paymentsProvider = AsyncNotifierProviderFamily<
    PaymentsNotifier, List<PaymentModel>, String>(
  PaymentsNotifier.new,
);
