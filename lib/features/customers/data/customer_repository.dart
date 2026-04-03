import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/api_service.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/customer_model.dart';

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  return CustomerRepository(
    api: ref.watch(apiServiceProvider),
    auth: ref.watch(authRepositoryProvider),
  );
});

/// Data layer for customer CRUD operations.
class CustomerRepository {
  CustomerRepository({required ApiService api, required AuthRepository auth})
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

  List<CustomerModel> _parseList(Map<String, dynamic> response) {
    final data = response['data'];
    if (data == null) return [];
    return (data as List)
        .map((e) => CustomerModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  CustomerModel _parseSingle(Map<String, dynamic> response) {
    return CustomerModel.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<List<CustomerModel>> list() async {
    final response = await _api.post(
      action: 'customers.list',
      token: await _freshToken(),
    );
    return _parseList(response);
  }

  /// Look up a customer by their exact NIK. Throws [ApiException] with
  /// [isNotFound] == true when no match exists.
  Future<CustomerModel?> getByNik(String nik) async {
    try {
      final response = await _api.post(
        action: 'customers.getByNIK',
        token: await _freshToken(),
        data: {'nik': nik},
      );
      return _parseSingle(response);
    } on ApiException catch (e) {
      if (e.isNotFound) return null;
      rethrow;
    }
  }

  Future<CustomerModel> create({
    required String nik,
    required String name,
    String phone = '',
    String address = '',
    String birthDate = '',
  }) async {
    final response = await _api.post(
      action: 'customers.create',
      token: await _freshToken(),
      data: {
        'nik':        nik,
        'name':       name,
        'phone':      phone,
        'address':    address,
        'birth_date': birthDate,
      },
    );
    return _parseSingle(response);
  }

  Future<CustomerModel> update({
    required String id,
    String? name,
    String? phone,
    String? address,
    String? birthDate,
  }) async {
    final response = await _api.post(
      action: 'customers.update',
      token: await _freshToken(),
      data: {
        'id': id,
        if (name != null) 'name': name,
        if (phone != null) 'phone': phone,
        if (address != null) 'address': address,
        if (birthDate != null) 'birth_date': birthDate,
      },
    );
    return _parseSingle(response);
  }

  Future<void> delete(String id) async {
    await _api.post(
      action: 'customers.delete',
      token: await _freshToken(),
      data: {'id': id},
    );
  }
}
