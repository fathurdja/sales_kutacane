import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/config/api_config.dart';
import 'package:kasir_kutacane/models/Item.dart';
import 'package:kasir_kutacane/models/stock_group.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/models/transactionItem.dart';
import 'package:kasir_kutacane/services/auth_service.dart';
import 'package:kasir_kutacane/services/offline_sync_service.dart';
import 'package:kasir_kutacane/services/stock_api_service.dart';
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

  /// Cek cepat apakah server utama Laravel aktif dan dapat dijangkau
  static Future<bool> isPrimaryServerOnline() async {
    try {
      final res = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/products'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Mengecek kesehatan koneksi database utama dan Supabase backup
  static Future<DatabaseConnectionStatus> checkConnectionStatus() async {
    // 1. Cek koneksi ke Primary API (api-v2)
    final bool primaryOnline = await isPrimaryServerOnline();

    if (primaryOnline) {
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
  /// Menjaga agar data stok (munit) di Supabase selalu terbarui
  static Future<bool> syncMasterProducts(List<Item> products) async {
    if (products.isEmpty) return false;

    try {
      final supabase = Supabase.instance.client;
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);

      final List<Map<String, dynamic>> records = products
          .where((item) => item.tyunit.isNotEmpty && item.tyunit != '00-123')
          .map((item) {
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

      if (records.isNotEmpty) {
        await supabase.from('munit').upsert(records);
        debugPrint('Berhasil sinkronisasi ${records.length} produk & data stok ke Supabase.');
      }
      return true;
    } catch (e) {
      debugPrint('Gagal sinkronisasi produk ke Supabase: $e');
      return false;
    }
  }

  /// Mengambil data master produk & stok dari Supabase jika database utama gagal
  static Future<List<Item>> fetchProductsFromSupabase() async {
    try {
      final supabase = Supabase.instance.client;
      final res = await supabase
          .from('munit')
          .select('*')
          .neq('tyunit', '00-123')
          .order('tyunit');

      final list = (res as List).map((json) {
        return Item.fromJson(json as Map<String, dynamic>);
      }).where((p) => p.tyunit.trim().isNotEmpty).toList();

      return list;
    } catch (e) {
      debugPrint('Gagal fetchProductsFromSupabase: $e');
      return [];
    }
  }

  /// Mengambil ringkasan stok kelompok komoditas (Galon, Botol 600, Botol 1500, Gelas)
  /// dari tabel munit Supabase saat server utama sedang offline.
  static Future<List<StockGroup>> fetchStockSummaryFromSupabase() async {
    try {
      final supabase = Supabase.instance.client;
      final res = await supabase
          .from('munit')
          .select('*')
          .neq('tyunit', '00-123')
          .order('tyunit');

      final List<dynamic> list = res as List<dynamic>;
      if (list.isEmpty) return [];

      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (final raw in list) {
        final map = raw as Map<String, dynamic>;
        final kdklp = map['kdklp']?.toString().toUpperCase();
        if (kdklp == null || kdklp.isEmpty) continue;
        grouped.putIfAbsent(kdklp, () => []).add(map);
      }

      const order = ['GALON', 'BOTOL_600', 'BOTOL_1500', 'GELAS'];
      final List<StockGroup> result = [];

      for (final groupKey in order) {
        final items = grouped[groupKey];
        if (items == null || items.isEmpty) continue;

        int maxKuota = 0;
        int totalTerjual = 0;
        int sisaStock = 0;
        List<StockVariantDetail> rincian = [];

        for (final it in items) {
          final kuota = (it['kuota'] is num)
              ? (it['kuota'] as num).toInt()
              : (int.tryParse(it['kuota']?.toString() ?? '0') ?? 0);
          if (kuota > maxKuota) maxKuota = kuota;

          final terjual = (it['terjual'] is num)
              ? (it['terjual'] as num).toInt()
              : (int.tryParse(it['terjual']?.toString() ?? '0') ?? 0);
          totalTerjual += terjual;

          final sisa = (it['sisa_kuota'] is num)
              ? (it['sisa_kuota'] as num).toInt()
              : (int.tryParse(it['sisa_kuota']?.toString() ?? '0') ?? 0);
          final stock = (it['stock'] is num)
              ? (it['stock'] as num).toInt()
              : (int.tryParse(it['stock']?.toString() ?? '0') ?? 0);
          final currentSisa = sisa > 0 ? sisa : stock;
          if (currentSisa > sisaStock) sisaStock = currentSisa;

          rincian.add(StockVariantDetail(
            tyunit: it['tyunit']?.toString() ?? '',
            namaProduk: it['ntyunit']?.toString() ?? '',
            harga: (it['hjual'] is num)
                ? (it['hjual'] as num).toDouble()
                : (double.tryParse(it['hjual']?.toString() ?? '0') ?? 0.0),
            terjual: terjual,
          ));
        }

        if (maxKuota == 0 && (sisaStock + totalTerjual) > 0) {
          maxKuota = sisaStock + totalTerjual;
        }

        result.add(StockGroup(
          kelompok: groupKey,
          displayName: StockGroup.getDisplayName(groupKey),
          unitName: StockGroup.getUnitName(groupKey),
          stockAwal: maxKuota,
          totalTerjual: totalTerjual,
          sisaStock: sisaStock,
          jumlahProduk: items.length,
          rincianProduk: rincian,
        ));
      }

      return result;
    } catch (e) {
      debugPrint('Gagal fetchStockSummaryFromSupabase: $e');
      return [];
    }
  }

  /// Mengurangi sisa kuota & stock pada tabel munit di Supabase saat transaksi offline dibuat
  static Future<void> decrementSupabaseStock(List<TransactionItem> items) async {
    if (items.isEmpty) return;
    try {
      final supabase = Supabase.instance.client;
      final res = await supabase.from('munit').select('*');
      final List<Map<String, dynamic>> allMunit =
          List<Map<String, dynamic>>.from(res as List);

      final Map<String, int> qtyPerKelompok = {};
      final Map<String, int> qtyPerTyunit = {};

      for (final item in items) {
        final totalQty = item.quantity + item.bonus;
        if (totalQty <= 0) continue;

        final tyunit = item.tyunit?.trim().toUpperCase() ?? '';
        final matched = allMunit.firstWhere(
          (m) => m['tyunit']?.toString().toUpperCase() == tyunit,
          orElse: () => {},
        );

        final kdklp = matched['kdklp']?.toString().toUpperCase() ?? '';
        if (kdklp.isNotEmpty) {
          qtyPerKelompok[kdklp] = (qtyPerKelompok[kdklp] ?? 0) + totalQty;
        }
        if (tyunit.isNotEmpty) {
          qtyPerTyunit[tyunit] = (qtyPerTyunit[tyunit] ?? 0) + totalQty;
        }
      }

      final List<Map<String, dynamic>> updates = [];
      for (final row in allMunit) {
        final kdklp = row['kdklp']?.toString().toUpperCase() ?? '';
        final tyunit = row['tyunit']?.toString().toUpperCase() ?? '';
        final int deductionForGroup = qtyPerKelompok[kdklp] ?? 0;
        final int deductionForVariant = qtyPerTyunit[tyunit] ?? 0;

        if (deductionForGroup > 0 || deductionForVariant > 0) {
          final currentSisa = (row['sisa_kuota'] is num)
              ? (row['sisa_kuota'] as num).toInt()
              : (int.tryParse(row['sisa_kuota']?.toString() ?? '0') ?? 0);
          final currentStock = (row['stock'] is num)
              ? (row['stock'] as num).toInt()
              : (int.tryParse(row['stock']?.toString() ?? '0') ?? 0);
          final currentTerjual = (row['terjual'] is num)
              ? (row['terjual'] as num).toInt()
              : (int.tryParse(row['terjual']?.toString() ?? '0') ?? 0);

          final newSisa = (currentSisa - deductionForGroup).clamp(0, 999999);
          final newStock = (currentStock - deductionForGroup).clamp(0, 999999);
          final newTerjual = currentTerjual + deductionForVariant;

          updates.add({
            'tyunit': row['tyunit'],
            'ntyunit': row['ntyunit'],
            'hjual': row['hjual'],
            'stock': newStock,
            'kdklp': row['kdklp'],
            'kuota': row['kuota'],
            'terjual': newTerjual,
            'sisa_kuota': newSisa,
            'userup': 'offline_sale',
            'tglup': DateTime.now().toIso8601String().substring(0, 10),
          });
        }
      }

      if (updates.isNotEmpty) {
        await supabase.from('munit').upsert(updates);
        debugPrint('Berhasil memperbarui stok ${updates.length} produk di Supabase munit.');
      }
    } catch (e) {
      debugPrint('Gagal decrementSupabaseStock: $e');
    }
  }

  /// Sinkronisasi otomatis transaksi yang tercatat di Supabase ke Server Utama (Laravel)
  /// dan membersihkan buffer transaksi (transaksi & transaksi_items) di Supabase setelah data cocok.
  /// PENTING: Data master stok (munit) TIDAK PERNAH DIHAPUS.
  static Future<void> syncSupabaseTransactionsToServer() async {
    try {
      final supabase = Supabase.instance.client;
      final trxList = await supabase.from('transaksi').select('*');
      if (trxList.isEmpty) return;

      debugPrint('Ditemukan ${trxList.length} transaksi di buffer Supabase untuk disinkronkan.');

      final headers = await AuthService.getAuthHeaders();
      final String apiUrl = '${ApiConfig.baseUrl}/transaksi';

      for (final trxMap in trxList) {
        final String idTransaksi = trxMap['id_transaksi']?.toString() ?? '';
        if (idTransaksi.isEmpty) continue;

        // Cek apakah transaksi sudah ada di server utama
        bool alreadyExists = false;
        try {
          final checkRes = await http
              .get(
                Uri.parse('$apiUrl?search=$idTransaksi'),
                headers: headers,
              )
              .timeout(const Duration(seconds: 4));

          if (checkRes.statusCode == 200) {
            final dynamic decoded = jsonDecode(checkRes.body);
            if (decoded is List) {
              alreadyExists = decoded.any((t) => t['id_transaksi'] == idTransaksi);
            }
          }
        } catch (_) {}

        if (alreadyExists) {
          // Data transaksi sudah masuk dan cocok di server utama -> Hapus buffer di Supabase
          try {
            await supabase.from('transaksi_items').delete().eq('id_transaksi', idTransaksi);
            await supabase.from('transaksi').delete().eq('id_transaksi', idTransaksi);
            await OfflineSyncService.removePendingTransaction(idTransaksi);
            debugPrint('Transaksi $idTransaksi sudah ada di Laravel. Buffer Supabase dibersihkan.');
          } catch (e) {
            debugPrint('Gagal membersihkan buffer Supabase untuk $idTransaksi: $e');
          }
          continue;
        }

        // Transaksi belum ada di server utama -> Kirim ke Laravel
        try {
          final itemsRes = await supabase
              .from('transaksi_items')
              .select('*')
              .eq('id_transaksi', idTransaksi);

          final List<dynamic> itemsList = itemsRes as List<dynamic>;

          final String dateStr = trxMap['tanggal']?.toString() ??
              trxMap['date']?.toString() ??
              DateTime.now().toIso8601String();
          final formattedDate = dateStr.contains('T')
              ? dateStr.replaceAll('T', ' ').substring(0, 19)
              : dateStr;

          final payload = {
            'id_transaksi': idTransaksi,
            'customerName': trxMap['customer_name'] ?? trxMap['customerName'] ?? '',
            'customer_name': trxMap['customer_name'] ?? trxMap['customerName'] ?? '',
            'alamat': trxMap['alamat'] ?? '',
            'date': formattedDate,
            'tanggal': formattedDate,
            'user_id': trxMap['user_id'] ?? AuthService.currentUser?.id,
            'user_name': trxMap['user_name'] ?? trxMap['sales_name'] ?? AuthService.currentUser?.name,
            'total': trxMap['total'] ?? 0,
            'status': trxMap['status'] ?? 'LUNAS',
            if (trxMap['tanggal_pelunasan'] != null)
              'tanggal_pelunasan': trxMap['tanggal_pelunasan'],
            'items': itemsList.map((it) {
              final itemMap = it as Map<String, dynamic>;
              return {
                'tyunit': itemMap['tyunit'] ?? 'BV01',
                'name': itemMap['nama_barang'] ?? '',
                'nama_barang': itemMap['nama_barang'] ?? '',
                'price': itemMap['harga'] ?? 0,
                'quantity': itemMap['quantity'] ?? 1,
                'bonus': itemMap['bonus'] ?? 0,
                'subtotal': itemMap['subtotal'] ?? 0,
              };
            }).toList(),
          };

          final postRes = await http
              .post(
                Uri.parse(apiUrl),
                headers: headers,
                body: jsonEncode(payload),
              )
              .timeout(const Duration(seconds: 10));

          final isDuplicate = postRes.statusCode == 409 ||
              postRes.body.contains('Duplicate entry') ||
              postRes.body.contains('1062') ||
              postRes.body.toLowerCase().contains('already exists');

          if (postRes.statusCode == 200 || postRes.statusCode == 201 || isDuplicate) {
            // Berhasil tersimpan di server utama -> Hapus buffer transaksi di Supabase
            await supabase.from('transaksi_items').delete().eq('id_transaksi', idTransaksi);
            await supabase.from('transaksi').delete().eq('id_transaksi', idTransaksi);
            await OfflineSyncService.removePendingTransaction(idTransaksi);
            debugPrint('Berhasil sync transaksi $idTransaksi ke Laravel & buffer Supabase dihapus.');
          } else {
            debugPrint('Gagal sync $idTransaksi ke server utama: ${postRes.statusCode} - ${postRes.body}');
          }
        } catch (postErr) {
          debugPrint('Error sync transaksi $idTransaksi: $postErr');
        }
      }

      // Perbarui stok master (munit) di Supabase dengan stok resmi terbaru dari Laravel
      try {
        final latestProducts = await StockApiService.fetchProducts();
        if (latestProducts.isNotEmpty) {
          await syncMasterProducts(latestProducts);
          debugPrint('Stok di Supabase munit berhasil disinkronkan kembali dengan data Laravel.');
        }
      } catch (e) {
        debugPrint('Catatan: Gagal memperbarui munit setelah sync: $e');
      }
    } catch (e) {
      debugPrint('syncSupabaseTransactionsToServer error: $e');
    }
  }

  /// Mengambil transaksi hari ini dari Supabase cadangan saat server utama offline
  static Future<List<Transaction>> fetchTodayTransactionsFromSupabase() async {
    try {
      final supabase = Supabase.instance.client;
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

      final res = await supabase
          .from('transaksi')
          .select('*')
          .gte('tanggal', '$todayStr 00:00:00')
          .lte('tanggal', '$todayStr 23:59:59')
          .order('tanggal', ascending: false);

      final List<dynamic> list = res as List<dynamic>;
      final List<Transaction> transactions = [];

      for (final raw in list) {
        final map = Map<String, dynamic>.from(raw as Map);
        final idTrx = map['id_transaksi']?.toString() ?? '';

        List<TransactionItem> items = [];
        try {
          final itemsRes = await supabase
              .from('transaksi_items')
              .select('*')
              .eq('id_transaksi', idTrx);
          for (final it in (itemsRes as List)) {
            items.add(TransactionItem.fromData(
              name: it['nama_barang']?.toString() ?? '',
              price: (it['harga'] is num)
                  ? (it['harga'] as num).toDouble()
                  : (double.tryParse(it['harga']?.toString() ?? '0') ?? 0.0),
              quantity: (it['quantity'] is num)
                  ? (it['quantity'] as num).toInt()
                  : (int.tryParse(it['quantity']?.toString() ?? '1') ?? 1),
              bonus: (it['bonus'] is num)
                  ? (it['bonus'] as num).toInt()
                  : (int.tryParse(it['bonus']?.toString() ?? '0') ?? 0),
              tyunit: it['tyunit']?.toString(),
            ));
          }
        } catch (_) {}

        final double total = (map['total'] is num)
            ? (map['total'] as num).toDouble()
            : (double.tryParse(map['total']?.toString() ?? '0') ?? 0.0);

        final rawDate = map['tanggal']?.toString() ?? map['date']?.toString();
        final date = Transaction.parseServerDate(rawDate);

        transactions.add(Transaction(
          id: idTrx,
          id_transaksi: idTrx,
          customerName: map['customer_name']?.toString() ?? '',
          alamat: map['alamat']?.toString() ?? '',
          date: date,
          total: total,
          status: map['status']?.toString() ?? 'LUNAS',
          items: items,
          isOffline: true,
          userName: map['sales_name']?.toString() ?? map['user_name']?.toString(),
        ));
      }

      return transactions;
    } catch (e) {
      debugPrint('Gagal fetchTodayTransactionsFromSupabase: $e');
      return [];
    }
  }
}
