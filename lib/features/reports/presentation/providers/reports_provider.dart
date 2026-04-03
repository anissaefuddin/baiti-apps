import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/api/api_exception.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/report_repository.dart';
import '../../domain/report_model.dart';

// ── Report filter state ───────────────────────────────────────────────────────

class ReportFilter {
  const ReportFilter({
    this.period = ReportPeriod.monthly,
    this.dateFrom,
    this.dateTo,
  });

  final ReportPeriod period;
  final DateTime? dateFrom;
  final DateTime? dateTo;

  ReportFilter copyWith({
    ReportPeriod? period,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool clearDates = false,
  }) {
    return ReportFilter(
      period:   period ?? this.period,
      dateFrom: clearDates ? null : (dateFrom ?? this.dateFrom),
      dateTo:   clearDates ? null : (dateTo   ?? this.dateTo),
    );
  }
}

// ── Filter notifier (sync) ────────────────────────────────────────────────────

class ReportFilterNotifier extends Notifier<ReportFilter> {
  @override
  ReportFilter build() => const ReportFilter();

  void setPeriod(ReportPeriod period) {
    if (period == ReportPeriod.custom) {
      state = state.copyWith(period: period);
    } else {
      state = state.copyWith(period: period, clearDates: true);
    }
  }

  void setDateRange(DateTime from, DateTime to) {
    state = state.copyWith(
      period:   ReportPeriod.custom,
      dateFrom: from,
      dateTo:   to,
    );
  }
}

final reportFilterProvider =
    NotifierProvider<ReportFilterNotifier, ReportFilter>(
  ReportFilterNotifier.new,
);

// ── Summary notifier ──────────────────────────────────────────────────────────

/// Automatically reloads when [reportFilterProvider] changes.
class ReportSummaryNotifier extends AsyncNotifier<ReportSummary> {
  @override
  Future<ReportSummary> build() {
    // ref.watch here means build() re-runs whenever the filter changes,
    // which automatically reloads the summary.
    final filter = ref.watch(reportFilterProvider);
    return _fetch(filter);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    final filter = ref.read(reportFilterProvider);
    state = await AsyncValue.guard(() => _fetch(filter));
  }

  Future<ReportSummary> _fetch(ReportFilter filter) {
    return _guard(
      () => ref.read(reportRepositoryProvider).summary(
            period:   filter.period,
            dateFrom: filter.dateFrom,
            dateTo:   filter.dateTo,
          ),
    );
  }

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

final reportSummaryProvider =
    AsyncNotifierProvider<ReportSummaryNotifier, ReportSummary>(
  ReportSummaryNotifier.new,
);

// ── Export notifier ───────────────────────────────────────────────────────────

/// Tracks a single export operation (idle → loading → done/error).
/// Not persistent — resets on each call to [export].
class ExportNotifier extends AsyncNotifier<ExportResult?> {
  @override
  Future<ExportResult?> build() async => null;

  /// Run export and write the CSV to the app's temporary directory.
  /// Returns the [File] path of the written file (for sharing).
  Future<String> export() async {
    state = const AsyncValue.loading();

    try {
      final filter = ref.read(reportFilterProvider);
      final result = await _guard(
        () => ref.read(reportRepositoryProvider).export(
              period:   filter.period,
              dateFrom: filter.dateFrom,
              dateTo:   filter.dateTo,
            ),
      );

      state = AsyncValue.data(result);

      // Write CSV to temp file.
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/${result.filename}');
      await file.writeAsString(result.csv, flush: true);
      return file.path;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

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

final exportProvider =
    AsyncNotifierProvider<ExportNotifier, ExportResult?>(
  ExportNotifier.new,
);
