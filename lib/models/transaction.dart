
import 'package:kasir_kutacane/models/transactionItem.dart';

class Transaction {
  String id;
  String customerName;
  DateTime date;
  String alamat;
  List<TransactionItem> items;
  double total;

  Transaction({
    required this.id,
    required this.customerName,
    required this.date,
    required this.alamat,
    required this.items,
    required this.total,
  });
}