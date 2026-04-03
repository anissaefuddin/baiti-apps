import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exception.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/room_repository.dart';
import '../../domain/room_model.dart';

// ── Rooms list provider ───────────────────────────────────────────────────────

/// Manages the rooms list and all mutating operations.
///
/// After each successful mutation the local list is updated immediately
/// (optimistic patch) so the UI responds without waiting for a re-fetch.
///
/// If the server returns UNAUTHORIZED, delegates to [AuthNotifier.handleSessionExpiry]
/// so the user is redirected to the login screen automatically.
class RoomsNotifier extends AsyncNotifier<List<RoomModel>> {
  @override
  Future<List<RoomModel>> build() =>
      ref.read(roomRepositoryProvider).list();

  // ── Read ────────────────────────────────────────────────────────────────

  /// Force a full reload from the server (used by pull-to-refresh).
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(roomRepositoryProvider).list(),
    );
  }

  // ── Write ───────────────────────────────────────────────────────────────

  /// Create a new room, append it to the local list on success.
  /// Returns the created [RoomModel].
  /// Throws on any error so the form screen can show the message.
  Future<RoomModel> create({
    required String name,
    required double pricePerNight,
    required int capacity,
    required String description,
  }) async {
    final room = await _guard(() => ref.read(roomRepositoryProvider).create(
          name: name,
          pricePerNight: pricePerNight,
          capacity: capacity,
          description: description,
        ));

    state.whenData((rooms) {
      state = AsyncValue.data([...rooms, room]);
    });
    return room;
  }

  /// Update an existing room; patches the local list on success.
  /// Returns the updated [RoomModel].
  Future<RoomModel> edit({
    required String id,
    String? name,
    double? pricePerNight,
    int? capacity,
    String? description,
    RoomStatus? status,
  }) async {
    final updated = await _guard(() => ref.read(roomRepositoryProvider).update(
            id: id,
            name: name,
            pricePerNight: pricePerNight,
            capacity: capacity,
            description: description,
            status: status,
          ));

    state.whenData((rooms) {
      state = AsyncValue.data(
        rooms.map((r) => r.id == id ? updated : r).toList(),
      );
    });
    return updated;
  }

  /// Toggle room status between available ↔ unavailable.
  Future<void> toggleStatus(RoomModel room) async {
    final newStatus =
        room.isAvailable ? RoomStatus.unavailable : RoomStatus.available;
    await edit(id: room.id, status: newStatus);
  }

  /// Delete a room; removes it from the local list on success.
  Future<void> delete(String id) async {
    await _guard(() => ref.read(roomRepositoryProvider).delete(id));

    state.whenData((rooms) {
      state = AsyncValue.data(rooms.where((r) => r.id != id).toList());
    });
  }

  // ── Session expiry guard ─────────────────────────────────────────────────

  /// Runs [fn], intercepting UNAUTHORIZED errors and triggering session expiry
  /// handling so the router redirects the user to login automatically.
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

final roomsProvider =
    AsyncNotifierProvider<RoomsNotifier, List<RoomModel>>(RoomsNotifier.new);
