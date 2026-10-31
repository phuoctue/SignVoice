import 'package:json_annotation/json_annotation.dart';

part 'user_model.g.dart';

/// User roles
enum UserRole {
  @JsonValue('USER')
  user,
  @JsonValue('STAFF')
  staff,
  @JsonValue('ADMIN')
  admin,
}

/// Account types
enum AccountType {
  @JsonValue('LOCAL')
  local,
  @JsonValue('GOOGLE')
  google,
  @JsonValue('FACEBOOK')
  facebook,
  @JsonValue('GUEST')
  guest,
}

/// Account status
enum AccountStatus {
  @JsonValue('ACTIVE')
  active,
  @JsonValue('SUSPENDED')
  suspended,
  @JsonValue('DELETED')
  deleted,
}

/// User model
@JsonSerializable()
class UserModel {
  @JsonKey(name: '_id')
  final String id;

  final String? email;
  final String displayName;
  final String? avatarUrl;

  final AccountType accountType;
  final UserRole role;
  final String? customRoleId;
  final String? customRoleName;
  @JsonKey(defaultValue: [])
  final List<String> permissions;
  final AccountStatus status;

  final bool isGuest;
  @JsonKey(defaultValue: false)
  final bool googleLinked;
  final DateTime? guestConvertedAt;

  final DateTime? lastLoginAt;
  final String? lastLoginIp;

  final DateTime createdAt;
  final DateTime updatedAt;

  UserModel({
    required this.id,
    this.email,
    required this.displayName,
    this.avatarUrl,
    required this.accountType,
    required this.role,
    this.customRoleId,
    this.customRoleName,
    this.permissions = const [],
    required this.status,
    required this.isGuest,
    this.googleLinked = false,
    this.guestConvertedAt,
    this.lastLoginAt,
    this.lastLoginIp,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => _$UserModelFromJson({
    ...json,
    '_id': json['_id'] ?? json['id'],
    'updatedAt': json['updatedAt'] ?? json['createdAt'],
  });

  Map<String, dynamic> toJson() => _$UserModelToJson(this);

  /// Check if user is active
  bool get isActive => status == AccountStatus.active;

  /// Check if user is admin
  bool get isAdmin => hasPermission('admin:access');

  /// Check if user is staff
  bool get isStaff => hasPermission('staff:access') || isAdmin;

  bool hasPermission(String permission) {
    if (customRoleId != null) return permissions.contains(permission);
    if (role == UserRole.admin) return true;
    return role == UserRole.staff &&
        const [
          'staff:access',
          'dictionary:read',
          'dictionary:write',
          'content:publish',
          'categories:read',
          'categories:write',
          'collections:read',
          'collections:moderate',
        ].contains(permission);
  }

  /// Get role name
  String get roleName {
    switch (role) {
      case UserRole.user:
        return 'USER';
      case UserRole.staff:
        return 'STAFF';
      case UserRole.admin:
        return 'ADMIN';
    }
  }

  /// Copy with method
  UserModel copyWith({
    String? id,
    String? email,
    String? displayName,
    String? avatarUrl,
    AccountType? accountType,
    UserRole? role,
    String? customRoleId,
    String? customRoleName,
    List<String>? permissions,
    AccountStatus? status,
    bool? isGuest,
    bool? googleLinked,
    DateTime? guestConvertedAt,
    DateTime? lastLoginAt,
    String? lastLoginIp,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      accountType: accountType ?? this.accountType,
      role: role ?? this.role,
      customRoleId: customRoleId ?? this.customRoleId,
      customRoleName: customRoleName ?? this.customRoleName,
      permissions: permissions ?? this.permissions,
      status: status ?? this.status,
      isGuest: isGuest ?? this.isGuest,
      googleLinked: googleLinked ?? this.googleLinked,
      guestConvertedAt: guestConvertedAt ?? this.guestConvertedAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      lastLoginIp: lastLoginIp ?? this.lastLoginIp,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
