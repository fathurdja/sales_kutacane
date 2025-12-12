import 'package:kasir_kutacane/models/transactionItem.dart';

class Transaction {
  String id;
  String id_transaksi;
  String customerName;
  DateTime date;
  String alamat;
  List<TransactionItem> items;
  double total;
  String status;

  Transaction({
    required this.id,
    required this.id_transaksi,
    required this.customerName,
    required this.date,
    required this.alamat,
    required this.items,
    required this.total,
    required this.status,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id_transaksi: json['id_transaksi'] ?? "",
      customerName: json['customerName'] ?? "",
      alamat: json['alamat'] ?? "",
      date: DateTime.tryParse(json['date'].toString()) ?? DateTime.now(),
      status: json['status'] ?? "",
      total: double.tryParse(json['total']?.toString() ?? "0") ?? 0,
      id: json['id']?.toString() ?? "",
      items:
          (json['items'] as List)
              .map((e) => TransactionItem.fromJson(e))
              .toList(),
    );
  }
}
