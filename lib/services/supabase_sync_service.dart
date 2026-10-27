import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kasir_kutacane/config/api_config.dart';
import 'package:kasir_kutacane/models/Item.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum DatabaseConnectionStatus {
  primaryOnline,
  primaryOfflineSupabaseReady,
  offlineLocal,
  checking,
}

class SupabaseSyncService {
  static final ValueNotifier<DatabaseConnectionStatus> connectionStatusNotifier =
      ValueNotifier<DatabaseConnectionStatus>(DatabaseConnectionStatus.checking);

  static Timer? _statusTimer;

  static void startMonitoring({Duration interval = const Duration(seconds: 45)}) {
    _statusTimer?.cancel();
    checkConnectionStatus();
    _statusTimer = Timer.periodic(interval, (_) => checkConnectionStatus());
  }

  static void stopMonitoring() {
    _statusTimer?.cancel();
    _statusTimer = null;
  }

  /// Mengecek kesehatan koneksi database utama dan Supabase backup
  static Future<DatabaseConnectionStatus> checkConnectionStatus() async {
    // 1. Cek koneksi ke Primary API (api-v2)
    bool isPrimaryOnline = false;
    try {
      final res = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/products'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        isPrimaryOnline = true;
      }
    } catch (_) {
      isPrimaryOnline = false;
    }

    if (isPrimaryOnline) {
      connectionStatusNotifier.value = DatabaseConnectionStatus.primaryOnline;
      return DatabaseConnectionStatus.primaryOnline;
    }

    // 2. Jika Primary offline, cek kesiapan Supabase Backup
    bool isSupabaseOnline = false;
    try {
      final supabase = Supabase.instance.client;
      await supabase.from('munit').select('tyunit').limit(1);
      isSupabaseOnline = true;
    } catch (_) {
      isSupabaseOnline = false;
    }

    if (isSupabaseOnline) {
      connectionStatusNotifier.value =
          DatabaseConnectionStatus.primaryOfflineSupabaseReady;
      return DatabaseConnectionStatus.primaryOfflineSupabaseReady;
    }

    // 3. Keduanya offline -> Mode lokal HP
    connectionStatusNotifier.value = DatabaseConnectionStatus.offlineLocal;
    return DatabaseConnectionStatus.offlineLocal;
  }

  /// Sinkronisasi master produk dan data stok dari database utama ke Supabase
  static Future<bool> syncMasterProducts(List<Item> products) async {
    if (products.isEmpty) return false;

    try {
      final supabase = Supabase.instance.client;
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);

      final List<Map<String, dynamic>> records = products.map((item) {
        return {
          'tyunit': item.tyunit,
          'ntyunit': item.name,
          'hjual': item.price,
          'stock': item.stock,
          'kdklp': item.kelompok,
          'kuota': item.kuota,
          'terjual': item.terjual,
          'sisa_kuota': item.sisaKuota,
          'userup': 'system_sync',
          'tglup': todayStr,
        };
      }).toList();

      await supabase.from('munit').upsert(records);
      debugPrint('Berhasil sinkronisasi ${records.length} produk & data stok ke Supabase.');
      return true;
    } catch (e) {
      debugPrint('Gagal sinkronisasi produk ke Supabase: $e');
      return false;
    }
  }

  /// Mengambil data master produk & stok dari Supabase jika database utama gagal
  static Future<List<Item>> fetchProductsFromSupabase() async {
    final supabase = Supabase.instance.client;
    final res = await supabase.from('munit').select('*').order('tyunit');

    final list = (res as List).map((json) {
      return Item.fromJson(json);
    }).toList();

    return list;
  }
}
