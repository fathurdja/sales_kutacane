import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kasir_kutacane/config/api_config.dart';
import 'package:kasir_kutacane/services/auth_service.dart';
import 'package:kasir_kutacane/services/stock_api_service.dart';
import 'package:kasir_kutacane/services/supabase_sync_service.dart';
import 'package:path_provider/path_provider.dart';

class PendingStockEntry {
  final String id;
  final DateTime timestamp;
  final String kdklp;
  final String jenisAksi; // 'TAMBAH_PASOKAN' atau 'SET_STOK_AWAL'
  final int jumlah;
  final bool resetTerjual;
  final String? keterangan;

  PendingStockEntry({
    required this.id,
    required this.timestamp,
    required this.kdklp,
    required this.jenisAksi,
    required this.jumlah,
    this.resetTerjual = false,
    this.keterangan,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'kdklp': kdklp,
      'jenis_aksi': jenisAksi,
      'jumlah': jumlah,
      'reset_terjual': resetTerjual,
      'keterangan': keterangan,
    };
  }

  factory PendingStockEntry.fromJson(Map<String, dynamic> json) {
    return PendingStockEntry(
      id: json['id']?.toString() ?? '',
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
      kdklp: json['kdklp']?.toString().toUpperCase() ?? '',
      jenisAksi: json['jenis_aksi']?.toString() ?? 'TAMBAH_PASOKAN',
      jumlah: (json['jumlah'] is num)
          ? (json['jumlah'] as num).toInt()
          : (int.tryParse(json['jumlah']?.toString() ?? '0') ?? 0),
      resetTerjual: json['reset_terjual'] == true,
      keterangan: json['keterangan']?.toString(),
    );
  }
}

class PendingStockSyncService {
  static const String _fileName = 'pending_stock_entries.json';
  static final List<PendingStockEntry> _memoryFallbackQueue = [];

  static Future<File?> _getFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/$_fileName');
    } catch (_) {
      return null;
    }
  }

  /// Menambahkan entri perubahan stok offline ke antrean pending
  static Future<void> addPendingEntry(PendingStockEntry entry) async {
    try {
      final file = await _getFile();
      if (file != null) {
        List<dynamic> queue = [];
        if (await file.exists()) {
          final content = await file.readAsString();
          if (content.trim().isNotEmpty) {
            queue = jsonDecode(content);
          }
        }
        queue.add(entry.toJson());
        await file.writeAsString(jsonEncode(queue));
      } else {
        _memoryFallbackQueue.add(entry);
      }
      debugPrint('Berhasil mencatat pending stok offline: ${entry.kdklp} (${entry.jenisAksi} = ${entry.jumlah})');
    } catch (e) {
      _memoryFallbackQueue.add(entry);
      debugPrint('Gagal menyimpan pending stok offline ke disk, disimpan di memori: $e');
    }
  }

  /// Mengambil daftar seluruh entri perubahan stok yang belum disinkronkan ke server utama
  static Future<List<PendingStockEntry>> getPendingEntries() async {
    try {
      final file = await _getFile();
      if (file == null || !await file.exists()) {
        return List.from(_memoryFallbackQueue);
      }

      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return List.from(_memoryFallbackQueue);
      }

      final List<dynamic> data = jsonDecode(content);
      final list = data
          .map((j) => PendingStockEntry.fromJson(j as Map<String, dynamic>))
          .toList();
      if (_memoryFallbackQueue.isNotEmpty) {
        list.addAll(_memoryFallbackQueue);
      }
      return list;
    } catch (e) {
      debugPrint('Gagal membaca antrean pending stok dari disk: $e');
      return List.from(_memoryFallbackQueue);
    }
  }

  /// Menghapus satu entri dari antrean setelah berhasil disinkronkan ke server
  static Future<void> removePendingEntry(String id) async {
    try {
      _memoryFallbackQueue.removeWhere((item) => item.id == id);
      final file = await _getFile();
      if (file == null || !await file.exists()) return;

      final content = await file.readAsString();
      if (content.trim().isEmpty) return;

      List<dynamic> queue = jsonDecode(content);
      queue.removeWhere((item) => item['id'] == id);
      await file.writeAsString(jsonEncode(queue));
    } catch (e) {
      debugPrint('Gagal menghapus pending stock entry: $e');
    }
  }

  /// Menyinkronkan seluruh perubahan stok offline ke Server Utama Laravel
  /// Saat server hidup kembali, data stok masuk dikirimkan dan monitoring stok di-trigger sync otomatis.
  static Future<int> syncPendingStockEntries() async {
    final entries = await getPendingEntries();
    if (entries.isEmpty) return 0;

    // Cek apakah server utama Laravel aktif
    final isOnline = await SupabaseSyncService.isPrimaryServerOnline();
    if (!isOnline) {
      debugPrint('Server utama masih offline, sinkronisasi stok pending ditunda.');
      return 0;
    }

    int syncedCount = 0;
    final headers = await AuthService.getAuthHeaders();

    for (final entry in entries) {
      try {
        if (entry.jenisAksi == 'TAMBAH_PASOKAN') {
          // Kirim ke endpoint resmi API-v2 /stock-masuk
          final body = jsonEncode({
            'kdklp': entry.kdklp,
            'jumlah': entry.jumlah,
            'keterangan': entry.keterangan ?? 'Sinkronisasi pasokan stok offline (${entry.kdklp})',
          });

          final res = await http
              .post(ApiConfig.stockMasukUri, headers: headers, body: body)
              .timeout(const Duration(seconds: 8));

          if (res.statusCode == 200 || res.statusCode == 201) {
            await removePendingEntry(entry.id);
            syncedCount++;
            debugPrint('Pending pasokan stok ${entry.kdklp} (+${entry.jumlah}) berhasil disinkronkan ke Laravel.');
          } else {
            debugPrint('Gagal sync pasokan stok ${entry.kdklp}: ${res.statusCode} - ${res.body}');
          }
        } else if (entry.jenisAksi == 'SET_STOK_AWAL') {
          // Kirim ke endpoint resmi /stock-awal
          final payload = {
            'kelompok': entry.kdklp,
            'stock_awal': entry.jumlah,
            'reset_terjual': entry.resetTerjual,
          };

          final res = await http
              .post(
                Uri.parse('${ApiConfig.baseUrl}/stock-awal'),
                headers: headers,
                body: jsonEncode(payload),
              )
              .timeout(const Duration(seconds: 8));

          if (res.statusCode == 200 || res.statusCode == 201) {
            await removePendingEntry(entry.id);
            syncedCount++;
            debugPrint('Pending set stok awal ${entry.kdklp} (${entry.jumlah}) berhasil disinkronkan ke Laravel.');
          } else {
            debugPrint('Gagal sync set stok awal ${entry.kdklp}: ${res.statusCode} - ${res.body}');
          }
        }
      } catch (e) {
        debugPrint('Error sync pending stock entry ${entry.id}: $e');
      }
    }

    // Jika ada setidaknya 1 perubahan stok yang disinkronkan:
    // Panggil syncStockMonitoring di Laravel agar tabel stock_monitorings dihitung ulang secara real-time!
    if (syncedCount > 0) {
      try {
        debugPrint('Memanggil sinkronisasi monitoring stok di server Laravel...');
        await StockApiService.syncStockMonitoring();
        debugPrint('Tabel monitoring stok di server Laravel berhasil disinkronkan secara otomatis.');
      } catch (e) {
        debugPrint('Catatan: Gagal trigger syncStockMonitoring: $e');
      }

      // Refresh master produk & sinkronkan kembali ke Supabase munit
      try {
        final products = await StockApiService.fetchProducts();
        if (products.isNotEmpty) {
          await SupabaseSyncService.syncMasterProducts(products);
        }
      } catch (_) {}
    }

    return syncedCount;
  }
}
