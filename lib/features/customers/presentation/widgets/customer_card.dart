import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../domain/customer_model.dart';
import '../providers/customers_provider.dart';

class CustomerCard extends ConsumerWidget {
  const CustomerCard({super.key, required this.customer, this.onTap});

  final CustomerModel customer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // Avatar circle with first letter
              CircleAvatar(
                radius: 22,
                backgroundColor: scheme.primaryContainer,
                child: Text(
                  customer.name.isNotEmpty
                      ? customer.name[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Name + masked NIK
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      customer.maskedNik,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                    ),
                    if (customer.phone.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.phone_outlined,
                              size: 12, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            customer.phone,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Popup menu
              _CardMenu(customer: customer),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Popup menu ────────────────────────────────────────────────────────────────

class _CardMenu extends ConsumerWidget {
  const _CardMenu({required this.customer});

  final CustomerModel customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return PopupMenuButton<_MenuAction>(
      icon: Icon(Icons.more_vert, color: scheme.onSurfaceVariant),
      onSelected: (action) => _onAction(context, ref, action),
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: _MenuAction.edit,
          child: Row(children: [
            Icon(Icons.edit_outlined, size: 18),
            SizedBox(width: 12),
            Text('Edit'),
          ]),
        ),
        PopupMenuItem(
          value: _MenuAction.delete,
          child: Row(children: [
            Icon(Icons.delete_outline,
                size: 18, color: scheme.error),
            const SizedBox(width: 12),
            Text('Hapus', style: TextStyle(color: scheme.error)),
          ]),
        ),
      ],
    );
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    _MenuAction action,
  ) async {
    switch (action) {
      case _MenuAction.edit:
        if (context.mounted) {
          context.go(
            '${AppRoutes.customers}/${customer.id}',
            extra: customer,
          );
        }
      case _MenuAction.delete:
        if (context.mounted) await _confirmDelete(context, ref);
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Tamu'),
        content: Text('Hapus "${customer.name}" dari daftar tamu?'),
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
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(customersProvider.notifier).delete(customer.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tamu berhasil dihapus'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }
}

enum _MenuAction { edit, delete }
