import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kasir_kutacane/config/api_config.dart';
import 'package:kasir_kutacane/models/Item.dart';
import 'package:kasir_kutacane/models/stock_group.dart';
import 'package:kasir_kutacane/services/auth_service.dart';
import 'package:kasir_kutacane/services/offline_sync_service.dart';
import 'package:kasir_kutacane/services/supabase_sync_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StockApiService {
  static String get baseUrl => ApiConfig.baseUrl;

  /// 1. Ambil Ringkasan Lengkap Kelompok Komoditas Fisik (Stok Awal, Terjual, Sisa, Rincian Varian)
  /// Stok awal yang diinput oleh Admin berlaku sebagai kuota bersama (shared pool) untuk seluruh sales.
  static Future<List<StockGroup>> fetchStockSummary() async {
    try {
      final uri = Uri.parse('$baseUrl/stock-summary');
      final headers = await AuthService.getAuthHeaders();
      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(response.body);
        List<dynamic> list;

        if (decoded is Map && decoded.containsKey('groups')) {
          list = decoded['groups'] as List<dynamic>;
        } else if (decoded is List) {
          list = decoded;
        } else {
          list = [];
        }

        return list
            .map((json) => StockGroup.fromJson(json as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception('Server merespons kode ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('fetchStockSummary gagal ($e), mencoba memuat dari Supabase backup...');
      try {
        final supabaseGroups = await SupabaseSyncService.fetchStockSummaryFromSupabase();
        if (supabaseGroups.isNotEmpty) {
          debugPrint('Berhasil memuat ${supabaseGroups.length} kelompok stok dari Supabase cadangan.');
          return supabaseGroups;
        }
      } catch (errSupabase) {
        debugPrint('Supabase fetchStockSummary error: $errSupabase');
      }
      rethrow;
    }
  }

  /// 2. Set Stok Awal (Kuota Masuk) untuk satu kelompok komoditas fisik
  /// Kuota ini berlaku untuk seluruh pengguna kasir (global shared stock).
  /// - [resetTerjual]: Jika true, counter penjualan varian di kelompok ini akan direset ke 0.
  static Future<Map<String, dynamic>> setStockAwal({
    required String kelompok,
    required int stockAwal,
    bool resetTerjual = false,
  }) async {
    final payload = {
      'kelompok': kelompok.toUpperCase(),
      'stock_awal': stockAwal,
      'reset_terjual': resetTerjual,
    };

    final headers = await AuthService.getAuthHeaders();
    final response = await http
        .post(
          Uri.parse('$baseUrl/stock-awal'),
          headers: headers,
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200 || response.statusCode == 201) {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : {'success': true};
    } else {
      String msg = 'Gagal menyimpan stok awal (${response.statusCode})';
      try {
        final b = jsonDecode(response.body);
        if (b is Map && b.containsKey('message')) msg = b['message'].toString();
      } catch (_) {}
      throw Exception(msg);
    }
  }

  /// 2B. Tambah Pasokan Stok Masuk (Restock Fisik di Tengah Hari)
  /// Menambahkan [tambahanQty] langsung ke sisa stok fisik yang sedang berjalan tanpa mereset counter penjualan.
  /// Formula Backend:
  ///   stok_awal_baru = current_stok_awal + tambahanQty
  ///   sisa_stok_baru = (current_stok_awal + tambahanQty) - total_terjual = current_sisa + tambahanQty
  static Future<Map<String, dynamic>> addStockMasuk({
    required String kelompok,
    required int tambahanQty,
    int? currentStockAwal,
  }) async {
    int baseStockAwal = currentStockAwal ?? 0;
    try {
      final groups = await fetchStockSummary();
      final currentGroup = groups
          .where((g) => g.kelompok.toUpperCase() == kelompok.toUpperCase())
          .firstOrNull;
      if (currentGroup != null) {
        baseStockAwal = currentGroup.stockAwal;
      }
    } catch (_) {
      // Fallback ke currentStockAwal jika terjadi kegagalan jaringan
    }

    final newStockAwal = baseStockAwal + tambahanQty;
    return await setStockAwal(
      kelompok: kelompok,
      stockAwal: newStockAwal,
      resetTerjual: false,
    );
  }

  /// 3. Ambil Rincian Barang Terjual Hari Ini (per varian)
  static Future<Map<String, dynamic>> fetchStockTerjual({
    String? kelompok,
  }) async {
    final queryParams = <String, String>{};
    if (kelompok != null && kelompok.isNotEmpty) queryParams['kelompok'] = kelompok;

    final uri = Uri.parse('$baseUrl/stock-terjual').replace(queryParameters: queryParams.isEmpty ? null : queryParams);
    final headers = await AuthService.getAuthHeaders();
    final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 8));

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Gagal memuat data stok terjual (${response.statusCode})');
    }
  }

  /// 4. Reset Counter Terjual Kembali ke 0 (Khusus Admin)
  static Future<void> resetStockTerjual({
    String? kelompok,
  }) async {
    final payload = <String, dynamic>{
      if (kelompok != null && kelompok.isNotEmpty) 'kelompok': kelompok,
    };

    final headers = await AuthService.getAuthHeaders();
    final response = await http
        .post(
          Uri.parse('$baseUrl/stock-terjual/reset'),
          headers: headers,
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200 && response.statusCode != 201) {
      String msg = 'Gagal mereset counter penjualan (${response.statusCode})';
      try {
        final b = jsonDecode(response.body);
        if (b is Map && b.containsKey('message')) msg = b['message'].toString();
      } catch (_) {}
      throw Exception(msg);
    }
  }

  /// 5. Ambil Daftar 13 Produk Boneva Lengkap dengan Info Kuota & Sisa Fisik Nyata
  static Future<List<Item>> fetchProducts() async {
    try {
      final headers = await AuthService.getAuthHeaders();
      final response = await http
          .get(Uri.parse('$baseUrl/products'), headers: headers)
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final List<dynamic> list = jsonDecode(response.body);
        final products =
            list.map((json) => Item.fromJson(json as Map<String, dynamic>)).toList();

        List<Item> finalProducts = products;
        // Sinkronkan secara ketat dengan kuota fisik dari /stock-summary
        try {
          final groups = await fetchStockSummary();
          final Map<String, int> groupStockMap = {};
          for (final g in groups) {
            groupStockMap[g.kelompok.toUpperCase()] = g.sisaStock;
          }

          finalProducts = products.map((p) {
            final gKey = p.kelompok.toUpperCase();
            if (groupStockMap.containsKey(gKey)) {
              final realGroupStock = groupStockMap[gKey]!;
              return Item(
                tyunit: p.tyunit,
                name: p.name,
                price: p.price,
                stock: realGroupStock,
                kelompok: p.kelompok,
                kuota: p.kuota,
                terjual: p.terjual,
                sisaKuota: realGroupStock,
              );
            }
            return p;
          }).toList();
        } catch (_) {}

        // Sinkronkan master data & stock ke Supabase Backup secara non-blocking
        unawaited(SupabaseSyncService.syncMasterProducts(finalProducts));

        return finalProducts;
      } else {
        throw Exception('Server merespons kode ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Gagal fetch products dari database utama ($e), mencoba Supabase backup...');
      try {
        final backupProducts = await SupabaseSyncService.fetchProductsFromSupabase();
        if (backupProducts.isNotEmpty) {
          debugPrint('Berhasil memuat ${backupProducts.length} produk dari Supabase backup.');
          await OfflineSyncService.cacheProducts(backupProducts);
          return backupProducts;
        }
      } catch (errSupabase) {
        debugPrint('Supabase fetch failed: $errSupabase');
      }
      rethrow;
    }
  }

  /// 6. Update Harga atau Data Varian di Master Stocks
  static Future<void> updateMasterProduct({
    required String tyunit,
    required String name,
    required int price,
  }) async {
    final payload = {
      'TYUNIT': tyunit,
      'NTYUNIT': name,
      'hjual': price,
    };

    final headers = await AuthService.getAuthHeaders();
    final response = await http
        .put(
          ApiConfig.masterStockDetailUri(tyunit),
          headers: headers,
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200 && response.statusCode != 201) {
      String msg = 'Gagal update data varian (${response.statusCode})';
      try {
        final b = jsonDecode(response.body);
        if (b is Map && b.containsKey('message')) msg = b['message'].toString();
      } catch (_) {}
      throw Exception(msg);
    }

    // Sinkronkan juga ke Supabase Backup jika ada
    try {
      final supabase = Supabase.instance.client;
      await supabase.from('munit').update({
        'ntyunit': name,
        'hjual': price,
        'userup': AuthService.currentUser?.username ?? 'admin',
        'tglup': DateTime.now().toIso8601String().substring(0, 10),
      }).eq('tyunit', tyunit);
    } catch (e) {
      debugPrint('Supabase master update error: $e');
    }

    // Perbarui cache produk lokal di memori & penyimpanan lokal HP
    try {
      await OfflineSyncService.updateCachedProduct(tyunit, name, price.toDouble());
    } catch (e) {
      debugPrint('Update local cached product error: $e');
    }
  }
}
