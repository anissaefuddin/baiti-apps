import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provided at app startup via ProviderScope override in main.dart.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (_) => throw UnimplementedError('sharedPreferencesProvider must be overridden in main'),
);

final localStorageProvider = Provider<LocalStorage>((ref) {
  return LocalStorage(ref.watch(sharedPreferencesProvider));
});

/// Thin wrapper around SharedPreferences with typed accessors.
class LocalStorage {
  LocalStorage(this._prefs);

  final SharedPreferences _prefs;

  // Keys
  static const _keyUserJson = 'user_json';
  static const _keyScriptUrl = 'apps_script_url';
  static const _keyCalendarId = 'calendar_id';

  // ── User session ──────────────────────────────────────────────────────────

  String? get userJson => _prefs.getString(_keyUserJson);

  Future<void> saveUserJson(String json) =>
      _prefs.setString(_keyUserJson, json);

  Future<void> clearUser() => _prefs.remove(_keyUserJson);

  // ── App config ────────────────────────────────────────────────────────────

  String? get scriptUrl => _prefs.getString(_keyScriptUrl);

  Future<void> saveScriptUrl(String url) =>
      _prefs.setString(_keyScriptUrl, url);

  String? get calendarId => _prefs.getString(_keyCalendarId);

  Future<void> saveCalendarId(String id) =>
      _prefs.setString(_keyCalendarId, id);

  /// Returns true only when the Apps Script URL has been configured.
  bool get isConfigured {
    final url = scriptUrl;
    return url != null && url.isNotEmpty;
  }
}
