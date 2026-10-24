import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/pages/transactionDetail.dart';
import 'package:kasir_kutacane/services/offline_sync_service.dart';
import 'package:kasir_kutacane/theme/app_theme.dart';
import 'package:kasir_kutacane/widgets/app_widgets.dart';
import 'package:path_provider/path_provider.dart';

enum TransactionQuickFilter {
  all,
  today,
  thisWeek,
  bonOnly,
}

class TransactionListPageBackup extends StatefulWidget {
  final VoidCallback? onCreateNota;

  const TransactionListPageBackup({super.key, this.onCreateNota});

  @override
  State<TransactionListPageBackup> createState() =>
      TransactionListPageBackupState();
}

class TransactionListPageBackupState extends State<TransactionListPageBackup> {
  final TextEditingController _searchCtrl = TextEditingController();
  DateTime? _filterDate;
  TransactionQuickFilter _quickFilter = TransactionQuickFilter.all;

  List<Transaction> _transactions = [];
  List<Transaction> _filteredTransactions = [];
  bool _isLoading = true;
  bool _isProcessing = false;
  int _pendingOfflineCount = 0;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    fetchTransactions();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> fetchTransactions() async {
    const url = 'https://laravel.fathurrzqn8n.web.id/api/transaksi';
    setState(() => _isLoading = true);

    // 1. Ambil antrean transaksi offline dari penyimpanan lokal HP
    List<Transaction> pendingOffline = [];
    try {
      pendingOffline = await OfflineSyncService.getPendingTransactions();
      for (final t in pendingOffline) {
        t.isOffline = true;
      }
      _pendingOfflineCount = pendingOffline.length;
    } catch (e) {
      debugPrint('Error membaca offline queue: $e');
    }

    // 2. Ambil dari server
    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);

        final serverTransactions = data
            .map<Transaction>(
              (json) => Transaction.fromJson(json as Map<String, dynamic>),
            )
            .toList();

        // Gabungkan transaksi server dan offline (tanpa duplikat ID)
        final Set<String> serverIds =
            serverTransactions.map((e) => e.id_transaksi).toSet();
        final unmergedOffline = pendingOffline
            .where((off) => !serverIds.contains(off.id_transaksi))
            .toList();

        final merged = [...unmergedOffline, ...serverTransactions]
          ..sort((a, b) => b.date.compareTo(a.date));

        if (!mounted) return;
        setState(() {
          _transactions = merged;
          _isLoading = false;
        });
        _applyFilter();
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint("Fetch server error (offline mode): $e");
      if (!mounted) return;
      setState(() {
        _transactions = pendingOffline..sort((a, b) => b.date.compareTo(a.date));
        _isLoading = false;
      });
      _applyFilter();
      if (pendingOffline.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Koneksi server terputus: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
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
              '${result.success} nota offline berhasil dihubungkan ke server!',
            ),
            backgroundColor: AppColors.lunas,
          ),
        );
      } else if (result.failed > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gagal sinkron: ${result.errors.firstOrNull ?? "Periksa jaringan"}',
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
          content: Text('Gagal sinkron: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
        fetchTransactions();
      }
    }
  }

  void _applyFilter() {
    final query = _searchCtrl.text.toLowerCase().trim();
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);

    // Hitung awal minggu ini (Senin)
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final startOfWeekDate = DateTime(
      startOfWeek.year,
      startOfWeek.month,
      startOfWeek.day,
    );

    setState(() {
      _filteredTransactions = _transactions.where((trx) {
        // 1. Text Search Filter (Nama Konsumen atau ID Transaksi)
        if (query.isNotEmpty) {
          final matchName = trx.customerName.toLowerCase().contains(query);
          final matchId = trx.id_transaksi.toLowerCase().contains(query);
          if (!matchName && !matchId) return false;
        }

        // 2. Custom Date Picker Filter
        if (_filterDate != null) {
          final isSameDay = trx.date.year == _filterDate!.year &&
              trx.date.month == _filterDate!.month &&
              trx.date.day == _filterDate!.day;
          if (!isSameDay) return false;
        }

        // 3. Quick Filter
        switch (_quickFilter) {
          case TransactionQuickFilter.all:
            return true;
          case TransactionQuickFilter.today:
            return DateFormat('yyyy-MM-dd').format(trx.date) == todayStr;
          case TransactionQuickFilter.thisWeek:
            return trx.date.isAfter(startOfWeekDate.subtract(const Duration(seconds: 1)));
          case TransactionQuickFilter.bonOnly:
            return trx.status.toUpperCase() == 'BON';
        }
      }).toList();
    });
  }

  Future<void> _selectFilterDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _filterDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _filterDate = picked;
        _quickFilter = TransactionQuickFilter.all; // reset quick filter
      });
      _applyFilter();
    }
  }

  void _clearDateFilter() {
    setState(() {
      _filterDate = null;
    });
    _applyFilter();
  }

  Future<void> _deleteTransaction(Transaction trx) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Transaksi?'),
        content: Text(
          'Apakah Anda yakin ingin menghapus nota ${trx.id_transaksi} atas nama ${trx.customerName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final id = trx.id;
    try {
      // Coba hapus via Laravel API atau fallback ke MockAPI
      final url = 'https://laravel.fathurrzqn8n.web.id/api/transaksi/$id';
      final response = await http.delete(Uri.parse(url));

      if (response.statusCode == 200 || response.statusCode == 204) {
        setState(() {
          _transactions.removeWhere((t) => t.id == id);
        });
        _applyFilter();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaksi berhasil dihapus')),
        );
      } else {
        // Fallback MockAPI jika endpoint Laravel belum ada
        final fallbackUrl =
            'http://6873b63ec75558e273550195.mockapi.io/transaksi/$id';
        await http.delete(Uri.parse(fallbackUrl));
        setState(() {
          _transactions.removeWhere((t) => t.id == id);
        });
        _applyFilter();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaksi berhasil dihapus')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal menghapus transaksi: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _exportToCSV() async {
    if (_transactions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada transaksi untuk diarsipkan')),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final dir = await getApplicationDocumentsDirectory();
      final path = "${dir.path}/arsip";
      final folder = Directory(path);

      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }

      final timestamp = DateFormat("yyyyMMdd_HHmmss").format(DateTime.now());
      final fileName = "transaksi_$timestamp.csv";
      final file = File("$path/$fileName");

      List<List<dynamic>> rows = [
        [
          "ID Transaksi",
          "Customer",
          "Alamat",
          "Tanggal",
          "Total",
          "Status",
          "Nama Barang",
          "Harga",
          "Qty",
          "Bonus",
          "Subtotal",
        ],
      ];

      for (var trx in _transactions) {
        for (var item in trx.items) {
          rows.add([
            trx.id_transaksi,
            trx.customerName,
            trx.alamat,
            trx.date.toIso8601String(),
            trx.total,
            trx.status,
            item.name,
            item.price,
            item.quantity,
            item.bonus,
            item.subtotal,
          ]);
        }
      }

      final csvData = const ListToCsvConverter().convert(rows);
      await file.writeAsString(csvData);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Berhasil diarsipkan ke $fileName")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Gagal export CSV: $e")),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _confirmDeleteAll() async {
    final count = _transactions.length;
    if (count == 0) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Semua Transaksi?'),
        content: Text(
          'Tindakan ini akan menghapus seluruh $count nota transaksi dari sistem secara permanen. '
          'Pastikan Anda sudah mengarsipkan data ke CSV terlebih dahulu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Hapus $count Nota'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isProcessing = true);
    try {
      // Hapus di mockapi jika digunakan
      const url = 'http://6873b63ec75558e273550195.mockapi.io/transaksi';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        for (var trx in data) {
          final deleteUrl = "$url/${trx['id']}";
          await http.delete(Uri.parse(deleteUrl));
        }
      }

      setState(() {
        _transactions.clear();
        _filteredTransactions.clear();
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Semua transaksi berhasil dihapus')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menghapus data: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daftar Transaksi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.archive_outlined),
            tooltip: 'Arsipkan ke CSV',
            onPressed: _exportToCSV,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'export') {
                _exportToCSV();
              } else if (value == 'deleteAll') {
                _confirmDeleteAll();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.file_download_outlined, size: 20),
                    SizedBox(width: 10),
                    Text('Export ke CSV'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'deleteAll',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep_outlined, size: 20, color: AppColors.error),
                    SizedBox(width: 10),
                    Text(
                      'Hapus Semua Data',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isProcessing
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: fetchTransactions,
              color: AppColors.primary,
              child: Column(
                children: [
                  // SEARCH BAR & QUICK FILTERS
                  Container(
                    color: AppColors.surface,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenMargin,
                      AppSpacing.sm,
                      AppSpacing.screenMargin,
                      AppSpacing.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Search Field
                        TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            hintText: 'Cari nota atau nama konsumen...',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            suffixIcon: _searchCtrl.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () => _searchCtrl.clear(),
                                  )
                                : null,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Quick Filter Chips Row
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildFilterChip(
                                label: 'Semua',
                                selected: _quickFilter == TransactionQuickFilter.all &&
                                    _filterDate == null,
                                onSelected: () {
                                  setState(() {
                                    _quickFilter = TransactionQuickFilter.all;
                                    _filterDate = null;
                                  });
                                  _applyFilter();
                                },
                              ),
                              const SizedBox(width: 8),
                              _buildFilterChip(
                                label: 'Hari Ini',
                                selected: _quickFilter == TransactionQuickFilter.today &&
                                    _filterDate == null,
                                onSelected: () {
                                  setState(() {
                                    _quickFilter = TransactionQuickFilter.today;
                                    _filterDate = null;
                                  });
                                  _applyFilter();
                                },
                              ),
                              const SizedBox(width: 8),
                              _buildFilterChip(
                                label: 'Minggu Ini',
                                selected: _quickFilter ==
                                        TransactionQuickFilter.thisWeek &&
                                    _filterDate == null,
                                onSelected: () {
                                  setState(() {
                                    _quickFilter = TransactionQuickFilter.thisWeek;
                                    _filterDate = null;
                                  });
                                  _applyFilter();
                                },
                              ),
                              const SizedBox(width: 8),
                              _buildFilterChip(
                                label: 'BON Saja',
                                selected: _quickFilter == TransactionQuickFilter.bonOnly &&
                                    _filterDate == null,
                                onSelected: () {
                                  setState(() {
                                    _quickFilter = TransactionQuickFilter.bonOnly;
                                    _filterDate = null;
                                  });
                                  _applyFilter();
                                },
                              ),
                              const SizedBox(width: 8),
                              // Date Picker Chip
                              ActionChip(
                                avatar: Icon(
                                  _filterDate == null
                                      ? Icons.calendar_today_outlined
                                      : Icons.check,
                                  size: 16,
                                  color: _filterDate != null
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                ),
                                label: Text(
                                  _filterDate == null
                                      ? 'Pilih Tanggal'
                                      : DateFormat('dd MMM yyyy').format(_filterDate!),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: _filterDate != null
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: _filterDate != null
                                        ? AppColors.primary
                                        : AppColors.textPrimary,
                                  ),
                                ),
                                backgroundColor: _filterDate != null
                                    ? AppColors.primaryLight
                                    : AppColors.background,
                                side: BorderSide(
                                  color: _filterDate != null
                                      ? AppColors.primary
                                      : AppColors.surfaceBorder,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.chipFull),
                                ),
                                onPressed: () => _selectFilterDate(context),
                              ),
                              if (_filterDate != null) ...[
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(
                                    Icons.cancel,
                                    size: 18,
                                    color: AppColors.textSecondary,
                                  ),
                                  tooltip: 'Hapus filter tanggal',
                                  onPressed: _clearDateFilter,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // OFFLINE SYNC ALERT BANNER
                  if (_pendingOfflineCount > 0)
                    Container(
                      margin: const EdgeInsets.fromLTRB(
                        AppSpacing.screenMargin,
                        0,
                        AppSpacing.screenMargin,
                        AppSpacing.sm,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.cloud_off_rounded,
                            size: 18,
                            color: Colors.amber.shade900,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '$_pendingOfflineCount nota tersimpan di HP (offline)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ),
                          _isSyncing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : TextButton(
                                  onPressed: syncOfflineData,
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.amber.shade900,
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text(
                                    'Hubungkan',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                        ],
                      ),
                    ),

                  // TRANSACTION LIST CONTENT
                  Expanded(
                    child: _isLoading
                        ? const SkeletonList(count: 6)
                        : _filteredTransactions.isEmpty
                            ? EmptyStateWidget(
                                icon: Icons.receipt_long_outlined,
                                title: _searchCtrl.text.isNotEmpty || _filterDate != null
                                    ? 'Tidak Ditemukan'
                                    : 'Belum Ada Transaksi',
                                subtitle: _searchCtrl.text.isNotEmpty
                                    ? 'Tidak ada nota yang cocok dengan pencarian Anda.'
                                    : 'Mulai buat nota pertama dengan tombol + Nota Baru.',
                                actionLabel: _searchCtrl.text.isNotEmpty
                                    ? 'Reset Filter'
                                    : (widget.onCreateNota != null ? 'Buat Nota Baru' : null),
                                onAction: _searchCtrl.text.isNotEmpty
                                    ? () {
                                        _searchCtrl.clear();
                                        _clearDateFilter();
                                        setState(() {
                                          _quickFilter = TransactionQuickFilter.all;
                                        });
                                        _applyFilter();
                                      }
                                    : widget.onCreateNota,
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.all(AppSpacing.screenMargin),
                                itemCount: _filteredTransactions.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: AppSpacing.cardGap),
                                itemBuilder: (context, index) {
                                  final trx = _filteredTransactions[index];
                                  return TransactionCard(
                                    transaction: trx,
                                    onTap: () async {
                                      final updated = await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => TransactionDetailPage(
                                            transaction: trx,
                                          ),
                                        ),
                                      );
                                      if (updated != null) {
                                        fetchTransactions();
                                      }
                                    },
                                    onLongPress: () => _deleteTransaction(trx),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? AppColors.primary : AppColors.textPrimary,
      ),
      backgroundColor: AppColors.background,
      selectedColor: AppColors.primaryLight,
      checkmarkColor: AppColors.primary,
      side: BorderSide(
        color: selected ? AppColors.primary : AppColors.surfaceBorder,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.chipFull),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    );
  }
}
