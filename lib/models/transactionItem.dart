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
    this.tyunit,
  })  : nameController = TextEditingController(text: name),
        priceController = TextEditingController(
          text: price.truncateToDouble() == price
              ? price.toInt().toString()
              : price.toStringAsFixed(2),
        ),
        qtyController = TextEditingController(text: quantity.toString()),
        bonusController = TextEditingController(text: bonus.toString());

  String get name => nameController.text;
  double get price => double.tryParse(priceController.text) ?? 0.0;
  int get quantity => int.tryParse(qtyController.text) ?? 0;
  double get subtotal => price * quantity;
  int get bonus => int.tryParse(bonusController.text) ?? 0;
  Item? selectedItem;
  String? tyunit;

  void dispose() {
    nameController.dispose();
    priceController.dispose();
    qtyController.dispose();
    bonusController.dispose();
  }

  factory TransactionItem.fromJson(Map<String, dynamic> json) {
    final rawPrice = json['harga'] ?? json['price'];
    final double parsedPrice = (rawPrice is num)
        ? rawPrice.toDouble()
        : (double.tryParse(rawPrice?.toString() ?? '0') ?? 0.0);

    final rawQty = json['quantity'] ?? json['qty'];
    final int parsedQty = (rawQty is num)
        ? rawQty.toInt()
        : (int.tryParse(rawQty?.toString() ?? '0') ?? 0);

    final rawBonus = json['bonus'];
    final int parsedBonus = (rawBonus is num)
        ? rawBonus.toInt()
        : (int.tryParse(rawBonus?.toString() ?? '0') ?? 0);

    final String name = json['nama_barang']?.toString() ??
        json['name']?.toString() ??
        '';
    final String? tyunit = json['tyunit']?.toString();

    return TransactionItem.fromData(
      name: name,
      price: parsedPrice,
      quantity: parsedQty,
      bonus: parsedBonus,
      tyunit: tyunit,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tyunit': tyunit ?? '',
      'price': price.truncateToDouble() == price ? price.toInt() : price,
      'quantity': quantity,
      'bonus': bonus,
      'subtotal':
          subtotal.truncateToDouble() == subtotal ? subtotal.toInt() : subtotal,
    };
  }
}
