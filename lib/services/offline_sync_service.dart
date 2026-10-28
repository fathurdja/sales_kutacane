import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/config/api_config.dart';
import 'package:kasir_kutacane/models/Item.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/services/auth_service.dart';
import 'package:kasir_kutacane/services/stock_api_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  // 1. RESOLVER TYUNIT CERDAS
  // ========================================================

  /// Meresolve kode tyunit yang valid berdasarkan tyunit, nama produk, dan harga
  static String resolveItemTyunit(
    String? currentTyunit,
    String itemName,
    double price, [
    List<Item>? productsList,
  ]) {
    final cur = currentTyunit?.trim().toUpperCase();
    if (cur != null && cur.isNotEmpty && cur != 'BV01') {
      return cur;
    }

    final cleanName = itemName.trim().toLowerCase();

    // Jika kode BV01 dan namanya memang galon, cek harga apakah spesifik varian tertentu
    if (cur == 'BV01' && (cleanName.contains('galon') || cleanName.isEmpty)) {
      if (price == 13000) return 'BV02';
      if (price == 16000) return 'BV03';
      if (price == 17000) return 'BV04';
      if (price == 75000) return 'BV06';
      if (price == 85000) return 'BV07';
      return 'BV01';
    }

    // Cocokkan dari daftar master produk jika ada
    if (productsList != null && productsList.isNotEmpty) {
      final exactMatch = productsList.where(
        (p) =>
            p.name.trim().toLowerCase() == cleanName &&
            (p.price - price).abs() < 1,
      ).firstOrNull;
      if (exactMatch != null && exactMatch.tyunit.isNotEmpty) {
        return exactMatch.tyunit;
      }

      final nameMatch = productsList.where(
        (p) => p.name.trim().toLowerCase() == cleanName,
      ).firstOrNull;
      if (nameMatch != null && nameMatch.tyunit.isNotEmpty) {
        return nameMatch.tyunit;
      }
    }

    // Fallback berdasarkan aturan komoditas resmi Boneva
    if (cleanName.contains('galon') || cleanName.contains('gln')) {
      if (price == 13000) return 'BV02';
      if (price == 16000) return 'BV03';
      if (price == 17000) return 'BV04';
      if (price == 75000) return 'BV06';
      if (price == 85000) return 'BV07';
      return 'BV01';
    } else if (cleanName.contains('600')) {
      if (price == 37000) return 'BV09';
      if (price == 38000) return 'BV10';
      if (price == 38500) return 'BV11';
      if (price == 39000) return 'BV12';
      if (price == 40000) return 'BV13';
      return 'BV08';
    } else if (cleanName.contains('1500') ||
        cleanName.contains('1.5') ||
        cleanName.contains('1,5')) {
      if (price == 41000) return 'BV15';
      if (price == 42000) return 'BV16';
      if (price == 43000) return 'BV17';
      return 'BV14';
    } else if (cleanName.contains('gelas') ||
        cleanName.contains('gls') ||
        cleanName.contains('cup')) {
      if (price == 21000) return 'BV19';
      if (price == 21500) return 'BV22';
      if (price == 22000) return 'BV20';
      if (price == 22500) return 'BV23';
      if (price == 23000) return 'BV21';
      return 'BV18';
    }

    return cur ?? 'BV01';
  }

  // ========================================================
  // 2. MANAJEMEN ANTREAN TRANSAKSI OFFLINE
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
        'user_id': transaction.userId ?? AuthService.currentUser?.id,
        'user_name': transaction.userName ?? AuthService.currentUser?.name,
        'tanggal_pelunasan': transaction.tanggalPelunasan != null
            ? DateFormat('yyyy-MM-dd').format(transaction.tanggalPelunasan!)
            : null,
        'items': transaction.items.map((item) {
          final price = item.price.truncateToDouble() == item.price
              ? item.price.toInt()
              : item.price;
          final subtotal = item.subtotal.truncateToDouble() == item.subtotal
              ? item.subtotal.toInt()
              : item.subtotal;
          final tyunit = resolveItemTyunit(item.tyunit, item.name, item.price);
          return {
            'tyunit': tyunit,
            'name': item.nameController.text,
            'nama_barang': item.nameController.text,
            'price': price,
            'harga': price,
            'quantity': item.quantity > 0 ? item.quantity : 1,
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
  // 3. SINKRONISASI KE SERVER UTAMA (LARAVEL API)
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

    // Muat cache produk lokal untuk membantu resolving tyunit & mencocokkan stok
    final cachedProducts = await getCachedProducts();

    for (final trx in pendingList) {
      try {
        final formattedDate =
            DateFormat('yyyy-MM-dd HH:mm:ss').format(trx.date);

        final payload = {
          'id_transaksi': trx.id_transaksi,
          'customerName': trx.customerName,
          'customer_name': trx.customerName,
          'alamat': trx.alamat,
          'date': formattedDate,
          'tanggal': formattedDate,
          'user_id': trx.userId ?? AuthService.currentUser?.id,
          'user_name': trx.userName ?? AuthService.currentUser?.name,
          'total': trx.total.truncateToDouble() == trx.total
              ? trx.total.toInt()
              : trx.total,
          'status': trx.status,
          if (trx.tanggalPelunasan != null || trx.status == 'LUNAS')
            'tanggal_pelunasan': trx.tanggalPelunasan != null
                ? DateFormat('yyyy-MM-dd').format(trx.tanggalPelunasan!)
                : DateFormat('yyyy-MM-dd').format(trx.date),
          'items': trx.items.map((item) {
            final tyunit = resolveItemTyunit(
              item.tyunit,
              item.name,
              item.price,
              cachedProducts,
            );
            final price = item.price.truncateToDouble() == item.price
                ? item.price.toInt()
                : item.price;
            final subtotal = item.subtotal.truncateToDouble() == item.subtotal
                ? item.subtotal.toInt()
                : item.subtotal;
            final qty = item.quantity > 0 ? item.quantity : 1;
            return {
              'tyunit': tyunit,
              'name': item.name,
              'nama_barang': item.name,
              'price': price,
              'harga': price,
              'quantity': qty,
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
            .timeout(const Duration(seconds: 12));

        final resBody = response.body;
        final isDuplicate = response.statusCode == 409 ||
            resBody.contains('Duplicate entry') ||
            resBody.contains('1062') ||
            resBody.toLowerCase().contains('already exists');

        if (response.statusCode == 200 || response.statusCode == 201 || isDuplicate) {
          // Berhasil dikirim ke server atau sudah pernah tercatat -> hapus dari antrean offline
          await removePendingTransaction(trx.id_transaksi);
          successCount++;

          // Sinkronkan juga ke Supabase cadangan jika memungkinkan
          try {
            final supabase = Supabase.instance.client;
            final itemsMap = trx.items.map((item) {
              final tyunit = resolveItemTyunit(item.tyunit, item.name, item.price, cachedProducts);
              return {
                'id_transaksi': trx.id_transaksi,
                'tyunit': tyunit,
                'nama_barang': item.name,
                'harga': item.price,
                'quantity': item.quantity > 0 ? item.quantity : 1,
                'bonus': item.bonus,
                'subtotal': item.subtotal,
              };
            }).toList();

            await supabase.from('transaksi').upsert({
              'id_transaksi': trx.id_transaksi,
              'customer_name': trx.customerName,
              'alamat': trx.alamat,
              'tanggal': formattedDate,
              'total': trx.total,
              'status': trx.status,
              'user_id': trx.userId ?? AuthService.currentUser?.id,
              'user_name': trx.userName ?? AuthService.currentUser?.name,
              'is_offline': false,
            });
            await supabase.from('transaksi_items').upsert(itemsMap);
          } catch (e) {
            debugPrint('Sinkronisasi Supabase saat sync: $e');
          }
        } else {
          failedCount++;
          String msg = 'Gagal sync ${trx.id_transaksi} (${response.statusCode})';
          try {
            final errBody = jsonDecode(resBody);
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

    // Jika ada yang berhasil disinkronkan, update data stok dari server agar stok di memori/cache cocok kembali
    if (successCount > 0) {
      try {
        final latestProducts = await StockApiService.fetchProducts();
        if (latestProducts.isNotEmpty) {
          await cacheProducts(latestProducts);
          debugPrint('Stok berhasil dicocokkan ulang setelah sinkronisasi $successCount nota.');
        }
      } catch (e) {
        debugPrint('Gagal refresh stock setelah sync (tetap mempertahankan stok lokal): $e');
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
  // 4. CACHE PRODUK LOKAL (Agar kasir tetap bisa pilih produk & cocok stok)
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

  /// Memperbarui satu produk di cache lokal (misalnya saat edit master produk ke 0)
  static Future<void> updateCachedProduct(
    String tyunit,
    String newName,
    double newPrice,
  ) async {
    try {
      final cached = await getCachedProducts();
      final updated = cached.map((p) {
        if (p.tyunit.toUpperCase() == tyunit.toUpperCase()) {
          return Item(
            tyunit: p.tyunit,
            name: newName,
            price: newPrice,
            stock: p.stock,
            kelompok: p.kelompok,
            kuota: p.kuota,
            terjual: p.terjual,
            sisaKuota: p.sisaKuota,
          );
        }
        return p;
      }).toList();
      await cacheProducts(updated);
    } catch (e) {
      debugPrint('Error updating cached product: $e');
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

  /// Data bawaan 23 produk Boneva lengkap jika aplikasi benar-benar pertama kali dibuka tanpa internet
  static List<Item> _getDefaultProductsFallback() {
    return [
      Item(tyunit: 'BV01', name: 'Boneva Galon isi saja', price: 0, stock: 18, kelompok: 'GALON', kuota: 429, terjual: 0, sisaKuota: 18),
      Item(tyunit: 'BV02', name: 'Boneva Galon isi saja', price: 13000, stock: 18, kelompok: 'GALON', kuota: 429, terjual: 186, sisaKuota: 18),
      Item(tyunit: 'BV03', name: 'Boneva Galon isi saja', price: 16000, stock: 18, kelompok: 'GALON', kuota: 429, terjual: 199, sisaKuota: 18),
      Item(tyunit: 'BV04', name: 'Boneva Galon isi saja', price: 17000, stock: 18, kelompok: 'GALON', kuota: 429, terjual: 24, sisaKuota: 18),
      Item(tyunit: 'BV05', name: 'Boneva Galon + isi', price: 0, stock: 18, kelompok: 'GALON', kuota: 429, terjual: 0, sisaKuota: 18),
      Item(tyunit: 'BV06', name: 'Boneva Galon + isi', price: 75000, stock: 18, kelompok: 'GALON', kuota: 429, terjual: 0, sisaKuota: 18),
      Item(tyunit: 'BV07', name: 'Boneva Galon + isi', price: 85000, stock: 18, kelompok: 'GALON', kuota: 429, terjual: 2, sisaKuota: 18),
      Item(tyunit: 'BV08', name: 'Boneva Botol 600 Ml', price: 0, stock: 28, kelompok: 'BOTOL_600', kuota: 405, terjual: 0, sisaKuota: 28),
      Item(tyunit: 'BV09', name: 'Boneva Botol 600 Ml', price: 37000, stock: 28, kelompok: 'BOTOL_600', kuota: 405, terjual: 30, sisaKuota: 28),
      Item(tyunit: 'BV10', name: 'Boneva Botol 600 Ml', price: 38000, stock: 28, kelompok: 'BOTOL_600', kuota: 405, terjual: 30, sisaKuota: 28),
      Item(tyunit: 'BV11', name: 'Boneva Botol 600 Ml', price: 38500, stock: 28, kelompok: 'BOTOL_600', kuota: 405, terjual: 0, sisaKuota: 28),
      Item(tyunit: 'BV12', name: 'Boneva Botol 600 Ml', price: 39000, stock: 28, kelompok: 'BOTOL_600', kuota: 405, terjual: 20, sisaKuota: 28),
      Item(tyunit: 'BV13', name: 'Boneva Botol 600 Ml', price: 40000, stock: 28, kelompok: 'BOTOL_600', kuota: 405, terjual: 297, sisaKuota: 28),
      Item(tyunit: 'BV14', name: 'Boneva Botol 1,5 L', price: 0, stock: 52, kelompok: 'BOTOL_1500', kuota: 84, terjual: 0, sisaKuota: 52),
      Item(tyunit: 'BV15', name: 'Boneva Botol 1,5 L', price: 41000, stock: 52, kelompok: 'BOTOL_1500', kuota: 84, terjual: 0, sisaKuota: 52),
      Item(tyunit: 'BV16', name: 'Boneva Botol 1,5 L', price: 42000, stock: 52, kelompok: 'BOTOL_1500', kuota: 84, terjual: 12, sisaKuota: 52),
      Item(tyunit: 'BV17', name: 'Boneva Botol 1,5 L', price: 43000, stock: 52, kelompok: 'BOTOL_1500', kuota: 84, terjual: 20, sisaKuota: 52),
      Item(tyunit: 'BV18', name: 'Boneva Gelas', price: 0, stock: 53, kelompok: 'GELAS', kuota: 529, terjual: 0, sisaKuota: 53),
      Item(tyunit: 'BV19', name: 'Boneva Gelas', price: 21000, stock: 53, kelompok: 'GELAS', kuota: 529, terjual: 25, sisaKuota: 53),
      Item(tyunit: 'BV20', name: 'Boneva Gelas', price: 22000, stock: 53, kelompok: 'GELAS', kuota: 529, terjual: 328, sisaKuota: 53),
      Item(tyunit: 'BV21', name: 'Boneva Gelas', price: 23000, stock: 53, kelompok: 'GELAS', kuota: 529, terjual: 123, sisaKuota: 53),
      Item(tyunit: 'BV22', name: 'Boneva Gelas', price: 21500, stock: 53, kelompok: 'GELAS', kuota: 529, terjual: 0, sisaKuota: 53),
      Item(tyunit: 'BV23', name: 'Boneva Gelas', price: 22500, stock: 53, kelompok: 'GELAS', kuota: 529, terjual: 0, sisaKuota: 53),
    ];
  }
}
