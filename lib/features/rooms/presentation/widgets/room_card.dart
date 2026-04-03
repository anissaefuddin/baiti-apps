import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../domain/room_model.dart';
import '../providers/rooms_provider.dart';

/// Card displayed in the room list. Tapping navigates to the edit form.
/// Long-pressing opens a context menu with toggle status and delete actions.
class RoomCard extends ConsumerWidget {
  const RoomCard({super.key, required this.room});

  final RoomModel room;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go(
          '${AppRoutes.rooms}/${room.id}',
          extra: room,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // ── Status indicator bar ───────────────────────────────────
              Container(
                width: 4,
                height: 52,
                decoration: BoxDecoration(
                  color: room.isAvailable
                      ? const Color(0xFF2E7D32)
                      : scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 14),

              // ── Room info ──────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            room.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusBadge(status: room.status),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.payments_outlined,
                            size: 14, color: scheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          room.formattedPrice,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                        const SizedBox(width: 16),
                        Icon(Icons.person_outline,
                            size: 14, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          '${room.capacity} tamu',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                    if (room.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        room.description,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              // ── Actions menu ───────────────────────────────────────────
              _CardMenu(room: room),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Status badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final RoomStatus status;

  @override
  Widget build(BuildContext context) {
    final isAvailable = status == RoomStatus.available;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isAvailable
            ? const Color(0xFFE8F5E9)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isAvailable
              ? const Color(0xFF2E7D32)
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// ── Card context menu ─────────────────────────────────────────────────────────

class _CardMenu extends ConsumerWidget {
  const _CardMenu({required this.room});

  final RoomModel room;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_MenuAction>(
      icon: Icon(Icons.more_vert,
          color: Theme.of(context).colorScheme.onSurfaceVariant),
      onSelected: (action) => _handleAction(context, ref, action),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _MenuAction.edit,
          child: const Row(
            children: [
              Icon(Icons.edit_outlined, size: 18),
              SizedBox(width: 12),
              Text('Edit'),
            ],
          ),
        ),
        PopupMenuItem(
          value: _MenuAction.toggleStatus,
          child: Row(
            children: [
              Icon(
                room.isAvailable
                    ? Icons.do_not_disturb_on_outlined
                    : Icons.check_circle_outline,
                size: 18,
              ),
              const SizedBox(width: 12),
              Text(room.isAvailable ? 'Nonaktifkan' : 'Aktifkan'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _MenuAction.delete,
          child: Row(
            children: [
              Icon(Icons.delete_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 12),
              Text(
                'Hapus',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    _MenuAction action,
  ) async {
    switch (action) {
      case _MenuAction.edit:
        context.go('${AppRoutes.rooms}/${room.id}', extra: room);

      case _MenuAction.toggleStatus:
        try {
          await ref.read(roomsProvider.notifier).toggleStatus(room);
        } catch (e) {
          if (context.mounted) _showError(context, e.toString());
        }

      case _MenuAction.delete:
        final confirmed = await _confirmDelete(context);
        if (confirmed && context.mounted) {
          try {
            await ref.read(roomsProvider.notifier).delete(room.id);
          } catch (e) {
            if (context.mounted) _showError(context, e.toString());
          }
        }
    }
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Hapus Kamar'),
            content: Text(
              'Yakin ingin menghapus "${room.name}"? Tindakan ini tidak dapat dibatalkan.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Hapus'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }
}

enum _MenuAction { edit, toggleStatus, delete }
