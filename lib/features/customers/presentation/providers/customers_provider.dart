import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exception.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/customer_repository.dart';
import '../../domain/customer_model.dart';

/// Manages the customer list and all mutating operations.
///
/// Follows the same pattern as [RoomsNotifier]:
/// - Optimistic local list updates after mutations (no re-fetch).
/// - UNAUTHORIZED errors delegate to [AuthNotifier.handleSessionExpiry].
class CustomersNotifier extends AsyncNotifier<List<CustomerModel>> {
  @override
  Future<List<CustomerModel>> build() =>
      ref.read(customerRepositoryProvider).list();

  // ── Read ──────────────────────────────────────────────────────────────────

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(customerRepositoryProvider).list(),
    );
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  Future<CustomerModel> create({
    required String nik,
    required String name,
    String phone = '',
    String address = '',
    String birthDate = '',
  }) async {
    final customer = await _guard(
      () => ref.read(customerRepositoryProvider).create(
            nik:       nik,
            name:      name,
            phone:     phone,
            address:   address,
            birthDate: birthDate,
          ),
    );
    state.whenData((list) {
      state = AsyncValue.data([...list, customer]);
    });
    return customer;
  }

  Future<CustomerModel> edit({
    required String id,
    String? name,
    String? phone,
    String? address,
    String? birthDate,
  }) async {
    final updated = await _guard(
      () => ref.read(customerRepositoryProvider).update(
            id:        id,
            name:      name,
            phone:     phone,
            address:   address,
            birthDate: birthDate,
          ),
    );
    state.whenData((list) {
      state = AsyncValue.data(
        list.map((c) => c.id == id ? updated : c).toList(),
      );
    });
    return updated;
  }

  Future<void> delete(String id) async {
    await _guard(() => ref.read(customerRepositoryProvider).delete(id));
    state.whenData((list) {
      state = AsyncValue.data(list.where((c) => c.id != id).toList());
    });
  }

  // ── Session expiry guard ──────────────────────────────────────────────────

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

final customersProvider =
    AsyncNotifierProvider<CustomersNotifier, List<CustomerModel>>(
  CustomersNotifier.new,
);
