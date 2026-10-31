import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/config/api_config.dart';
import 'package:kasir_kutacane/models/stock_group.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/pages/guide_page.dart';
import 'package:kasir_kutacane/pages/pelunasan_page.dart';
import 'package:kasir_kutacane/pages/stock_input_page.dart';
import 'package:kasir_kutacane/pages/transactionDetail.dart';
import 'package:kasir_kutacane/services/auth_service.dart';
import 'package:kasir_kutacane/services/offline_sync_service.dart';
import 'package:kasir_kutacane/services/pelunasan_history_service.dart';
import 'package:kasir_kutacane/services/printerBluetooth.dart';
import 'package:kasir_kutacane/services/stock_api_service.dart';
import 'package:kasir_kutacane/services/supabase_sync_service.dart';
import 'package:kasir_kutacane/theme/app_theme.dart';
import 'package:kasir_kutacane/widgets/app_widgets.dart';

class HomePage extends StatefulWidget {
  final VoidCallback onCreateNota;

  const HomePage({super.key, required this.onCreateNota});

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  bool _loading = true;
  List<Transaction> _todayTransactions = [];
  List<StockGroup> _stockGroups = [];
  String? _errorMessage;
  int _pendingOfflineCount = 0;
  bool _isSyncing = false;
  int _allActiveBonCount = 0;

  @override
  void initState() {
    super.initState();
    SupabaseSyncService.startMonitoring();
    fetchTodayTransactions();
  }

  @override
  void dispose() {
    SupabaseSyncService.stopMonitoring();
    super.dispose();
  }

  Future<void> fetchTodayTransactions() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final today = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(today);

    // 1. Ambil antrean transaksi offline dari penyimpanan lokal HP
    List<Transaction> offlineToday = [];
    try {
      final allOffline = await OfflineSyncService.getPendingTransactions();
      _pendingOfflineCount = allOffline.length;
      offlineToday = allOffline.where((trx) {
        return DateFormat('yyyy-MM-dd').format(trx.date) == todayStr;
      }).toList();
      for (final t in offlineToday) {
        t.isOffline = true;
      }
    } catch (e) {
      debugPrint('Error membaca transaksi offline: $e');
    }

    // 2. Ambil transaksi dari server utama dengan Auth Header (terisolasi per user)
    try {
      final authHeaders = await AuthService.getAuthHeaders();
      final response = await http.get(
        ApiConfig.transaksiUri,
        headers: authHeaders,
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final allServerTransactions = data
            .map<Transaction>(
              (json) => Transaction.fromJson(json as Map<String, dynamic>),
            )
            .toList();

        // Sinkronkan status pelunasan dengan PelunasanHistoryService
        final historyMap = await PelunasanHistoryService.loadHistory();
        for (final t in allServerTransactions) {
          if (historyMap.containsKey(t.id_transaksi)) {
            final rec = historyMap[t.id_transaksi]!;
            t.status = 'LUNAS';
            t.tanggalPelunasan = rec.tanggalPelunasan;
          } else if (t.status.toUpperCase() == 'LUNAS' && t.tanggalPelunasan == null) {
            t.tanggalPelunasan = t.date;
          }
        }

        final activeBonTotal = allServerTransactions
            .where((t) => t.status.toUpperCase() == 'BON')
            .length;

        final serverToday = allServerTransactions.where((trx) {
          return DateFormat('yyyy-MM-dd').format(trx.date) == todayStr;
        }).toList();

        // Gabungkan transaksi server dan transaksi offline lokal yang belum tersinkron
        final Set<String> existingIds =
            serverToday.map((e) => e.id_transaksi).toSet();
        final unmergedOffline = offlineToday
            .where((off) => !existingIds.contains(off.id_transaksi))
            .toList();

        final merged = [...unmergedOffline, ...serverToday]
          ..sort((a, b) => b.date.compareTo(a.date));

        if (!mounted) return;
        setState(() {
          _todayTransactions = merged;
          _allActiveBonCount = activeBonTotal;
          _loading = false;
        });

        // Muat ringkasan kuota komoditas fisik dari backend baru
        try {
          final groups = await StockApiService.fetchStockSummary();
          if (mounted) {
            setState(() => _stockGroups = groups);
          }
        } catch (_) {}

        // Sinkronkan transaksi buffer dari Supabase ke server utama di latar belakang
        unawaited(SupabaseSyncService.syncSupabaseTransactionsToServer());
      } else {
        throw Exception('Server error (${response.statusCode})');
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint("Server utama offline ($e), memuat cadangan Supabase & antrean lokal...");

      // 1. Ambil transaksi hari ini dari Supabase cadangan jika ada
      List<Transaction> supabaseToday = [];
      try {
        supabaseToday =
            await SupabaseSyncService.fetchTodayTransactionsFromSupabase();
      } catch (errSupabase) {
        debugPrint("Gagal fetchTodayTransactionsFromSupabase: $errSupabase");
      }

      // 2. Gabungkan transaksi lokal dan Supabase (hilangkan duplikat)
      final Set<String> existingLocalIds =
          offlineToday.map((e) => e.id_transaksi).toSet();
      final unmergedSupabase = supabaseToday
          .where((sup) => !existingLocalIds.contains(sup.id_transaksi))
          .toList();

      final mergedOffline = [...offlineToday, ...unmergedSupabase]
        ..sort((a, b) => b.date.compareTo(a.date));

      // 3. Muat ringkasan kuota komoditas fisik dari Supabase (agar stok tetap kelihatan!)
      List<StockGroup> fallbackGroups = [];
      try {
        fallbackGroups =
            await SupabaseSyncService.fetchStockSummaryFromSupabase();
      } catch (errStock) {
        debugPrint("Gagal fetchStockSummaryFromSupabase: $errStock");
      }

      setState(() {
        _loading = false;
        _errorMessage = null; // Menghilangkan banner error merah jika cadangan Supabase aktif
        _todayTransactions = mergedOffline;
        if (fallbackGroups.isNotEmpty) {
          _stockGroups = fallbackGroups;
        }
      });
    }
  }

  Future<void> syncOfflineData() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    try {
      final result = await OfflineSyncService.syncPendingTransactions();
      if (!mounted) return;

      if (result.success > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Berhasil menghubungkan & menyinkronkan ${result.success} nota ke server!',
            ),
            backgroundColor: AppColors.lunas,
          ),
        );
      } else if (result.failed > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gagal sinkronisasi: ${result.errors.firstOrNull ?? "Coba lagi"}',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Semua data sudah tersinkronkan.'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Koneksi server gagal: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
        fetchTodayTransactions();
      }
    }
  }

  double get _totalOmzet =>
      _todayTransactions.fold(0.0, (sum, trx) => sum + trx.total);

  int get _jumlahBon =>
      _todayTransactions.where((t) => t.status.toUpperCase() == 'BON').length;

  @override
  Widget build(BuildContext context) {
    final currencyFormat =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ');
    final dateFormat = DateFormat('dd MMM yyyy');

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.screenMargin,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Sales Kencana',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(DateTime.now()),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Segarkan data',
            onPressed: fetchTodayTransactions,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Menu Cepat',
            onSelected: (val) {
              if (val == 'pelunasan') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PelunasanPage()),
                ).then((_) => fetchTodayTransactions());
              } else if (val == 'stock') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StockInputPage()),
                ).then((_) => fetchTodayTransactions());
              } else if (val == 'printer') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Printbluetooth(
                      orderItems: const [],
                      paymentMethod: 'Tunai',
                      total: 0,
                      date: DateTime.now(),
                      customerName: 'Uji Coba Printer',
                      alamat: 'Gorontalo',
                      idTransaksi: 'TEST-001',
                      status: 'LUNAS',
                    ),
                  ),
                );
              } else if (val == 'guide') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GuidePage()),
                );
              }
            },
            itemBuilder: (ctx) => [
              if (AuthService.currentUser?.isAdmin == true)
                const PopupMenuItem(
                  value: 'pelunasan',
                  child: Row(
                    children: [
                      Icon(Icons.receipt_long_rounded,
                          size: 20, color: AppColors.bon),
                      SizedBox(width: 10),
                      Text('Pelunasan Bon'),
                    ],
                  ),
                ),
              PopupMenuItem(
                value: 'stock',
                child: Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined,
                        size: 20, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Text(AuthService.currentUser?.isAdmin == true
                        ? 'Manajemen Stok'
                        : 'Stok Terjual & Produk'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'printer',
                child: Row(
                  children: [
                    Icon(Icons.print_outlined,
                        size: 20, color: Color(0xFF16A34A)),
                    SizedBox(width: 10),
                    Text('Printer Bluetooth'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'guide',
                child: Row(
                  children: [
                    Icon(Icons.help_outline,
                        size: 20, color: AppColors.textSecondary),
                    SizedBox(width: 10),
                    Text('Panduan Kasir'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: fetchTodayTransactions,
        child: _loading
            ? const SkeletonList(count: 4)
            : _buildContent(currencyFormat, dateFormat),
      ),
    );
  }

  Widget _buildUserHeaderCard() {
    final user = AuthService.currentUser;
    if (user == null) return const SizedBox.shrink();

    final isAdmin = user.isAdmin;
    final accentColor = isAdmin ? Colors.purple : AppColors.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
        boxShadow: AppShadow.card,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: accentColor.withValues(alpha: 0.12),
            child: Icon(
              isAdmin
                  ? Icons.admin_panel_settings_rounded
                  : Icons.person_rounded,
              color: accentColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        user.name,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: accentColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        isAdmin ? 'ADMIN' : 'SALES ARMADA',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: accentColor,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  isAdmin
                      ? 'Hak Akses Stok: Full Access (Semua Sales)'
                      : 'Hak Akses Stok: Terisolasi (Armada ${user.name})',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isAdmin
                        ? Colors.purple.shade700
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StockInputPage()),
            ),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppColors.bgSecondary,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                size: 18,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(NumberFormat currencyFormat, DateFormat dateFormat) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenMargin),
      children: [
        // Status Koneksi Database & Backup Supabase
        _buildDatabaseStatusBar(),
        const SizedBox(height: AppSpacing.xs),

        // Kartu Profil & Status Pengguna (Rapi & Tidak Tertimpa)
        _buildUserHeaderCard(),

        // Kartu ringkasan omzet
        OmzetSummaryCard(
          totalOmzet: _totalOmzet,
          jumlahNota: _todayTransactions.length,
          jumlahBon: _jumlahBon,
          formattedOmzet: currencyFormat.format(_totalOmzet),
        ),
        const SizedBox(height: AppSpacing.md),

        // Banner Monitoring Bon jika ada transaksi BON belum lunas (Khusus Admin)
        if (AuthService.currentUser?.isAdmin == true && (_jumlahBon > 0 || _allActiveBonCount > 0)) ...[
          _buildBonAlertCard(),
          const SizedBox(height: AppSpacing.md),
        ],

        // Status Kuota Komoditas Fisik (Admin) ATAU Performa Stok Terjual (Sales)
        if (AuthService.currentUser?.isAdmin == true)
          _buildCommodityGlance()
        else
          _buildSalesTerjualGlance(),
        const SizedBox(height: AppSpacing.md),

        // Banner Antrean Offline (Jika ada nota yang tersimpan di HP)
        if (_pendingOfflineCount > 0) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.cloud_off_rounded,
                    size: 20,
                    color: Colors.amber.shade900,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$_pendingOfflineCount Nota Tersimpan di HP (Offline)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.amber.shade900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Server offline/downtime. Hubungkan ke server saat online.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.amber.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _isSyncing
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.shade800,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: syncOfflineData,
                        child: const Text(
                          'Hubungkan',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        // Banner Panduan Cepat & Alur Kerja
        InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const GuidePage()),
          ),
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border:
                  Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.auto_stories,
                    size: 18,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Panduan, Peran & Alur Kasir',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        'Panduan peran Admin/Sales, alur nota, stok, pelunasan & laporan',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 13,
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Tombol Aksi: Buat Nota Baru & Input Stok / Pelunasan
        Row(
          children: [
            Expanded(
              flex: 3,
              child: ElevatedButton.icon(
                onPressed: widget.onCreateNota,
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Buat Nota Baru'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StockInputPage()),
                  ).then((_) => fetchTodayTransactions());
                },
                icon: const Icon(
                  Icons.inventory_2_outlined,
                  size: 18,
                ),
                label: Text(
                  AuthService.currentUser?.isAdmin == true
                      ? 'Input Stok'
                      : 'Katalog Stok',
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxl),

        // Error state
        if (_errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.errorBg,
              borderRadius: BorderRadius.circular(AppRadius.input),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.wifi_off, color: AppColors.error, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Gagal memuat data',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.error,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Periksa koneksi internet Anda',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.error.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: fetchTodayTransactions,
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],

        // Header: Nota Terakhir
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Nota Terakhir',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              DateFormat('dd MMM yyyy').format(DateTime.now()),
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        // Daftar nota
        if (_todayTransactions.isEmpty && _errorMessage == null)
          EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'Belum ada nota hari ini',
            subtitle: 'Buat nota pertama untuk memulai penjualan',
            actionLabel: 'Buat Nota',
            onAction: widget.onCreateNota,
          )
        else
          ...List.generate(
            _todayTransactions.length > 5 ? 5 : _todayTransactions.length,
            (index) {
              final trx = _todayTransactions[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
                child: TransactionCard(
                  transaction: trx,
                  idTransaksi: trx.id_transaksi,
                  customerName: trx.customerName,
                  alamat: trx.alamat,
                  date: trx.date,
                  total: trx.total,
                  status: trx.status,
                  isOffline: trx.isOffline,
                  formattedTotal: currencyFormat.format(trx.total),
                  formattedDate: dateFormat.format(trx.date),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            TransactionDetailPage(transaction: trx),
                      ),
                    );
                    fetchTodayTransactions();
                  },
                ),
              );
            },
          ),

        if (_todayTransactions.length > 5) ...[
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () {},
              child: Text(
                  'Lihat ${_todayTransactions.length - 5} nota lainnya →'),
            ),
          ),
        ],

        // padding bawah
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildCommodityGlance() {
    return Container(
      padding: const EdgeInsets.all(14),
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
              const Row(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 18, color: AppColors.primary),
                  SizedBox(width: 8),
                  Text(
                    'Sisa Kuota Komoditas Fisik',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StockInputPage()),
                ).then((_) => fetchTodayTransactions()),
                child: const Text(
                  'Kelola Stok >',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_stockGroups.isEmpty)
            Row(
              children: [
                _miniGlanceItem('Galon', Icons.water_drop_outlined, const Color(0xFF0288D1), '-'),
                const SizedBox(width: 8),
                _miniGlanceItem('Btl 600', Icons.local_drink_outlined, const Color(0xFF00897B), '-'),
                const SizedBox(width: 8),
                _miniGlanceItem('Btl 1.5L', Icons.wine_bar_outlined, const Color(0xFF5E35B1), '-'),
                const SizedBox(width: 8),
                _miniGlanceItem('Gelas', Icons.crop_square_outlined, const Color(0xFFE65100), '-'),
              ],
            )
          else
            Row(
              children: _stockGroups.map((g) {
                final isLast = g.kelompok == _stockGroups.last.kelompok;
                final color = _getGroupColor(g.kelompok);
                final icon = _getGroupIcon(g.kelompok);
                final sisa = '${g.sisaStock}';
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: isLast ? 0 : 8),
                    child: _miniGlanceItem(
                      _shortGroupName(g.kelompok),
                      icon,
                      color,
                      sisa,
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _miniGlanceItem(String title, IconData icon, Color color, String sisa) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            sisa,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }

  String _shortGroupName(String k) {
    switch (k.toUpperCase()) {
      case 'GALON':
        return 'Galon';
      case 'BOTOL_600':
        return 'Btl 600';
      case 'BOTOL_1500':
        return 'Btl 1.5L';
      case 'GELAS':
        return 'Gelas';
      default:
        return k;
    }
  }

  Color _getGroupColor(String k) {
    switch (k.toUpperCase()) {
      case 'GALON':
        return const Color(0xFF0288D1);
      case 'BOTOL_600':
        return const Color(0xFF00897B);
      case 'BOTOL_1500':
        return const Color(0xFF5E35B1);
      case 'GELAS':
        return const Color(0xFFE65100);
      default:
        return AppColors.primary;
    }
  }

  IconData _getGroupIcon(String k) {
    switch (k.toUpperCase()) {
      case 'GALON':
        return Icons.water_drop_outlined;
      case 'BOTOL_600':
        return Icons.local_drink_outlined;
      case 'BOTOL_1500':
        return Icons.wine_bar_outlined;
      case 'GELAS':
        return Icons.crop_square_outlined;
      default:
        return Icons.inventory_2_outlined;
    }
  }

  Widget _buildDatabaseStatusBar() {
    return ValueListenableBuilder<DatabaseConnectionStatus>(
      valueListenable: SupabaseSyncService.connectionStatusNotifier,
      builder: (context, status, _) {
        Color bgColor;
        Color borderColor;
        Color textColor;
        IconData icon;
        String title;
        String subtitle;

        switch (status) {
          case DatabaseConnectionStatus.primaryOnline:
            bgColor = const Color(0xFFE8F5E9);
            borderColor = const Color(0xFFA5D6A7);
            textColor = const Color(0xFF2E7D32);
            icon = Icons.cloud_done_rounded;
            title = 'Database Utama Aktif (api-v2)';
            subtitle = 'Koneksi aktif • Backup Supabase & lokal siaga';
            break;
          case DatabaseConnectionStatus.primaryOfflineSupabaseReady:
            bgColor = const Color(0xFFFFF8E1);
            borderColor = const Color(0xFFFFE082);
            textColor = const Color(0xFFF57F17);
            icon = Icons.cloud_sync_rounded;
            title = 'Database Utama Offline • Supabase Siap';
            subtitle = 'Failover aktif: Nota otomatis dialihkan ke Supabase';
            break;
          case DatabaseConnectionStatus.offlineLocal:
            bgColor = const Color(0xFFFFEBEE);
            borderColor = const Color(0xFFFFCDD2);
            textColor = const Color(0xFFC62828);
            icon = Icons.cloud_off_rounded;
            title = 'Mode Offline (Penyimpanan HP)';
            subtitle = 'Nota tersimpan di HP, siap disinkronkan saat online';
            break;
          case DatabaseConnectionStatus.checking:
            bgColor = Colors.grey.shade100;
            borderColor = Colors.grey.shade300;
            textColor = AppColors.textSecondary;
            icon = Icons.wifi_protected_setup_rounded;
            title = 'Memeriksa Status Database...';
            subtitle = 'Menghubungkan ke API v2 & Supabase';
            break;
        }

        return InkWell(
          onTap: () async {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Memeriksa ulang koneksi database...'),
                duration: Duration(seconds: 1),
              ),
            );
            await SupabaseSyncService.checkConnectionStatus();
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: textColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: textColor.withOpacity(0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Cek',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBonAlertCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.bonBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.bon.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.bon.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: AppColors.bon,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_allActiveBonCount > 0 ? _allActiveBonCount : _jumlahBon} Transaksi Bon Belum Lunas',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.bon,
                  ),
                ),
                const Text(
                  'Catat tanggal pelunasan pelanggan di menu Pelunasan.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.bon,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PelunasanPage()),
            ).then((_) => fetchTodayTransactions()),
            child: const Text('Buka →', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesTerjualGlance() {
    int galonTerjual = 0;
    int btl600Terjual = 0;
    int btl1500Terjual = 0;
    int gelasTerjual = 0;

    for (final trx in _todayTransactions) {
      for (final item in trx.items) {
        final code = (item.tyunit ?? '').toUpperCase();
        final name = item.name.toUpperCase();
        final qty = item.quantity + item.bonus;

        if (code.contains('BV01') ||
            code.contains('BV02') ||
            code.contains('BV03') ||
            code.contains('BV04') ||
            code.contains('BV05') ||
            code.contains('BV06') ||
            code.contains('BV07') ||
            name.contains('GALON')) {
          galonTerjual += qty;
        } else if (code.contains('BV08') ||
            code.contains('BV09') ||
            code.contains('BV10') ||
            code.contains('BV11') ||
            code.contains('BV12') ||
            code.contains('BV13') ||
            name.contains('600')) {
          btl600Terjual += qty;
        } else if (code.contains('BV14') ||
            code.contains('BV15') ||
            code.contains('BV16') ||
            code.contains('BV17') ||
            name.contains('1500') ||
            name.contains('1.5') ||
            name.contains('1,5')) {
          btl1500Terjual += qty;
        } else if (code.contains('BV18') ||
            code.contains('BV19') ||
            code.contains('BV20') ||
            code.contains('BV21') ||
            code.contains('BV22') ||
            code.contains('BV23') ||
            name.contains('GELAS')) {
          gelasTerjual += qty;
        }
      }
    }

    final totalUnit = galonTerjual + btl600Terjual + btl1500Terjual + gelasTerjual;

    return Container(
      padding: const EdgeInsets.all(14),
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
              Row(
                children: [
                  const Icon(Icons.point_of_sale_outlined, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Stok Terjual Saya ($totalUnit Unit)',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StockInputPage()),
                ).then((_) => fetchTodayTransactions()),
                child: const Text(
                  'Lihat Detail >',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _miniSalesTerjualItem(
                  'Galon',
                  Icons.water_drop_outlined,
                  const Color(0xFF0288D1),
                  '$galonTerjual',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniSalesTerjualItem(
                  'Btl 600',
                  Icons.local_drink_outlined,
                  const Color(0xFF00897B),
                  '$btl600Terjual',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniSalesTerjualItem(
                  'Btl 1.5L',
                  Icons.wine_bar_outlined,
                  const Color(0xFF5E35B1),
                  '$btl1500Terjual',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniSalesTerjualItem(
                  'Gelas',
                  Icons.crop_square_outlined,
                  const Color(0xFFE65100),
                  '$gelasTerjual',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniSalesTerjualItem(
    String title,
    IconData icon,
    Color color,
    String count,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            count,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color),
          ),
          const Text(
            'terjual',
            style: TextStyle(fontSize: 9, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
