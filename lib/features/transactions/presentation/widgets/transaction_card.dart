import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../domain/transaction_model.dart';

/// A card showing a single booking in the transaction list.
///
/// Tapping navigates to the detail screen (passing [TransactionModel] via extra).
class TransactionCard extends StatelessWidget {
  const TransactionCard({super.key, required this.transaction});

  final TransactionModel transaction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = transaction;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go(
          '${AppRoutes.transactions}/${t.id}',
          extra: t,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Status stripe ──────────────────────────────────────────
              Container(
                width: 4,
                height: 60,
                decoration: BoxDecoration(
                  color: _statusColor(t.paymentStatus, scheme),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 14),

              // ── Content ────────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: booking code + status badge
                    Row(
                      children: [
                        Text(
                          t.bookingCode,
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                fontFamily: 'monospace',
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        const Spacer(),
                        _StatusBadge(status: t.paymentStatus),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Customer + room
                    Text(
                      t.customerName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      t.roomName,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 6),

                    // Dates + total
                    Row(
                      children: [
                        Icon(Icons.calendar_today_outlined,
                            size: 13, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          '${t.formattedCheckIn}  →  ${t.formattedCheckOut}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        const Spacer(),
                        Text(
                          t.formattedTotal,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _statusColor(PaymentStatus status, ColorScheme scheme) {
    return switch (status) {
      PaymentStatus.paid    => const Color(0xFF2E7D32),
      PaymentStatus.partial => const Color(0xFFE65100),
      PaymentStatus.unpaid  => scheme.error,
    };
  }
}

// ── Status badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final PaymentStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      PaymentStatus.paid    => (
          'Lunas',
          const Color(0xFFE8F5E9),
          const Color(0xFF2E7D32),
        ),
      PaymentStatus.partial => (
          'DP',
          const Color(0xFFFFF3E0),
          const Color(0xFFE65100),
        ),
      PaymentStatus.unpaid  => (
          'Belum Bayar',
          Theme.of(context).colorScheme.errorContainer,
          Theme.of(context).colorScheme.onErrorContainer,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}
