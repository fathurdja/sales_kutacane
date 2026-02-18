class Product {
  final String tyunit;
  final String name;
  final double price;

  Product({
    required this.tyunit,
    required this.name,
    required this.price,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      tyunit: json['TYUNIT'] ?? '',
      name: json['NTYUNIT'] ?? '',
      price: (json['hjual'] as num).toDouble(),
    );
  }
}
