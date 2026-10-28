class Customer {
  final int id;
  final String name;
  final String alamat;
  final String? telepon;
  final String? keterangan;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Customer({
    required this.id,
    required this.name,
    this.alamat = '',
    this.telepon,
    this.keterangan,
    this.createdAt,
    this.updatedAt,
  });

  String get customerName => name;

  factory Customer.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final int parsedId = (rawId is num)
        ? rawId.toInt()
        : (int.tryParse(rawId?.toString() ?? '0') ?? 0);

    final name = json['name']?.toString() ??
        json['customer_name']?.toString() ??
        '';

    final alamat = json['alamat']?.toString() ?? '';
    final telepon = json['telepon']?.toString();
    final keterangan = json['keterangan']?.toString();

    DateTime? created;
    if (json['created_at'] != null && json['created_at'].toString().isNotEmpty) {
      created = DateTime.tryParse(json['created_at'].toString());
    }

    DateTime? updated;
    if (json['updated_at'] != null && json['updated_at'].toString().isNotEmpty) {
      updated = DateTime.tryParse(json['updated_at'].toString());
    }

    return Customer(
      id: parsedId,
      name: name,
      alamat: alamat,
      telepon: telepon,
      keterangan: keterangan,
      createdAt: created,
      updatedAt: updated,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'customer_name': name,
      'alamat': alamat,
      'telepon': telepon,
      'keterangan': keterangan,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  Customer copyWith({
    int? id,
    String? name,
    String? alamat,
    String? telepon,
    String? keterangan,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      alamat: alamat ?? this.alamat,
      telepon: telepon ?? this.telepon,
      keterangan: keterangan ?? this.keterangan,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

