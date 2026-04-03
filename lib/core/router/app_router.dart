import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/customers/domain/customer_model.dart';
import '../../features/customers/presentation/screens/customer_form_screen.dart';
import '../../features/customers/presentation/screens/customer_list_screen.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/rooms/domain/room_model.dart';
import '../../features/rooms/presentation/screens/room_form_screen.dart';
import '../../features/rooms/presentation/screens/room_list_screen.dart';
import '../../features/settings/presentation/screens/about_screen.dart';
import '../../features/settings/presentation/screens/setup_screen.dart';
import '../../features/calendar/presentation/screens/calendar_screen.dart';
import '../../features/reports/presentation/screens/reports_screen.dart';
import '../../features/transactions/domain/transaction_model.dart';
import '../../features/transactions/presentation/screens/booking_form_screen.dart';
import '../../features/transactions/presentation/screens/transaction_detail_screen.dart';
import '../../features/transactions/presentation/screens/transaction_list_screen.dart';

/// Named route paths. Always use these constants — never hardcode strings.
abstract class AppRoutes {
  static const splash    = '/splash';
  static const login     = '/login';
  static const setup     = '/setup';
  static const dashboard = '/dashboard';
  static const rooms       = '/rooms';
  static const roomNew     = '/rooms/new';
  // Edit: /rooms/:id — build with: '${AppRoutes.rooms}/${room.id}'
  static const customers   = '/customers';
  static const customerNew = '/customers/new';
  // Edit: /customers/:id — build with: '${AppRoutes.customers}/${customer.id}'
  static const transactions = '/transactions';
  static const bookingNew   = '/transactions/new';
  // Detail: /transactions/:id — build with: '${AppRoutes.transactions}/${txn.id}'
  static const reports  = '/reports';
  static const calendar = '/calendar';
  static const about    = '/about';
}

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      if (authState.isLoading) return AppRoutes.splash;

      final auth = authState.valueOrNull;
      final isAuthenticated = auth?.isAuthenticated ?? false;
      final loc = state.matchedLocation;

      if (loc == AppRoutes.splash) return null;
      if (loc == AppRoutes.setup) return null;

      if (!isAuthenticated && loc != AppRoutes.login) return AppRoutes.login;
      if (isAuthenticated && loc == AppRoutes.login) return AppRoutes.dashboard;

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.setup,
        builder: (_, __) => const SetupScreen(),
      ),
      GoRoute(
        path: AppRoutes.about,
        builder: (_, __) => const AboutScreen(),
      ),
      GoRoute(
        path: AppRoutes.dashboard,
        builder: (_, __) => const DashboardScreen(),
      ),

      // ── Rooms ────────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.rooms,
        builder: (_, __) => const RoomListScreen(),
      ),
      GoRoute(
        path: AppRoutes.roomNew,
        builder: (_, __) => const RoomFormScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.rooms}/:id',
        builder: (context, state) {
          final room = state.extra as RoomModel?;
          return RoomFormScreen(room: room);
        },
      ),

      // ── Customers ─────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.customers,
        builder: (_, __) => const CustomerListScreen(),
      ),
      GoRoute(
        path: AppRoutes.customerNew,
        builder: (_, __) => const CustomerFormScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.customers}/:id',
        builder: (context, state) {
          final customer = state.extra as CustomerModel?;
          return CustomerFormScreen(customer: customer);
        },
      ),

      // ── Reports ───────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.reports,
        builder: (_, __) => const ReportsScreen(),
      ),
      // ── Calendar ──────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.calendar,
        builder: (_, __) => const CalendarScreen(),
      ),

      // ── Transactions ───────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.transactions,
        builder: (_, __) => const TransactionListScreen(),
      ),
      GoRoute(
        path: AppRoutes.bookingNew,
        builder: (_, __) => const BookingFormScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.transactions}/:id',
        builder: (context, state) {
          final txn = state.extra as TransactionModel?;
          if (txn == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Transaksi')),
              body: const Center(child: Text('Data tidak ditemukan')),
            );
          }
          return TransactionDetailScreen(transaction: txn);
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Halaman tidak ditemukan')),
      body: Center(child: Text(state.error.toString())),
    ),
  );
});
