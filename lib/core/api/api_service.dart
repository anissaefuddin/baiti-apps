import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'api_exception.dart';

final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService(ref.watch(appConfigProvider));
});

/// Base HTTP service for all Apps Script Web App calls.
///
/// ## Apps Script redirect behaviour
/// Apps Script Web Apps always respond to POST with HTTP 302 + a Location
/// header pointing to a `script.googleusercontent.com/macros/echo?…` URL.
/// That echo URL accepts only GET and returns the actual JSON response.
///
/// The `package:http` client does NOT follow redirects automatically for POST,
/// so we implement the two-step manually:
///   1. POST to the /exec URL → expect 302, extract Location header.
///   2. GET the Location URL → returns { "success": bool, "data": ..., ... }.
///
/// All Apps Script responses use HTTP 200.  Success/failure is determined by
/// the `success` field in the JSON body; `error_code` drives retry logic.
class ApiService {
  ApiService(this._config);

  final AppConfig _config;

  static const _lockTimeoutErrorCode = 'LOCK_TIMEOUT';
  static const _maxRetries = 3;
  static const _timeout = Duration(seconds: 30);

  // Single http.Client reused across requests (keep-alive, connection pooling).
  final _client = http.Client();

  Future<Map<String, dynamic>> post({
    required String action,
    String? token,
    Map<String, dynamic>? data,
    int attempt = 1,
  }) async {
    if (_config.scriptUrl.isEmpty) {
      throw const ApiException(
          'Apps Script URL is not configured. Go to Settings.');
    }

    final body = jsonEncode({
      'action': action,
      if (token != null) 'token': token,
      if (data != null) 'data': data,
    });

    try {
      // ── Step 1: POST to /exec — expect 302 ──────────────────────────────
      final postResponse = await _client
          .post(
            Uri.parse(_config.scriptUrl),
            headers: {
              HttpHeaders.contentTypeHeader: 'application/json',
              HttpHeaders.acceptHeader: 'application/json',
            },
            body: body,
          )
          .timeout(_timeout);

      // Resolve the echo URL from the Location header (302 redirect).
      final String echoUrl;
      if (postResponse.statusCode == 302) {
        final location = postResponse.headers['location'];
        if (location == null || location.isEmpty) {
          throw const ApiException(
              'Invalid redirect from server: missing Location header.');
        }
        echoUrl = location;
      } else if (postResponse.statusCode == 200) {
        // Some Apps Script deployments skip the redirect and return JSON directly.
        return _parseAndValidate(postResponse.body, action, token, data, attempt);
      } else {
        throw ApiException.fromStatusCode(postResponse.statusCode);
      }

      // ── Step 2: GET the echo URL — returns the actual JSON response ──────
      final getResponse = await _client
          .get(Uri.parse(echoUrl))
          .timeout(_timeout);

      if (getResponse.statusCode != 200) {
        throw ApiException.fromStatusCode(getResponse.statusCode);
      }

      return _parseAndValidate(getResponse.body, action, token, data, attempt);

    } on ApiException {
      rethrow;
    } on SocketException {
      throw const ApiException('No internet connection. Check your network.');
    } on HttpException {
      throw const ApiException('Network error. Please try again.');
    } on FormatException {
      throw const ApiException('Invalid response from server.');
    } catch (e) {
      throw ApiException('Unexpected error: $e');
    }
  }

  /// Parse the JSON body, handle LOCK_TIMEOUT retry, and throw on error.
  Future<Map<String, dynamic>> _parseAndValidate(
    String responseBody,
    String action,
    String? token,
    Map<String, dynamic>? data,
    int attempt,
  ) async {
    final json = jsonDecode(responseBody) as Map<String, dynamic>;

    // Retry transparently on LOCK_TIMEOUT (server busy acquiring script lock).
    if (json['success'] != true &&
        json['error_code'] == _lockTimeoutErrorCode &&
        attempt < _maxRetries) {
      await Future<void>.delayed(Duration(seconds: attempt * 2));
      return post(action: action, token: token, data: data, attempt: attempt + 1);
    }

    if (json['success'] != true) {
      final errorCode = json['error_code']?.toString();
      final message = json['error']?.toString() ?? 'Unknown server error';
      throw ApiException(message, errorCode: errorCode);
    }

    return json;
  }
}
