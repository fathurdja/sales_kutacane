class Item {
  final String tyunit;
  final String name;
  final double price;
  final int stock;

  Item({
    required this.tyunit,
    required this.name,
    required this.price,
    this.stock = 0,
  });

  factory Item.fromJson(Map<String, dynamic> json) {
    final rawPrice = json['hjual'] ?? json['price'];
    final double parsedPrice = (rawPrice is num)
        ? rawPrice.toDouble()
        : (double.tryParse(rawPrice?.toString() ?? '0') ?? 0.0);

    final rawStock = json['stock'];
    final int parsedStock = (rawStock is num)
        ? rawStock.toInt()
        : (int.tryParse(rawStock?.toString() ?? '0') ?? 0);

    final tyunit = json['TYUNIT']?.toString() ??
        json['tyunit']?.toString() ??
        (json['id'] != null
            ? 'BV${json['id'].toString().padLeft(2, '0')}'
            : '');
    final name =
        json['NTYUNIT']?.toString() ?? json['name']?.toString() ?? '';

    return Item(
      tyunit: tyunit,
      name: name,
      price: parsedPrice,
      stock: parsedStock,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'TYUNIT': tyunit,
      'NTYUNIT': name,
      'hjual': price,
      'stock': stock,
    };
  }
}
