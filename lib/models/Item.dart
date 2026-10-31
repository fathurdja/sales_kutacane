class Item {
  final String tyunit;
  final String name;
  final double price;
  final int stock;
  final String kelompok; // GALON, BOTOL_600, BOTOL_1500, GELAS
  final int kuota;
  final int terjual;
  final int sisaKuota;

  Item({
    required this.tyunit,
    required this.name,
    required this.price,
    this.stock = 0,
    this.kelompok = '',
    this.kuota = 0,
    this.terjual = 0,
    this.sisaKuota = 0,
  });

  factory Item.fromJson(Map<String, dynamic> json) {
    final rawPrice = json['hjual'] ?? json['price'] ?? json['harga'];
    final double parsedPrice = (rawPrice is num)
        ? rawPrice.toDouble()
        : (double.tryParse(rawPrice?.toString() ?? '0') ?? 0.0);

    final tyunit = json['TYUNIT']?.toString() ??
        json['tyunit']?.toString() ??
        (json['id'] != null
            ? 'BV${json['id'].toString().padLeft(2, '0')}'
            : '');
    final name =
        json['NTYUNIT']?.toString() ?? json['name']?.toString() ?? json['nama_produk']?.toString() ?? '';

    final kelompok = (json['kdklp']?.toString() ??
        json['kelompok']?.toString() ??
        _inferKelompok(tyunit.isNotEmpty ? tyunit : (json['id']?.toString() ?? ''))).toUpperCase();

    final rawStock = json['stock'];
    final int parsedStock = (rawStock is num)
        ? rawStock.toInt()
        : (int.tryParse(rawStock?.toString() ?? '0') ?? 0);

    final rawKuota = json['kuota'] ?? json['stock_awal'];
    final int parsedKuota = (rawKuota is num)
        ? rawKuota.toInt()
        : (int.tryParse(rawKuota?.toString() ?? '0') ?? 0);

    final rawTerjual = json['terjual'] ?? json['total_terjual'];
    final int parsedTerjual = (rawTerjual is num)
        ? rawTerjual.toInt()
        : (int.tryParse(rawTerjual?.toString() ?? '0') ?? 0);

    final rawSisaKuota = json['sisa_kuota'] ?? json['sisa_stock'];
    final int parsedSisaKuota = (rawSisaKuota is num)
        ? rawSisaKuota.toInt()
        : (int.tryParse(rawSisaKuota?.toString() ?? '0') ??
            (parsedKuota > 0 ? (parsedKuota - parsedTerjual).clamp(0, 999999) : 0));

    // Prioritaskan sisaKuota fisik jika ada. Jika sisaKuota 0, gunakan parsedStock atau kuota - terjual
    final int effectiveStock;
    if (parsedSisaKuota > 0) {
      effectiveStock = parsedSisaKuota;
    } else if (parsedStock > 0) {
      effectiveStock = parsedStock;
    } else if (parsedKuota > 0) {
      effectiveStock = (parsedKuota - parsedTerjual).clamp(0, 999999);
    } else {
      effectiveStock = 0;
    }

    return Item(
      tyunit: tyunit,
      name: name,
      price: parsedPrice,
      stock: effectiveStock,
      kelompok: kelompok,
      kuota: parsedKuota,
      terjual: parsedTerjual,
      sisaKuota: parsedSisaKuota,
    );
  }

  static String _inferKelompok(String codeOrId) {
    final code = codeOrId.toUpperCase();
    if (code.contains('BV01') ||
        code.contains('BV02') ||
        code.contains('BV03') ||
        code.contains('BV04') ||
        code.contains('BV05') ||
        code.contains('BV06') ||
        code.contains('BV07') ||
        code == '1' ||
        code == '2' ||
        code == '3' ||
        code == '4' ||
        code == '5' ||
        code == '6' ||
        code == '7') {
      return 'GALON';
    }
    if (code.contains('BV08') ||
        code.contains('BV09') ||
        code.contains('BV10') ||
        code.contains('BV11') ||
        code.contains('BV12') ||
        code.contains('BV13') ||
        code == '8' ||
        code == '9' ||
        code == '10' ||
        code == '11' ||
        code == '12' ||
        code == '13') {
      return 'BOTOL_600';
    }
    if (code.contains('BV14') ||
        code.contains('BV15') ||
        code.contains('BV16') ||
        code.contains('BV17') ||
        code == '14' ||
        code == '15' ||
        code == '16' ||
        code == '17') {
      return 'BOTOL_1500';
    }
    if (code.contains('BV18') ||
        code.contains('BV19') ||
        code.contains('BV20') ||
        code.contains('BV21') ||
        code.contains('BV22') ||
        code.contains('BV23') ||
        code == '18' ||
        code == '19' ||
        code == '20' ||
        code == '21' ||
        code == '22' ||
        code == '23') {
      return 'GELAS';
    }
    return '';
  }

  Map<String, dynamic> toJson() {
    return {
      'TYUNIT': tyunit,
      'NTYUNIT': name,
      'hjual': price,
      'stock': stock,
      'kdklp': kelompok,
      'kelompok': kelompok,
      'kuota': kuota,
      'terjual': terjual,
      'sisa_kuota': sisaKuota,
    };
  }
}
