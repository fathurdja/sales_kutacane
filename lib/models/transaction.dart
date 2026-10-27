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
  DateTime? tanggalPelunasan;
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
    this.tanggalPelunasan,
    this.isOffline = false,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    final rawTotal = json['total'];
    final double parsedTotal = (rawTotal is num)
        ? rawTotal.toDouble()
        : (double.tryParse(rawTotal?.toString() ?? '0') ?? 0.0);

    DateTime? parsedPelunasan;
    if (json['tanggal_pelunasan'] != null &&
        json['tanggal_pelunasan'].toString().isNotEmpty &&
        json['tanggal_pelunasan'].toString() != 'null') {
      parsedPelunasan =
          DateTime.tryParse(json['tanggal_pelunasan'].toString())?.toLocal();
    }

    final rawDateStr =
        json['tanggal']?.toString() ?? json['date']?.toString() ?? '';
    final parsedDate = (DateTime.tryParse(rawDateStr) ?? DateTime.now()).toLocal();

    return Transaction(
      id: (json['id'] != null && json['id'].toString().isNotEmpty)
          ? json['id'].toString()
          : (json['id_transaksi']?.toString() ?? ''),
      id_transaksi: json['id_transaksi']?.toString() ??
          json['id']?.toString() ??
          '',
      customerName: json['customer_name']?.toString() ??
          json['customerName']?.toString() ??
          '',
      alamat: json['alamat']?.toString() ?? '',
      date: parsedDate,
      total: parsedTotal,
      status: json['status']?.toString() ?? 'LUNAS',
      tanggalPelunasan: parsedPelunasan,
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
      'tanggal_pelunasan': tanggalPelunasan != null
          ? DateFormat('yyyy-MM-dd').format(tanggalPelunasan!)
          : null,
      'items': items.map((i) => i.toJson()).toList(),
    };
  }
}
