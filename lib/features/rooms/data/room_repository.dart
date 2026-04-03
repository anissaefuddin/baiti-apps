import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/api_service.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/room_model.dart';

final roomRepositoryProvider = Provider<RoomRepository>((ref) {
  return RoomRepository(
    api: ref.watch(apiServiceProvider),
    auth: ref.watch(authRepositoryProvider),
  );
});

/// Data layer for room CRUD operations.
/// Each public method obtains a fresh Google ID token before the API call —
/// token refresh is handled transparently by [AuthRepository.getFreshToken].
class RoomRepository {
  RoomRepository({required ApiService api, required AuthRepository auth})
      : _api = api,
        _auth = auth;

  final ApiService _api;
  final AuthRepository _auth;

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<String> _freshToken() async {
    final token = await _auth.getFreshToken();
    if (token == null) throw const ApiException('Sesi berakhir. Silakan masuk kembali.', errorCode: 'UNAUTHORIZED');
    return token;
  }

  List<RoomModel> _parseList(Map<String, dynamic> response) {
    final data = response['data'];
    if (data == null) return [];
    return (data as List)
        .map((e) => RoomModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  RoomModel _parseSingle(Map<String, dynamic> response) {
    return RoomModel.fromJson(response['data'] as Map<String, dynamic>);
  }

  // ── CRUD ─────────────────────────────────────────────────────────────────

  Future<List<RoomModel>> list() async {
    final response = await _api.post(
      action: 'rooms.list',
      token: await _freshToken(),
    );
    return _parseList(response);
  }

  Future<RoomModel> create({
    required String name,
    required double pricePerNight,
    required int capacity,
    required String description,
  }) async {
    final response = await _api.post(
      action: 'rooms.create',
      token: await _freshToken(),
      data: {
        'name': name,
        'price_per_night': pricePerNight,
        'capacity': capacity,
        'description': description,
      },
    );
    return _parseSingle(response);
  }

  Future<RoomModel> update({
    required String id,
    String? name,
    double? pricePerNight,
    int? capacity,
    String? description,
    RoomStatus? status,
  }) async {
    final response = await _api.post(
      action: 'rooms.update',
      token: await _freshToken(),
      data: {
        'id': id,
        if (name != null) 'name': name,
        if (pricePerNight != null) 'price_per_night': pricePerNight,
        if (capacity != null) 'capacity': capacity,
        if (description != null) 'description': description,
        if (status != null) 'status': status.value,
      },
    );
    return _parseSingle(response);
  }

  Future<void> delete(String id) async {
    await _api.post(
      action: 'rooms.delete',
      token: await _freshToken(),
      data: {'id': id},
    );
  }
}
