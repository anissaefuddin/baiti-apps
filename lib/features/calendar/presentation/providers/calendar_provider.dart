import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../transactions/domain/transaction_model.dart';
import '../../../transactions/presentation/providers/transactions_provider.dart';

// ── Selected day state ────────────────────────────────────────────────────────

class CalendarState {
  const CalendarState({
    required this.focusedDay,
    required this.selectedDay,
  });

  final DateTime focusedDay;
  final DateTime selectedDay;

  CalendarState copyWith({DateTime? focusedDay, DateTime? selectedDay}) {
    return CalendarState(
      focusedDay:  focusedDay  ?? this.focusedDay,
      selectedDay: selectedDay ?? this.selectedDay,
    );
  }
}

class CalendarNotifier extends Notifier<CalendarState> {
  @override
  CalendarState build() {
    final today = _today();
    return CalendarState(focusedDay: today, selectedDay: today);
  }

  void selectDay(DateTime day, DateTime focused) {
    state = state.copyWith(
      selectedDay: _normalise(day),
      focusedDay:  _normalise(focused),
    );
  }

  void changePage(DateTime focused) {
    state = state.copyWith(focusedDay: _normalise(focused));
  }

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTime _normalise(DateTime d) => DateTime(d.year, d.month, d.day);
}

final calendarProvider = NotifierProvider<CalendarNotifier, CalendarState>(
  CalendarNotifier.new,
);

// ── Derived: transactions for a given day ─────────────────────────────────────

/// Returns all transactions that include [day] in their stay.
/// Stay range is [checkIn, checkOut) — checkout day is excluded so two
/// back-to-back bookings don't both appear on the handover day.
List<TransactionModel> transactionsForDay(
  DateTime day,
  List<TransactionModel> all,
) {
  final d = DateTime(day.year, day.month, day.day);
  return all.where((t) {
    final checkIn  = DateTime(t.checkIn.year,  t.checkIn.month,  t.checkIn.day);
    final checkOut = DateTime(t.checkOut.year, t.checkOut.month, t.checkOut.day);
    return !d.isBefore(checkIn) && d.isBefore(checkOut);
  }).toList();
}

/// Provider family that returns transactions for a given normalised day.
/// Automatically updates when [transactionsProvider] changes.
final transactionsForDayProvider =
    Provider.family<List<TransactionModel>, DateTime>((ref, day) {
  final all = ref.watch(transactionsProvider).valueOrNull ?? [];
  return transactionsForDay(day, all);
});
