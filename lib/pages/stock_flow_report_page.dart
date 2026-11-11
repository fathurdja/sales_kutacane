import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/config/api_config.dart';
import 'package:kasir_kutacane/models/stock_change_log.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/services/auth_service.dart';
import 'package:kasir_kutacane/services/offline_sync_service.dart';
import 'package:kasir_kutacane/services/pending_stock_sync_service.dart';
import 'package:kasir_kutacane/services/stock_api_service.dart';
import 'package:kasir_kutacane/services/stock_change_log_service.dart';
import 'package:kasir_kutacane/theme/app_theme.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ringkasan keluar masuk per komoditas fisik
class CommodityFlowSummary {
  final String kelompok; // GALON, BOTOL_600, BOTOL_1500, GELAS
  final String displayName;
  final String unitName;
  int sisaKemarin = 0; // Sisa stok hari sebelumnya / stok awal
  int masukHariIni = 0; // Stok masuk / pasokan baru murni hari ini
  int masuk = 0; // Kompatibilitas
  int keluar = 0; // Stok terjual hari ini
  int currentSisa = 0; // Sisa fisik terkini / sisa akumulasi
  int totalTransaksi = 0;
  double totalNominal = 0;

  CommodityFlowSummary({
    required this.kelompok,
    required this.displayName,
    required this.unitName,
    this.sisaKemarin = 0,
    this.masukHariIni = 0,
    this.masuk = 0,
    this.keluar = 0,
    this.currentSisa = 0,
    this.totalTransaksi = 0,
    this.totalNominal = 0,
  });

  /// Selisih stok murni hari ini (Stok Masuk Hari Ini - Stok Terjual Hari Ini)
  int get selisihHariIni => (masukHariIni > 0 || sisaKemarin > 0 ? masukHariIni : masuk) - keluar;

  /// Sisa stok akumulasi akhir periode (Sisa Kemarin + Masuk Hari Ini - Terjual Hari Ini)
  int get sisaAkumulasi => sisaKemarin + (masukHariIni > 0 ? masukHariIni : masuk) - keluar;

  /// Kompatibilitas untuk kode/test lama yang membaca .net
  int get net => (masukHariIni > 0 || sisaKemarin > 0 ? masukHariIni : masuk) - keluar;
}

/// Rekap data harian untuk tabel bulanan
class DailyStockFlowRecord {
  final DateTime date;
  int sisaKemarin = 0; // Stok awal bawaan kemarin
  int masukHariIni = 0; // Penambahan pasokan hari ini
  int totalMasuk = 0; // Kompatibilitas
  int totalKeluar = 0;
  int sisaAkumulasiRecord = 0;
  int logCount = 0;
  int transactionCount = 0;
  double totalNominal = 0;
  String? hari;
  final Map<String, int> masukPerKelompok = {};
  final Map<String, int> keluarPerKelompok = {};

  DailyStockFlowRecord({
    required this.date,
    this.sisaKemarin = 0,
    this.masukHariIni = 0,
    this.totalMasuk = 0,
    this.totalKeluar = 0,
    this.sisaAkumulasiRecord = 0,
    this.logCount = 0,
    this.transactionCount = 0,
    this.totalNominal = 0,
    this.hari,
  });

  /// Selisih murni transaksi hari ini
  int get selisihHariIni => (masukHariIni > 0 || sisaKemarin > 0 ? masukHariIni : totalMasuk) - totalKeluar;

  /// Sisa akumulasi akhir hari tersebut
  int get sisaAkumulasi => sisaAkumulasiRecord > 0 ? sisaAkumulasiRecord : (sisaKemarin + (masukHariIni > 0 ? masukHariIni : totalMasuk) - totalKeluar);

  int get net => selisihHariIni;
  bool get hasActivity => (masukHariIni > 0 || totalMasuk > 0) || totalKeluar > 0 || sisaKemarin > 0;
}

class StockFlowReportPage extends StatefulWidget {
  const StockFlowReportPage({super.key});

  /// Resolusi kelompok komoditas fisik dari kode varian & nama barang
  static String resolveCommodityKelompok({String? tyunit, String? itemName}) {
    final code = (tyunit ?? '').toUpperCase().trim();
    final name = (itemName ?? '').toLowerCase();

    if (code.contains('BV01') ||
        code.contains('BV02') ||
        code.contains('BV03') ||
        code.contains('BV04') ||
        code.contains('BV05') ||
        code.contains('BV06') ||
        code.contains('BV07') ||
        name.contains('galon')) {
      return 'GALON';
    }
    if (code.contains('BV08') ||
        code.contains('BV09') ||
        code.contains('BV10') ||
        code.contains('BV11') ||
        code.contains('BV12') ||
        code.contains('BV13') ||
        name.contains('600')) {
      return 'BOTOL_600';
    }
    if (code.contains('BV14') ||
        code.contains('BV15') ||
        code.contains('BV16') ||
        code.contains('BV17') ||
        name.contains('1,5') ||
        name.contains('1.5')) {
      return 'BOTOL_1500';
    }
    if (code.contains('BV18') ||
        code.contains('BV19') ||
        code.contains('BV20') ||
        code.contains('BV21') ||
        code.contains('BV22') ||
        code.contains('BV23') ||
        name.contains('gelas')) {
      return 'GELAS';
    }
    return 'LAINNYA';
  }

  @override
  State<StockFlowReportPage> createState() => _StockFlowReportPageState();
}

class _StockFlowReportPageState extends State<StockFlowReportPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isLoading = true;
  String? _errorMessage;
  bool _isSyncingServer = false;

  // Mode: 0 = Harian, 1 = Mingguan, 2 = Bulanan, 3 = Rentang Tanggal
  DateTime _selectedDate = DateTime.now();
  late DateTime _selectedWeekStart;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  late DateTime _customStartDate;
  late DateTime _customEndDate;
  String _selectedKelompok = 'ALL'; // 'ALL', 'GALON', 'BOTOL_600', 'BOTOL_1500', 'GELAS'

  Map<String, dynamic>? _serverDailyData;
  Map<String, dynamic>? _serverWeeklyData;
  Map<String, dynamic>? _serverMonthlyData;
  Map<String, dynamic>? _serverCustomRangeData;

  List<StockChangeLog> _allStockLogs = [];
  List<Transaction> _allTransactions = [];

  final DateFormat _dateFormat = DateFormat('dd MMMM yyyy');
  final DateFormat _monthFormat = DateFormat('MMMM yyyy');
  final DateFormat _timeFormat = DateFormat('HH:mm');

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedWeekStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    _customEndDate = DateTime(now.year, now.month, now.day);
    _customStartDate = _customEndDate.subtract(const Duration(days: 6));

    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Memuat data dari Server API-v2 (Monitoring Stok Harian, Mingguan, Bulanan, & Rentang)
  /// dengan fallback otomatis ke log lokal dan cache transaksi jika offline
  Future<void> _loadAllData() async {
    if (AuthService.currentUser?.isAdmin != true) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Akses ditolak: Menu ini khusus Administrator.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 0. Sinkronkan antrean penambahan stok offline ke server jika sudah online
      try {
        await PendingStockSyncService.syncPendingStockEntries();
      } catch (errSync) {
        debugPrint('Catatan: syncPendingStockEntries ditunda: $errSync');
      }

      // Ambil monitoring dari server API-v2
      try {
        _serverDailyData = await StockApiService.fetchStockMonitoring(
          date: _selectedDateStr,
        );
      } catch (e) {
        debugPrint('Gagal fetch daily monitoring dari API ($e)');
        _serverDailyData = null;
      }

      try {
        _serverWeeklyData = await StockApiService.fetchStockMonitoring(
          startDate: _selectedWeekStartStr,
          endDate: _selectedWeekEndStr,
        );
      } catch (e) {
        debugPrint('Gagal fetch weekly monitoring dari API ($e)');
        _serverWeeklyData = null;
      }

      try {
        _serverMonthlyData = await StockApiService.fetchStockMonitoring(
          month: _selectedMonthStr,
        );
      } catch (e) {
        debugPrint('Gagal fetch monthly monitoring dari API ($e)');
        _serverMonthlyData = null;
      }

      try {
        _serverCustomRangeData = await StockApiService.fetchStockMonitoring(
          startDate: _customStartDateStr,
          endDate: _customEndDateStr,
        );
      } catch (e) {
        debugPrint('Gagal fetch custom range monitoring dari API ($e)');
        _serverCustomRangeData = null;
      }

      // 1. Ambil riwayat log perubahan stok fisik (Stok Masuk)
      final logs = await StockChangeLogService.getLogs();

      // 2. Ambil data transaksi penjualan (Stok Keluar)
      List<Transaction> transactions = [];
      try {
        final headers = await AuthService.getAuthHeaders();
        final res = await http
            .get(ApiConfig.transaksiUri, headers: headers)
            .timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final List<dynamic> data = jsonDecode(res.body);
          transactions = data
              .map((j) => Transaction.fromJson(j as Map<String, dynamic>))
              .toList();
        }
      } catch (errApi) {
        debugPrint('Gagal load transaksi dari server utama ($errApi), coba Supabase...');
        try {
          final supabase = Supabase.instance.client;
          final res = await supabase
              .from('transaksi')
              .select('*')
              .order('tanggal', ascending: false);
          transactions = (res as List)
              .map((j) => Transaction.fromJson(j as Map<String, dynamic>))
              .toList();
        } catch (errSupabase) {
          debugPrint('Gagal load transaksi dari Supabase ($errSupabase)');
        }
      }

      // Gabungkan dengan transaksi offline pending di smartphone jika ada
      final pending = await OfflineSyncService.getPendingTransactions();
      for (final p in pending) {
        if (!transactions.any((t) => t.id_transaksi == p.id_transaksi)) {
          transactions.add(p);
        }
      }

      if (!mounted) return;
      setState(() {
        _allStockLogs = logs;
        _allTransactions = transactions;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Gagal memuat data: $e';
      });
    }
  }

  /// Reload data harian khusus saat berpindah tanggal di kalender
  Future<void> _loadDailyDataOnly() async {
    try {
      final res = await StockApiService.fetchStockMonitoring(date: _selectedDateStr);
      if (mounted) {
        setState(() => _serverDailyData = res);
      }
    } catch (e) {
      debugPrint('Gagal load daily data: $e');
      if (mounted) setState(() => _serverDailyData = null);
    }
  }

  /// Reload data mingguan khusus saat berpindah minggu
  Future<void> _loadWeeklyDataOnly() async {
    try {
      final res = await StockApiService.fetchStockMonitoring(
        startDate: _selectedWeekStartStr,
        endDate: _selectedWeekEndStr,
      );
      if (mounted) {
        setState(() => _serverWeeklyData = res);
      }
    } catch (e) {
      debugPrint('Gagal load weekly data: $e');
      if (mounted) setState(() => _serverWeeklyData = null);
    }
  }

  /// Reload data bulanan khusus saat berpindah bulan di kalender
  Future<void> _loadMonthlyDataOnly() async {
    try {
      final res = await StockApiService.fetchStockMonitoring(month: _selectedMonthStr);
      if (mounted) {
        setState(() => _serverMonthlyData = res);
      }
    } catch (e) {
      debugPrint('Gagal load monthly data: $e');
      if (mounted) setState(() => _serverMonthlyData = null);
    }
  }

  /// Reload data rentang kustom saat rentang tanggal diubah
  Future<void> _loadCustomRangeDataOnly() async {
    try {
      final res = await StockApiService.fetchStockMonitoring(
        startDate: _customStartDateStr,
        endDate: _customEndDateStr,
      );
      if (mounted) {
        setState(() => _serverCustomRangeData = res);
      }
    } catch (e) {
      debugPrint('Gagal load custom range data: $e');
      if (mounted) setState(() => _serverCustomRangeData = null);
    }
  }

  /// Khusus Admin: Hitung ulang dan sinkronisasi seluruh tabel monitoring stok di server
  Future<void> _syncServerMonitoring() async {
    setState(() => _isSyncingServer = true);
    try {
      // 1. Kirim semua stok masuk offline ke Laravel jika ada antrean
      try {
        await PendingStockSyncService.syncPendingStockEntries();
      } catch (_) {}

      // 2. Hitung ulang monitoring stok di Laravel
      final res = await StockApiService.syncStockMonitoring();
      if (!mounted) return;
      final msg = res['message'] ?? 'Sinkronisasi monitoring stok berhasil.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(msg.toString())),
            ],
          ),
          backgroundColor: AppColors.primary,
        ),
      );
      await _loadAllData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal sinkronisasi data: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSyncingServer = false);
    }
  }

  // ===========================================================================
  // RESOLUSI KELOMPOK KOMODITAS DARI KODE & NAMA BARANG
  // ===========================================================================
  static String resolveCommodityKelompok({String? tyunit, String? itemName}) =>
      StockFlowReportPage.resolveCommodityKelompok(tyunit: tyunit, itemName: itemName);

  // ===========================================================================
  // FILTERING & AGREGASI HARIAN, MINGGUAN, BULANAN, & RENTANG
  // ===========================================================================
  String get _selectedDateStr => DateFormat('yyyy-MM-dd').format(_selectedDate);

  DateTime get _selectedWeekEnd => _selectedWeekStart.add(const Duration(days: 6));
  String get _selectedWeekStartStr => DateFormat('yyyy-MM-dd').format(_selectedWeekStart);
  String get _selectedWeekEndStr => DateFormat('yyyy-MM-dd').format(_selectedWeekEnd);
  String get _customStartDateStr => DateFormat('yyyy-MM-dd').format(_customStartDate);
  String get _customEndDateStr => DateFormat('yyyy-MM-dd').format(_customEndDate);

  List<StockChangeLog> _getLogsBetween(DateTime start, DateTime end) {
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
    return _allStockLogs.where((l) {
      if (l.timestamp.isBefore(s) || l.timestamp.isAfter(e)) return false;
      if (_selectedKelompok != 'ALL' && l.kelompok.toUpperCase() != _selectedKelompok) {
        return false;
      }
      return true;
    }).toList();
  }

  List<Transaction> _getTransactionsBetween(DateTime start, DateTime end) {
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
    return _allTransactions.where((t) {
      return !t.date.isBefore(s) && !t.date.isAfter(e);
    }).toList();
  }

  List<StockChangeLog> get _dailyLogs {
    return _allStockLogs.where((l) {
      final dateMatch = DateFormat('yyyy-MM-dd').format(l.timestamp) == _selectedDateStr;
      if (!dateMatch) return false;
      if (_selectedKelompok != 'ALL' && l.kelompok.toUpperCase() != _selectedKelompok) {
        return false;
      }
      return true;
    }).toList();
  }

  List<Transaction> get _dailyTransactions {
    return _allTransactions.where((t) {
      return DateFormat('yyyy-MM-dd').format(t.date) == _selectedDateStr;
    }).toList();
  }

  List<StockChangeLog> get _weeklyLogs => _getLogsBetween(_selectedWeekStart, _selectedWeekEnd);
  List<Transaction> get _weeklyTransactions => _getTransactionsBetween(_selectedWeekStart, _selectedWeekEnd);

  List<StockChangeLog> get _customRangeLogs => _getLogsBetween(_customStartDate, _customEndDate);
  List<Transaction> get _customRangeTransactions => _getTransactionsBetween(_customStartDate, _customEndDate);

  Map<String, CommodityFlowSummary> _calculateCommoditySummaries({
    required List<StockChangeLog> logs,
    required List<Transaction> transactions,
    Map<String, dynamic>? serverData,
    DateTime? referenceStartDate,
  }) {
    final Map<String, CommodityFlowSummary> map = {
      'GALON': CommodityFlowSummary(
        kelompok: 'GALON',
        displayName: 'Boneva Galon (19L)',
        unitName: 'Galon',
      ),
      'BOTOL_600': CommodityFlowSummary(
        kelompok: 'BOTOL_600',
        displayName: 'Boneva Botol 600ml',
        unitName: 'Dus/Btl',
      ),
      'BOTOL_1500': CommodityFlowSummary(
        kelompok: 'BOTOL_1500',
        displayName: 'Boneva Botol 1.5L',
        unitName: 'Dus/Btl',
      ),
      'GELAS': CommodityFlowSummary(
        kelompok: 'GELAS',
        displayName: 'Boneva Gelas',
        unitName: 'Dus',
      ),
    };

    // 1. Jika ada data resmi server API-v2, gunakan nilai terverifikasi dari server
    if (serverData != null && serverData['per_kelompok'] is List) {
      final perKlp = serverData['per_kelompok'] as List;
      for (final raw in perKlp) {
        if (raw is Map) {
          final k = (raw['kdklp'] ?? '').toString().toUpperCase();
          if (map.containsKey(k)) {
            int stokAwal = (raw['stok_awal'] as num?)?.toInt() ?? 0;
            int stokTambahan = (raw['stok_tambahan'] as num?)?.toInt() ?? 0;
            final int stokTerjual = (raw['stock_terjual'] as num?)?.toInt() ?? 0;
            final int sisaStock = (raw['sisa_stock'] as num?)?.toInt() ?? (stokAwal + stokTambahan - stokTerjual);

            // Jika API server belum memisahkan stok_awal dan stok_tambahan:
            if (stokAwal == 0 && stokTambahan == 0) {
              final localMasuk = logs
                  .where((l) => l.kelompok.toUpperCase() == k)
                  .fold<int>(0, (sum, l) => sum + (l.tambahanQty > 0 ? l.tambahanQty : 0));
              if (localMasuk > 0) {
                stokTambahan = localMasuk;
                stokAwal = (sisaStock + stokTerjual - stokTambahan);
                if (stokAwal < 0) stokAwal = 0;
              } else {
                final rawStockMasuk = (raw['stock_masuk'] as num?)?.toInt() ?? 0;
                stokTambahan = rawStockMasuk;
                stokAwal = (sisaStock + stokTerjual - stokTambahan);
                if (stokAwal < 0) stokAwal = 0;
              }
            }

            map[k]!.sisaKemarin = stokAwal;
            map[k]!.masukHariIni = stokTambahan;
            map[k]!.masuk = stokTambahan; // Murni stok masuk hari ini (tidak dicampur dengan sisa kemarin)
            map[k]!.keluar = stokTerjual;
            map[k]!.currentSisa = sisaStock;
            map[k]!.totalTransaksi = (raw['total_transaksi'] as num?)?.toInt() ?? 0;
            map[k]!.totalNominal = (raw['total_nominal'] as num?)?.toDouble() ?? 0.0;
          }
        }
      }

      // Hitung ulang totalTransaksi unik per kelompok dari daftar transaksi aktual jika tersedia
      if (transactions.isNotEmpty) {
        for (final k in map.keys) {
          final matching = transactions.where(
            (t) => t.items.any((it) => resolveCommodityKelompok(tyunit: it.tyunit, itemName: it.name) == k),
          ).toList();
          if (matching.isNotEmpty) {
            map[k]!.totalTransaksi = matching.length;
            final double nom = matching.fold<double>(0.0, (sum, t) {
              return sum + t.items.where((it) => resolveCommodityKelompok(tyunit: it.tyunit, itemName: it.name) == k).fold<double>(0.0, (iSum, it) => iSum + it.subtotal);
            });
            if (nom > 0) {
              map[k]!.totalNominal = nom;
            }
          }
        }
      }
      return map;
    }

    // 2. Fallback lokal saat offline
    // Hitung Sisa Stok Bawaan (sebelum tanggal/periode terpilih)
    final refDate = referenceStartDate ?? _selectedDate;
    final dateStartOfDay = DateTime(refDate.year, refDate.month, refDate.day);
    for (final k in map.keys) {
      int priorMasuk = 0;
      for (final l in _allStockLogs) {
        if (l.timestamp.isBefore(dateStartOfDay) && l.kelompok.toUpperCase() == k) {
          priorMasuk += (l.tambahanQty > 0 ? l.tambahanQty : 0);
        }
      }
      int priorKeluar = 0;
      for (final t in _allTransactions) {
        if (t.date.isBefore(dateStartOfDay)) {
          for (final item in t.items) {
            if (resolveCommodityKelompok(tyunit: item.tyunit, itemName: item.name) == k) {
              priorKeluar += (item.quantity + item.bonus);
            }
          }
        }
      }
      map[k]!.sisaKemarin = (priorMasuk - priorKeluar) > 0 ? (priorMasuk - priorKeluar) : 0;
    }

    // 1. Akumulasi Stok Masuk Hari Ini dari Log Pasokan
    for (final log in logs) {
      final k = log.kelompok.toUpperCase();
      if (map.containsKey(k)) {
        final qty = log.tambahanQty > 0 ? log.tambahanQty : 0;
        map[k]!.masukHariIni += qty;
        map[k]!.masuk += qty;
      }
    }

    // 2. Akumulasi Stok Keluar dari Transaksi
    for (final trx in transactions) {
      for (final item in trx.items) {
        final k = resolveCommodityKelompok(
          tyunit: item.tyunit,
          itemName: item.name,
        );
        if (map.containsKey(k)) {
          final qtyOut = item.quantity + item.bonus;
          map[k]!.keluar += qtyOut;
          map[k]!.totalNominal += item.subtotal;
        }
      }
    }

    // Hitung jumlah nota transaksi unik per kelompok (tanpa duplikasi antar item di transaksi yang sama)
    for (final k in map.keys) {
      map[k]!.totalTransaksi = transactions.where(
        (t) => t.items.any((it) => resolveCommodityKelompok(tyunit: it.tyunit, itemName: it.name) == k),
      ).length;
    }

    for (final s in map.values) {
      s.currentSisa = s.sisaKemarin + s.masukHariIni - s.keluar;
    }

    return map;
  }

  // ===========================================================================
  // FILTERING & AGREGASI BULANAN
  // ===========================================================================
  String get _selectedMonthStr => DateFormat('yyyy-MM').format(_selectedMonth);

  List<StockChangeLog> get _monthlyLogs {
    return _allStockLogs.where((l) {
      final monthMatch = DateFormat('yyyy-MM').format(l.timestamp) == _selectedMonthStr;
      if (!monthMatch) return false;
      if (_selectedKelompok != 'ALL' && l.kelompok.toUpperCase() != _selectedKelompok) {
        return false;
      }
      return true;
    }).toList();
  }

  List<Transaction> get _monthlyTransactions {
    return _allTransactions.where((t) {
      return DateFormat('yyyy-MM').format(t.date) == _selectedMonthStr;
    }).toList();
  }

  /// Menghasilkan rekap kalender harian untuk rentang waktu tertentu
  List<DailyStockFlowRecord> _generateRecordsForRange(
    DateTime startDate,
    DateTime endDate,
    Map<String, dynamic>? serverData,
  ) {
    // 1. Jika ada data daily resmi dari server API-v2
    if (serverData != null && serverData['daily'] is List) {
      final dailyList = serverData['daily'] as List;
      final List<DailyStockFlowRecord> serverRecords = [];
      for (final item in dailyList) {
        if (item is Map) {
          final tglStr = item['tanggal']?.toString() ?? '';
          DateTime d;
          try {
            d = DateTime.parse(tglStr);
          } catch (_) {
            continue;
          }

          final rec = DailyStockFlowRecord(
            date: d,
            hari: item['hari']?.toString(),
          );

          if (_selectedKelompok == 'ALL') {
            rec.sisaKemarin = (item['stok_awal'] as num?)?.toInt() ?? 0;
            rec.masukHariIni = (item['stok_tambahan'] as num?)?.toInt() ?? ((item['total_masuk'] as num?)?.toInt() ?? 0);
            rec.totalMasuk = rec.masukHariIni;
            rec.totalKeluar = (item['total_terjual'] as num?)?.toInt() ?? 0;
            rec.sisaAkumulasiRecord = (item['sisa_stock'] as num?)?.toInt() ?? (rec.sisaKemarin + rec.masukHariIni - rec.totalKeluar);
            rec.transactionCount = (item['total_transaksi'] as num?)?.toInt() ?? 0;
            rec.totalNominal = (item['total_nominal'] as num?)?.toDouble() ?? 0.0;
          } else {
            final rincian = item['rincian'] as List?;
            if (rincian != null) {
              for (final r in rincian) {
                if (r is Map && (r['kdklp'] ?? '').toString().toUpperCase() == _selectedKelompok) {
                  rec.sisaKemarin = (r['stok_awal'] as num?)?.toInt() ?? 0;
                  rec.masukHariIni = (r['stok_tambahan'] as num?)?.toInt() ?? ((r['stock_masuk'] as num?)?.toInt() ?? 0);
                  rec.totalMasuk = rec.masukHariIni;
                  rec.totalKeluar = (r['stock_terjual'] as num?)?.toInt() ?? 0;
                  rec.sisaAkumulasiRecord = (r['sisa_stock'] as num?)?.toInt() ?? (rec.sisaKemarin + rec.masukHariIni - rec.totalKeluar);
                  rec.transactionCount = (r['total_transaksi'] as num?)?.toInt() ?? 0;
                  rec.totalNominal = (r['total_nominal'] as num?)?.toDouble() ?? 0.0;
                  break;
                }
              }
            }
          }
          serverRecords.add(rec);
        }
      }
      serverRecords.sort((a, b) => a.date.compareTo(b.date));

      // Jika server tidak mengirim stok_awal harian secara berkesinambungan,
      // sambungkan sisa akumulasi hari sebelumnya ke sisa kemarin hari berikutnya:
      int runningServerSisa = 0;
      bool hasInitialSisa = false;
      for (final rec in serverRecords) {
        if (!hasInitialSisa && rec.sisaKemarin > 0) {
          runningServerSisa = rec.sisaKemarin;
          hasInitialSisa = true;
        } else if (hasInitialSisa && rec.sisaKemarin == 0) {
          rec.sisaKemarin = runningServerSisa;
        }
        rec.sisaAkumulasiRecord = rec.sisaKemarin + rec.masukHariIni - rec.totalKeluar;
        runningServerSisa = rec.sisaAkumulasiRecord;
      }

      return serverRecords;
    }

    // 2. Fallback lokal saat offline
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    final daysCount = end.difference(start).inDays + 1;

    final Map<String, DailyStockFlowRecord> recordMap = {};
    for (int i = 0; i < daysCount; i++) {
      final d = start.add(Duration(days: i));
      final key = DateFormat('yyyy-MM-dd').format(d);
      recordMap[key] = DailyStockFlowRecord(date: d);
    }

    final rangeLogs = _getLogsBetween(start, end);
    final rangeTrx = _getTransactionsBetween(start, end);

    // Agregasikan Masuk
    for (final log in rangeLogs) {
      final key = DateFormat('yyyy-MM-dd').format(log.timestamp);
      if (recordMap.containsKey(key)) {
        final rec = recordMap[key]!;
        final qty = log.tambahanQty > 0 ? log.tambahanQty : 0;
        rec.masukHariIni += qty;
        rec.totalMasuk += qty;
        rec.logCount += 1;
        rec.masukPerKelompok[log.kelompok] =
            (rec.masukPerKelompok[log.kelompok] ?? 0) + qty;
      }
    }

    // Agregasikan Keluar
    for (final trx in rangeTrx) {
      final key = DateFormat('yyyy-MM-dd').format(trx.date);
      if (recordMap.containsKey(key)) {
        final rec = recordMap[key]!;
        rec.transactionCount += 1;
        for (final item in trx.items) {
          final k = resolveCommodityKelompok(tyunit: item.tyunit, itemName: item.name);
          if (_selectedKelompok == 'ALL' || k == _selectedKelompok) {
            final qtyOut = item.quantity + item.bonus;
            rec.totalKeluar += qtyOut;
            rec.totalNominal += item.subtotal;
            rec.keluarPerKelompok[k] = (rec.keluarPerKelompok[k] ?? 0) + qtyOut;
          }
        }
      }
    }

    final list = recordMap.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    int runningSisa = 0;
    for (final l in _allStockLogs) {
      if (l.timestamp.isBefore(start)) {
        if (_selectedKelompok == 'ALL' || l.kelompok.toUpperCase() == _selectedKelompok) {
          runningSisa += (l.tambahanQty > 0 ? l.tambahanQty : 0);
        }
      }
    }
    for (final t in _allTransactions) {
      if (t.date.isBefore(start)) {
        for (final item in t.items) {
          final k = resolveCommodityKelompok(tyunit: item.tyunit, itemName: item.name);
          if (_selectedKelompok == 'ALL' || k == _selectedKelompok) {
            runningSisa -= (item.quantity + item.bonus);
          }
        }
      }
    }
    if (runningSisa < 0) runningSisa = 0;

    for (final rec in list) {
      rec.sisaKemarin = runningSisa;
      rec.sisaAkumulasiRecord = rec.sisaKemarin + rec.masukHariIni - rec.totalKeluar;
      runningSisa = rec.sisaAkumulasiRecord;
    }

    return list;
  }

  /// Menghasilkan rekap kalender harian untuk bulan yang dipilih (Tanggal 1 s/d akhir bulan)
  List<DailyStockFlowRecord> _generateMonthlyCalendarRecords() {
    final year = _selectedMonth.year;
    final month = _selectedMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    return _generateRecordsForRange(
      DateTime(year, month, 1),
      DateTime(year, month, daysInMonth),
      _serverMonthlyData,
    );
  }

  /// Menghasilkan rekap kalender harian untuk minggu yang dipilih (Senin s/d Minggu)
  List<DailyStockFlowRecord> _generateWeeklyCalendarRecords() {
    return _generateRecordsForRange(
      _selectedWeekStart,
      _selectedWeekEnd,
      _serverWeeklyData,
    );
  }

  /// Menghasilkan rekap kalender harian untuk rentang tanggal kustom yang dipilih
  List<DailyStockFlowRecord> _generateCustomRangeCalendarRecords() {
    return _generateRecordsForRange(
      _customStartDate,
      _customEndDate,
      _serverCustomRangeData,
    );
  }

  // ===========================================================================
  // NAVIGASI PERIODE
  // ===========================================================================
  void _changeDate(DateTime newDate) {
    setState(() {
      _selectedDate = newDate;
    });
    _loadDailyDataOnly();
  }

  Future<void> _pickArbitraryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      _changeDate(picked);
    }
  }

  void _changeMonth(int deltaMonths) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + deltaMonths,
        1,
      );
    });
    _loadMonthlyDataOnly();
  }

  void _changeWeek(int deltaWeeks) {
    setState(() {
      _selectedWeekStart = _selectedWeekStart.add(Duration(days: deltaWeeks * 7));
    });
    _loadWeeklyDataOnly();
  }

  Future<void> _pickCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _customStartDate, end: _customEndDate),
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _customStartDate = picked.start;
        _customEndDate = picked.end;
      });
      _loadCustomRangeDataOnly();
    }
  }

  // ===========================================================================
  // EKSPOR PDF & CSV
  // ===========================================================================
  Future<void> _exportPdfReport() async {
    final tabIndex = _tabController.index;
    String periodDesc = '';
    String reportTypeDesc = '';
    Map<String, CommodityFlowSummary> summaries;
    List<DailyStockFlowRecord> calendarRecords = [];

    switch (tabIndex) {
      case 0:
        periodDesc = _dateFormat.format(_selectedDate);
        reportTypeDesc = 'Laporan Harian';
        summaries = _calculateCommoditySummaries(
          logs: _dailyLogs,
          transactions: _dailyTransactions,
          serverData: _serverDailyData,
          referenceStartDate: _selectedDate,
        );
        break;
      case 1:
        periodDesc = '${DateFormat('dd MMM yyyy').format(_selectedWeekStart)} - ${DateFormat('dd MMM yyyy').format(_selectedWeekEnd)}';
        reportTypeDesc = 'Laporan Mingguan';
        summaries = _calculateCommoditySummaries(
          logs: _weeklyLogs,
          transactions: _weeklyTransactions,
          serverData: _serverWeeklyData,
          referenceStartDate: _selectedWeekStart,
        );
        calendarRecords = _generateWeeklyCalendarRecords();
        break;
      case 2:
        periodDesc = _monthFormat.format(_selectedMonth);
        reportTypeDesc = 'Laporan Bulanan';
        summaries = _calculateCommoditySummaries(
          logs: _monthlyLogs,
          transactions: _monthlyTransactions,
          serverData: _serverMonthlyData,
          referenceStartDate: DateTime(_selectedMonth.year, _selectedMonth.month, 1),
        );
        calendarRecords = _generateMonthlyCalendarRecords();
        break;
      case 3:
      default:
        periodDesc = '${DateFormat('dd MMM yyyy').format(_customStartDate)} - ${DateFormat('dd MMM yyyy').format(_customEndDate)}';
        reportTypeDesc = 'Laporan Rentang Tanggal';
        summaries = _calculateCommoditySummaries(
          logs: _customRangeLogs,
          transactions: _customRangeTransactions,
          serverData: _serverCustomRangeData,
          referenceStartDate: _customStartDate,
        );
        calendarRecords = _generateCustomRangeCalendarRecords();
        break;
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'LAPORAN ARUS STOK MASUK & KELUAR',
                        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text('Kencana Cahaya Amanah (Boneva Gorontalo)'),
                      pw.Text('Periode: $periodDesc ($reportTypeDesc)'),
                    ],
                  ),
                  pw.Text(
                    'Dicetak: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 14),

            // Ringkasan Total
            pw.Text(
              '1. REKAPITULASI TOTAL KOMODITAS',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: ['Kelompok Komoditas', 'Satuan', 'Sisa Kemarin', 'Masuk (+)', 'Terjual (-)', 'Selisih', 'Sisa Akumulasi'],
              data: summaries.values.map((s) {
                return [
                  s.displayName,
                  s.unitName,
                  '${s.sisaKemarin}',
                  '+${s.masukHariIni}',
                  '-${s.keluar}',
                  '${s.selisihHariIni >= 0 ? '+' : ''}${s.selisihHariIni}',
                  '${s.sisaAkumulasi}',
                ];
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.center,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
                6: pw.Alignment.centerRight,
              },
            ),
            pw.SizedBox(height: 18),

            // Rincian Detail
            if (tabIndex > 0) ...[
              pw.Text(
                '2. REKAPITULASI HARIAN ($periodDesc)',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 6),
              pw.TableHelper.fromTextArray(
                headers: ['Tanggal', 'Sisa Kemarin', 'Masuk (+)', 'Terjual (-)', 'Selisih', 'Sisa Akumulasi', 'Aktivitas'],
                data: calendarRecords.where((r) => r.hasActivity).map((r) {
                  return [
                    DateFormat('dd/MM/yyyy').format(r.date),
                    '${r.sisaKemarin}',
                    '+${r.masukHariIni}',
                    '-${r.totalKeluar}',
                    '${r.selisihHariIni >= 0 ? '+' : ''}${r.selisihHariIni}',
                    '${r.sisaAkumulasi}',
                    '${r.transactionCount} Nota (${r.totalNominal > 0 ? 'Rp ${NumberFormat('#,###', 'id_ID').format(r.totalNominal)}' : '-'})',
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                cellStyle: const pw.TextStyle(fontSize: 8.5),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerRight,
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.centerRight,
                  4: pw.Alignment.centerRight,
                  5: pw.Alignment.centerRight,
                  6: pw.Alignment.centerLeft,
                },
              ),
            ] else ...[
              pw.Text(
                '2. LOG INPUT STOK MASUK HARI INI',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 6),
              if (_dailyLogs.isEmpty)
                pw.Text('Tidak ada input stok masuk pada tanggal ini.', style: const pw.TextStyle(fontSize: 9))
              else
                pw.TableHelper.fromTextArray(
                  headers: ['Jam', 'Komoditas', 'Jenis Aksi', 'Tambahan', 'Sisa Sebelum -> Sesudah', 'Oleh'],
                  data: _dailyLogs.map((l) {
                    return [
                      DateFormat('HH:mm').format(l.timestamp),
                      l.displayName.isNotEmpty ? l.displayName : l.kelompok,
                      l.jenisAksi,
                      '+${l.tambahanQty} ${l.unitName}',
                      '${l.sisaSebelum} -> ${l.sisaSesudah}',
                      l.userName,
                    ];
                  }).toList(),
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                  cellStyle: const pw.TextStyle(fontSize: 8.5),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                ),
            ],
          ];
        },
      ),
    );

    final bytes = await pdf.save();
    final fileName = 'laporan_stok_${tabIndex == 0 ? DateFormat('yyyyMMdd').format(_selectedDate) : tabIndex == 1 ? 'mingguan_$_selectedWeekStartStr' : tabIndex == 2 ? DateFormat('yyyyMM').format(_selectedMonth) : 'rentang_$_customStartDateStr'}.pdf';
    await Printing.sharePdf(bytes: bytes, filename: fileName);
  }

  Future<void> _exportCsvReport() async {
    try {
      final tabIndex = _tabController.index;
      String periodDesc = '';
      String fileSuffix = '';
      Map<String, CommodityFlowSummary> summaries;
      List<DailyStockFlowRecord> calendarRecords = [];

      switch (tabIndex) {
        case 0:
          periodDesc = _dateFormat.format(_selectedDate);
          fileSuffix = DateFormat('yyyyMMdd').format(_selectedDate);
          summaries = _calculateCommoditySummaries(
            logs: _dailyLogs,
            transactions: _dailyTransactions,
            serverData: _serverDailyData,
            referenceStartDate: _selectedDate,
          );
          break;
        case 1:
          periodDesc = '${DateFormat('dd MMM yyyy').format(_selectedWeekStart)} - ${DateFormat('dd MMM yyyy').format(_selectedWeekEnd)}';
          fileSuffix = 'minggu_${_selectedWeekStartStr}_sd_$_selectedWeekEndStr';
          summaries = _calculateCommoditySummaries(
            logs: _weeklyLogs,
            transactions: _weeklyTransactions,
            serverData: _serverWeeklyData,
            referenceStartDate: _selectedWeekStart,
          );
          calendarRecords = _generateWeeklyCalendarRecords();
          break;
        case 2:
          periodDesc = _monthFormat.format(_selectedMonth);
          fileSuffix = DateFormat('yyyyMM').format(_selectedMonth);
          summaries = _calculateCommoditySummaries(
            logs: _monthlyLogs,
            transactions: _monthlyTransactions,
            serverData: _serverMonthlyData,
            referenceStartDate: DateTime(_selectedMonth.year, _selectedMonth.month, 1),
          );
          calendarRecords = _generateMonthlyCalendarRecords();
          break;
        case 3:
        default:
          periodDesc = '${DateFormat('dd MMM yyyy').format(_customStartDate)} - ${DateFormat('dd MMM yyyy').format(_customEndDate)}';
          fileSuffix = 'rentang_${_customStartDateStr}_sd_$_customEndDateStr';
          summaries = _calculateCommoditySummaries(
            logs: _customRangeLogs,
            transactions: _customRangeTransactions,
            serverData: _serverCustomRangeData,
            referenceStartDate: _customStartDate,
          );
          calendarRecords = _generateCustomRangeCalendarRecords();
          break;
      }

      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/arsip_stok');
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }

      final fileName = 'stok_$fileSuffix.csv';
      final file = File('${folder.path}/$fileName');

      final buffer = StringBuffer();
      buffer.writeln('LAPORAN ARUS STOK KENCANA CAHAYA AMANAH');
      buffer.writeln('Periode,$periodDesc');
      buffer.writeln('');

      buffer.writeln('Kelompok Komoditas,Satuan,Sisa Kemarin,Stok Masuk,Stok Terjual,Selisih,Sisa Stok Akumulasi');
      for (final s in summaries.values) {
        buffer.writeln('"${s.displayName}","${s.unitName}",${s.sisaKemarin},${s.masukHariIni},${s.keluar},${s.selisihHariIni},${s.sisaAkumulasi}');
      }

      if (tabIndex > 0) {
        buffer.writeln('');
        buffer.writeln('REKAPITULASI HARIAN');
        buffer.writeln('Tanggal,Sisa Kemarin,Total Masuk,Total Terjual,Selisih,Sisa Akumulasi,Jumlah Nota');
        for (final r in calendarRecords.where((r) => r.hasActivity)) {
          buffer.writeln('${DateFormat('yyyy-MM-dd').format(r.date)},${r.sisaKemarin},${r.masukHariIni},${r.totalKeluar},${r.selisihHariIni},${r.sisaAkumulasi},${r.transactionCount}');
        }
      }

      await file.writeAsString(buffer.toString());

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv', name: fileName)],
        text: 'Laporan Stok $periodDesc',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal export CSV: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  // ===========================================================================
  // WIDGET BUILD
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    final isAdmin = AuthService.currentUser?.isAdmin == true;

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Monitoring Stok')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.screenMargin),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_rounded, size: 64, color: AppColors.error),
                const SizedBox(height: 16),
                const Text(
                  'Akses Dibatasi',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Modul Monitoring Stok Masuk & Keluar ini hanya boleh diakses oleh Administrator.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Kembali ke Menu Utama'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Monitoring Stok Masuk & Keluar'),
            Text(
              'Laporan arus pasokan & penjualan kasir',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: _isSyncingServer
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                  )
                : const Icon(Icons.sync_rounded),
            tooltip: 'Sinkronisasi Data Server',
            onPressed: _isSyncingServer ? null : _syncServerMonitoring,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Export PDF',
            onPressed: _exportPdfReport,
          ),
          IconButton(
            icon: const Icon(Icons.archive_outlined),
            tooltip: 'Export CSV',
            onPressed: _exportCsvReport,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Data',
            onPressed: _loadAllData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(icon: Icon(Icons.today_rounded, size: 20), text: 'Harian'),
            Tab(icon: Icon(Icons.view_week_rounded, size: 20), text: 'Mingguan'),
            Tab(icon: Icon(Icons.calendar_month_rounded, size: 20), text: 'Bulanan'),
            Tab(icon: Icon(Icons.date_range_rounded, size: 20), text: 'Rentang Tanggal'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.screenMargin),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                        const SizedBox(height: 12),
                        Text(_errorMessage!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _loadAllData, child: const Text('Coba Lagi')),
                      ],
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildDailyView(),
                    _buildWeeklyView(),
                    _buildMonthlyView(),
                    _buildCustomRangeView(),
                  ],
                ),
    );
  }

  // ===========================================================================
  // TAMPILAN 1: LAPORAN HARIAN (PER HARI)
  // ===========================================================================
  Widget _buildDailyView() {
    final summaries = _calculateCommoditySummaries(
      logs: _dailyLogs,
      transactions: _dailyTransactions,
      serverData: _serverDailyData,
    );

    int totalSisaKemarin = 0;
    int totalMasukHariIni = 0;
    int totalKeluar = 0;

    for (final s in summaries.values) {
      if (_selectedKelompok == 'ALL' || s.kelompok == _selectedKelompok) {
        totalSisaKemarin += s.sisaKemarin;
        totalMasukHariIni += s.masukHariIni;
        totalKeluar += s.keluar;
      }
    }

    // Hitung total nota transaksi unik agar cocok 1:1 dengan Laporan Harian (bukan akumulasi per kelompok yang menimbulkan duplikasi)
    final matchingTrx = _selectedKelompok == 'ALL'
        ? _dailyTransactions
        : _dailyTransactions.where((t) => t.items.any((it) => resolveCommodityKelompok(tyunit: it.tyunit, itemName: it.name) == _selectedKelompok)).toList();
    final int totalTrx = matchingTrx.length;
    final double totalNominal = _selectedKelompok == 'ALL'
        ? matchingTrx.fold<double>(0.0, (sum, t) => sum + t.total)
        : matchingTrx.fold<double>(0.0, (sum, t) {
            return sum + t.items.where((it) => resolveCommodityKelompok(tyunit: it.tyunit, itemName: it.name) == _selectedKelompok).fold<double>(0.0, (iSum, it) => iSum + it.subtotal);
          });

    final int selisihHariIni = totalMasukHariIni - totalKeluar;
    final int sisaAkumulasi = totalSisaKemarin + totalMasukHariIni - totalKeluar;

    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenMargin),
        children: [
          // 1. Selector Tanggal Interaktif
          _buildDailyDateSelector(),
          const SizedBox(height: 14),

          // 2. Filter Kelompok Komoditas
          _buildKelompokFilterChips(),
          const SizedBox(height: 14),

          // 3. Kartu Ringkasan KPI
          _buildSummaryKpiCards(
            sisaKemarin: totalSisaKemarin,
            masukHariIni: totalMasukHariIni,
            totalKeluar: totalKeluar,
            selisihHariIni: selisihHariIni,
            sisaAkumulasi: sisaAkumulasi,
            totalTrx: totalTrx,
            totalNominal: totalNominal,
            isServerData: _serverDailyData != null,
            periodTitle: _dateFormat.format(_selectedDate),
          ),
          const SizedBox(height: 16),

          // 4. Rincian Grid Komoditas
          _buildCommodityGrid(summaries),
          const SizedBox(height: 20),

          // 5. Rincian Input Stok Masuk Hari Ini
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Riwayat Stok Masuk Hari Ini (${_dailyLogs.length})',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              Text(
                _dateFormat.format(_selectedDate),
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_dailyLogs.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 20, color: AppColors.textSecondary),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Belum ada penambahan stok fisik yang diinput pada tanggal ini.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            )
          else
            ..._dailyLogs.map((l) => _buildLogCard(l)),

          const SizedBox(height: 20),

          // 6. Rincian Nota Penjualan Hari Ini
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Nota Terjual Hari Ini (${_dailyTransactions.length})',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              Text(
                'Total: $totalKeluar Unit',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.deepOrange),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_dailyTransactions.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.receipt_long_outlined, size: 20, color: AppColors.textSecondary),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tidak ada transaksi penjualan pada tanggal ini.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            )
          else
            ..._dailyTransactions.map((trx) => _buildTransactionCard(trx)),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAMPILAN 2: LAPORAN MINGGUAN (PER MINGGU)
  // ===========================================================================
  Widget _buildWeeklyView() {
    final summaries = _calculateCommoditySummaries(
      logs: _weeklyLogs,
      transactions: _weeklyTransactions,
      serverData: _serverWeeklyData,
      referenceStartDate: _selectedWeekStart,
    );

    int totalSisaKemarin = 0;
    int totalMasukMingguIni = 0;
    int totalKeluar = 0;

    for (final s in summaries.values) {
      if (_selectedKelompok == 'ALL' || s.kelompok == _selectedKelompok) {
        totalSisaKemarin += s.sisaKemarin;
        totalMasukMingguIni += s.masukHariIni;
        totalKeluar += s.keluar;
      }
    }

    final matchingWeeklyTrx = _selectedKelompok == 'ALL'
        ? _weeklyTransactions
        : _weeklyTransactions.where((t) => t.items.any((it) => resolveCommodityKelompok(tyunit: it.tyunit, itemName: it.name) == _selectedKelompok)).toList();
    final int totalTrx = matchingWeeklyTrx.length;
    final double totalNominal = _selectedKelompok == 'ALL'
        ? matchingWeeklyTrx.fold<double>(0.0, (sum, t) => sum + t.total)
        : matchingWeeklyTrx.fold<double>(0.0, (sum, t) {
            return sum + t.items.where((it) => resolveCommodityKelompok(tyunit: it.tyunit, itemName: it.name) == _selectedKelompok).fold<double>(0.0, (iSum, it) => iSum + it.subtotal);
          });

    final int selisihMingguIni = totalMasukMingguIni - totalKeluar;
    final int sisaAkumulasi = totalSisaKemarin + totalMasukMingguIni - totalKeluar;
    final calendarRecords = _generateWeeklyCalendarRecords();
    final weekRangeTitle = '${DateFormat('dd MMM').format(_selectedWeekStart)} - ${DateFormat('dd MMM yyyy').format(_selectedWeekEnd)}';

    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenMargin),
        children: [
          // 1. Selector Minggu Interaktif (< Minggu >)
          _buildWeeklySelector(),
          const SizedBox(height: 14),

          // 2. Filter Kelompok Komoditas
          _buildKelompokFilterChips(),
          const SizedBox(height: 14),

          // 3. Kartu Ringkasan KPI Akumulasi Minggu Ini
          _buildSummaryKpiCards(
            sisaKemarin: totalSisaKemarin,
            masukHariIni: totalMasukMingguIni,
            totalKeluar: totalKeluar,
            selisihHariIni: selisihMingguIni,
            sisaAkumulasi: sisaAkumulasi,
            totalTrx: totalTrx,
            totalNominal: totalNominal,
            isServerData: _serverWeeklyData != null,
            isMonthly: true,
            periodTitle: 'Akumulasi 1 Minggu ($weekRangeTitle)',
          ),
          const SizedBox(height: 16),

          // 4. Rincian Akumulasi Komoditas Minggu Ini
          _buildCommodityGrid(summaries, isMonthly: true),
          const SizedBox(height: 20),

          // 5. Tabel Rekapitulasi Harian dalam 1 Minggu
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Rekap Harian Minggu Ini (${calendarRecords.where((r) => r.hasActivity).length} Hari Aktif)',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              const Text(
                'Ketuk tanggal untuk detail',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildMonthlyCalendarTable(calendarRecords),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAMPILAN 3: LAPORAN BULANAN (PER BULAN)
  // ===========================================================================
  Widget _buildMonthlyView() {
    final summaries = _calculateCommoditySummaries(
      logs: _monthlyLogs,
      transactions: _monthlyTransactions,
      serverData: _serverMonthlyData,
    );

    int totalSisaKemarin = 0;
    int totalMasukBulanIni = 0;
    int totalKeluar = 0;

    for (final s in summaries.values) {
      if (_selectedKelompok == 'ALL' || s.kelompok == _selectedKelompok) {
        totalSisaKemarin += s.sisaKemarin;
        totalMasukBulanIni += s.masukHariIni;
        totalKeluar += s.keluar;
      }
    }

    final matchingMonthlyTrx = _selectedKelompok == 'ALL'
        ? _monthlyTransactions
        : _monthlyTransactions.where((t) => t.items.any((it) => resolveCommodityKelompok(tyunit: it.tyunit, itemName: it.name) == _selectedKelompok)).toList();
    final int totalTrx = matchingMonthlyTrx.length;
    final double totalNominal = _selectedKelompok == 'ALL'
        ? matchingMonthlyTrx.fold<double>(0.0, (sum, t) => sum + t.total)
        : matchingMonthlyTrx.fold<double>(0.0, (sum, t) {
            return sum + t.items.where((it) => resolveCommodityKelompok(tyunit: it.tyunit, itemName: it.name) == _selectedKelompok).fold<double>(0.0, (iSum, it) => iSum + it.subtotal);
          });

    final int selisihBulanIni = totalMasukBulanIni - totalKeluar;
    final int sisaAkumulasi = totalSisaKemarin + totalMasukBulanIni - totalKeluar;
    final calendarRecords = _generateMonthlyCalendarRecords();

    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenMargin),
        children: [
          // 1. Selector Bulan Interaktif (< Bulan >)
          _buildMonthlySelector(),
          const SizedBox(height: 14),

          // 2. Filter Kelompok Komoditas
          _buildKelompokFilterChips(),
          const SizedBox(height: 14),

          // 3. Kartu Ringkasan KPI Akumulasi Bulan Ini
          _buildSummaryKpiCards(
            sisaKemarin: totalSisaKemarin,
            masukHariIni: totalMasukBulanIni,
            totalKeluar: totalKeluar,
            selisihHariIni: selisihBulanIni,
            sisaAkumulasi: sisaAkumulasi,
            totalTrx: totalTrx,
            totalNominal: totalNominal,
            isServerData: _serverMonthlyData != null,
            isMonthly: true,
            periodTitle: 'Akumulasi ${_monthFormat.format(_selectedMonth)}',
          ),
          const SizedBox(height: 16),

          // 4. Rincian Akumulasi Komoditas Bulan Ini
          _buildCommodityGrid(summaries, isMonthly: true),
          const SizedBox(height: 20),

          // 5. Tabel Kalender Rekapitulasi Harian
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Rekapitulasi Harian Kalender (${calendarRecords.where((r) => r.hasActivity).length} Hari Aktif)',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              const Text(
                'Ketuk tanggal untuk detail',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildMonthlyCalendarTable(calendarRecords),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAMPILAN 4: LAPORAN RENTANG TANGGAL (KUSTOM DARI TANGGAL SEKIAN KE SEKIAN)
  // ===========================================================================
  Widget _buildCustomRangeView() {
    final summaries = _calculateCommoditySummaries(
      logs: _customRangeLogs,
      transactions: _customRangeTransactions,
      serverData: _serverCustomRangeData,
      referenceStartDate: _customStartDate,
    );

    int totalSisaKemarin = 0;
    int totalMasukPeriode = 0;
    int totalKeluar = 0;

    for (final s in summaries.values) {
      if (_selectedKelompok == 'ALL' || s.kelompok == _selectedKelompok) {
        totalSisaKemarin += s.sisaKemarin;
        totalMasukPeriode += s.masukHariIni;
        totalKeluar += s.keluar;
      }
    }

    final matchingRangeTrx = _selectedKelompok == 'ALL'
        ? _customRangeTransactions
        : _customRangeTransactions.where((t) => t.items.any((it) => resolveCommodityKelompok(tyunit: it.tyunit, itemName: it.name) == _selectedKelompok)).toList();
    final int totalTrx = matchingRangeTrx.length;
    final double totalNominal = _selectedKelompok == 'ALL'
        ? matchingRangeTrx.fold<double>(0.0, (sum, t) => sum + t.total)
        : matchingRangeTrx.fold<double>(0.0, (sum, t) {
            return sum + t.items.where((it) => resolveCommodityKelompok(tyunit: it.tyunit, itemName: it.name) == _selectedKelompok).fold<double>(0.0, (iSum, it) => iSum + it.subtotal);
          });

    final int selisihPeriode = totalMasukPeriode - totalKeluar;
    final int sisaAkumulasi = totalSisaKemarin + totalMasukPeriode - totalKeluar;
    final calendarRecords = _generateCustomRangeCalendarRecords();
    final rangeTitle = '${DateFormat('dd MMM yyyy').format(_customStartDate)} s/d ${DateFormat('dd MMM yyyy').format(_customEndDate)}';

    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenMargin),
        children: [
          // 1. Selector Rentang Tanggal Interaktif
          _buildCustomRangeSelector(),
          const SizedBox(height: 14),

          // 2. Filter Kelompok Komoditas
          _buildKelompokFilterChips(),
          const SizedBox(height: 14),

          // 3. Kartu Ringkasan KPI Akumulasi Rentang
          _buildSummaryKpiCards(
            sisaKemarin: totalSisaKemarin,
            masukHariIni: totalMasukPeriode,
            totalKeluar: totalKeluar,
            selisihHariIni: selisihPeriode,
            sisaAkumulasi: sisaAkumulasi,
            totalTrx: totalTrx,
            totalNominal: totalNominal,
            isServerData: _serverCustomRangeData != null,
            isMonthly: true,
            periodTitle: 'Akumulasi Rentang ($rangeTitle)',
          ),
          const SizedBox(height: 16),

          // 4. Rincian Komoditas Rentang Tanggal
          _buildCommodityGrid(summaries, isMonthly: true),
          const SizedBox(height: 20),

          // 5. Tabel Rekapitulasi Harian dalam Rentang
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Rekapitulasi Harian Rentang (${calendarRecords.where((r) => r.hasActivity).length} Hari Aktif)',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              const Text(
                'Ketuk tanggal untuk detail',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildMonthlyCalendarTable(calendarRecords),
        ],
      ),
    );
  }

  // ===========================================================================
  // KOMPONEN: SELECTOR TANGGAL & BULAN
  // ===========================================================================
  Widget _buildDailyDateSelector() {
    final now = DateTime.now();
    final isToday = DateFormat('yyyy-MM-dd').format(_selectedDate) ==
        DateFormat('yyyy-MM-dd').format(now);
    final isYesterday = DateFormat('yyyy-MM-dd').format(_selectedDate) ==
        DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 1)));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, size: 16),
            tooltip: 'Hari Sebelumnya',
            onPressed: () => _changeDate(_selectedDate.subtract(const Duration(days: 1))),
          ),
          Expanded(
            child: InkWell(
              onTap: _pickArbitraryDate,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    Text(
                      _dateFormat.format(_selectedDate),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isToday
                          ? '• Hari Ini •'
                          : (isYesterday ? '• Kemarin •' : 'Ketuk untuk pilih kalender'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isToday ? AppColors.primary : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            tooltip: 'Hari Selanjutnya',
            onPressed: () => _changeDate(_selectedDate.add(const Duration(days: 1))),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlySelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, size: 16),
            tooltip: 'Bulan Sebelumnya',
            onPressed: () => _changeMonth(-1),
          ),
          Column(
            children: [
              Text(
                _monthFormat.format(_selectedMonth),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 2),
              const Text(
                'Akumulasi 1 Bulan Penuh',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            tooltip: 'Bulan Selanjutnya',
            onPressed: () => _changeMonth(1),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklySelector() {
    final startStr = DateFormat('dd MMM').format(_selectedWeekStart);
    final endStr = DateFormat('dd MMM yyyy').format(_selectedWeekEnd);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, size: 16),
            tooltip: 'Minggu Sebelumnya',
            onPressed: () => _changeWeek(-1),
          ),
          Column(
            children: [
              Text(
                '$startStr - $endStr',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 2),
              const Text(
                'Periode 1 Minggu (Senin - Minggu)',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            tooltip: 'Minggu Selanjutnya',
            onPressed: () => _changeWeek(1),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomRangeSelector() {
    final startStr = DateFormat('dd MMM yyyy').format(_customStartDate);
    final endStr = DateFormat('dd MMM yyyy').format(_customEndDate);
    final days = _customEndDate.difference(_customStartDate).inDays + 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.date_range_rounded, color: AppColors.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: _pickCustomDateRange,
              borderRadius: BorderRadius.circular(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$startStr  ➔  $endStr',
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Rentang $days Hari terpilih • Ketuk untuk ubah kalender',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: _pickCustomDateRange,
            icon: const Icon(Icons.calendar_today_rounded, size: 14),
            label: const Text('Pilih', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildKelompokFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ...['ALL', 'GALON', 'BOTOL_600', 'BOTOL_1500', 'GELAS'].map((k) {
            final isSel = _selectedKelompok == k;
            final label = k == 'ALL'
                ? 'Semua Komoditas'
                : k == 'GALON'
                    ? 'Galon (19L)'
                    : k == 'BOTOL_600'
                        ? 'Botol 600ml'
                        : k == 'BOTOL_1500'
                            ? 'Botol 1.5L'
                            : 'Gelas 220ml';

            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(label),
                selected: isSel,
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: isSel ? Colors.white : AppColors.textPrimary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
                onSelected: (_) {
                  setState(() => _selectedKelompok = k);
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  // ===========================================================================
  // KOMPONEN: KARTU RINGKASAN KPI
  // ===========================================================================
  Widget _buildSummaryKpiCards({
    required int sisaKemarin,
    required int masukHariIni,
    required int totalKeluar,
    required int selisihHariIni,
    required int sisaAkumulasi,
    required String periodTitle,
    int totalTrx = 0,
    double totalNominal = 0,
    bool isServerData = false,
    bool isMonthly = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Status & Periode (Simetris & Terlindungi dari Overflow)
          Row(
            children: [
              const Icon(Icons.analytics_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  periodTitle,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isServerData ? Colors.green.shade50 : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: isServerData ? Colors.green.shade200 : Colors.orange.shade200,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isServerData ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                      size: 11,
                      color: isServerData ? Colors.green.shade800 : Colors.orange.shade800,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      isServerData ? 'Server' : 'Offline',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isServerData ? Colors.green.shade800 : Colors.orange.shade800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: const Text(
                  'Admin',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2x2 Grid KPI Simetris (Ukuran Seimbang 50%-50%)
          // Baris 1: Sisa Kemarin (Kiri) & Stok Masuk (Kanan)
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    label: isMonthly ? 'Sisa Awal Bulan' : 'Sisa Kemarin',
                    value: '$sisaKemarin',
                    unit: 'Unit Bawaan',
                    color: const Color(0xFF475569),
                    bgColor: const Color(0xFFF1F5F9),
                    icon: Icons.history_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMetricTile(
                    label: isMonthly ? 'Masuk Bulan Ini' : 'Masuk Hari Ini',
                    value: '+$masukHariIni',
                    unit: 'Pasokan Baru',
                    color: const Color(0xFF0CA678),
                    bgColor: const Color(0xFFE6FCF5),
                    icon: Icons.add_circle_outline,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Baris 2: Stok Terjual (Kiri) & Selisih (Kanan)
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    label: isMonthly ? 'Terjual Bulan Ini' : 'Terjual Hari Ini',
                    value: '-$totalKeluar',
                    unit: 'Total Penjualan',
                    color: Colors.deepOrange,
                    bgColor: const Color(0xFFFBE9E7),
                    icon: Icons.remove_circle_outline,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMetricTile(
                    label: isMonthly ? 'Selisih Bulan' : 'Selisih Hari Ini',
                    value: '${selisihHariIni >= 0 ? '+' : ''}$selisihHariIni',
                    unit: 'Masuk - Terjual',
                    color: selisihHariIni >= 0 ? const Color(0xFF0CA678) : Colors.red.shade700,
                    bgColor: selisihHariIni >= 0 ? const Color(0xFFE6FCF5) : Colors.red.shade50,
                    icon: Icons.compare_arrows_rounded,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Baris 3: Banner Penuh SISA STOK AKUMULASI (Highlight Simetris & Anti-Overflow)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.inventory_2_rounded, size: 16, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'SISA STOK AKUMULASI',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                          color: AppColors.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'Kemarin ($sisaKemarin) + Masuk ($masukHariIni) - Terjual ($totalKeluar)',
                        style: TextStyle(fontSize: 9.5, color: Colors.grey.shade700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  constraints: const BoxConstraints(maxWidth: 105),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      '$sisaAkumulasi Unit',
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (totalTrx > 0 || totalNominal > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.bgSecondary,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long_rounded, size: 16, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    '$totalTrx Nota Transaksi',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.payments_outlined, size: 16, color: Color(0xFF0CA678)),
                  const SizedBox(width: 4),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Rp ${NumberFormat('#,###', 'id_ID').format(totalNominal)}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0CA678),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required String unit,
    required Color color,
    required Color bgColor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            unit,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // KOMPONEN: GRID 4 KOMODITAS FISIK
  // ===========================================================================
  Widget _buildCommodityGrid(Map<String, CommodityFlowSummary> summaries, {bool isMonthly = false}) {
    final list = summaries.values.where((s) {
      if (_selectedKelompok == 'ALL') return true;
      return s.kelompok == _selectedKelompok;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Rincian Per Kelompok Komoditas',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 8),
        ...list.map((s) => _buildCommodityCard(s, isMonthly: isMonthly)),
      ],
    );
  }

  Widget _buildCommodityCard(CommodityFlowSummary s, {bool isMonthly = false}) {
    final Color groupColor = _getGroupColor(s.kelompok);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header Kartu Komoditas
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: groupColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_getGroupIcon(s.kelompok), color: groupColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.displayName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Satuan: ${s.unitName}',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Badge Sisa Akumulasi (Anti-Overflow & Terukur)
              Container(
                constraints: const BoxConstraints(maxWidth: 115),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: groupColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: groupColor.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'SISA AKUMULASI',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: groupColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${s.sisaAkumulasi} ${s.unitName}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: groupColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2. Body Grid 2x2 Simetris & Seragam (Semua box memiliki ukuran seimbang dan anti-overflow)
          // Baris 1: Sisa Kemarin (Kiri) & Masuk (Kanan)
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _buildCommodityMiniTile(
                    label: isMonthly ? 'Awal Bulan' : 'Sisa Kemarin',
                    value: '${s.sisaKemarin}',
                    unit: s.unitName,
                    color: const Color(0xFF475569),
                    bgColor: const Color(0xFFF1F5F9),
                    icon: Icons.history_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildCommodityMiniTile(
                    label: isMonthly ? 'Masuk Bulan Ini' : 'Masuk Hari Ini',
                    value: '+${s.masukHariIni}',
                    unit: s.unitName,
                    color: const Color(0xFF0CA678),
                    bgColor: const Color(0xFFE6FCF5),
                    icon: Icons.add_circle_outline,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Baris 2: Terjual (Kiri) & Selisih (Kanan)
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _buildCommodityMiniTile(
                    label: isMonthly ? 'Terjual Bulan Ini' : 'Terjual Hari Ini',
                    value: '-${s.keluar}',
                    unit: s.unitName,
                    color: Colors.deepOrange,
                    bgColor: const Color(0xFFFBE9E7),
                    icon: Icons.remove_circle_outline,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildCommodityMiniTile(
                    label: isMonthly ? 'Selisih Bulan' : 'Selisih Hari Ini',
                    value: '${s.selisihHariIni >= 0 ? '+' : ''}${s.selisihHariIni}',
                    unit: s.unitName,
                    color: s.selisihHariIni >= 0 ? const Color(0xFF0CA678) : Colors.red.shade700,
                    bgColor: s.selisihHariIni >= 0 ? const Color(0xFFE6FCF5) : Colors.red.shade50,
                    icon: Icons.compare_arrows_rounded,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 3. Footer Seragam: Nota & Omset (Selalu tampil di setiap kartu agar simetris satu ukuran)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.bgSecondary,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.receipt_outlined, size: 13, color: AppColors.primary),
                const SizedBox(width: 5),
                Text(
                  '${s.totalTransaksi} Nota',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.payments_outlined, size: 13, color: Color(0xFF0CA678)),
                const SizedBox(width: 4),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Rp ${NumberFormat('#,###', 'id_ID').format(s.totalNominal)}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0CA678),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommodityMiniTile({
    required String label,
    required String value,
    required String unit,
    required Color color,
    required Color bgColor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: color.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // KOMPONEN: TABEL KALENDER BULANAN
  // ===========================================================================
  Widget _buildMonthlyCalendarTable(List<DailyStockFlowRecord> records) {
    final activeRecords = records.where((r) => r.hasActivity).toList();

    if (activeRecords.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Center(
          child: Text(
            'Tidak ada aktivitas pergerakan stok pada bulan ini.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.bgSecondary,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 3, child: Text('Tanggal', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                Expanded(flex: 2, child: Text('Masuk (+)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF0CA678)), textAlign: TextAlign.right)),
                Expanded(flex: 2, child: Text('Terjual (-)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.deepOrange), textAlign: TextAlign.right)),
                Expanded(flex: 2, child: Text('Selisih', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.blueGrey), textAlign: TextAlign.right)),
                Expanded(flex: 2, child: Text('Sisa', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.primary), textAlign: TextAlign.right)),
                Expanded(flex: 1, child: SizedBox()),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: activeRecords.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final r = activeRecords[i];
              final masukVal = r.masukHariIni > 0 ? r.masukHariIni : r.totalMasuk;
              return InkWell(
                onTap: () {
                  // Berpindah ke tab Harian untuk tanggal ini
                  setState(() {
                    _selectedDate = r.date;
                    _tabController.animateTo(0);
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat('dd MMM yyyy').format(r.date),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5),
                            ),
                            Text(
                              '${r.hari != null ? '${r.hari} • ' : ''}Kemarin: ${r.sisaKemarin}${r.transactionCount > 0 ? ' • ${r.transactionCount} Nota' : ''}',
                              style: const TextStyle(fontSize: 9.5, color: AppColors.textSecondary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          masukVal > 0 ? '+$masukVal' : '0',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: masukVal > 0 ? const Color(0xFF0CA678) : Colors.grey,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          r.totalKeluar > 0 ? '-${r.totalKeluar}' : '0',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: r.totalKeluar > 0 ? Colors.deepOrange : Colors.grey,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          '${r.selisihHariIni >= 0 ? '+' : ''}${r.selisihHariIni}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: r.selisihHariIni >= 0 ? Colors.green.shade800 : Colors.red.shade800,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          '${r.sisaAkumulasi}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                      const Expanded(
                        flex: 1,
                        child: Icon(Icons.arrow_forward_ios_rounded, size: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // KOMPONEN: KARTU LOG STOK MASUK
  // ===========================================================================
  Widget _buildLogCard(StockChangeLog l) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6FCF5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  l.jenisAksi,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF0CA678)),
                ),
              ),
              Text(
                _timeFormat.format(l.timestamp),
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l.displayName.isNotEmpty ? l.displayName : l.kelompok,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              Text(
                '+${l.tambahanQty} ${l.unitName}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0CA678)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Sisa Sebelum: ${l.sisaSebelum} ➔ Sisa Sesudah: ${l.sisaSesudah} ${l.unitName} (oleh ${l.userName})',
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // KOMPONEN: KARTU NOTA TRANSAKSI TERJUAL
  // ===========================================================================
  Widget _buildTransactionCard(Transaction trx) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final totalQty = trx.items.fold(0, (sum, i) => sum + i.quantity + i.bonus);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                trx.id_transaksi,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
              ),
              Text(
                _timeFormat.format(trx.date),
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                trx.customerName,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              Text(
                '-$totalQty Unit',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.deepOrange),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Total: ${currency.format(trx.total)} • Status: ${trx.status}',
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // HELPER WARNA & IKON KOMODITAS
  // ===========================================================================
  Color _getGroupColor(String kelompok) {
    switch (kelompok.toUpperCase()) {
      case 'GALON':
        return Colors.blue.shade700;
      case 'BOTOL_600':
        return Colors.teal.shade700;
      case 'BOTOL_1500':
        return Colors.indigo.shade700;
      case 'GELAS':
        return Colors.purple.shade700;
      default:
        return AppColors.primary;
    }
  }

  IconData _getGroupIcon(String kelompok) {
    switch (kelompok.toUpperCase()) {
      case 'GALON':
        return Icons.water_drop_outlined;
      case 'BOTOL_600':
        return Icons.local_drink_outlined;
      case 'BOTOL_1500':
        return Icons.wine_bar_outlined;
      case 'GELAS':
        return Icons.local_cafe_outlined;
      default:
        return Icons.inventory_2_outlined;
    }
  }
}
