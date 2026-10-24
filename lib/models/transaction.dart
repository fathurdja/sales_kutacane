import 'package:intl/intl.dart';
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
  bool isOffline;

  Transaction({
    required this.id,
    required this.id_transaksi,
    required this.customerName,
    required this.date,
    required this.alamat,
    required this.items,
    required this.total,
    required this.status,
    this.isOffline = false,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    final rawTotal = json['total'];
    final double parsedTotal = (rawTotal is num)
        ? rawTotal.toDouble()
        : (double.tryParse(rawTotal?.toString() ?? '0') ?? 0.0);

    return Transaction(
      id: json['id']?.toString() ?? '',
      id_transaksi: json['id_transaksi']?.toString() ?? '',
      customerName: json['customer_name']?.toString() ??
          json['customerName']?.toString() ??
          '',
      alamat: json['alamat']?.toString() ?? '',
      date: DateTime.tryParse(
            json['tanggal']?.toString() ?? json['date']?.toString() ?? '',
          ) ??
          DateTime.now(),
      total: parsedTotal,
      status: json['status']?.toString() ?? 'LUNAS',
      isOffline: json['is_offline'] == true,
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => TransactionItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    return {
      'id_transaksi': id_transaksi,
      'customerName': customerName,
      'alamat': alamat,
      'date': dateFormat.format(date),
      'total': total.truncateToDouble() == total ? total.toInt() : total,
      'status': status,
      'items': items.map((i) => i.toJson()).toList(),
    };
  }
}
