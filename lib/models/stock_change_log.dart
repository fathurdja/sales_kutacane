class StockChangeLog {
  final String id;
  final DateTime timestamp;
  final String kelompok; // GALON, BOTOL_600, BOTOL_1500, GELAS
  final String displayName;
  final String unitName;
  final String jenisAksi; // 'TAMBAH_PASOKAN', 'SET_STOK_AWAL', 'RESET_TERJUAL'
  final int stokAwalSebelum;
  final int tambahanQty;
  final int stokAwalSesudah;
  final int sisaSebelum;
  final int sisaSesudah;
  final int totalTerjualSaatIni;
  final String userName;
  final String? keterangan;

  StockChangeLog({
    required this.id,
    required this.timestamp,
    required this.kelompok,
    required this.displayName,
    required this.unitName,
    required this.jenisAksi,
    required this.stokAwalSebelum,
    required this.tambahanQty,
    required this.stokAwalSesudah,
    required this.sisaSebelum,
    required this.sisaSesudah,
    required this.totalTerjualSaatIni,
    required this.userName,
    this.keterangan,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'kelompok': kelompok,
      'display_name': displayName,
      'unit_name': unitName,
      'jenis_aksi': jenisAksi,
      'stok_awal_sebelum': stokAwalSebelum,
      'tambahan_qty': tambahanQty,
      'stok_awal_sesudah': stokAwalSesudah,
      'sisa_sebelum': sisaSebelum,
      'sisa_sesudah': sisaSesudah,
      'total_terjual_saat_ini': totalTerjualSaatIni,
      'user_name': userName,
      'keterangan': keterangan,
    };
  }

  factory StockChangeLog.fromJson(Map<String, dynamic> json) {
    return StockChangeLog(
      id: json['id']?.toString() ?? '',
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
      kelompok: json['kelompok']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? '',
      unitName: json['unit_name']?.toString() ?? 'Unit',
      jenisAksi: json['jenis_aksi']?.toString() ?? 'TAMBAH_PASOKAN',
      stokAwalSebelum: (json['stok_awal_sebelum'] is num) ? (json['stok_awal_sebelum'] as num).toInt() : (int.tryParse(json['stok_awal_sebelum']?.toString() ?? '0') ?? 0),
      tambahanQty: (json['tambahan_qty'] is num) ? (json['tambahan_qty'] as num).toInt() : (int.tryParse(json['tambahan_qty']?.toString() ?? '0') ?? 0),
      stokAwalSesudah: (json['stok_awal_sesudah'] is num) ? (json['stok_awal_sesudah'] as num).toInt() : (int.tryParse(json['stok_awal_sesudah']?.toString() ?? '0') ?? 0),
      sisaSebelum: (json['sisa_sebelum'] is num) ? (json['sisa_sebelum'] as num).toInt() : (int.tryParse(json['sisa_sebelum']?.toString() ?? '0') ?? 0),
      sisaSesudah: (json['sisa_sesudah'] is num) ? (json['sisa_sesudah'] as num).toInt() : (int.tryParse(json['sisa_sesudah']?.toString() ?? '0') ?? 0),
      totalTerjualSaatIni: (json['total_terjual_saat_ini'] is num) ? (json['total_terjual_saat_ini'] as num).toInt() : (int.tryParse(json['total_terjual_saat_ini']?.toString() ?? '0') ?? 0),
      userName: json['user_name']?.toString() ?? 'Admin',
      keterangan: json['keterangan']?.toString(),
    );
  }
}

