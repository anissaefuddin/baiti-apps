/// Thrown by [ApiService] for any non-success response.
///
/// [errorCode] matches the `error_code` field returned by the Apps Script
/// backend (e.g. 'UNAUTHORIZED', 'LOCK_TIMEOUT', 'CONFLICT').
/// [statusCode] is only set for real HTTP-level errors (non-200 responses).
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.errorCode});

  final String message;
  final int? statusCode;   // HTTP status — only for infrastructure errors
  final String? errorCode; // Apps Script error_code from JSON body

  factory ApiException.fromStatusCode(int code) {
    return switch (code) {
      401 => const ApiException('Authentication failed.', statusCode: 401),
      403 => const ApiException('Access denied.', statusCode: 403),
      500 => const ApiException('Server error. Please try again later.', statusCode: 500),
      _ => ApiException('Unexpected HTTP error ($code).', statusCode: code),
    };
  }

  // Checks against Apps Script error_code values (see apps-script/utils.js ERROR_CODE).
  bool get isUnauthorized  => errorCode == 'UNAUTHORIZED'  || statusCode == 401;
  bool get isLockTimeout   => errorCode == 'LOCK_TIMEOUT';
  bool get isConflict      => errorCode == 'CONFLICT';
  bool get isNotFound      => errorCode == 'NOT_FOUND';
  bool get isValidation    => errorCode == 'VALIDATION';

  @override
  String toString() => 'ApiException(code=$errorCode, http=$statusCode): $message';
}
