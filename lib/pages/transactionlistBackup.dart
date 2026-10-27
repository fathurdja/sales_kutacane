import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/config/api_config.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/models/user_model.dart';
import 'package:kasir_kutacane/pages/transactionDetail.dart';
import 'package:kasir_kutacane/services/auth_service.dart';
import 'package:kasir_kutacane/services/daily_closing_service.dart';
import 'package:kasir_kutacane/services/offline_sync_service.dart';
import 'package:kasir_kutacane/services/pelunasan_history_service.dart';
import 'package:kasir_kutacane/theme/app_theme.dart';
import 'package:kasir_kutacane/widgets/app_widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum TransactionQuickFilter {
  all,
  today,
  thisWeek,
  bonOnly,
  qrisOnly,
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
  UserModel? _currentUser;
  List<UserModel> _salesUsers = [];
  int? _selectedSalesUserId;

  @override
  void initState() {
    super.initState();
    _loadUserAndSales();
    fetchTransactions();
    _searchCtrl.addListener(_applyFilter);
  }

  Future<void> _loadUserAndSales() async {
    final user = await AuthService.getCurrentUser();
    if (!mounted) return;
    setState(() => _currentUser = user);

    if (user != null && user.isUserAdmin) {
      try {
        final users = await AuthService.fetchUsers();
        if (!mounted) return;
        setState(() => _salesUsers = users);
      } catch (e) {
        debugPrint('Error fetching sales users: $e');
      }
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> fetchTransactions() async {
    String url = '${ApiConfig.baseUrl}/transaksi';
    if (_selectedSalesUserId != null) {
      url = '$url?user_id=$_selectedSalesUserId';
    }
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

    // 2. Ambil dari server dengan Bearer token
    try {
      final headers = await AuthService.getAuthHeaders();
      final response = await http
          .get(
            Uri.parse(url),
            headers: headers,
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);

        final serverTransactions = data
            .map<Transaction>(
              (json) => Transaction.fromJson(json as Map<String, dynamic>),
            )
            .toList();

        // Sinkronkan status pelunasan dengan PelunasanHistoryService
        final historyMap = await PelunasanHistoryService.loadHistory();
        for (final t in serverTransactions) {
          if (historyMap.containsKey(t.id_transaksi)) {
            final rec = historyMap[t.id_transaksi]!;
            t.status = 'LUNAS';
            t.tanggalPelunasan = rec.tanggalPelunasan;
          } else if (t.status.toUpperCase() == 'LUNAS' && t.tanggalPelunasan == null) {
            t.tanggalPelunasan = t.date;
          }
        }

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

    final isSales = _currentUser != null && !_currentUser!.isUserAdmin;
    if (isSales) {
      // Sales HANYA bisa melihat transaksi hari ini
      setState(() {
        _filteredTransactions = _transactions.where((trx) {
          final isToday = DateFormat('yyyy-MM-dd').format(trx.date) == todayStr;
          if (!isToday) return false;

          if (query.isNotEmpty) {
            final matchName = trx.customerName.toLowerCase().contains(query);
            final matchId = trx.id_transaksi.toLowerCase().contains(query);
            if (!matchName && !matchId) return false;
          }
          return true;
        }).toList();
      });
      return;
    }

    // Hitung awal minggu ini (Senin) untuk Admin
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final startOfWeekDate = DateTime(
      startOfWeek.year,
      startOfWeek.month,
      startOfWeek.day,
    );

    setState(() {
      _filteredTransactions = _transactions.where((trx) {
        // 0. Filter Sales Armada jika dipilih oleh Admin
        if (_selectedSalesUserId != null) {
          if (trx.userId != null && trx.userId != _selectedSalesUserId) return false;
        }

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
          case TransactionQuickFilter.qrisOnly:
            return trx.status.toUpperCase() == 'QRIS';
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
    final isAdmin = _currentUser?.isUserAdmin ?? false;
    if (!isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hanya Admin yang memiliki hak akses menghapus transaksi.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Transaksi?'),
        content: Text(
          'Apakah Anda yakin ingin menghapus nota ${trx.id_transaksi} atas nama ${trx.customerName}?\n\n'
          'Tindakan ini hanya dapat dilakukan oleh Admin (misal untuk transaksi yang terinput dua kali).',
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

    final id = trx.id_transaksi.isNotEmpty ? trx.id_transaksi : trx.id;
    setState(() => _isProcessing = true);

    try {
      if (trx.isOffline) {
        await OfflineSyncService.removePendingTransaction(id);
      } else {
        // 1. Hapus via Laravel API dengan Auth Header
        final url = '${ApiConfig.baseUrl}/transaksi/$id';
        final authHeaders = await AuthService.getAuthHeaders();
        final response = await http.delete(
          Uri.parse(url),
          headers: authHeaders,
        ).timeout(const Duration(seconds: 8));

        // Bersihkan juga jika ada sisa duplikat di offline queue
        await OfflineSyncService.removePendingTransaction(id);

        if (response.statusCode != 200 && response.statusCode != 204) {
          throw Exception('Server mengembalikan kode: ${response.statusCode}');
        }
      }

      // 2. Hapus juga dari Supabase Backup jika tersimpan
      try {
        final supabase = Supabase.instance.client;
        await supabase.from('transaksi_items').delete().eq('id_transaksi', id);
        await supabase.from('transaksi').delete().eq('id_transaksi', id);
      } catch (errSupabase) {
        debugPrint('Catatan Supabase delete: $errSupabase');
      }

      // 3. Bersihkan dari riwayat pelunasan jika ada
      await PelunasanHistoryService.removeSettlement(id);

      setState(() {
        _transactions.removeWhere((t) => t.id_transaksi == id || t.id == id);
      });
      _applyFilter();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nota $id berhasil dihapus'),
          backgroundColor: AppColors.lunas,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal menghapus transaksi: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
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

  Future<void> _showDailyClosingDialog() async {
    if (_currentUser?.isUserAdmin != true) return;
    setState(() => _isProcessing = true);
    DailyClosingPreview preview;
    try {
      preview = await DailyClosingService.getClosingPreview(_transactions);
    } catch (e) {
      preview = DailyClosingPreview(
        totalTransactions: _transactions.length,
        totalRevenue: _transactions.fold(0.0, (acc, t) => acc + t.total),
        stockItems: [],
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }

    if (!mounted) return;

    bool rolloverStock = true;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.event_repeat_rounded, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tutup Buku Harian',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Arsip & Rollover Stok Besok',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Summary Nota
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.receipt_long, color: Colors.blue, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${preview.totalTransactions} Nota Transaksi Hari Ini',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                Text(
                                  'Total Omzet: Rp ${NumberFormat('#,###', 'id_ID').format(preview.totalRevenue.toInt())}',
                                  style: TextStyle(color: Colors.blue.shade800, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Point 1: Auto Archive
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Transaksi hari ini otomatis diarsipkan ke CSV (tersimpan aman di menu Arsip).',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Point 2: Rollover Stock Header & Table
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.inventory_2_outlined, color: AppColors.primary, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Stok awal besok otomatis diset dari sisa stok hari ini:',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (preview.stockItems.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          children: preview.stockItems.map((item) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    item.label,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        'Sisa: ${item.sisaStockHariIni}',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                      ),
                                      const Icon(Icons.arrow_right_alt, size: 16, color: Colors.grey),
                                      Text(
                                        'Besok: ${item.stockAwalBesok}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(left: 28),
                        child: Text(
                          '(Stok server akan dicek saat proses berlangsung)',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                        ),
                      ),

                    const SizedBox(height: 12),

                    // Checkbox Rollover
                    Container(
                      decoration: BoxDecoration(
                        color: rolloverStock ? Colors.green.shade50 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: rolloverStock ? Colors.green.shade300 : Colors.grey.shade300,
                        ),
                      ),
                      child: CheckboxListTile(
                        value: rolloverStock,
                        onChanged: (val) {
                          setDialogState(() {
                            rolloverStock = val ?? true;
                          });
                        },
                        title: const Text(
                          'Rollover Stok Otomatis',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text(
                          'Sisa stok jadi stok awal besok & reset counter penjualan ke 0',
                          style: TextStyle(fontSize: 11),
                        ),
                        activeColor: Colors.green.shade700,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Setelah proses ini selesai, daftar transaksi kasir hari ini akan bersih untuk siap digunakan esok hari.',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Batal'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Proses Tutup Buku'),
                  onPressed: () => Navigator.pop(ctx, true),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    // Eksekusi Tutup Buku & Rollover
    setState(() => _isProcessing = true);
    try {
      final result = await DailyClosingService.executeDailyClosing(
        transactions: _transactions,
        rolloverStock: rolloverStock,
      );

      if (!mounted) return;

      if (result.success) {
        setState(() {
          _transactions.clear();
          _filteredTransactions.clear();
        });

        // Dialog Sukses
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.task_alt, color: Colors.green, size: 28),
                SizedBox(width: 10),
                Text('Tutup Buku Berhasil!'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '1. ${result.totalTransactionsArchived} nota transaksi telah berhasil disimpan ke arsip.',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  'Berkas: ${result.archiveFileName}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 10),
                if (rolloverStock) ...[
                  const Text(
                    '2. Stok awal besok telah diset dari sisa stok hari ini:',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  ...result.rolloverItems.map(
                    (it) => Padding(
                      padding: const EdgeInsets.only(left: 12, bottom: 2),
                      child: Text(
                        '• ${it.label}: ${it.stockAwalBesok} unit (Sisa ${it.sisaStockHariIni})',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Counter penjualan harian telah direset ke 0.',
                    style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w500),
                  ),
                ],
              ],
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Selesai'),
              ),
            ],
          ),
        );

        // Muat ulang daftar transaksi
        fetchTransactions();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tutup buku gagal: ${result.errorMessage ?? "Terjadi kesalahan"}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Terjadi kesalahan: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _confirmDeleteAll() async {
    await _showDailyClosingDialog();
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
              if (value == 'closing') {
                _showDailyClosingDialog();
              } else if (value == 'export') {
                _exportToCSV();
              } else if (value == 'deleteAll') {
                _confirmDeleteAll();
              }
            },
            itemBuilder: (ctx) => [
              if (_currentUser?.isUserAdmin == true)
                const PopupMenuItem(
                  value: 'closing',
                  child: Row(
                    children: [
                      Icon(Icons.event_repeat_rounded, size: 20, color: AppColors.primary),
                      SizedBox(width: 10),
                      Text(
                        'Tutup Buku & Rollover Stok',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
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
              if (_currentUser?.isUserAdmin == true)
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

                        // Filter Khusus Admin: Pilih Sales Armada
                        if (_currentUser?.isUserAdmin == true && _salesUsers.isNotEmpty) ...[
                          Row(
                            children: [
                              const Icon(Icons.people_alt_outlined, size: 16, color: AppColors.primary),
                              const SizedBox(width: 6),
                              const Text(
                                'Filter Sales Armada:',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                ChoiceChip(
                                  label: const Text('Semua Sales'),
                                  selected: _selectedSalesUserId == null,
                                  onSelected: (_) {
                                    setState(() => _selectedSalesUserId = null);
                                    fetchTransactions();
                                  },
                                ),
                                const SizedBox(width: 6),
                                ..._salesUsers.where((u) => !u.isAdmin).map((u) {
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: ChoiceChip(
                                      label: Text(u.name),
                                      selected: _selectedSalesUserId == u.id,
                                      onSelected: (_) {
                                        setState(() => _selectedSalesUserId = u.id);
                                        fetchTransactions();
                                      },
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],

                        // Quick Filter Chips Row (Khusus Admin)
                        if (_currentUser?.isUserAdmin == true) ...[
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
                                _buildFilterChip(
                                  label: 'QRIS Saja',
                                  selected: _quickFilter == TransactionQuickFilter.qrisOnly &&
                                      _filterDate == null,
                                  onSelected: () {
                                    setState(() {
                                      _quickFilter = TransactionQuickFilter.qrisOnly;
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
                        ] else ...[
                          // Banner Info Khusus Sales: Hanya Transaksi Hari Ini
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(AppRadius.card),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.today_rounded, size: 16, color: AppColors.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Transaksi Hari Ini (${DateFormat('dd MMMM yyyy', 'id_ID').format(DateTime.now())})',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${_filteredTransactions.length} Nota',
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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
                                    onLongPress: (_currentUser?.isUserAdmin == true)
                                        ? () => _deleteTransaction(trx)
                                        : null,
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
