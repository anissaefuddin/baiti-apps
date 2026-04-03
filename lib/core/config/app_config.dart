import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../storage/local_storage.dart';

final appConfigProvider = Provider<AppConfig>((ref) {
  return AppConfig(ref.watch(localStorageProvider));
});

/// Runtime configuration loaded from local storage.
/// Set once via [SetupScreen], then read on every API call.
class AppConfig {
  AppConfig(this._storage);

  final LocalStorage _storage;

  String get scriptUrl => _storage.scriptUrl ?? '';
  String get calendarId => _storage.calendarId ?? '';
  bool get isConfigured => _storage.isConfigured;
}
