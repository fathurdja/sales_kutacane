import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kasir_kutacane/config/api_config.dart';
import 'package:kasir_kutacane/models/Item.dart';
import 'package:kasir_kutacane/models/stock_group.dart';
import 'package:kasir_kutacane/services/auth_service.dart';
import 'package:kasir_kutacane/services/offline_sync_service.dart';
import 'package:kasir_kutacane/services/pending_stock_sync_service.dart';
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
          .timeout(const Duration(seconds: 3));

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
  /// Jika server utama Laravel offline, otomatis fallback ke Supabase munit & antrean pending.
  static Future<Map<String, dynamic>> setStockAwal({
    required String kelompok,
    required int stockAwal,
    bool resetTerjual = false,
  }) async {
    final groupKey = kelompok.toUpperCase();
    final payload = {
      'kelompok': groupKey,
      'stock_awal': stockAwal,
      'reset_terjual': resetTerjual,
    };

    // 1. Coba simpan ke Server Utama Laravel
    try {
      final headers = await AuthService.getAuthHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/stock-awal'),
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body);

        // Sinkronkan ke Supabase & cache lokal secara non-blocking
        unawaited(SupabaseSyncService.setStockAwalToSupabase(
          kelompok: groupKey,
          stockAwal: stockAwal,
          resetTerjual: resetTerjual,
        ));
        unawaited(OfflineSyncService.updateCachedGroupStock(
          groupKey,
          stockAwal,
          stockAwal,
          resetTerjual: resetTerjual,
        ));

        return decoded is Map<String, dynamic> ? decoded : {'success': true};
      }
    } catch (e) {
      debugPrint('POST /stock-awal gagal ($e), beralih ke fallback Supabase & offline queue...');
    }

    // 2. Fallback: Simpan ke Supabase Backup (munit)
    bool supabaseSuccess = false;
    try {
      supabaseSuccess = await SupabaseSyncService.setStockAwalToSupabase(
        kelompok: groupKey,
        stockAwal: stockAwal,
        resetTerjual: resetTerjual,
      );
    } catch (errSupabase) {
      debugPrint('Fallback Supabase setStockAwal error: $errSupabase');
    }

    // 3. Masukkan ke Antrean Pending Sync (agar saat server Laravel menyala, disinkronkan & monitoring di-sync)
    await PendingStockSyncService.addPendingEntry(
      PendingStockEntry(
        id: 'STOCK-AWAL-${DateTime.now().millisecondsSinceEpoch}',
        timestamp: DateTime.now(),
        kdklp: groupKey,
        jenisAksi: 'SET_STOK_AWAL',
        jumlah: stockAwal,
        resetTerjual: resetTerjual,
        keterangan: resetTerjual
            ? 'Reset & set stok awal offline ($groupKey = $stockAwal)'
            : 'Set stok awal offline ($groupKey = $stockAwal)',
      ),
    );

    // 4. Update cache produk lokal di HP
    await OfflineSyncService.updateCachedGroupStock(
      groupKey,
      stockAwal,
      stockAwal,
      resetTerjual: resetTerjual,
    );

    return {
      'success': true,
      'is_offline': true,
      'fallback': supabaseSuccess ? 'supabase' : 'local_storage',
      'message': supabaseSuccess
          ? 'Stok awal berhasil disimpan ke database cadangan Supabase (Server utama offline). Data akan otomatis disinkronkan ke server saat menyala.'
          : 'Stok awal tersimpan di penyimpanan offline HP & akan disinkronkan otomatis saat server menyala.',
    };
  }

  /// 2B. Tambah Pasokan Stok Masuk (Restock Fisik di Tengah Hari)
  /// Menggunakan endpoint resmi API-v2 /stock-masuk (terhubung ke tabel stock_entries & stock_monitorings).
  /// Jika server utama Laravel offline, otomatis fallback ke Supabase munit & antrean pending.
  static Future<Map<String, dynamic>> addStockMasuk({
    required String kelompok,
    required int tambahanQty,
    int? currentStockAwal,
    String? keterangan,
  }) async {
    final groupKey = kelompok.toUpperCase();

    // 1. Coba endpoint resmi API-v2 /stock-masuk di server utama
    try {
      final headers = await AuthService.getAuthHeaders();
      final body = jsonEncode({
        'kdklp': groupKey,
        'jumlah': tambahanQty,
        'keterangan': keterangan ?? 'Penambahan pasokan stok $groupKey',
      });
      final res = await http
          .post(ApiConfig.stockMasukUri, headers: headers, body: body)
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200 || res.statusCode == 201) {
        final decoded = jsonDecode(res.body);

        // Sinkronkan ke Supabase & cache lokal
        unawaited(SupabaseSyncService.addStockMasukToSupabase(
          kelompok: groupKey,
          tambahanQty: tambahanQty,
          keterangan: keterangan,
        ));

        return decoded is Map<String, dynamic> ? decoded : {'success': true};
      }
    } catch (e) {
      debugPrint('POST /stock-masuk gagal ($e), beralih ke fallback Supabase & offline queue...');
    }

    // 2. Fallback: Simpan ke Supabase Backup (munit)
    bool supabaseSuccess = false;
    try {
      supabaseSuccess = await SupabaseSyncService.addStockMasukToSupabase(
        kelompok: groupKey,
        tambahanQty: tambahanQty,
        keterangan: keterangan,
      );
    } catch (errSupabase) {
      debugPrint('Fallback Supabase addStockMasuk error: $errSupabase');
    }

    // 3. Masukkan ke Antrean Pending Sync (agar saat server Laravel menyala, disinkronkan & monitoring di-sync)
    await PendingStockSyncService.addPendingEntry(
      PendingStockEntry(
        id: 'STOCK-MASUK-${DateTime.now().millisecondsSinceEpoch}',
        timestamp: DateTime.now(),
        kdklp: groupKey,
        jenisAksi: 'TAMBAH_PASOKAN',
        jumlah: tambahanQty,
        resetTerjual: false,
        keterangan: keterangan ?? 'Penambahan pasokan stok offline $groupKey',
      ),
    );

    // 4. Update cache produk lokal di HP
    try {
      final cached = await OfflineSyncService.getCachedProducts();
      final matched = cached.where((p) => p.kelompok.toUpperCase() == groupKey).firstOrNull;
      if (matched != null) {
        final newKuota = matched.kuota + tambahanQty;
        final newSisa = (matched.sisaKuota > 0 ? matched.sisaKuota : matched.stock) + tambahanQty;
        await OfflineSyncService.updateCachedGroupStock(groupKey, newKuota, newSisa);
      }
    } catch (_) {}

    return {
      'success': true,
      'is_offline': true,
      'fallback': supabaseSuccess ? 'supabase' : 'local_storage',
      'message': supabaseSuccess
          ? 'Pasokan stok berhasil disimpan ke database cadangan Supabase (Server utama offline). Data akan otomatis disinkronkan ke server saat menyala.'
          : 'Pasokan stok tersimpan di penyimpanan offline HP & akan disinkronkan otomatis saat server menyala.',
    };
  }

  /// 3. Ambil Rincian Barang Terjual Hari Ini (per varian)
  static Future<Map<String, dynamic>> fetchStockTerjual({
    String? kelompok,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (kelompok != null && kelompok.isNotEmpty) queryParams['kelompok'] = kelompok;

      final uri = Uri.parse('$baseUrl/stock-terjual').replace(queryParameters: queryParams.isEmpty ? null : queryParams);
      final headers = await AuthService.getAuthHeaders();
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('fetchStockTerjual offline fallback: $e');
    }

    // Fallback aman ketika server offline, agar Future.wait di UI tidak error / macet
    return {
      'success': true,
      'is_offline': true,
      'total_terjual': 0,
      'items': [],
    };
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
          .timeout(const Duration(seconds: 3));

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

  /// 7. Mengambil Data Lengkap Monitoring Stok (API-v2 /stock-monitoring)
  /// Mendukung filter ?month=YYYY-MM, ?date=YYYY-MM-DD, ?kdklp=KELOMPOK
  static Future<Map<String, dynamic>> fetchStockMonitoring({
    String? month,
    String? date,
    String? kdklp,
    String? startDate,
    String? endDate,
  }) async {
    final queryParams = <String, String>{};
    if (month != null && month.isNotEmpty) queryParams['month'] = month;
    if (date != null && date.isNotEmpty) queryParams['date'] = date;
    if (kdklp != null && kdklp.isNotEmpty && kdklp.toUpperCase() != 'ALL') {
      queryParams['kdklp'] = kdklp.toUpperCase();
    }
    if (startDate != null && startDate.isNotEmpty) queryParams['start_date'] = startDate;
    if (endDate != null && endDate.isNotEmpty) queryParams['end_date'] = endDate;

    final uri = ApiConfig.stockMonitoringUri.replace(
      queryParameters: queryParams.isEmpty ? null : queryParams,
    );
    final headers = await AuthService.getAuthHeaders();
    final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 6));

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    }
    throw Exception('Gagal memuat monitoring stok (${response.statusCode})');
  }

  /// 8. Khusus Admin: Sinkronisasi Ulang Seluruh Tabel Monitoring Stok dari Transaksi
  static Future<Map<String, dynamic>> syncStockMonitoring() async {
    final headers = await AuthService.getAuthHeaders();
    final response = await http
        .post(ApiConfig.stockMonitoringSyncUri, headers: headers)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200 || response.statusCode == 201) {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : {'success': true};
    }
    throw Exception('Gagal sinkronisasi data monitoring (${response.statusCode})');
  }
}
