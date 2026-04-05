import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../customers/presentation/providers/customers_provider.dart';
import '../../../payments/presentation/widgets/add_payment_sheet.dart';
import '../../../payments/presentation/widgets/payment_history_list.dart';
import '../../../rooms/presentation/providers/rooms_provider.dart';
import '../../domain/transaction_model.dart';
import '../providers/transactions_provider.dart';
import '../widgets/pdf_action_sheet.dart';

/// Detail screen for a single booking.
///
/// Accepts an initial [transaction] via GoRouter extra, then watches
/// [transactionsProvider] for live updates — so after a payment is added
/// the status header and financial summary update automatically.
class TransactionDetailScreen extends ConsumerWidget {
  const TransactionDetailScreen({super.key, required this.transaction});

  /// Initial snapshot from the list screen (no extra API call needed).
  final TransactionModel transaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Prefer the live version from the provider so payment updates reflect
    // immediately, but fall back to the passed-in snapshot if not found yet.
    final live = ref.watch(transactionsProvider).valueOrNull
        ?.where((t) => t.id == transaction.id)
        .firstOrNull;
    final t = live ?? transaction;

    final scheme   = Theme.of(context).colorScheme;
    final customer = ref.watch(customersProvider).valueOrNull
        ?.where((c) => c.id == t.customerId)
        .firstOrNull;
    final rooms = ref.watch(roomsProvider).valueOrNull
            ?.where((r) => t.roomIds.contains(r.id))
            .toList() ??
        [];

    final isPaid = t.paymentStatus == PaymentStatus.paid;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          t.bookingCode,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.transactions),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Dokumen PDF',
            onPressed: () => _showPdfSheet(context, t),
          ),
        ],
      ),
      floatingActionButton: isPaid
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showAddPayment(context, t),
              icon: const Icon(Icons.add),
              label: const Text('Tambah Pembayaran'),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        children: [
          // ── Payment status header ─────────────────────────────────────
          _StatusHeader(transaction: t),
          const SizedBox(height: 20),

          // ── Date & nights ─────────────────────────────────────────────
          _SectionCard(
            icon: Icons.calendar_month_outlined,
            title: 'Tanggal Menginap',
            child: Column(
              children: [
                _InfoRow(label: 'Check-in',  value: t.formattedCheckIn,  bold: true),
                const SizedBox(height: 8),
                _InfoRow(label: 'Check-out', value: t.formattedCheckOut, bold: true),
                const Divider(height: 24),
                _InfoRow(label: 'Lama menginap', value: '${t.nights} malam'),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Customer ──────────────────────────────────────────────────
          _SectionCard(
            icon: Icons.person_outline,
            title: 'Tamu',
            child: customer != null
                ? Column(
                    children: [
                      _InfoRow(label: 'Nama', value: customer.name),
                      const SizedBox(height: 8),
                      _InfoRow(label: 'NIK', value: customer.maskedNik),
                      if (customer.phone.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _InfoRow(label: 'Telepon', value: customer.phone),
                      ],
                    ],
                  )
                : _InfoRow(label: 'Nama Tamu', value: t.customerName),
          ),
          const SizedBox(height: 12),

          // ── Room(s) ───────────────────────────────────────────────────
          _SectionCard(
            icon: Icons.meeting_room_outlined,
            title: 'Kamar',
            child: rooms.isNotEmpty
                ? Column(
                    children: [
                      for (int i = 0; i < rooms.length; i++) ...[
                        if (i > 0) const Divider(height: 20),
                        _InfoRow(label: 'Nama', value: rooms[i].name),
                        const SizedBox(height: 8),
                        _InfoRow(
                          label: 'Harga / Malam',
                          value: rooms[i].formattedPrice,
                        ),
                        const SizedBox(height: 8),
                        _InfoRow(
                          label: 'Kapasitas',
                          value: '${rooms[i].capacity} tamu',
                        ),
                      ],
                    ],
                  )
                : _InfoRow(label: 'Nama Kamar', value: t.roomName),
          ),
          const SizedBox(height: 12),

          // ── Financial summary ─────────────────────────────────────────
          _SectionCard(
            icon: Icons.payments_outlined,
            title: 'Ringkasan Pembayaran',
            child: Column(
              children: [
                _InfoRow(label: 'Total', value: t.formattedTotal, bold: true),
                const SizedBox(height: 8),
                _InfoRow(label: 'Dibayar', value: t.formattedDp),
                const Divider(height: 24),
                _InfoRow(
                  label: 'Sisa',
                  value: t.formattedRemaining,
                  bold: true,
                  valueColor: t.remaining > 0
                      ? scheme.error
                      : const Color(0xFF2E7D32),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Payment history ───────────────────────────────────────────
          _SectionCard(
            icon: Icons.history_outlined,
            title: 'Riwayat Pembayaran',
            trailing: isPaid
                ? null
                : TextButton.icon(
                    onPressed: () => _showAddPayment(context, t),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Tambah'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
            child: PaymentHistoryList(transactionId: t.id),
          ),
          const SizedBox(height: 12),

          // ── Calendar sync ─────────────────────────────────────────────
          _SectionCard(
            icon: Icons.event_outlined,
            title: 'Google Calendar',
            child: Row(
              children: [
                Icon(
                  t.hasCalendarEvent
                      ? Icons.check_circle_outline
                      : Icons.sync_problem_outlined,
                  size: 18,
                  color: t.hasCalendarEvent
                      ? const Color(0xFF2E7D32)
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Text(
                  t.hasCalendarEvent ? 'Event tersinkron' : 'Tidak ada event kalender',
                  style: TextStyle(
                    color: t.hasCalendarEvent
                        ? const Color(0xFF2E7D32)
                        : scheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),

          // ── Notes ─────────────────────────────────────────────────────
          if (t.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SectionCard(
              icon: Icons.notes_outlined,
              title: 'Catatan',
              child: Text(t.notes,
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
        ],
      ),
    );
  }

  void _showAddPayment(BuildContext context, TransactionModel t) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => AddPaymentSheet(transaction: t),
    );
  }

  void _showPdfSheet(BuildContext context, TransactionModel t) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => PdfActionSheet(transaction: t),
    );
  }
}

// ── Payment status header ─────────────────────────────────────────────────────

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.transaction});
  final TransactionModel transaction;

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final (bg, fg) = switch (t.paymentStatus) {
      PaymentStatus.paid    => (const Color(0xFFE8F5E9), const Color(0xFF2E7D32)),
      PaymentStatus.partial => (const Color(0xFFFFF3E0), const Color(0xFFE65100)),
      PaymentStatus.unpaid  => (
          Theme.of(context).colorScheme.errorContainer,
          Theme.of(context).colorScheme.onErrorContainer,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Status Pembayaran',
                  style: TextStyle(
                      color: fg.withValues(alpha: 0.7), fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  t.paymentStatus.label,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                t.formattedTotal,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              if (t.paymentStatus != PaymentStatus.unpaid)
                Text(
                  'Dibayar ${t.formattedDp}',
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.75),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Section card ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 0.5,
                      ),
                ),
                if (trailing != null) ...[
                  const Spacer(),
                  trailing!,
                ],
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
                  color: valueColor,
                ),
          ),
        ),
      ],
    );
  }
}
