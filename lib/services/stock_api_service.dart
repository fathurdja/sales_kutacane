import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:kasir_kutacane/models/Item.dart';
import 'package:kasir_kutacane/models/stock_group.dart';
import 'package:kasir_kutacane/services/auth_service.dart';

class StockApiService {
  static const String baseUrl = 'https://laravel.fathurrzqn8n.web.id/api';

  /// 1. Ambil Ringkasan Lengkap Kelompok Komoditas Fisik (Stok Awal, Terjual, Sisa, Rincian Varian)
  /// - Jika dipanggil oleh User (Sales): Otomatis menampilkan kuota khusus armadanya.
  /// - Jika Admin: Default menampilkan stok total, atau bisa memfilter dengan parameter [userId].
  static Future<List<StockGroup>> fetchStockSummary({int? userId}) async {
    final uri = userId != null
        ? Uri.parse('$baseUrl/stock-summary?user_id=$userId')
        : Uri.parse('$baseUrl/stock-summary');

    final headers = await AuthService.getAuthHeaders();
    final response = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 8));

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
      throw Exception('Gagal memuat ringkasan stok (${response.statusCode})');
    }
  }

  /// 2. Set Stok Awal (Kuota Masuk) untuk satu kelompok komoditas fisik
  /// - [userId]: Khusus Admin yang ingin mengalokasikan stok ke sales tertentu (misal Sales 1 -> user_id: 2).
  /// - [resetTerjual]: Jika true, counter penjualan varian di kelompok ini akan direset ke 0.
  static Future<Map<String, dynamic>> setStockAwal({
    required String kelompok,
    required int stockAwal,
    int? userId,
    bool resetTerjual = false,
  }) async {
    final payload = {
      'kelompok': kelompok.toUpperCase(),
      'stock_awal': stockAwal,
      if (userId != null) 'user_id': userId,
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

  /// 3. Ambil Rincian Barang Terjual Hari Ini (per varian)
  static Future<Map<String, dynamic>> fetchStockTerjual({
    String? kelompok,
    int? userId,
  }) async {
    final queryParams = <String, String>{};
    if (kelompok != null && kelompok.isNotEmpty) queryParams['kelompok'] = kelompok;
    if (userId != null) queryParams['user_id'] = userId.toString();

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
    int? userId,
  }) async {
    final payload = <String, dynamic>{
      if (kelompok != null && kelompok.isNotEmpty) 'kelompok': kelompok,
      if (userId != null) 'user_id': userId,
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

  /// 5. Ambil Daftar 13 Produk Boneva Lengkap dengan Info Kuota & Sisa
  static Future<List<Item>> fetchProducts() async {
    final headers = await AuthService.getAuthHeaders();
    final response = await http
        .get(Uri.parse('$baseUrl/products'), headers: headers)
        .timeout(const Duration(seconds: 8));

    if (response.statusCode == 200) {
      final List<dynamic> list = jsonDecode(response.body);
      return list.map((json) => Item.fromJson(json as Map<String, dynamic>)).toList();
    } else {
      throw Exception('Gagal memuat daftar produk (${response.statusCode})');
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
        .post(
          Uri.parse('$baseUrl/update-stock'),
          headers: headers,
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      String msg = 'Gagal update data varian (${response.statusCode})';
      try {
        final b = jsonDecode(response.body);
        if (b is Map && b.containsKey('message')) msg = b['message'].toString();
      } catch (_) {}
      throw Exception(msg);
    }
  }
}
