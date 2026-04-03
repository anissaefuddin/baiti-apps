import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exception.dart';
import '../../data/auth_repository.dart';
import '../../domain/user_model.dart';

// ── Error model ───────────────────────────────────────────────────────────────

enum AuthErrorType {
  network,      // No internet / socket error
  cancelled,    // User dismissed the Google picker
  unauthorized, // Server rejected the token
  notConfigured,// Apps Script URL not set up
  unknown,      // Anything else
}

/// Structured auth error shown in [LoginScreen].
class AuthError {
  const AuthError({
    required this.type,
    required this.title,
    this.message = '',
  });

  final AuthErrorType type;
  final String title;
  final String message;

  /// Map from [ApiException] or arbitrary exception to a typed [AuthError].
  factory AuthError.from(Object error) {
    if (error is ApiException) {
      if (error.isUnauthorized) {
        return const AuthError(
          type: AuthErrorType.unauthorized,
          title: 'Token tidak valid',
          message: 'Sesi Google Anda kedaluwarsa. Silakan masuk kembali.',
        );
      }
      if (error.message.contains('cancelled') ||
          error.message.contains('dibatalkan')) {
        return const AuthError(
          type: AuthErrorType.cancelled,
          title: 'Login dibatalkan',
        );
      }
      if (error.message.contains('No internet') ||
          error.message.contains('SocketException')) {
        return const AuthError(
          type: AuthErrorType.network,
          title: 'Tidak ada koneksi internet',
          message: 'Periksa koneksi jaringan Anda dan coba lagi.',
        );
      }
      if (error.message.contains('URL is not configured') ||
          error.message.contains('not configured')) {
        return const AuthError(
          type: AuthErrorType.notConfigured,
          title: 'Aplikasi belum dikonfigurasi',
          message: 'Buka Pengaturan dan masukkan URL server.',
        );
      }
      return AuthError(
        type: AuthErrorType.unknown,
        title: 'Login gagal',
        message: error.message,
      );
    }

    final msg = error.toString();
    if (msg.contains('cancelled') || msg.contains('cancel')) {
      return const AuthError(
        type: AuthErrorType.cancelled,
        title: 'Login dibatalkan',
      );
    }
    return AuthError(
      type: AuthErrorType.unknown,
      title: 'Login gagal',
      message: msg,
    );
  }
}

// ── Auth state ────────────────────────────────────────────────────────────────

enum AuthStatus { authenticated, unauthenticated }

class AuthState {
  const AuthState({
    required this.status,
    this.user,
    this.error,
  });

  final AuthStatus status;
  final UserModel? user;

  /// Non-null when the last sign-in attempt failed.
  /// Cleared when [AuthNotifier.clearError] or [AuthNotifier.signIn] is called.
  final AuthError? error;

  bool get isAuthenticated => status == AuthStatus.authenticated;

  AuthState copyWith({
    AuthStatus? status,
    UserModel? user,
    AuthError? error,
    bool clearError = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class AuthNotifier extends AsyncNotifier<AuthState> {
  /// Initialise from cache — synchronous, no network call.
  /// Fast startup: the user sees the dashboard immediately if a session exists.
  @override
  Future<AuthState> build() async {
    final user = ref.watch(authRepositoryProvider).getCachedUser();
    if (user != null) {
      return AuthState(status: AuthStatus.authenticated, user: user);
    }
    return const AuthState(status: AuthStatus.unauthenticated);
  }

  /// Full Google Sign-In flow:
  ///   google_sign_in → idToken → POST auth.login → cache user
  Future<void> signIn() async {
    // Clear previous errors and enter loading.
    state = const AsyncValue.loading();

    final result = await AsyncValue.guard<AuthState>(() async {
      final user = await ref.read(authRepositoryProvider).signIn();
      return AuthState(status: AuthStatus.authenticated, user: user);
    });

    if (result.hasError) {
      state = AsyncValue.data(
        AuthState(
          status: AuthStatus.unauthenticated,
          error: AuthError.from(result.error ?? 'Unknown error'),
        ),
      );
    } else {
      state = result;
    }
  }

  /// Signs out: clears Google session + local cache.
  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = const AsyncValue.data(
      AuthState(status: AuthStatus.unauthenticated),
    );
  }

  /// Called when a protected API call returns UNAUTHORIZED (session expired).
  /// Clears the cached session and forces the user back to login.
  Future<void> handleSessionExpiry() async {
    await ref.read(authRepositoryProvider).signOut();
    state = AsyncValue.data(
      AuthState(
        status: AuthStatus.unauthenticated,
        error: const AuthError(
          type: AuthErrorType.unauthorized,
          title: 'Sesi berakhir',
          message: 'Silakan masuk kembali untuk melanjutkan.',
        ),
      ),
    );
  }

  /// Dismiss the error banner without changing auth status.
  void clearError() {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(current.copyWith(clearError: true));
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final authProvider =
    AsyncNotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
