import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kasir_kutacane/config/api_config.dart';
import 'package:kasir_kutacane/models/user_model.dart';
import 'package:path_provider/path_provider.dart';

class AuthService {
  static String get baseUrl => ApiConfig.baseUrl;
  static const String _sessionFileName = 'user_session.json';

  static UserModel? _cachedUser;
  static String? _cachedToken;

  static UserModel? get currentUser => _cachedUser;
  static String? get currentToken => _cachedToken;

  /// Inisialisasi awal saat aplikasi dibuka
  static Future<void> init() async {
    await _loadSessionFromFile();
  }

  static Future<File> _getSessionFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_sessionFileName');
  }

  /// Mengambil header default dengan Bearer Token jika sudah login
  static Future<Map<String, String>> getAuthHeaders() async {
    final token = await getToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// Login ke server Laravel menggunakan username atau email
  static Future<UserModel> login({
    required String login,
    required String password,
  }) async {
    final uri = Uri.parse('$baseUrl/login');
    final payload = {
      'login': login.trim(),
      'password': password,
    };

    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 10));

    final Map<String, dynamic> body = jsonDecode(response.body);

    if (response.statusCode == 200 && body['success'] == true) {
      final token = body['token']?.toString() ?? '';
      final user = UserModel.fromJson(body['user'] as Map<String, dynamic>);

      _cachedToken = token;
      _cachedUser = user;

      // Simpan session ke penyimpanan HP
      await _saveSessionToFile(token, user);

      return user;
    } else {
      final errorMsg = body['message']?.toString() ??
          'Login gagal. Periksa username dan password.';
      throw Exception(errorMsg);
    }
  }

  /// Simpan session ke file lokal
  static Future<void> _saveSessionToFile(String token, UserModel user) async {
    try {
      final file = await _getSessionFile();
      final data = {
        'token': token,
        'user': user.toJson(),
        'saved_at': DateTime.now().toIso8601String(),
      };
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('Error saving session file: $e');
    }
  }

  /// Cek apakah pengguna sudah login
  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// Ambil Token login aktif
  static Future<String?> getToken() async {
    if (_cachedToken != null && _cachedToken!.isNotEmpty) {
      return _cachedToken;
    }
    await _loadSessionFromFile();
    return _cachedToken;
  }

  /// Ambil Profil User aktif
  static Future<UserModel?> getCurrentUser() async {
    if (_cachedUser != null) {
      return _cachedUser;
    }
    await _loadSessionFromFile();
    return _cachedUser;
  }

  /// Muat session dari file lokal
  static Future<void> _loadSessionFromFile() async {
    try {
      final file = await _getSessionFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final Map<String, dynamic> data = jsonDecode(content);
          _cachedToken = data['token']?.toString();
          if (data['user'] != null) {
            _cachedUser =
                UserModel.fromJson(data['user'] as Map<String, dynamic>);
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading session file: $e');
    }
  }

  /// Refresh profil user dari server via GET /api/me
  static Future<UserModel?> checkMe() async {
    try {
      final headers = await getAuthHeaders();
      final response = await http
          .get(Uri.parse('$baseUrl/me'), headers: headers)
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['user'] != null) {
          final user =
              UserModel.fromJson(data['user'] as Map<String, dynamic>);
          _cachedUser = user;
          final token = await getToken();
          if (token != null) {
            await _saveSessionToFile(token, user);
          }
          return user;
        }
      }
    } catch (e) {
      debugPrint('Check me error: $e');
    }
    return getCurrentUser();
  }

  /// Logout akun
  static Future<void> logout() async {
    try {
      final headers = await getAuthHeaders();
      await http
          .post(Uri.parse('$baseUrl/logout'), headers: headers)
          .timeout(const Duration(seconds: 4));
    } catch (_) {}

    _cachedToken = null;
    _cachedUser = null;

    try {
      final file = await _getSessionFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Error deleting session file: $e');
    }
  }

  /// Khusus Admin: Ambil daftar seluruh sales & ringkasan omset (GET /api/users)
  static Future<List<UserModel>> fetchUsers() async {
    final headers = await getAuthHeaders();
    final response = await http
        .get(Uri.parse('$baseUrl/users'), headers: headers)
        .timeout(const Duration(seconds: 8));

    if (response.statusCode == 200) {
      final Map<String, dynamic> body = jsonDecode(response.body);
      final List<dynamic> list = body['data'] ?? [];
      return list
          .map((json) => UserModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } else {
      throw Exception('Gagal memuat daftar sales (${response.statusCode})');
    }
  }
}
