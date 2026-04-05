import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

// ── Model ─────────────────────────────────────────────────────────────────────

enum BackendStatusCode { active, inactive, checking, idle }

class BackendStatus {
  const BackendStatus({
    required this.status,
    required this.httpCode,
    required this.responseTime,
    required this.checkedAt,
    this.error,
  });

  const BackendStatus.idle()
      : status = BackendStatusCode.idle,
        httpCode = 0,
        responseTime = -1,
        checkedAt = null,
        error = null;

  const BackendStatus.checking()
      : status = BackendStatusCode.checking,
        httpCode = 0,
        responseTime = -1,
        checkedAt = null,
        error = null;

  final BackendStatusCode status;
  final int httpCode;
  final int responseTime; // milliseconds; -1 = timeout / no response
  final DateTime? checkedAt;
  final String? error;

  bool get isActive => status == BackendStatusCode.active;
}

// ── Service ───────────────────────────────────────────────────────────────────

class BackendStatusService {
  BackendStatusService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _timeout = Duration(seconds: 10);

  /// Checks whether [url] responds successfully.
  ///
  /// Apps Script URLs (script.google.com / googleusercontent.com) do not
  /// support HEAD — always use GET for them.  For all other URLs try HEAD
  /// first and fall back to GET if the server returns a non-2xx response.
  Future<BackendStatus> check(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      return BackendStatus(
        status: BackendStatusCode.inactive,
        httpCode: 0,
        responseTime: -1,
        checkedAt: DateTime.now(),
        error: 'URL tidak valid',
      );
    }

    final needsGet = url.contains('script.google.com') ||
        url.contains('googleusercontent.com');

    try {
      if (needsGet) {
        return await _get(uri);
      }

      // Try HEAD first, fall back to GET on non-2xx
      final headResult = await _head(uri);
      if (headResult.isActive) return headResult;
      return await _get(uri);
    } on SocketException {
      return BackendStatus(
        status: BackendStatusCode.inactive,
        httpCode: 0,
        responseTime: -1,
        checkedAt: DateTime.now(),
        error: 'Tidak ada koneksi internet',
      );
    } catch (e) {
      return BackendStatus(
        status: BackendStatusCode.inactive,
        httpCode: 0,
        responseTime: -1,
        checkedAt: DateTime.now(),
        error: e.toString(),
      );
    }
  }

  Future<BackendStatus> _head(Uri uri) async {
    final sw = Stopwatch()..start();
    try {
      final res = await _client
          .head(uri, headers: {HttpHeaders.acceptHeader: 'application/json'})
          .timeout(_timeout);
      return _fromResponse(res.statusCode, sw.elapsedMilliseconds);
    } on Exception {
      return BackendStatus(
        status: BackendStatusCode.inactive,
        httpCode: 0,
        responseTime: sw.elapsedMilliseconds,
        checkedAt: DateTime.now(),
      );
    }
  }

  Future<BackendStatus> _get(Uri uri) async {
    final sw = Stopwatch()..start();
    final res = await _client
        .get(uri, headers: {HttpHeaders.acceptHeader: 'application/json'})
        .timeout(_timeout);
    return _fromResponse(res.statusCode, sw.elapsedMilliseconds);
  }

  BackendStatus _fromResponse(int code, int ms) => BackendStatus(
        status: _isOk(code)
            ? BackendStatusCode.active
            : BackendStatusCode.inactive,
        httpCode: code,
        responseTime: ms,
        checkedAt: DateTime.now(),
      );

  static bool _isOk(int code) => code >= 200 && code < 400;
}

// ── Provider ──────────────────────────────────────────────────────────────────

class BackendStatusNotifier extends Notifier<BackendStatus> {
  @override
  BackendStatus build() => const BackendStatus.idle();

  Future<void> check(String url) async {
    state = const BackendStatus.checking();
    state = await BackendStatusService().check(url);
  }

  void reset() => state = const BackendStatus.idle();
}

final backendStatusProvider =
    NotifierProvider<BackendStatusNotifier, BackendStatus>(
  BackendStatusNotifier.new,
);
