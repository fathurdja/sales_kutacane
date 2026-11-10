import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PelunasanRecord {
  final String idTransaksi;
  final String customerName;
  final double total;
  final DateTime tanggalPelunasan;
  final DateTime settledAt;

  PelunasanRecord({
    required this.idTransaksi,
    required this.customerName,
    required this.total,
    required this.tanggalPelunasan,
    required this.settledAt,
  });

  factory PelunasanRecord.fromJson(Map<String, dynamic> json) {
    return PelunasanRecord(
      idTransaksi: json['id_transaksi']?.toString() ?? '',
      customerName: json['customer_name']?.toString() ?? '',
      total: (json['total'] is num)
          ? (json['total'] as num).toDouble()
          : (double.tryParse(json['total']?.toString() ?? '0') ?? 0.0),
      tanggalPelunasan: DateTime.tryParse(json['tanggal_pelunasan']?.toString() ?? '') ??
          DateTime.now(),
      settledAt: DateTime.tryParse(json['settled_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id_transaksi': idTransaksi,
      'customer_name': customerName,
      'total': total,
      'tanggal_pelunasan': DateFormat('yyyy-MM-dd').format(tanggalPelunasan),
      'settled_at': settledAt.toIso8601String(),
    };
  }
}

/// Model untuk mencatat setiap transaksi pembayaran (baik cicilan sebagian maupun lunas penuh)
class PelunasanPayment {
  final String id;
  final String customerName;
  final String? idTransaksi; // Opsional jika pembayaran mencakup beberapa nota sekaligus
  final double nominalBayar;
  final double sisaBon;
  final DateTime tanggalPelunasan;
  final DateTime settledAt;
  final String? catatan;
  final bool isLunas;

  PelunasanPayment({
    required this.id,
    required this.customerName,
    this.idTransaksi,
    required this.nominalBayar,
    required this.sisaBon,
    required this.tanggalPelunasan,
    required this.settledAt,
    this.catatan,
    this.isLunas = false,
  });

  factory PelunasanPayment.fromJson(Map<String, dynamic> json) {
    return PelunasanPayment(
      id: json['id']?.toString() ?? '',
      customerName: json['customer_name']?.toString() ?? '',
      idTransaksi: json['id_transaksi']?.toString(),
      nominalBayar: (json['nominal_bayar'] is num)
          ? (json['nominal_bayar'] as num).toDouble()
          : (double.tryParse(json['nominal_bayar']?.toString() ?? '0') ?? 0.0),
      sisaBon: (json['sisa_bon'] is num)
          ? (json['sisa_bon'] as num).toDouble()
          : (double.tryParse(json['sisa_bon']?.toString() ?? '0') ?? 0.0),
      tanggalPelunasan: DateTime.tryParse(json['tanggal_pelunasan']?.toString() ?? '') ??
          DateTime.now(),
      settledAt: DateTime.tryParse(json['settled_at']?.toString() ?? '') ??
          DateTime.now(),
      catatan: json['catatan']?.toString(),
      isLunas: json['is_lunas'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customer_name': customerName,
      'id_transaksi': idTransaksi,
      'nominal_bayar': nominalBayar,
      'sisa_bon': sisaBon,
      'tanggal_pelunasan': DateFormat('yyyy-MM-dd').format(tanggalPelunasan),
      'settled_at': settledAt.toIso8601String(),
      'catatan': catatan,
      'is_lunas': isLunas,
    };
  }
}

class PelunasanHistoryService {
  static const String _fileName = 'pelunasan_history.json';
  static const String _paymentsFileName = 'pelunasan_payments.json';

  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<File> _getPaymentsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_paymentsFileName');
  }

  /// Memuat semua riwayat pelunasan dari penyimpanan lokal HP
  static Future<Map<String, PelunasanRecord>> loadHistory() async {
    final Map<String, PelunasanRecord> map = {};

    // 1. Baca dari file lokal HP
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final Map<String, dynamic> decoded = jsonDecode(content);
          for (final entry in decoded.entries) {
            map[entry.key] = PelunasanRecord.fromJson(entry.value as Map<String, dynamic>);
          }
        }
      }
    } catch (e) {
      debugPrint('Error reading pelunasan_history.json: $e');
    }

    // 2. Sinkronkan juga dari Supabase jika ada
    try {
      final supabase = Supabase.instance.client;
      final res = await supabase
          .from('transaksi')
          .select('id_transaksi, customer_name, total, tanggal_pelunasan')
          .eq('status', 'LUNAS')
          .not('tanggal_pelunasan', 'is', null);

      if (res.isNotEmpty) {
        bool changed = false;
        for (final row in res) {
          final idTrx = row['id_transaksi']?.toString() ?? '';
          if (idTrx.isNotEmpty && !map.containsKey(idTrx)) {
            final tglPelunasanStr = row['tanggal_pelunasan']?.toString();
            if (tglPelunasanStr != null && tglPelunasanStr.isNotEmpty) {
              final rec = PelunasanRecord(
                idTransaksi: idTrx,
                customerName: row['customer_name']?.toString() ?? '',
                total: (row['total'] is num)
                    ? (row['total'] as num).toDouble()
                    : (double.tryParse(row['total']?.toString() ?? '0') ?? 0.0),
                tanggalPelunasan: DateTime.tryParse(tglPelunasanStr) ?? DateTime.now(),
                settledAt: DateTime.now(),
              );
              map[idTrx] = rec;
              changed = true;
            }
          }
        }
        if (changed) {
          await _saveMap(map);
        }
      }
    } catch (e) {
      debugPrint('Catatan: Supabase fetch pelunasan history: $e');
    }

    return map;
  }

  /// Menyimpan riwayat pelunasan baru (penuh)
  static Future<void> recordSettlement({
    required String idTransaksi,
    required String customerName,
    required double total,
    required DateTime tanggalPelunasan,
  }) async {
    final map = await loadHistory();
    map[idTransaksi] = PelunasanRecord(
      idTransaksi: idTransaksi,
      customerName: customerName,
      total: total,
      tanggalPelunasan: tanggalPelunasan,
      settledAt: DateTime.now(),
    );
    await _saveMap(map);

    // Sekaligus catat ke riwayat pembayaran
    await recordPayment(
      customerName: customerName,
      idTransaksi: idTransaksi,
      nominalBayar: total,
      sisaBon: 0.0,
      tanggalPelunasan: tanggalPelunasan,
      isLunas: true,
      catatan: 'Pelunasan Penuh Nota $idTransaksi',
    );
  }

  /// Menghapus riwayat pelunasan jika nota diubah kembali ke BON/QRIS atau transaksi dihapus
  static Future<void> removeSettlement(String idTransaksi) async {
    final map = await loadHistory();
    if (map.containsKey(idTransaksi)) {
      map.remove(idTransaksi);
      await _saveMap(map);
    }
  }

  static Future<void> _saveMap(Map<String, PelunasanRecord> map) async {
    try {
      final file = await _getFile();
      final data = map.map((k, v) => MapEntry(k, v.toJson()));
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('Error writing pelunasan_history.json: $e');
    }
  }

  // ===========================================================================
  // RIWAYAT PEMBAYARAN CICILAN / SEBAGIAN (PARTIAL PAYMENTS)
  // ===========================================================================

  /// Memuat semua daftar pembayaran sebagian maupun lunas
  static Future<List<PelunasanPayment>> loadPaymentHistory() async {
    final List<PelunasanPayment> list = [];
    try {
      final file = await _getPaymentsFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final List<dynamic> decoded = jsonDecode(content);
          for (final item in decoded) {
            list.add(PelunasanPayment.fromJson(item as Map<String, dynamic>));
          }
        }
      }
    } catch (e) {
      debugPrint('Error reading pelunasan_payments.json: $e');
    }

    // Urutkan dari pembayaran terbaru
    list.sort((a, b) => b.tanggalPelunasan.compareTo(a.tanggalPelunasan));
    return list;
  }

  /// Mencatat pembayaran (sebagian atau penuh) untuk pelanggan atau nota
  static Future<PelunasanPayment> recordPayment({
    required String customerName,
    String? idTransaksi,
    required double nominalBayar,
    required double sisaBon,
    required DateTime tanggalPelunasan,
    String? catatan,
    bool isLunas = false,
  }) async {
    final payments = await loadPaymentHistory();
    final payment = PelunasanPayment(
      id: 'PAY-${DateTime.now().millisecondsSinceEpoch}',
      customerName: customerName,
      idTransaksi: idTransaksi,
      nominalBayar: nominalBayar,
      sisaBon: sisaBon,
      tanggalPelunasan: tanggalPelunasan,
      settledAt: DateTime.now(),
      catatan: catatan,
      isLunas: isLunas,
    );

    payments.insert(0, payment);
    await _savePayments(payments);
    return payment;
  }

  /// Mengambil seluruh riwayat pembayaran untuk satu nama pelanggan tertentu
  static Future<List<PelunasanPayment>> getPaymentsForCustomer(String customerName) async {
    final norm = customerName.trim().toLowerCase();
    final all = await loadPaymentHistory();
    return all.where((p) => p.customerName.trim().toLowerCase() == norm).toList();
  }

  /// Mengambil total akumulasi pembayaran cicilan yang pernah disetor oleh pelanggan
  static Future<double> getTotalPaidForCustomer(String customerName) async {
    final payments = await getPaymentsForCustomer(customerName);
    return payments.fold<double>(0.0, (double sum, p) => sum + p.nominalBayar);
  }

  /// Mengambil seluruh riwayat pembayaran untuk satu No Nota transaksi spesifik
  static Future<List<PelunasanPayment>> getPaymentsForTransaction(String idTransaksi) async {
    final all = await loadPaymentHistory();
    return all.where((p) => p.idTransaksi == idTransaksi).toList();
  }

  /// Mengambil total cicilan yang pernah dibayar untuk satu No Nota spesifik
  static Future<double> getTotalPaidForTransaction(String idTransaksi) async {
    final payments = await getPaymentsForTransaction(idTransaksi);
    return payments.fold<double>(0.0, (double sum, p) => sum + p.nominalBayar);
  }

  static Future<void> _savePayments(List<PelunasanPayment> payments) async {
    try {
      final file = await _getPaymentsFile();
      final data = payments.map((p) => p.toJson()).toList();
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('Error writing pelunasan_payments.json: $e');
    }
  }
}
