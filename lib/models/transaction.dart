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
  int? userId;
  String? userName;

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
    this.userId,
    this.userName,
  });

  bool get isLunas => status.toUpperCase() == 'LUNAS';
  bool get isBon => status.toUpperCase() == 'BON';
  bool get isQris => status.toUpperCase() == 'QRIS';

  /// Parse string tanggal dari server secara presisi tanpa pergeseran timezone (UTC drift)
  static DateTime parseServerDate(String? raw) {
    if (raw == null || raw.isEmpty || raw == 'null') {
      return DateTime.now();
    }
    String cleaned = raw.trim();
    if (cleaned.endsWith('Z') || cleaned.endsWith('z')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    if (cleaned.length > 19 &&
        (cleaned.endsWith('+00:00') || cleaned.endsWith('+0000'))) {
      cleaned = cleaned.substring(
          0, cleaned.length - (cleaned.endsWith('+00:00') ? 6 : 5));
    }
    final dt = DateTime.tryParse(cleaned);
    if (dt != null) {
      return DateTime(
        dt.year,
        dt.month,
        dt.day,
        dt.hour,
        dt.minute,
        dt.second,
        dt.millisecond,
      );
    }
    return DateTime.tryParse(raw) ?? DateTime.now();
  }

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
          parseServerDate(json['tanggal_pelunasan'].toString());
    }

    final rawDateStr =
        json['tanggal']?.toString() ?? json['date']?.toString() ?? '';
    final parsedDate = parseServerDate(rawDateStr);

    final int? parsedUserId = json['user_id'] != null
        ? int.tryParse(json['user_id'].toString())
        : (json['user'] is Map && json['user']['id'] != null
            ? int.tryParse(json['user']['id'].toString())
            : null);

    final String? parsedUserName = json['user_name']?.toString() ??
        (json['user'] is Map ? json['user']['name']?.toString() : null);

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
      userId: parsedUserId,
      userName: parsedUserName,
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
      'user_id': userId,
      'user_name': userName,
      'items': items.map((i) => i.toJson()).toList(),
    };
  }
}
