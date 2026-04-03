import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../core/router/app_router.dart';
import '../../../transactions/domain/transaction_model.dart';
import '../../domain/report_model.dart';
import '../providers/reports_provider.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(reportSummaryProvider);
    final filter       = ref.watch(reportFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.dashboard),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat ulang',
            onPressed: () =>
                ref.read(reportSummaryProvider.notifier).refresh(),
          ),
          _ExportButton(),
        ],
      ),
      body: Column(
        children: [
          _PeriodFilter(filter: filter),
          Expanded(
            child: summaryAsync.when(
              loading: () => const _LoadingView(),
              error:   (e, _) => _ErrorView(
                message: e.toString(),
                onRetry: () =>
                    ref.read(reportSummaryProvider.notifier).refresh(),
              ),
              data: (report) => _ReportBody(report: report),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Period filter bar ─────────────────────────────────────────────────────────

class _PeriodFilter extends ConsumerWidget {
  const _PeriodFilter({required this.filter});
  final ReportFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      color: scheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ReportPeriod.values.map((p) {
                final selected = filter.period == p;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(p.label),
                    selected: selected,
                    onSelected: (_) => _onPeriodTap(context, ref, p),
                  ),
                );
              }).toList(),
            ),
          ),
          // Show custom date range when active
          if (filter.period == ReportPeriod.custom &&
              filter.dateFrom != null &&
              filter.dateTo != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${_fmt(filter.dateFrom!)}  –  ${_fmt(filter.dateTo!)}',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static final _fmt = DateFormat('d MMM yyyy', 'id_ID').format;

  Future<void> _onPeriodTap(
    BuildContext context,
    WidgetRef ref,
    ReportPeriod period,
  ) async {
    if (period == ReportPeriod.custom) {
      await _pickCustomRange(context, ref);
    } else {
      ref.read(reportFilterProvider.notifier).setPeriod(period);
    }
  }

  Future<void> _pickCustomRange(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      initialDateRange: DateTimeRange(
        start: ref.read(reportFilterProvider).dateFrom ?? now,
        end:   ref.read(reportFilterProvider).dateTo   ?? now,
      ),
      helpText: 'Pilih Rentang Tanggal',
    );
    if (range == null) return;
    ref.read(reportFilterProvider.notifier).setDateRange(range.start, range.end);
  }
}

// ── Export button ─────────────────────────────────────────────────────────────

class _ExportButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exportState = ref.watch(exportProvider);
    final isLoading   = exportState.isLoading;

    return IconButton(
      icon: isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.download_outlined),
      tooltip: 'Ekspor CSV',
      onPressed: isLoading ? null : () => _export(context, ref),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    try {
      final filePath = await ref.read(exportProvider.notifier).export();
      if (!context.mounted) return;

      final result = ref.read(exportProvider).valueOrNull;
      await Share.shareXFiles(
        [XFile(filePath, mimeType: 'text/csv')],
        subject: result?.filename ?? 'laporan.csv',
      );
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ekspor gagal: $e')),
      );
    }
  }
}

// ── Report body ───────────────────────────────────────────────────────────────

class _ReportBody extends ConsumerWidget {
  const _ReportBody({required this.report});
  final ReportSummary report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () => ref.read(reportSummaryProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // ── Period label ─────────────────────────────────────────────
          Text(
            '${report.formattedPeriodFrom}  –  ${report.formattedPeriodTo}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),

          // ── Summary cards ─────────────────────────────────────────────
          _SummaryGrid(report: report),
          const SizedBox(height: 20),

          // ── Status breakdown ──────────────────────────────────────────
          _StatusBreakdownCard(breakdown: report.statusBreakdown),
          const SizedBox(height: 20),

          // ── Upcoming bookings ─────────────────────────────────────────
          _SectionHeader(
            icon: Icons.upcoming_outlined,
            title: 'Check-in 7 Hari Ke Depan',
            count: report.upcomingBookings.length,
          ),
          const SizedBox(height: 8),
          if (report.upcomingBookings.isEmpty)
            _EmptyChip(label: 'Tidak ada check-in dalam 7 hari ke depan')
          else
            ...report.upcomingBookings.map(
              (t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SummaryTransactionTile(transaction: t, showCheckIn: true),
              ),
            ),
          const SizedBox(height: 20),

          // ── Unpaid / partial ──────────────────────────────────────────
          _SectionHeader(
            icon: Icons.warning_amber_outlined,
            title: 'Belum Lunas',
            count: report.unpaidTransactions.length,
          ),
          const SizedBox(height: 8),
          if (report.unpaidTransactions.isEmpty)
            _EmptyChip(label: 'Semua transaksi sudah lunas')
          else
            ...report.unpaidTransactions.map(
              (t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SummaryTransactionTile(transaction: t, showRemaining: true),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Summary grid ──────────────────────────────────────────────────────────────

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.report});
  final ReportSummary report;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: _MetricCard(
            icon: Icons.receipt_long_outlined,
            label: 'Total Booking',
            value: '${report.totalBookings}',
            valueColor: scheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricCard(
            icon: Icons.payments_outlined,
            label: 'Total Pendapatan',
            value: report.formattedTotal,
            valueColor: const Color(0xFF2E7D32),
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: valueColor,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status breakdown ──────────────────────────────────────────────────────────

class _StatusBreakdownCard extends StatelessWidget {
  const _StatusBreakdownCard({required this.breakdown});
  final StatusBreakdown breakdown;

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
                Icon(Icons.donut_small_outlined,
                    size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  'Breakdown Status',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _BreakdownItem(
                  label: 'Belum Bayar',
                  count: breakdown.unpaid,
                  color: scheme.error,
                ),
                const SizedBox(width: 16),
                _BreakdownItem(
                  label: 'DP / Sebagian',
                  count: breakdown.partial,
                  color: const Color(0xFFE65100),
                ),
                const SizedBox(width: 16),
                _BreakdownItem(
                  label: 'Lunas',
                  count: breakdown.paid,
                  color: const Color(0xFF2E7D32),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BreakdownItem extends StatelessWidget {
  const _BreakdownItem({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$count',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold, color: color),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.count,
  });

  final IconData icon;
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: scheme.onPrimaryContainer,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Summary transaction tile ──────────────────────────────────────────────────

class _SummaryTransactionTile extends StatelessWidget {
  const _SummaryTransactionTile({
    required this.transaction,
    this.showCheckIn   = false,
    this.showRemaining = false,
  });

  final SummaryTransaction transaction;
  final bool showCheckIn;
  final bool showRemaining;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t      = transaction;

    final (statusBg, statusFg) = switch (t.paymentStatus) {
      PaymentStatus.paid    => (const Color(0xFFE8F5E9), const Color(0xFF2E7D32)),
      PaymentStatus.partial => (const Color(0xFFFFF3E0), const Color(0xFFE65100)),
      PaymentStatus.unpaid  => (scheme.errorContainer, scheme.onErrorContainer),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Booking code + status chip
                  Row(
                    children: [
                      Text(
                        t.bookingCode,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontFamily: 'monospace',
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusBg,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          t.paymentStatus.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: statusFg,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t.customerName,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                  if (showCheckIn)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(Icons.login_outlined,
                              size: 12, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            'Check-in: ${t.formattedCheckIn}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
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
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (showRemaining && t.remaining > 0)
                  Text(
                    'Sisa ${t.formattedRemaining}',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.error,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _EmptyChip extends StatelessWidget {
  const _EmptyChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ── Loading ───────────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shimmer = (double h) => Container(
          height: h,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
        );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: shimmer(90)),
            const SizedBox(width: 12),
            Expanded(child: shimmer(90)),
          ]),
          const SizedBox(height: 16),
          shimmer(80),
          const SizedBox(height: 20),
          shimmer(14),
          const SizedBox(height: 8),
          shimmer(64),
          const SizedBox(height: 8),
          shimmer(64),
        ],
      ),
    );
  }
}

// ── Error ─────────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: scheme.error),
            const SizedBox(height: 16),
            Text('Gagal memuat laporan',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    )),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }
}
