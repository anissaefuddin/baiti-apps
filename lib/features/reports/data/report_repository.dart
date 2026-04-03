import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/api_service.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/report_model.dart';

final reportRepositoryProvider = Provider<ReportRepository>((ref) {
  return ReportRepository(
    api:  ref.watch(apiServiceProvider),
    auth: ref.watch(authRepositoryProvider),
  );
});

class ReportRepository {
  ReportRepository({required ApiService api, required AuthRepository auth})
      : _api = api,
        _auth = auth;

  final ApiService _api;
  final AuthRepository _auth;

  Future<String> _freshToken() async {
    final token = await _auth.getFreshToken();
    if (token == null) {
      throw const ApiException(
        'Sesi berakhir. Silakan masuk kembali.',
        errorCode: 'UNAUTHORIZED',
      );
    }
    return token;
  }

  Future<ReportSummary> summary({
    required ReportPeriod period,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final response = await _api.post(
      action: 'reports.summary',
      token:  await _freshToken(),
      data: {
        'period': period.value,
        if (period == ReportPeriod.custom && dateFrom != null)
          'date_from': _fmtDate(dateFrom),
        if (period == ReportPeriod.custom && dateTo != null)
          'date_to': _fmtDate(dateTo),
      },
    );
    return ReportSummary.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<ExportResult> export({
    required ReportPeriod period,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final response = await _api.post(
      action: 'reports.export',
      token:  await _freshToken(),
      data: {
        'period': period.value,
        if (period == ReportPeriod.custom && dateFrom != null)
          'date_from': _fmtDate(dateFrom),
        if (period == ReportPeriod.custom && dateTo != null)
          'date_to': _fmtDate(dateTo),
      },
    );
    return ExportResult.fromJson(response['data'] as Map<String, dynamic>);
  }

  static String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
