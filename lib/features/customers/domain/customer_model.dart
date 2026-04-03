/// Domain model for a guest/customer (Tamu).
///
/// Mirrors the `customers` sheet row structure defined in config.js.
class CustomerModel {
  const CustomerModel({
    required this.id,
    required this.nik,
    required this.name,
    required this.phone,
    required this.address,
    required this.birthDate,
    required this.ktpUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// 16-digit Nomor Induk Kependudukan (Indonesian national ID number).
  final String nik;

  final String name;
  final String phone;
  final String address;
  final String birthDate;
  final String ktpUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// NIK masked for display: show first 6 and last 4 digits only.
  /// e.g. "337406**1290**0001" → "337406••••••0001"
  String get maskedNik {
    if (nik.length != 16) return nik;
    return '${nik.substring(0, 6)}••••••${nik.substring(12)}';
  }

  factory CustomerModel.fromJson(Map<String, dynamic> json) {
    return CustomerModel(
      id:        json['id'] as String,
      nik:       json['nik'] as String,
      name:      json['name'] as String,
      phone:     (json['phone'] as String?) ?? '',
      address:   (json['address'] as String?) ?? '',
      birthDate: (json['birth_date'] as String?) ?? '',
      ktpUrl:    (json['ktp_url'] as String?) ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  CustomerModel copyWith({
    String? name,
    String? phone,
    String? address,
    String? birthDate,
    DateTime? updatedAt,
  }) {
    return CustomerModel(
      id:        id,
      nik:       nik,
      name:      name ?? this.name,
      phone:     phone ?? this.phone,
      address:   address ?? this.address,
      birthDate: birthDate ?? this.birthDate,
      ktpUrl:    ktpUrl,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
