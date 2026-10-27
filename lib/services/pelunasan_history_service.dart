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

class PelunasanHistoryService {
  static const String _fileName = 'pelunasan_history.json';

  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
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

  /// Menyimpan riwayat pelunasan baru
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
}
