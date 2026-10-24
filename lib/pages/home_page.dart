import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/pages/guide_page.dart';
import 'package:kasir_kutacane/pages/stock_input_page.dart';
import 'package:kasir_kutacane/pages/transactionDetail.dart';
import 'package:kasir_kutacane/services/offline_sync_service.dart';
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
  String? _errorMessage;
  int _pendingOfflineCount = 0;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    fetchTodayTransactions();
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

    // 2. Ambil transaksi dari server utama
    try {
      final response = await http.get(
        Uri.parse('https://laravel.fathurrzqn8n.web.id/api/transaksi'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final allServerTransactions = data
            .map<Transaction>(
              (json) => Transaction.fromJson(json as Map<String, dynamic>),
            )
            .toList();

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
          _loading = false;
        });
      } else {
        throw Exception('Server error (${response.statusCode})');
      }
    } catch (e) {
      if (!mounted) return;
      // Jika server offline / downtime, gunakan data offline lokal saja
      setState(() {
        _loading = false;
        _errorMessage = offlineToday.isNotEmpty
            ? null
            : 'Server sedang tidak dapat dijangkau (Mode Offline).';
        _todayTransactions = offlineToday
          ..sort((a, b) => b.date.compareTo(a.date));
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sales Kencana'),
            Text(
              'Kencana Cahaya Amanah',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Panduan Pengguna & Alur Kasir',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GuidePage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.inventory_2_outlined),
            tooltip: 'Input & Kelola Stok',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StockInputPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Buat Nota Baru',
            onPressed: widget.onCreateNota,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchTodayTransactions,
            tooltip: 'Refresh data',
          ),
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

  Widget _buildContent(NumberFormat currencyFormat, DateFormat dateFormat) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenMargin),
      children: [
        // Kartu ringkasan omzet
        OmzetSummaryCard(
          totalOmzet: _totalOmzet,
          jumlahNota: _todayTransactions.length,
          jumlahBon: _jumlahBon,
          formattedOmzet: currencyFormat.format(_totalOmzet),
        ),
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
                        'Panduan & Alur Kerja Kasir',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        'Pelajari 5 langkah operasional: stok, nota, cetak, hingga laporan',
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

        // Tombol Aksi: Buat Nota Baru & Input Stok
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
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StockInputPage()),
                ),
                icon: const Icon(Icons.inventory_2_outlined, size: 18),
                label: const Text('Input Stok'),
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
}
