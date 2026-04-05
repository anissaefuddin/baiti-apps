import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/api_service.dart';
import '../../../core/storage/local_storage.dart';
import '../domain/user_model.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    api: ref.watch(apiServiceProvider),
    storage: ref.watch(localStorageProvider),
  );
});

/// Handles Google Sign-In, token exchange with Apps Script, and session
/// persistence in local storage.
///
/// Three entry points:
///   [signIn]        — full interactive Google picker flow
///   [silentSignIn]  — background token refresh (no UI)
///   [signOut]       — clear Google session + local cache
///   [getCachedUser] — read local cache without any network call
class AuthRepository {
  AuthRepository({
    required ApiService api,
    required LocalStorage storage,
  })  : _api = api,
        _storage = storage;

  final ApiService _api;
  final LocalStorage _storage;

  // Calendar scope needed by Phase 3 booking creation.
  // All scopes must be declared upfront to avoid mid-session permission prompts.
  //
  // serverClientId is the Web OAuth client ID from google-services.json.
  // It is required on Android so that GoogleSignIn returns an idToken
  // (without it, idToken is null even on a successful sign-in).
  // The value matches the type-3 client_id in google-services.json.
  static final _googleSignIn = GoogleSignIn(
    serverClientId:
        '824479873111-hl2mt61ateisc8i3u1en5b86u3jps0vp.apps.googleusercontent.com',
    scopes: [
      'email',
      'profile',
      'https://www.googleapis.com/auth/calendar.events',
    ],
  );

  // ── Public API ────────────────────────────────────────────────────────────

  /// Full interactive sign-in: shows Google account picker, exchanges token
  /// with Apps Script, caches and returns the [UserModel].
  ///
  /// Throws [ApiException] on network or server errors.
  /// Throws [ApiException] with message 'cancelled' if the user dismissed the picker.
  Future<UserModel> signIn() async {
    final account = await _googleSignIn.signIn();
    if (account == null) {
      // User dismissed the account picker.
      throw const ApiException('Sign-in dibatalkan.');
    }

    return _exchangeTokenAndCache(account);
  }

  /// Silent sign-in: refreshes the Google token in the background without UI.
  ///
  /// Use this on app resume to ensure the token context is fresh before making
  /// API calls. Returns null if no previous session exists.
  ///
  /// Does NOT contact Apps Script — only refreshes the Google-side token.
  Future<GoogleSignInAccount?> silentSignIn() async {
    try {
      return await _googleSignIn.signInSilently();
    } catch (_) {
      return null;
    }
  }

  /// Get a fresh idToken from the currently signed-in Google account.
  /// Returns null if no Google session is active.
  Future<String?> getFreshToken() async {
    final account = _googleSignIn.currentUser ?? await silentSignIn();
    if (account == null) return null;

    try {
      final auth = await account.authentication;
      return auth.idToken;
    } catch (_) {
      return null;
    }
  }

  /// Get a fresh OAuth2 access token from the currently signed-in Google account.
  ///
  /// On Android, declared scopes in [GoogleSignIn] are not automatically
  /// re-requested for existing sessions. We call [requestScopes] to ensure
  /// the calendar scope is actually granted before fetching the token.
  ///
  /// Returns null if no Google session is active or the user denies calendar access.
  Future<String?> getFreshAccessToken() async {
    final account = _googleSignIn.currentUser ?? await silentSignIn();
    if (account == null) return null;

    try {
      const calendarScope = 'https://www.googleapis.com/auth/calendar.events';

      // Check whether the calendar scope is already granted.
      final hasScope =
          await _googleSignIn.canAccessScopes([calendarScope]);

      if (!hasScope) {
        // Show the one-time consent dialog; returns false if the user denies.
        final granted =
            await _googleSignIn.requestScopes([calendarScope]);
        if (!granted) return null;
      }

      // Clear cached auth so we get a fresh token that includes the new scope.
      await account.clearAuthCache();
      final auth = await account.authentication;
      return auth.accessToken;
    } catch (_) {
      return null;
    }
  }

  /// Clear the Google session and erase the locally-cached user.
  Future<void> signOut() async {
    // Disconnect revokes access and clears the cached account.
    // Use signOut() to just clear local state without revoking access.
    await _googleSignIn.signOut();
    await _storage.clearUser();
  }

  /// Return the locally-cached [UserModel] without any network call.
  ///
  /// Returns null if:
  ///   - no session has been persisted
  ///   - the stored JSON is corrupt
  UserModel? getCachedUser() {
    final json = _storage.userJson;
    if (json == null) return null;
    try {
      return UserModel.fromJsonString(json);
    } catch (_) {
      // Corrupt cache — clear it to prevent infinite error loops.
      _storage.clearUser();
      return null;
    }
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  /// Exchange a [GoogleSignInAccount]'s idToken with Apps Script's auth.login,
  /// parse the returned user, cache it, and return it.
  Future<UserModel> _exchangeTokenAndCache(GoogleSignInAccount account) async {
    final auth = await account.authentication;
    final idToken = auth.idToken;

    if (idToken == null || idToken.isEmpty) {
      throw const ApiException(
        'Gagal mendapatkan token. Coba masuk kembali.',
      );
    }

    final response = await _api.post(
      action: 'auth.login',
      token: idToken,
    );

    final user = UserModel.fromJson(
      response['data'] as Map<String, dynamic>,
    );

    await _storage.saveUserJson(user.toJsonString());
    return user;
  }
}
