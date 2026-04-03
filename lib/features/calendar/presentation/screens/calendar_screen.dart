import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../../core/router/app_router.dart';
import '../../../transactions/domain/transaction_model.dart';
import '../../../transactions/presentation/providers/transactions_provider.dart';
import '../providers/calendar_provider.dart';

class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txnsAsync = ref.watch(transactionsProvider);
    final calState  = ref.watch(calendarProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kalender Booking'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.dashboard),
        ),
        actions: [
          // Jump to today
          IconButton(
            icon: const Icon(Icons.today_outlined),
            tooltip: 'Hari Ini',
            onPressed: () {
              final today = DateTime.now();
              ref.read(calendarProvider.notifier).selectDay(today, today);
            },
          ),
        ],
      ),
      body: txnsAsync.when(
        // While transactions load, show a skeleton calendar
        loading: () => const _LoadingView(),
        error: (e, _) => _ErrorView(
          message: e.toString(),
          onRetry: () =>
              ref.read(transactionsProvider.notifier).refresh(),
        ),
        data: (allTxns) => _CalendarBody(
          allTxns:   allTxns,
          calState:  calState,
        ),
      ),
    );
  }
}

// ── Main body ─────────────────────────────────────────────────────────────────

class _CalendarBody extends ConsumerWidget {
  const _CalendarBody({required this.allTxns, required this.calState});

  final List<TransactionModel> allTxns;
  final CalendarState calState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme       = Theme.of(context).colorScheme;
    final selectedTxns = transactionsForDay(calState.selectedDay, allTxns);

    return Column(
      children: [
        // ── Calendar ──────────────────────────────────────────────────────
        _CalendarWidget(
          allTxns:    allTxns,
          calState:   calState,
          onDaySelected: (day, focused) =>
              ref.read(calendarProvider.notifier).selectDay(day, focused),
          onPageChanged: (focused) =>
              ref.read(calendarProvider.notifier).changePage(focused),
        ),

        const Divider(height: 1),

        // ── Selected day header ───────────────────────────────────────────
        _DayHeader(day: calState.selectedDay, count: selectedTxns.length),

        // ── Booking list for selected day ─────────────────────────────────
        Expanded(
          child: selectedTxns.isEmpty
              ? _EmptyDayView(day: calState.selectedDay)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: selectedTxns.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _BookingTile(
                      transaction: selectedTxns[i],
                      onTap: () => context.go(
                        '${AppRoutes.transactions}/${selectedTxns[i].id}',
                        extra: selectedTxns[i],
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

// ── TableCalendar wrapper ─────────────────────────────────────────────────────

class _CalendarWidget extends StatelessWidget {
  const _CalendarWidget({
    required this.allTxns,
    required this.calState,
    required this.onDaySelected,
    required this.onPageChanged,
  });

  final List<TransactionModel> allTxns;
  final CalendarState calState;
  final void Function(DateTime, DateTime) onDaySelected;
  final void Function(DateTime) onPageChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return TableCalendar<TransactionModel>(
      locale: 'id_ID',
      firstDay: DateTime.utc(2020, 1, 1),
      lastDay:  DateTime.utc(2030, 12, 31),
      focusedDay:  calState.focusedDay,
      selectedDayPredicate: (day) =>
          isSameDay(day, calState.selectedDay),

      // Lock to month view — no toggle needed for this use case.
      calendarFormat: CalendarFormat.month,
      availableCalendarFormats: const {CalendarFormat.month: 'Bulan'},

      // Provide transactions for each day.
      eventLoader: (day) => transactionsForDay(day, allTxns),

      onDaySelected: onDaySelected,
      onPageChanged: onPageChanged,

      // ── Styling ─────────────────────────────────────────────────────────
      headerStyle: HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        titleTextStyle: Theme.of(context).textTheme.titleMedium!.copyWith(
              fontWeight: FontWeight.bold,
            ),
        leftChevronIcon:  Icon(Icons.chevron_left,  color: scheme.onSurface),
        rightChevronIcon: Icon(Icons.chevron_right, color: scheme.onSurface),
        headerPadding: const EdgeInsets.symmetric(vertical: 12),
      ),

      daysOfWeekStyle: DaysOfWeekStyle(
        weekdayStyle: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w500),
        weekendStyle: TextStyle(
            color: scheme.primary,
            fontSize: 12,
            fontWeight: FontWeight.w500),
      ),

      calendarStyle: CalendarStyle(
        outsideDaysVisible: true,
        outsideTextStyle: TextStyle(color: scheme.onSurface.withValues(alpha: 0.3)),

        // Today circle
        todayDecoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        todayTextStyle: TextStyle(
            color: scheme.primary, fontWeight: FontWeight.bold),

        // Selected day filled circle
        selectedDecoration: BoxDecoration(
          color: scheme.primary,
          shape: BoxShape.circle,
        ),
        selectedTextStyle: TextStyle(
            color: scheme.onPrimary, fontWeight: FontWeight.bold),

        // Weekend text
        weekendTextStyle: TextStyle(color: scheme.primary),

        // Suppress default dot markers — we draw our own.
        markersMaxCount: 0,
      ),

      // ── Custom marker builder ────────────────────────────────────────────
      calendarBuilders: CalendarBuilders(
        markerBuilder: (context, day, events) {
          if (events.isEmpty) return const SizedBox.shrink();
          return _StatusDots(transactions: events);
        },
      ),
    );
  }
}

// ── Status dots below each day cell ──────────────────────────────────────────

/// Shows up to 3 coloured dots representing the payment statuses present
/// on a given day. Priority order: unpaid (red) > partial (orange) > paid (green).
class _StatusDots extends StatelessWidget {
  const _StatusDots({required this.transactions});

  final List<TransactionModel> transactions;

  static const _kDotSize = 5.0;

  @override
  Widget build(BuildContext context) {
    // Collect distinct statuses in priority order.
    final statuses = <PaymentStatus>[];
    for (final s in [
      PaymentStatus.unpaid,
      PaymentStatus.partial,
      PaymentStatus.paid,
    ]) {
      if (transactions.any((t) => t.paymentStatus == s)) statuses.add(s);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: statuses.map((s) {
          return Container(
            width:  _kDotSize,
            height: _kDotSize,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: _dotColor(s),
              shape: BoxShape.circle,
            ),
          );
        }).toList(),
      ),
    );
  }

  static Color _dotColor(PaymentStatus s) => switch (s) {
        PaymentStatus.paid    => const Color(0xFF2E7D32),
        PaymentStatus.partial => const Color(0xFFE65100),
        PaymentStatus.unpaid  => const Color(0xFFD32F2F),
      };
}

// ── Day header ────────────────────────────────────────────────────────────────

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.count});

  final DateTime day;
  final int count;

  static final _fmt = DateFormat('EEEE, d MMMM yyyy', 'id_ID');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      color: scheme.surfaceContainerLowest,
      child: Row(
        children: [
          Expanded(
            child: Text(
              _fmt.format(day),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          if (count > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$count booking',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Booking tile ──────────────────────────────────────────────────────────────

class _BookingTile extends StatelessWidget {
  const _BookingTile({required this.transaction, required this.onTap});

  final TransactionModel transaction;
  final VoidCallback onTap;

  static final _dateFmt = DateFormat('d MMM', 'id_ID');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t      = transaction;

    final (statusBg, statusFg, statusLabel) = switch (t.paymentStatus) {
      PaymentStatus.paid    => (
          const Color(0xFFE8F5E9),
          const Color(0xFF2E7D32),
          'Lunas',
        ),
      PaymentStatus.partial => (
          const Color(0xFFFFF3E0),
          const Color(0xFFE65100),
          'DP',
        ),
      PaymentStatus.unpaid  => (
          scheme.errorContainer,
          scheme.onErrorContainer,
          'Belum Bayar',
        ),
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Status stripe
              Container(
                width: 5,
                color: statusFg,
              ),

              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Customer + room
                            Text(
                              t.customerName,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              t.roomName,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: scheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 6),
                            // Date range + nights
                            Row(
                              children: [
                                Icon(Icons.calendar_today_outlined,
                                    size: 12,
                                    color: scheme.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text(
                                  '${_dateFmt.format(t.checkIn)} → '
                                  '${_dateFmt.format(t.checkOut)}'
                                  '  ·  ${t.nights} malam',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 8),

                      // Right column: status badge + price + chevron
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusBg,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: statusFg,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            t.formattedTotal,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          Icon(Icons.chevron_right,
                              size: 16,
                              color: scheme.onSurfaceVariant),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty day view ────────────────────────────────────────────────────────────

class _EmptyDayView extends StatelessWidget {
  const _EmptyDayView({required this.day});
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_available_outlined,
                size: 48, color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              'Tidak ada booking',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tidak ada tamu menginap pada tanggal ini.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Loading skeleton ──────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        // Calendar placeholder
        Container(
          height: 380,
          color: scheme.surface,
          padding: const EdgeInsets.all(16),
          child: const Center(child: CircularProgressIndicator()),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: 3,
            itemBuilder: (_, __) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                height: 80,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Error view ────────────────────────────────────────────────────────────────

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
            Text(
              'Gagal memuat data kalender',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
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
