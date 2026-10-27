import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/config/api_config.dart';
import 'package:kasir_kutacane/models/Item.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/services/auth_service.dart';
import 'package:path_provider/path_provider.dart';

class SyncResult {
  final int total;
  final int success;
  final int failed;
  final List<String> errors;

  SyncResult({
    required this.total,
    required this.success,
    required this.failed,
    required this.errors,
  });

  bool get isAllSuccess => total > 0 && success == total;
}

class OfflineSyncService {
  static const String _queueFileName = 'offline_transactions_queue.json';
  static const String _productsCacheFileName = 'cached_master_products.json';
  static String get _apiUrl => '${ApiConfig.baseUrl}/transaksi';

  /// Mendapatkan file direktori dokumen lokal aplikasi
  static Future<File> _getLocalFile(String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/$fileName';
    return File(filePath);
  }

  // ========================================================
  // 1. MANAJEMEN ANTREAN TRANSAKSI OFFLINE
  // ========================================================

  /// Menyimpan transaksi ke penyimpanan lokal smartphone
  static Future<void> saveOfflineTransaction(Transaction transaction) async {
    try {
      final file = await _getLocalFile(_queueFileName);
      List<dynamic> queue = [];

      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          queue = jsonDecode(content);
        }
      }

      // Hindari duplikasi jika ID transaksi sudah ada di antrean
      queue.removeWhere((item) =>
          item['id_transaksi'] == transaction.id_transaksi);

      final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
      final transactionJson = {
        'id': transaction.id.isNotEmpty ? transaction.id : transaction.id_transaksi,
        'id_transaksi': transaction.id_transaksi,
        'customerName': transaction.customerName,
        'customer_name': transaction.customerName,
        'alamat': transaction.alamat,
        'date': dateFormat.format(transaction.date),
        'tanggal': transaction.date.toIso8601String(),
        'total': transaction.total,
        'status': transaction.status,
        'is_offline': true,
        'saved_at': DateTime.now().toIso8601String(),
        'items': transaction.items.map((item) {
          final price = item.price.truncateToDouble() == item.price
              ? item.price.toInt()
              : item.price;
          final subtotal = item.subtotal.truncateToDouble() == item.subtotal
              ? item.subtotal.toInt()
              : item.subtotal;
          return {
            'tyunit': item.tyunit ?? 'BV01',
            'name': item.nameController.text,
            'nama_barang': item.nameController.text,
            'price': price,
            'harga': price,
            'quantity': item.quantity,
            'bonus': item.bonus,
            'subtotal': subtotal,
          };
        }).toList(),
      };

      queue.add(transactionJson);
      await file.writeAsString(jsonEncode(queue));
      debugPrint('Berhasil simpan offline: ${transaction.id_transaksi}');
    } catch (e) {
      debugPrint('Gagal simpan offline ke file lokal: $e');
      rethrow;
    }
  }

  /// Membaca daftar seluruh transaksi offline yang belum tersinkronkan
  static Future<List<Transaction>> getPendingTransactions() async {
    try {
      final file = await _getLocalFile(_queueFileName);
      if (!await file.exists()) return [];

      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];

      final List<dynamic> data = jsonDecode(content);
      return data
          .map<Transaction>(
            (json) => Transaction.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } catch (e) {
      debugPrint('Gagal membaca antrean offline: $e');
      return [];
    }
  }

  /// Menghitung jumlah nota yang masih tersimpan secara offline
  static Future<int> getPendingCount() async {
    final pending = await getPendingTransactions();
    return pending.length;
  }

  /// Menghapus nota tertentu dari antrean offline (misal setelah sukses sync)
  static Future<void> removePendingTransaction(String idTransaksi) async {
    try {
      final file = await _getLocalFile(_queueFileName);
      if (!await file.exists()) return;

      final content = await file.readAsString();
      if (content.trim().isEmpty) return;

      List<dynamic> queue = jsonDecode(content);
      queue.removeWhere((item) => item['id_transaksi'] == idTransaksi);
      await file.writeAsString(jsonEncode(queue));
    } catch (e) {
      debugPrint('Gagal menghapus item antrean offline: $e');
    }
  }

  /// Menghapus seluruh antrean offline
  static Future<void> clearQueue() async {
    try {
      final file = await _getLocalFile(_queueFileName);
      if (await file.exists()) {
        await file.writeAsString(jsonEncode([]));
      }
    } catch (e) {
      debugPrint('Gagal membersihkan antrean: $e');
    }
  }

  // ========================================================
  // 2. SINKRONISASI KE SERVER UTAMA (LARAVEL API)
  // ========================================================

  /// Menyinkronkan seluruh transaksi offline ke server saat online
  static Future<SyncResult> syncPendingTransactions() async {
    final pendingList = await getPendingTransactions();
    if (pendingList.isEmpty) {
      return SyncResult(total: 0, success: 0, failed: 0, errors: []);
    }

    int successCount = 0;
    int failedCount = 0;
    List<String> errors = [];

    for (final trx in pendingList) {
      try {
        final formattedDate =
            DateFormat('yyyy-MM-dd HH:mm:ss').format(trx.date);

        final payload = {
          'id_transaksi': trx.id_transaksi,
          'customerName': trx.customerName,
          'alamat': trx.alamat,
          'date': formattedDate,
          'total': trx.total.truncateToDouble() == trx.total
              ? trx.total.toInt()
              : trx.total,
          'status': trx.status,
          'items': trx.items.map((item) {
            final tyunit = (item.tyunit != null && item.tyunit!.isNotEmpty)
                ? item.tyunit
                : 'BV01';
            final price = item.price.truncateToDouble() == item.price
                ? item.price.toInt()
                : item.price;
            final subtotal = item.subtotal.truncateToDouble() == item.subtotal
                ? item.subtotal.toInt()
                : item.subtotal;
            return {
              'tyunit': tyunit,
              'price': price,
              'quantity': item.quantity,
              'bonus': item.bonus,
              'subtotal': subtotal,
            };
          }).toList(),
        };

        final headers = await AuthService.getAuthHeaders();
        final response = await http
            .post(
              Uri.parse(_apiUrl),
              headers: headers,
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200 || response.statusCode == 201) {
          // Berhasil dikirim ke server -> hapus dari antrean offline
          await removePendingTransaction(trx.id_transaksi);
          successCount++;
        } else {
          failedCount++;
          String msg = 'Gagal sync ${trx.id_transaksi} (${response.statusCode})';
          try {
            final errBody = jsonDecode(response.body);
            if (errBody is Map && errBody.containsKey('message')) {
              msg = '${trx.id_transaksi}: ${errBody['message']}';
            }
          } catch (_) {}
          errors.add(msg);
        }
      } catch (e) {
        failedCount++;
        errors.add('${trx.id_transaksi}: $e');
      }
    }

    return SyncResult(
      total: pendingList.length,
      success: successCount,
      failed: failedCount,
      errors: errors,
    );
  }

  // ========================================================
  // 3. CACHE PRODUK LOKAL (Agar kasir tetap bisa pilih produk)
  // ========================================================

  /// Menyimpan cache master stock lokal agar kasir tetap bisa memilih barang saat offline
  static Future<void> cacheProducts(List<Item> products) async {
    try {
      if (products.isEmpty) return;
      final file = await _getLocalFile(_productsCacheFileName);
      final jsonList = products.map((p) => p.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Gagal cache produk lokal: $e');
    }
  }

  /// Mengambil daftar produk dari cache lokal jika server sedang offline
  static Future<List<Item>> getCachedProducts() async {
    try {
      final file = await _getLocalFile(_productsCacheFileName);
      if (!await file.exists()) return _getDefaultProductsFallback();

      final content = await file.readAsString();
      if (content.trim().isEmpty) return _getDefaultProductsFallback();

      final List<dynamic> data = jsonDecode(content);
      return data
          .map<Item>((json) => Item.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Gagal baca cache produk lokal, pakai fallback: $e');
      return _getDefaultProductsFallback();
    }
  }

  /// Data bawaan 13 produk Boneva jika aplikasi benar-benar pertama kali dibuka tanpa internet
  static List<Item> _getDefaultProductsFallback() {
    return [
      Item(tyunit: 'BV01', name: 'Boneva Galon isi partai', price: 13000, stock: 100),
      Item(tyunit: 'BV02', name: 'Boneva Galon isi saja', price: 16000, stock: 100),
      Item(tyunit: 'BV03', name: 'Boneva Galon isi saja', price: 17000, stock: 100),
      Item(tyunit: 'BV04', name: 'Boneva Galon + isi Partai', price: 75000, stock: 100),
      Item(tyunit: 'BV05', name: 'Boneva Galon + isi', price: 85000, stock: 100),
      Item(tyunit: 'BV06', name: 'Boneva Botol 600 Ml', price: 37000, stock: 100),
      Item(tyunit: 'BV07', name: 'Boneva Botol 600 Ml', price: 38000, stock: 100),
      Item(tyunit: 'BV08', name: 'Boneva Botol 600 Ml', price: 40000, stock: 100),
      Item(tyunit: 'BV09', name: 'Boneva Botol 1,5 L', price: 41000, stock: 100),
      Item(tyunit: 'BV10', name: 'Boneva Botol 1,5 L', price: 43000, stock: 100),
      Item(tyunit: 'BV11', name: 'Boneva Gelas', price: 23000, stock: 100),
      Item(tyunit: 'BV12', name: 'Boneva Gelas', price: 22000, stock: 100),
      Item(tyunit: 'BV13', name: 'Boneva Gelas', price: 21000, stock: 100),
    ];
  }
}
