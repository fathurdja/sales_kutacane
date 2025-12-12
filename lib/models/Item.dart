class Item {
  final String name;
  final double price;

  Item({required this.name, required this.price});
   factory Item.fromJson(Map<String, dynamic> json) {
    return Item(
      name: json['NTYUNIT'] ?? '',
      price: double.tryParse(json['hjual'].toString()) ?? 0.0,
    );
  }
}
