import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../domain/transaction_model.dart';
import '../providers/transactions_provider.dart';
import '../widgets/transaction_card.dart';

// ── Filter enum ───────────────────────────────────────────────────────────────

enum _Filter {
  active('Aktif'),
  all('Semua'),
  unpaid('Belum Bayar'),
  partial('DP'),
  paid('Lunas');

  const _Filter(this.label);
  final String label;
}

// ── Screen ────────────────────────────────────────────────────────────────────

class TransactionListScreen extends ConsumerStatefulWidget {
  const TransactionListScreen({super.key});

  @override
  ConsumerState<TransactionListScreen> createState() =>
      _TransactionListScreenState();
}

class _TransactionListScreenState
    extends ConsumerState<TransactionListScreen> {
  _Filter _filter = _Filter.active;

  /// Today at midnight — anything with checkOut before this is "closed".
  static DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  List<TransactionModel> _apply(List<TransactionModel> all) {
    return switch (_filter) {
      _Filter.active  => all.where((t) => !t.checkOut.isBefore(_today)).toList(),
      _Filter.all     => all,
      _Filter.unpaid  => all.where((t) => t.paymentStatus == PaymentStatus.unpaid).toList(),
      _Filter.partial => all.where((t) => t.paymentStatus == PaymentStatus.partial).toList(),
      _Filter.paid    => all.where((t) => t.paymentStatus == PaymentStatus.paid).toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final txnsAsync = ref.watch(transactionsProvider);
    final scheme    = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaksi'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.dashboard),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat ulang',
            onPressed: () => ref.read(transactionsProvider.notifier).refresh(),
          ),
        ],
        // Filter chips in the bottom of AppBar
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: _Filter.values.map((f) {
                final selected = _filter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(f.label),
                    selected: selected,
                    onSelected: (_) => setState(() => _filter = f),
                    selectedColor: scheme.primaryContainer,
                    checkmarkColor: scheme.onPrimaryContainer,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go(AppRoutes.bookingNew),
        icon: const Icon(Icons.add),
        label: const Text('Buat Pemesanan'),
      ),
      body: txnsAsync.when(
        loading: () => const _LoadingView(),
        error: (err, _) => _ErrorView(
          message: err.toString(),
          onRetry: () => ref.read(transactionsProvider.notifier).refresh(),
        ),
        data: (all) {
          final txns = _apply(all);
          if (txns.isEmpty) {
            return _EmptyView(
              filter: _filter,
              totalCount: all.length,
              onShowAll: () => setState(() => _filter = _Filter.all),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(transactionsProvider.notifier).refresh(),
            child: Column(
              children: [
                // Count banner
                Container(
                  width: double.infinity,
                  color: scheme.surfaceContainerLow,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 6,
                  ),
                  child: Text(
                    '${txns.length} transaksi'
                    '${_filter == _Filter.active ? ' aktif' : ''}'
                    ' dari ${all.length} total',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: txns.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TransactionCard(transaction: txns[i]),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Loading ───────────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: 5,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _SkeletonCard(),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4, height: 60,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Shimmer(width: 100, height: 11),
                  const SizedBox(height: 6),
                  _Shimmer(width: 160, height: 14),
                  const SizedBox(height: 4),
                  _Shimmer(width: 120, height: 12),
                  const SizedBox(height: 8),
                  _Shimmer(width: double.infinity, height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Shimmer extends StatelessWidget {
  const _Shimmer({required this.width, required this.height});
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

// ── Empty ─────────────────────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  const _EmptyView({
    required this.filter,
    required this.totalCount,
    required this.onShowAll,
  });

  final _Filter filter;
  final int totalCount;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final isActiveFilter = filter == _Filter.active;
    final title = isActiveFilter
        ? 'Tidak ada transaksi aktif'
        : 'Tidak ada transaksi';
    final subtitle = isActiveFilter && totalCount > 0
        ? 'Ada $totalCount transaksi yang sudah selesai.'
        : filter == _Filter.all
            ? 'Buat pemesanan pertama dengan\nmenekan tombol di bawah.'
            : 'Tidak ada transaksi dengan filter ini.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.receipt_long_outlined,
                  size: 40, color: scheme.onTertiaryContainer),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            if (isActiveFilter && totalCount > 0) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: onShowAll,
                icon: const Icon(Icons.history, size: 16),
                label: const Text('Lihat semua transaksi'),
              ),
            ],
          ],
        ),
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
            Text(
              'Gagal memuat transaksi',
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
