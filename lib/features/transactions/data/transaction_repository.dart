import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/api_service.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/transaction_model.dart';

final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  return TransactionRepository(
    api: ref.watch(apiServiceProvider),
    auth: ref.watch(authRepositoryProvider),
  );
});

/// Data layer for booking/transaction operations.
class TransactionRepository {
  TransactionRepository({required ApiService api, required AuthRepository auth})
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

  Future<List<TransactionModel>> list() async {
    final response = await _api.post(
      action: 'transactions.list',
      token: await _freshToken(),
    );
    final data = response['data'];
    if (data == null) return [];
    return (data as List)
        .map((e) => TransactionModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Check room availability for a date range without creating a booking.
  /// Returns immediately (no lock acquired).
  Future<AvailabilityResult> checkAvailability({
    required String roomId,
    required DateTime checkIn,
    required DateTime checkOut,
    String? excludeId,
  }) async {
    final response = await _api.post(
      action: 'transactions.checkAvailability',
      token: await _freshToken(),
      data: {
        'room_id':   roomId,
        'check_in':  _fmtDate(checkIn),
        'check_out': _fmtDate(checkOut),
        if (excludeId != null) 'exclude_id': excludeId,
      },
    );
    final d = response['data'] as Map<String, dynamic>;
    final available = d['available'] as bool? ?? false;
    final conflict  = d['conflict'] as Map<String, dynamic>?;
    return AvailabilityResult(
      available:    available,
      conflictCode: conflict?['booking_code'] as String?,
    );
  }

  /// Create a new booking. Returns the created [TransactionModel] (with
  /// denormalized customer_name and room_name).
  Future<TransactionModel> create({
    required String customerId,
    required String roomId,
    required DateTime checkIn,
    required DateTime checkOut,
    String notes = '',
  }) async {
    final response = await _api.post(
      action: 'transactions.create',
      token: await _freshToken(),
      data: {
        'customer_id': customerId,
        'room_id':     roomId,
        'check_in':    _fmtDate(checkIn),
        'check_out':   _fmtDate(checkOut),
        'notes':       notes,
      },
    );
    return TransactionModel.fromJson(response['data'] as Map<String, dynamic>);
  }

  /// Format [DateTime] as 'YYYY-MM-DD' (date-only, no time component).
  static String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
