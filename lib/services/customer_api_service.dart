import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kasir_kutacane/config/api_config.dart';
import 'package:kasir_kutacane/models/customer_model.dart';
import 'package:kasir_kutacane/services/auth_service.dart';
import 'package:path_provider/path_provider.dart';

class CustomerApiService {
  static const String _cacheFileName = 'cached_customers.json';

  static Future<File> _getLocalFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_cacheFileName');
  }

  /// Ambil daftar seluruh pelanggan (online dengan sinkronisasi cache lokal)
  static Future<List<Customer>> fetchCustomers({
    String? search,
    bool forceRefresh = false,
  }) async {
    List<Customer> localList = await getCachedCustomers();

    try {
      final headers = await AuthService.getAuthHeaders();
      Uri uri = ApiConfig.customersUri;
      if (search != null && search.trim().isNotEmpty) {
        uri = uri.replace(queryParameters: {'search': search.trim()});
      }

      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        List<dynamic> rawList = [];

        if (decoded is List) {
          rawList = decoded;
        } else if (decoded is Map && decoded['data'] is List) {
          rawList = decoded['data'] as List<dynamic>;
        }

        final serverCustomers = rawList
            .map((item) => Customer.fromJson(item as Map<String, dynamic>))
            .where((c) => c.name.trim().isNotEmpty)
            .toList();

        // Urutkan alfabetis A-Z
        serverCustomers.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );

        if (search == null || search.trim().isEmpty) {
          await cacheCustomers(serverCustomers);
        }

        return serverCustomers;
      }
    } catch (e) {
      debugPrint('CustomerApiService fetch error ($e), fallback ke cache...');
    }

    // Jika offline / gagal, filter secara lokal dari cache
    if (search != null && search.trim().isNotEmpty) {
      final q = search.trim().toLowerCase();
      return localList
          .where(
            (c) =>
                c.name.toLowerCase().contains(q) ||
                c.alamat.toLowerCase().contains(q),
          )
          .toList();
    }

    return localList;
  }

  /// Tambah data pelanggan baru ke server dan perbarui cache lokal
  static Future<Customer> addCustomer({
    required String name,
    String alamat = '',
    String? telepon,
    String? keterangan,
  }) async {
    final cleanName = name.trim();
    final cleanAlamat = alamat.trim().isEmpty ? 'Gorontalo' : alamat.trim();
    final cleanTelepon = telepon?.trim().isNotEmpty == true ? telepon!.trim() : null;
    final cleanKet = keterangan?.trim().isNotEmpty == true ? keterangan!.trim() : null;

    final payload = {
      'name': cleanName,
      'customer_name': cleanName,
      'alamat': cleanAlamat,
      if (cleanTelepon != null) 'telepon': cleanTelepon,
      if (cleanKet != null) 'keterangan': cleanKet,
    };

    final headers = await AuthService.getAuthHeaders();
    try {
      final response = await http
          .post(
            ApiConfig.customersUri,
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body);
        final customerData =
            (decoded is Map && decoded.containsKey('data')) ? decoded['data'] : decoded;
        final created = Customer.fromJson(customerData as Map<String, dynamic>);

        // Tambah ke cache lokal
        await _insertOrUpdateLocalCache(created);
        return created;
      } else {
        String msg = 'Gagal menambah pelanggan (${response.statusCode})';
        try {
          final b = jsonDecode(response.body);
          if (b is Map && b.containsKey('message')) msg = b['message'].toString();
        } catch (_) {}
        throw Exception(msg);
      }
    } catch (e) {
      debugPrint('Server addCustomer failed ($e), simpan sementara ke cache offline');
      // Buat customer lokal sementara jika offline
      final offlineCustomer = Customer(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        name: cleanName,
        alamat: cleanAlamat,
        telepon: cleanTelepon,
        keterangan: cleanKet,
        createdAt: DateTime.now(),
      );
      await _insertOrUpdateLocalCache(offlineCustomer);
      return offlineCustomer;
    }
  }

  /// Edit data pelanggan
  static Future<Customer> updateCustomer({
    required int id,
    required String name,
    String alamat = '',
    String? telepon,
    String? keterangan,
  }) async {
    final cleanName = name.trim();
    final cleanAlamat = alamat.trim();

    final payload = {
      'name': cleanName,
      'customer_name': cleanName,
      'alamat': cleanAlamat,
      'telepon': telepon?.trim(),
      'keterangan': keterangan?.trim(),
    };

    final headers = await AuthService.getAuthHeaders();
    try {
      final response = await http
          .put(
            ApiConfig.customerDetailUri(id),
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body);
        final customerData =
            (decoded is Map && decoded.containsKey('data')) ? decoded['data'] : decoded;
        final updated = Customer.fromJson(customerData as Map<String, dynamic>);
        await _insertOrUpdateLocalCache(updated);
        return updated;
      }
    } catch (e) {
      debugPrint('updateCustomer error: $e');
    }

    // Fallback update lokal
    final fallback = Customer(
      id: id,
      name: cleanName,
      alamat: cleanAlamat,
      telepon: telepon,
      keterangan: keterangan,
      updatedAt: DateTime.now(),
    );
    await _insertOrUpdateLocalCache(fallback);
    return fallback;
  }

  /// Hapus data pelanggan
  static Future<bool> deleteCustomer(int id) async {
    final headers = await AuthService.getAuthHeaders();
    bool serverSuccess = false;
    try {
      final response = await http
          .delete(ApiConfig.customerDetailUri(id), headers: headers)
          .timeout(const Duration(seconds: 8));
      serverSuccess = (response.statusCode == 200 || response.statusCode == 204);
    } catch (e) {
      debugPrint('deleteCustomer error: $e');
    }

    // Hapus dari cache lokal
    try {
      final cached = await getCachedCustomers();
      cached.removeWhere((c) => c.id == id);
      await cacheCustomers(cached);
    } catch (_) {}

    return serverSuccess;
  }

  /// Update / Insert satu pelanggan ke cache lokal
  static Future<void> _insertOrUpdateLocalCache(Customer customer) async {
    try {
      final cached = await getCachedCustomers();
      cached.removeWhere((c) =>
          c.id == customer.id ||
          c.name.trim().toLowerCase() == customer.name.trim().toLowerCase());
      cached.add(customer);
      cached.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      await cacheCustomers(cached);
    } catch (e) {
      debugPrint('Error updating local customer cache: $e');
    }
  }

  /// Simpan seluruh daftar pelanggan ke cache lokal JSON
  static Future<void> cacheCustomers(List<Customer> list) async {
    try {
      if (list.isEmpty) return;
      final file = await _getLocalFile();
      final jsonList = list.map((c) => c.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Gagal cache customer: $e');
    }
  }

  /// Baca cache pelanggan lokal (fallback ke 80 pelanggan awal jika file belum ada)
  static Future<List<Customer>> getCachedCustomers() async {
    try {
      final file = await _getLocalFile();
      if (!await file.exists()) return _getDefaultInitialCustomers();

      final content = await file.readAsString();
      if (content.trim().isEmpty) return _getDefaultInitialCustomers();

      final List<dynamic> data = jsonDecode(content);
      if (data.isEmpty) return _getDefaultInitialCustomers();

      final list = data
          .map<Customer>((json) => Customer.fromJson(json as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return list;
    } catch (e) {
      debugPrint('Gagal baca cache customer: $e');
      return _getDefaultInitialCustomers();
    }
  }

  /// 80 Data Pelanggan Awal dari Rekapitulasi Riwayat Transaksi Server
  static List<Customer> _getDefaultInitialCustomers() {
    final names = [
      '230 Cafe', 'Adira', 'Ajama Kopitiam', 'Als Cafe', 'Anis Naki',
      'Apotik Hanifa', 'Arsya Permai', 'B-One Mart', 'Bima', 'Biro Pengadaan Prop Gtlo',
      'Bisnis Center UBM', 'Bulan Cake', 'Ci Ana', 'Combos A Yani', 'Combos Limboto',
      'CombosKasuari', 'DD Mart', 'Damhil', 'Danny', 'Depan bpjs',
      'Depot Kai', 'Dewi BSM', 'Dikes hasni', 'Dikes Mei', 'Dikes Yankes',
      'El-Madinah', 'Galon Pecah', 'Garuda I donesia', 'Gembira Tamalate', 'Hasjrat Limboto',
      'Hasrat Abadi', 'HSB', 'HSB ( Rully)', 'Humind', 'Hyundai',
      'Ibu Dian', 'Ibu Ella', 'Ibu Hetty', 'Ibu Vita', 'K3 Futsal',
      'Kantin Al-Hijrah', 'Kantin SMA 1', 'Kingdom Gym', 'ko heng', 'konsumen',
      'Koperasi Unisan', 'Lapak Jaman', 'Lapak Syifa Limboto', 'Mama Cece', 'Masuk Rumah',
      'Mulia Mart', 'Nasdem Gorontalo', 'Pak Iwan', 'Pak Kus', 'Pengadilan Agama',
      'PLN', 'Ronny Mandiri', 'rosi BPS', 'rumah', 'Sampoerna',
      'San San', 'San-San', 'Sinar Krida', 'SKY', 'SMP 1',
      'SMP 2', 'SMP 6', 'Sofyan Tambipi', 'Synsana', 'TC Motor',
      'TDT Kota', 'Titi', 'Tk Plastik Mikel', 'Toko Karawo Limboto', 'Toko Mandiri',
      'Toko Nues', 'Yan Melati', 'Yudha', 'Yudi Telaga', 'Yusrin Telaga',
    ];

    int idx = 1;
    return names.map((n) {
      return Customer(
        id: idx++,
        name: n,
        alamat: 'Gorontalo',
      );
    }).toList();
  }
}

