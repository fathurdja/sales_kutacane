class UserModel {
  final int id;
  final String name;
  final String username;
  final String email;
  final String role;
  final bool isAdmin;
  final bool canManageStock;
  final int totalTransaksi;
  final double totalOmset;

  UserModel({
    required this.id,
    required this.name,
    required this.username,
    required this.email,
    required this.role,
    required this.isAdmin,
    required this.canManageStock,
    this.totalTransaksi = 0,
    this.totalOmset = 0.0,
  });

  bool get isUserAdmin => isAdmin || role.toLowerCase() == 'admin';

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final rawTotalTrx = json['total_transaksi'] ?? json['totalTransaksi'];
    final int parsedTrx = (rawTotalTrx is num)
        ? rawTotalTrx.toInt()
        : (int.tryParse(rawTotalTrx?.toString() ?? '0') ?? 0);

    final rawOmset = json['total_omset'] ?? json['totalOmset'];
    final double parsedOmset = (rawOmset is num)
        ? rawOmset.toDouble()
        : (double.tryParse(rawOmset?.toString() ?? '0') ?? 0.0);

    final String roleStr = json['role']?.toString().toLowerCase() ?? 'user';
    final bool adminFlag = json['is_admin'] == true || roleStr == 'admin';
    final bool manageStockFlag =
        json['can_manage_stock'] == true || adminFlag;

    return UserModel(
      id: (json['id'] is num)
          ? (json['id'] as num).toInt()
          : (int.tryParse(json['id']?.toString() ?? '0') ?? 0),
      name: json['name']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: roleStr,
      isAdmin: adminFlag,
      canManageStock: manageStockFlag,
      totalTransaksi: parsedTrx,
      totalOmset: parsedOmset,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'username': username,
      'email': email,
      'role': role,
      'is_admin': isAdmin,
      'can_manage_stock': canManageStock,
      'total_transaksi': totalTransaksi,
      'total_omset': totalOmset,
    };
  }
}
