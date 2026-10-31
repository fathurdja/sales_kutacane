import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kasir_kutacane/config/api_config.dart';
import 'package:kasir_kutacane/models/user_model.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  /// Login dengan dual-server authentication (Server Laravel utama -> Supabase failover otomatis)
  static Future<UserModel> login({
    required String login,
    required String password,
  }) async {
    final trimmedLogin = login.trim();

    // 1. Coba login ke server Laravel utama terlebih dahulu
    try {
      final uri = Uri.parse('$baseUrl/login');
      final payload = {
        'login': trimmedLogin,
        'password': password,
      };

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'User-Agent': 'Dart/3.5 (dart:io)',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body);
        if (body['success'] == true) {
          final token = body['token']?.toString() ?? '';
          final user = UserModel.fromJson(body['user'] as Map<String, dynamic>);

          _cachedToken = token;
          _cachedUser = user;

          // Simpan session ke file lokal HP
          await _saveSessionToFile(token, user, rawPassword: password);

          // Lakukan background sync user & password ke Supabase agar Supabase selalu sinkron
          _syncUserToSupabase(user, password);

          return user;
        } else {
          final errorMsg = body['message']?.toString() ??
              'Kredensial tidak cocok. Periksa kembali username dan kata sandi.';
          throw Exception(errorMsg);
        }
      } else if (response.statusCode == 401) {
        final Map<String, dynamic> body = jsonDecode(response.body);
        final errorMsg = body['message']?.toString() ??
            'Username atau password salah.';
        throw Exception(errorMsg);
      } else {
        debugPrint(
            'Server Laravel merespons status ${response.statusCode}. Beralih ke Supabase...');
      }
    } on Exception catch (e) {
      final errMsg = e.toString().toLowerCase();
      if (errMsg.contains('kredensial tidak cocok') ||
          errMsg.contains('kata sandi salah') ||
          errMsg.contains('password salah') ||
          errMsg.contains('username atau password salah')) {
        rethrow;
      }
      debugPrint('Koneksi server Laravel gagal ($e). Mencoba autentikasi via Supabase...');
    }

    // 2. FAILOVER AUTENTIKASI VIA SUPABASE
    return await _loginViaSupabase(login: trimmedLogin, password: password);
  }

  /// Autentikasi cadangan menggunakan database Supabase Cloud
  static Future<UserModel> _loginViaSupabase({
    required String login,
    required String password,
  }) async {
    try {
      final supabase = Supabase.instance.client;
      final List<dynamic> users = await supabase
          .from('users')
          .select('*')
          .timeout(const Duration(seconds: 8));

      final q = login.trim().toLowerCase();
      Map<String, dynamic>? matched;

      for (final u in users) {
        if (u is! Map<String, dynamic>) continue;
        final name = (u['name'] ?? '').toString().toLowerCase();
        final email = (u['email'] ?? '').toString().toLowerCase();
        final emailPrefix = email.contains('@') ? email.split('@').first : '';
        final nameNoSpace = name.replaceAll(' ', '');

        if (q == name || q == email || q == emailPrefix || q == nameNoSpace) {
          matched = u;
          break;
        }
      }

      if (matched == null) {
        throw Exception(
          'Akun "$login" tidak ditemukan di server maupun database Supabase.',
        );
      }

      final storedPassword = (matched['password'] ?? '').toString();
      if (storedPassword != password) {
        throw Exception('Kata sandi salah. Silakan periksa kembali.');
      }

      final int id = matched['id'] is num
          ? (matched['id'] as num).toInt()
          : (int.tryParse(matched['id'].toString()) ?? 0);
      final String rawName = matched['name']?.toString() ?? '';
      final String email = matched['email']?.toString() ?? '';
      final bool isAdmin = id == 1 || rawName.toLowerCase().contains('admin');
      final String role = isAdmin ? 'admin' : 'user';
      final String username = rawName.toLowerCase().replaceAll(' ', '');

      final user = UserModel(
        id: id,
        name: rawName,
        username: username,
        email: email,
        role: role,
        isAdmin: isAdmin,
        canManageStock: isAdmin,
      );

      final token = 'supabase_token_${user.id}_${DateTime.now().millisecondsSinceEpoch}';
      _cachedToken = token;
      _cachedUser = user;

      await _saveSessionToFile(token, user, rawPassword: password);

      debugPrint(
          'Autentikasi BERHASIL via Supabase Cloud untuk user: ${user.name} (${user.role})');
      return user;
    } catch (e) {
      debugPrint('Supabase Auth failover error: $e');
      if (e.toString().contains('tidak ditemukan') ||
          e.toString().contains('Kata sandi salah')) {
        rethrow;
      }
      // Jika jaringan offline total, verifikasi terhadap session lokal
      return await _loginOfflineLocal(login: login, password: password);
    }
  }

  /// Autentikasi lokal offline jika tidak ada koneksi sama sekali
  static Future<UserModel> _loginOfflineLocal({
    required String login,
    required String password,
  }) async {
    try {
      final file = await _getSessionFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final data = jsonDecode(content);
          final savedUser =
              UserModel.fromJson(data['user'] as Map<String, dynamic>);
          final savedPass = data['saved_password']?.toString();

          final q = login.trim().toLowerCase();
          final matches = q == savedUser.name.toLowerCase() ||
              q == savedUser.username.toLowerCase() ||
              q == savedUser.email.toLowerCase();

          if (matches && savedPass == password) {
            _cachedUser = savedUser;
            _cachedToken = data['token']?.toString() ?? 'offline_local_token';
            return savedUser;
          }
        }
      }
    } catch (_) {}

    throw Exception(
      'Gagal terhubung ke server utama dan Supabase. Pastikan koneksi internet aktif.',
    );
  }

  /// Sinkronkan user & password ke Supabase agar selalu update
  static Future<void> _syncUserToSupabase(
    UserModel user,
    String password,
  ) async {
    try {
      final supabase = Supabase.instance.client;
      await supabase.from('users').upsert({
        'id': user.id,
        'name': user.name,
        'email': user.email,
        'password': password,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Catatan: Background sync user ke Supabase: $e');
    }
  }

  /// Simpan session ke file lokal
  static Future<void> _saveSessionToFile(
    String token,
    UserModel user, {
    String? rawPassword,
  }) async {
    try {
      final file = await _getSessionFile();
      final data = {
        'token': token,
        'user': user.toJson(),
        if (rawPassword != null) 'saved_password': rawPassword,
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
    try {
      final headers = await getAuthHeaders();
      final response = await http
          .get(Uri.parse('$baseUrl/users'), headers: headers)
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body);
        final List<dynamic> list = body['data'] ?? [];
        return list
            .map((json) => UserModel.fromJson(json as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint(
          'Gagal fetch users dari server Laravel ($e), mencoba Supabase...');
    }

    // Failover ke Supabase users
    try {
      final supabase = Supabase.instance.client;
      final res = await supabase.from('users').select('*').order('id');
      final List<UserModel> fallbackUsers = [];
      for (final raw in res) {
        final int id = raw['id'] is num
            ? (raw['id'] as num).toInt()
            : (int.tryParse(raw['id'].toString()) ?? 0);
        final String name = raw['name']?.toString() ?? '';
        final String email = raw['email']?.toString() ?? '';
        final bool isAdmin = id == 1 || name.toLowerCase().contains('admin');
        fallbackUsers.add(
          UserModel(
            id: id,
            name: name,
            username: name.toLowerCase().replaceAll(' ', ''),
            email: email,
            role: isAdmin ? 'admin' : 'user',
            isAdmin: isAdmin,
            canManageStock: isAdmin,
          ),
        );
      }
      if (fallbackUsers.isNotEmpty) return fallbackUsers;
    } catch (eSupabase) {
      debugPrint('Supabase fetch users error: $eSupabase');
    }

    return [];
  }
}
