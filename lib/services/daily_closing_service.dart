import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/models/stock_group.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/services/auth_service.dart';
import 'package:kasir_kutacane/services/offline_sync_service.dart';
import 'package:kasir_kutacane/services/stock_api_service.dart';
import 'package:path_provider/path_provider.dart';

class RolloverStockItem {
  final String kelompok;
  final String label;
  final int stockAwalHariIni;
  final int terjualHariIni;
  final int sisaStockHariIni;

  RolloverStockItem({
    required this.kelompok,
    required this.label,
    required this.stockAwalHariIni,
    required this.terjualHariIni,
    required this.sisaStockHariIni,
  });

  int get stockAwalBesok => sisaStockHariIni < 0 ? 0 : sisaStockHariIni;
}

class DailyClosingPreview {
  final int totalTransactions;
  final double totalRevenue;
  final List<RolloverStockItem> stockItems;

  DailyClosingPreview({
    required this.totalTransactions,
    required this.totalRevenue,
    required this.stockItems,
  });
}

class DailyClosingResult {
  final bool success;
  final String archiveFileName;
  final String archiveFilePath;
  final int totalTransactionsArchived;
  final double totalRevenue;
  final List<RolloverStockItem> rolloverItems;
  final String? errorMessage;

  DailyClosingResult({
    required this.success,
    required this.archiveFileName,
    required this.archiveFilePath,
    required this.totalTransactionsArchived,
    required this.totalRevenue,
    required this.rolloverItems,
    this.errorMessage,
  });
}

class DailyClosingService {
  static String getLabelForKelompok(String kelompok) {
    switch (kelompok.toUpperCase()) {
      case 'GALON':
        return 'Galon Boneva (19L)';
      case 'BOTOL_600':
        return 'Botol 600ml';
      case 'BOTOL_1500':
        return 'Botol 1500ml';
      case 'GELAS':
        return 'Gelas 220ml';
      default:
        return kelompok;
    }
  }

  /// Mengambil data ringkasan stok hari ini dan rincian transaksi untuk preview sebelum tutup buku
  static Future<DailyClosingPreview> getClosingPreview(
      List<Transaction> transactions) async {
    List<StockGroup> groups = [];
    try {
      groups = await StockApiService.fetchStockSummary();
    } catch (e) {
      debugPrint('Gagal memuat ringkasan stok untuk preview: $e');
    }

    final double revenue = transactions.fold(0.0, (acc, t) => acc + t.total);

    final stockItems = groups.map((g) {
      return RolloverStockItem(
        kelompok: g.kelompok,
        label: getLabelForKelompok(g.kelompok),
        stockAwalHariIni: g.stockAwal,
        terjualHariIni: g.totalTerjual,
        sisaStockHariIni: g.sisaStock,
      );
    }).toList();

    return DailyClosingPreview(
      totalTransactions: transactions.length,
      totalRevenue: revenue,
      stockItems: stockItems,
    );
  }

  /// Otomatis menyimpan transaksi hari ini ke berkas CSV di folder /arsip HP
  static Future<File> autoSaveArchive(List<Transaction> transactions) async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/arsip';
    final folder = Directory(path);

    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }

    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'Arsip_Tutup_Buku_$timestamp.csv';
    final file = File('$path/$fileName');

    final List<List<dynamic>> rows = [
      [
        'ID Transaksi',
        'Customer',
        'Alamat',
        'Tanggal',
        'Status',
        'Total Nota',
        'Kode Varian (TYUNIT)',
        'Nama Produk',
        'Harga Satuan',
        'Jumlah Qty',
        'Bonus',
        'Subtotal',
      ],
    ];

    if (transactions.isEmpty) {
      rows.add(['TIDAK_ADA_TRANSAKSI', '-', '-', DateTime.now().toIso8601String(), '-', 0, '-', '-', 0, 0, 0, 0]);
    } else {
      for (final trx in transactions) {
        final dateStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(trx.date);
        if (trx.items.isEmpty) {
          rows.add([
            trx.id_transaksi,
            trx.customerName,
            trx.alamat,
            dateStr,
            trx.status,
            trx.total,
            '-',
            '-',
            0,
            0,
            0,
            0,
          ]);
        } else {
          for (final item in trx.items) {
            rows.add([
              trx.id_transaksi,
              trx.customerName,
              trx.alamat,
              dateStr,
              trx.status,
              trx.total,
              item.tyunit ?? '-',
              item.name,
              item.price,
              item.quantity,
              item.bonus,
              item.subtotal,
            ]);
          }
        }
      }
    }

    final csvData = const ListToCsvConverter().convert(rows);
    await file.writeAsString(csvData);
    debugPrint('Berhasil auto-archive transaksi ke ${file.path}');
    return file;
  }

  /// Menjalankan proses Tutup Buku Harian Lengkap:
  /// 1. Ambil sisa stok fisik saat ini (sisa_stock = stock_awal - terjual)
  /// 2. Otomatis arsipkan seluruh transaksi ke CSV lokal
  /// 3. Hapus data transaksi dari server & antrean offline
  /// 4. Rollover sisa stok menjadi stok awal besok via POST /api/stock-awal (reset_terjual: true)
  static Future<DailyClosingResult> executeDailyClosing({
    required List<Transaction> transactions,
    bool rolloverStock = true,
  }) async {
    try {
      // 1. Ambil sisa stok sebelum menghapus transaksi
      List<StockGroup> currentGroups = [];
      try {
        currentGroups = await StockApiService.fetchStockSummary();
      } catch (e) {
        debugPrint('Gagal fetch summary sebelum closing: $e');
      }

      final rolloverItems = currentGroups.map((g) {
        return RolloverStockItem(
          kelompok: g.kelompok,
          label: getLabelForKelompok(g.kelompok),
          stockAwalHariIni: g.stockAwal,
          terjualHariIni: g.totalTerjual,
          sisaStockHariIni: g.sisaStock,
        );
      }).toList();

      // 2. Otomatis arsipkan transaksi ke berkas CSV lokal
      final archiveFile = await autoSaveArchive(transactions);
      final archiveFileName = archiveFile.path.split(Platform.isWindows ? '\\' : '/').last;
      final double totalRevenue = transactions.fold(0.0, (acc, t) => acc + t.total);

      // 3. Hapus transaksi di server Laravel (sesuai hak akses pengguna)
      final headers = await AuthService.getAuthHeaders();
      for (final trx in transactions) {
        final id = trx.id_transaksi.isNotEmpty ? trx.id_transaksi : trx.id;
        if (!trx.isOffline && id.isNotEmpty) {
          try {
            await http.delete(
              Uri.parse('https://laravel.fathurrzqn8n.web.id/api/transaksi/$id'),
              headers: headers,
            ).timeout(const Duration(seconds: 8));
          } catch (e) {
            debugPrint('Error delete server trx $id: $e');
          }
        }
      }

      // Bersihkan juga antrean offline
      await OfflineSyncService.clearQueue();

      // 4. Lakukan Rollover Stok: Stok Awal Besok = Sisa Stok Hari Ini, Terjual = 0
      // Catatan: Hanya Admin yang memiliki izin can_manage_stock di server
      final currentUser = await AuthService.getCurrentUser();
      final bool canManage = currentUser == null || currentUser.canManageStock;

      if (rolloverStock && canManage && currentGroups.isNotEmpty) {
        for (final group in currentGroups) {
          final nextStockAwal = group.sisaStock < 0 ? 0 : group.sisaStock;
          try {
            await StockApiService.setStockAwal(
              kelompok: group.kelompok,
              stockAwal: nextStockAwal,
              resetTerjual: true,
            );
            debugPrint(
              'Rollover ${group.kelompok}: Stok Awal Besok = $nextStockAwal, reset terjual = 0',
            );
          } catch (e) {
            debugPrint('Error rollover stok ${group.kelompok}: $e');
          }
        }
      }

      return DailyClosingResult(
        success: true,
        archiveFileName: archiveFileName,
        archiveFilePath: archiveFile.path,
        totalTransactionsArchived: transactions.length,
        totalRevenue: totalRevenue,
        rolloverItems: rolloverItems,
      );
    } catch (e) {
      debugPrint('Error executeDailyClosing: $e');
      return DailyClosingResult(
        success: false,
        archiveFileName: '',
        archiveFilePath: '',
        totalTransactionsArchived: 0,
        totalRevenue: 0,
        rolloverItems: [],
        errorMessage: e.toString(),
      );
    }
  }
}
