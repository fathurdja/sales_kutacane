import 'package:flutter/material.dart';

class TransactionItem {
  final TextEditingController nameController;
  final TextEditingController priceController;
  final TextEditingController qtyController;

  TransactionItem()
      : nameController = TextEditingController(),
        priceController = TextEditingController(),
        qtyController = TextEditingController();

  TransactionItem.fromData({
    required String name,
    required double price,
    required int quantity,
  })  : nameController = TextEditingController(text: name),
        priceController = TextEditingController(text: price.toString()),
        qtyController = TextEditingController(text: quantity.toString());

  String get name => nameController.text;
  double get price => double.tryParse(priceController.text) ?? 0.0;
  int get quantity => int.tryParse(qtyController.text) ?? 0;
  double get subtotal => price * quantity;

  void dispose() {
    nameController.dispose();
    priceController.dispose();
    qtyController.dispose();
  }

  factory TransactionItem.fromJson(Map<String, dynamic> json) {
    return TransactionItem.fromData(
      name: json['name'],
      price: (json['price'] as num).toDouble(),
      quantity: json['quantity'] as int,
    );
  }
}
