import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:kasir_kutacane/models/stock_change_log.dart';
import 'package:path_provider/path_provider.dart';

class StockChangeLogService {
  static const String _fileName = 'stock_change_logs.json';

  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Menambahkan satu entri riwayat perubahan stok
  static Future<void> addLog(StockChangeLog log) async {
    try {
      final file = await _getFile();
      List<dynamic> logs = [];

      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          logs = jsonDecode(content);
        }
      }

      // Masukkan log baru di awal (terbaru di atas)
      logs.insert(0, log.toJson());

      // Batasi maksimal 500 entri log terakhir agar tidak membengkak
      if (logs.length > 500) {
        logs = logs.sublist(0, 500);
      }

      await file.writeAsString(jsonEncode(logs));
      debugPrint('Log perubahan stok dicatat: ${log.kelompok} +${log.tambahanQty} (sisa: ${log.sisaSebelum} -> ${log.sisaSesudah})');
    } catch (e) {
      debugPrint('Gagal menyimpan log perubahan stok: $e');
    }
  }

  /// Mengambil daftar seluruh riwayat perubahan stok, diurutkan dari yang paling baru
  static Future<List<StockChangeLog>> getLogs({String? kelompok}) async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return [];

      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];

      final List<dynamic> data = jsonDecode(content);
      var list = data
          .map((json) => StockChangeLog.fromJson(json as Map<String, dynamic>))
          .toList();

      if (kelompok != null && kelompok.isNotEmpty && kelompok.toUpperCase() != 'SEMUA') {
        list = list.where((l) => l.kelompok.toUpperCase() == kelompok.toUpperCase()).toList();
      }

      // Pastikan urut terbaru
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return list;
    } catch (e) {
      debugPrint('Gagal membaca log perubahan stok: $e');
      return [];
    }
  }

  /// Mengambil entri log terakhir untuk kelompok komoditas tertentu
  static Future<StockChangeLog?> getLastLogForKelompok(String kelompok) async {
    try {
      final logs = await getLogs(kelompok: kelompok);
      return logs.firstOrNull;
    } catch (_) {
      return null;
    }
  }

  /// Menghapus seluruh riwayat log
  static Future<void> clearLogs() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        await file.writeAsString(jsonEncode([]));
      }
    } catch (e) {
      debugPrint('Gagal membersihkan log perubahan stok: $e');
    }
  }
}

