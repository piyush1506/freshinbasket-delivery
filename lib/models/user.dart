class User {
  final int id;
  final String username;
  final String email;
  final String role;
  final String? phoneNumber;
  final String? address;
  final String? avatar;

  final bool isActive;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    this.phoneNumber,
    this.address,
    this.avatar,
    this.isActive = true,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? 0,
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? 'DELIVERY',
      phoneNumber: json['phone_number'],
      address: json['address'],
      avatar: json['avatar'],
      isActive: json['is_active'] ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'email': email,
    'role': role,
    'phone_number': phoneNumber,
    'address': address,
    'avatar': avatar,
    'is_active': isActive,
  };
}
