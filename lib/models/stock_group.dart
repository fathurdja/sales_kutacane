class StockVariantDetail {
  final String tyunit;
  final String namaProduk;
  final double harga;
  final int terjual;

  StockVariantDetail({
    required this.tyunit,
    required this.namaProduk,
    required this.harga,
    required this.terjual,
  });

  factory StockVariantDetail.fromJson(Map<String, dynamic> json) {
    final rawHarga = json['harga'] ?? json['hjual'] ?? json['price'];
    final double parsedHarga = (rawHarga is num)
        ? rawHarga.toDouble()
        : (double.tryParse(rawHarga?.toString() ?? '0') ?? 0.0);

    final rawTerjual = json['terjual'] ?? 0;
    final int parsedTerjual = (rawTerjual is num)
        ? rawTerjual.toInt()
        : (int.tryParse(rawTerjual?.toString() ?? '0') ?? 0);

    return StockVariantDetail(
      tyunit: json['tyunit']?.toString() ?? '',
      namaProduk: json['nama_produk']?.toString() ?? json['name']?.toString() ?? '',
      harga: parsedHarga,
      terjual: parsedTerjual,
    );
  }
}

class StockGroup {
  final String kelompok; // GALON, BOTOL_600, BOTOL_1500, GELAS
  final String displayName;
  final String unitName;
  final int stockAwal;
  final int totalTerjual;
  final int sisaStock;
  final int jumlahProduk;
  final List<StockVariantDetail> rincianProduk;

  StockGroup({
    required this.kelompok,
    required this.displayName,
    required this.unitName,
    required this.stockAwal,
    required this.totalTerjual,
    required this.sisaStock,
    required this.jumlahProduk,
    this.rincianProduk = const [],
  });

  factory StockGroup.fromJson(Map<String, dynamic> json) {
    final kelompok = json['kelompok']?.toString() ?? '';
    final rawAwal = json['stock_awal'] ?? json['kuota'] ?? 0;
    final int stockAwal = (rawAwal is num) ? rawAwal.toInt() : (int.tryParse(rawAwal.toString()) ?? 0);

    final rawTerjual = json['total_terjual'] ?? json['terjual'] ?? 0;
    final int totalTerjual = (rawTerjual is num) ? rawTerjual.toInt() : (int.tryParse(rawTerjual.toString()) ?? 0);

    final rawSisa = json['sisa_stock'] ?? json['sisa_kuota'] ?? (stockAwal - totalTerjual);
    final int sisaStock = (rawSisa is num) ? rawSisa.toInt() : (int.tryParse(rawSisa.toString()) ?? 0);

    final rawJumlah = json['jumlah_produk'] ?? (json['rincian_produk'] is List ? (json['rincian_produk'] as List).length : 0);
    final int jumlahProduk = (rawJumlah is num) ? rawJumlah.toInt() : (int.tryParse(rawJumlah.toString()) ?? 0);

    List<StockVariantDetail> rincian = [];
    if (json['rincian_produk'] is List) {
      rincian = (json['rincian_produk'] as List)
          .map((v) => StockVariantDetail.fromJson(v as Map<String, dynamic>))
          .toList();
    }

    return StockGroup(
      kelompok: kelompok,
      displayName: _getDisplayName(kelompok),
      unitName: _getUnitName(kelompok),
      stockAwal: stockAwal,
      totalTerjual: totalTerjual,
      sisaStock: sisaStock < 0 ? 0 : sisaStock,
      jumlahProduk: jumlahProduk,
      rincianProduk: rincian,
    );
  }

  static String _getDisplayName(String kelompok) {
    switch (kelompok.toUpperCase()) {
      case 'GALON':
        return 'Boneva Galon (19L)';
      case 'BOTOL_600':
        return 'Boneva Botol 600ml';
      case 'BOTOL_1500':
        return 'Boneva Botol 1.5L';
      case 'GELAS':
        return 'Boneva Gelas';
      default:
        return kelompok;
    }
  }

  static String _getUnitName(String kelompok) {
    switch (kelompok.toUpperCase()) {
      case 'GALON':
        return 'Galon';
      case 'BOTOL_600':
        return 'Dus/Btl';
      case 'BOTOL_1500':
        return 'Dus/Btl';
      case 'GELAS':
        return 'Dus';
      default:
        return 'Unit';
    }
  }

  double get persentaseTersedia {
    if (stockAwal <= 0) return 0.0;
    return (sisaStock / stockAwal).clamp(0.0, 1.0);
  }
}
