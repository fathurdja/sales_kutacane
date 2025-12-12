import 'package:flutter/material.dart';
import 'package:kasir_kutacane/models/Item.dart';

class TransactionItem {
  final TextEditingController nameController;
  final TextEditingController priceController;
  final TextEditingController qtyController;
  final TextEditingController bonusController;

  TransactionItem()
    : nameController = TextEditingController(),
      priceController = TextEditingController(),
      qtyController = TextEditingController(),
      bonusController = TextEditingController();

  TransactionItem.fromData({
    required String name,
    required double price,
    required int quantity,
    required int bonus,
  }) : nameController = TextEditingController(text: name),
       priceController = TextEditingController(text: price.toString()),
       qtyController = TextEditingController(text: quantity.toString()),
       bonusController = TextEditingController(text: bonus.toString());

  String get name => nameController.text;
  double get price => double.tryParse(priceController.text) ?? 0.0;
  int get quantity => int.tryParse(qtyController.text) ?? 0;
  double get subtotal => price * quantity;
  int get bonus => int.tryParse(bonusController.text) ?? 0;
  Item? selectedItem;

  void dispose() {
    nameController.dispose();
    priceController.dispose();
    qtyController.dispose();
    bonusController.dispose();
  }

  factory TransactionItem.fromJson(Map<String, dynamic> json) {
    return TransactionItem.fromData(
      name: json['name'],
      price: (json['price'] as num).toDouble(),
      quantity: json['quantity'] as int,
      bonus: json['bonus'] as int,
    );
  }
}
