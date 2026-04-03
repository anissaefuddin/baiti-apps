import 'dart:convert';

/// Mirrors the `users` sheet schema defined in project.me.
class UserModel {
  const UserModel({
    required this.id,
    required this.googleId,
    required this.email,
    required this.name,
    required this.role,
    required this.createdAt,
  });

  final String id;
  final String googleId;
  final String email;
  final String name;
  final String role; // 'admin' | 'staff'
  final DateTime createdAt;

  bool get isAdmin => role == 'admin';

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      googleId: json['google_id'] as String,
      email: json['email'] as String,
      name: json['name'] as String,
      role: json['role'] as String? ?? 'staff',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'google_id': googleId,
        'email': email,
        'name': name,
        'role': role,
        'created_at': createdAt.toIso8601String(),
      };

  String toJsonString() => jsonEncode(toJson());

  factory UserModel.fromJsonString(String str) =>
      UserModel.fromJson(jsonDecode(str) as Map<String, dynamic>);

  UserModel copyWith({
    String? id,
    String? googleId,
    String? email,
    String? name,
    String? role,
    DateTime? createdAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      googleId: googleId ?? this.googleId,
      email: email ?? this.email,
      name: name ?? this.name,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
