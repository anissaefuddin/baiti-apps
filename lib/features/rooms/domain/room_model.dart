import 'package:intl/intl.dart';

// ── Status enum ───────────────────────────────────────────────────────────────

enum RoomStatus { available, unavailable }

extension RoomStatusX on RoomStatus {
  String get value => switch (this) {
        RoomStatus.available => 'available',
        RoomStatus.unavailable => 'unavailable',
      };

  String get label => switch (this) {
        RoomStatus.available => 'Tersedia',
        RoomStatus.unavailable => 'Tidak Tersedia',
      };

  static RoomStatus fromString(String? s) => switch (s) {
        'unavailable' => RoomStatus.unavailable,
        _ => RoomStatus.available,
      };
}

// ── Model ─────────────────────────────────────────────────────────────────────

/// Mirrors the `rooms` sheet schema defined in project.me.
class RoomModel {
  const RoomModel({
    required this.id,
    required this.name,
    required this.pricePerNight,
    required this.capacity,
    required this.description,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final double pricePerNight;
  final int capacity;
  final String description;
  final RoomStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isAvailable => status == RoomStatus.available;

  /// Formatted as "Rp 150.000" using Indonesian locale.
  String get formattedPrice {
    return NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    ).format(pricePerNight);
  }

  factory RoomModel.fromJson(Map<String, dynamic> json) {
    return RoomModel(
      id: json['id'] as String,
      name: json['name'] as String,
      pricePerNight: (json['price_per_night'] as num).toDouble(),
      capacity: (json['capacity'] as num).toInt(),
      description: json['description'] as String? ?? '',
      status: RoomStatusX.fromString(json['status'] as String?),
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price_per_night': pricePerNight,
        'capacity': capacity,
        'description': description,
        'status': status.value,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  RoomModel copyWith({
    String? id,
    String? name,
    double? pricePerNight,
    int? capacity,
    String? description,
    RoomStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RoomModel(
      id: id ?? this.id,
      name: name ?? this.name,
      pricePerNight: pricePerNight ?? this.pricePerNight,
      capacity: capacity ?? this.capacity,
      description: description ?? this.description,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
