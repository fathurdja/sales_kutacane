import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/config/api_config.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/models/user_model.dart';
import 'package:kasir_kutacane/pages/transactionDetail.dart';
import 'package:kasir_kutacane/services/auth_service.dart';
import 'package:kasir_kutacane/services/offline_sync_service.dart';
import 'package:kasir_kutacane/services/pelunasan_history_service.dart';
import 'package:kasir_kutacane/services/print.dart';
import 'package:kasir_kutacane/services/printerBluetooth.dart';
import 'package:kasir_kutacane/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PelunasanPage extends StatefulWidget {
  const PelunasanPage({super.key});

  @override
  State<PelunasanPage> createState() => _PelunasanPageState();
}

class _PelunasanPageState extends State<PelunasanPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();

  List<Transaction> _allTransactions = [];
  bool _isLoading = true;
  String? _errorMessage;
  UserModel? _currentUser;

  bool get _isAdmin => _currentUser?.isUserAdmin ?? false;

  // Filter tipe pembayaran: 'ALL', 'BON', 'QRIS' (Item 3)
  String _paymentFilter = 'ALL';

  // Filter tanggal: 'SEMUA', 'HARI_INI', 'MINGGU_INI', 'CUSTOM' (Item 5)
  String _dateFilterPreset = 'SEMUA';
  DateTime? _filterDate;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchCtrl.addListener(() => setState(() {}));
    _loadCurrentUser();
    fetchTransactions();
  }

  Future<void> _loadCurrentUser() async {
    final user = await AuthService.getCurrentUser();
    if (mounted) {
      setState(() => _currentUser = user);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> fetchTransactions() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final token = await AuthService.getToken();
      final headers = {
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      final response = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/transaksi'), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final list = data.map((json) => Transaction.fromJson(json)).toList();

        // Sinkronkan dan lengkapi tanggal_pelunasan dari PelunasanHistoryService
        final historyMap = await PelunasanHistoryService.loadHistory();
        for (final t in list) {
          if (historyMap.containsKey(t.id_transaksi)) {
            final rec = historyMap[t.id_transaksi]!;
            t.status = 'LUNAS';
            t.tanggalPelunasan = rec.tanggalPelunasan;
          } else if (t.status.toUpperCase() == 'LUNAS' && t.tanggalPelunasan == null) {
            t.tanggalPelunasan = t.date;
          }
        }

        // Gabungkan juga dengan transaksi offline lokal jika ada yang berstatus BON
        final pending = await OfflineSyncService.getPendingTransactions();
        for (final p in pending) {
          if (!list.any((t) => t.id_transaksi == p.id_transaksi)) {
            p.isOffline = true;
            list.insert(0, p);
          }
        }

        if (mounted) {
          setState(() {
            _allTransactions = list;
            _isLoading = false;
          });
        }
      } else {
        throw Exception('Server mengembalikan kode status ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetch transaksi: $e, mencoba memuat dari offline/Supabase...');
      // Fallback: muat dari Supabase jika koneksi server utama gagal
      try {
        final supabase = Supabase.instance.client;
        final res = await supabase
            .from('transaksi')
            .select('*')
            .order('tanggal', ascending: false);

        final list = (res as List)
            .map((json) => Transaction.fromJson(json))
            .toList();

        final historyMap = await PelunasanHistoryService.loadHistory();
        for (final t in list) {
          if (historyMap.containsKey(t.id_transaksi)) {
            final rec = historyMap[t.id_transaksi]!;
            t.status = 'LUNAS';
            t.tanggalPelunasan = rec.tanggalPelunasan;
          } else if (t.status.toUpperCase() == 'LUNAS' && t.tanggalPelunasan == null) {
            t.tanggalPelunasan = t.date;
          }
        }

        if (mounted) {
          setState(() {
            _allTransactions = list;
            _isLoading = false;
            _errorMessage = 'Mode Cadangan Supabase: Menampilkan data tersinkron.';
          });
        }
      } catch (err) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Gagal memuat data transaksi: $e';
          });
        }
      }
    }
  }

  bool _matchesDateFilter(DateTime targetDate) {
    if (_dateFilterPreset == 'SEMUA') return true;

    final now = DateTime.now();
    if (_dateFilterPreset == 'HARI_INI') {
      return targetDate.year == now.year &&
          targetDate.month == now.month &&
          targetDate.day == now.day;
    } else if (_dateFilterPreset == 'MINGGU_INI') {
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      final startOfWeekDate = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
      return targetDate.isAfter(startOfWeekDate.subtract(const Duration(seconds: 1)));
    } else if (_dateFilterPreset == 'CUSTOM' && _filterDate != null) {
      return targetDate.year == _filterDate!.year &&
          targetDate.month == _filterDate!.month &&
          targetDate.day == _filterDate!.day;
    }
    return true;
  }

  Future<void> _selectCustomDateFilter() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Pilih Tanggal Transaksi / Pelunasan',
    );
    if (picked != null) {
      setState(() {
        _filterDate = picked;
        _dateFilterPreset = 'CUSTOM';
      });
    }
  }

  List<Transaction> get _pendingTransactions {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _allTransactions.where((t) {
      final isPending = t.isBon || t.isQris;
      if (!isPending) return false;

      // Filter jenis pembayaran (Item 3)
      if (_paymentFilter == 'BON' && !t.isBon) return false;
      if (_paymentFilter == 'QRIS' && !t.isQris) return false;

      // Filter tanggal nota dibuat (Item 5)
      if (!_matchesDateFilter(t.date)) return false;

      if (q.isEmpty) return true;
      return t.customerName.toLowerCase().contains(q) ||
          t.id_transaksi.toLowerCase().contains(q) ||
          t.alamat.toLowerCase().contains(q);
    }).toList();
  }


  List<Transaction> get _lunasTransactions {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _allTransactions.where((t) {
      final isLunas = t.isLunas;
      if (!isLunas) return false;

      // Filter tanggal pelunasan / pembayaran (Item 5)
      final effectiveDate = t.tanggalPelunasan ?? t.date;
      if (!_matchesDateFilter(effectiveDate)) return false;

      if (q.isEmpty) return true;
      return t.customerName.toLowerCase().contains(q) ||
          t.id_transaksi.toLowerCase().contains(q) ||
          t.alamat.toLowerCase().contains(q);
    }).toList();
  }

  double get _totalPiutangBon {
    return _allTransactions
        .where((t) => t.isBon)
        .fold(0.0, (sum, t) => sum + t.total);
  }

  double get _totalPendingQris {
    return _allTransactions
        .where((t) => t.isQris)
        .fold(0.0, (sum, t) => sum + t.total);
  }

  double get _totalPendingAll => _totalPiutangBon + _totalPendingQris;

  void _showPelunasanDialog(Transaction trx) {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hanya Admin yang dapat memproses pelunasan / verifikasi pembayaran.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    DateTime selectedDate = DateTime.now();
    bool isSubmitting = false;
    final isQris = trx.isQris;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final currencyFormat =
              NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
          final dateFormat = DateFormat('dd MMMM yyyy', 'id_ID');

          return Container(
            padding: EdgeInsets.only(
              left: AppSpacing.screenMargin,
              right: AppSpacing.screenMargin,
              top: AppSpacing.xl,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.xl,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (isQris ? AppColors.qris : AppColors.lunas).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isQris ? Icons.qr_code_2_rounded : Icons.task_alt_rounded,
                          color: isQris ? AppColors.qris : AppColors.lunas,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isQris ? 'Verifikasi Pembayaran QRIS' : 'Pelunasan Transaksi Bon',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              'Nomor Nota: ${trx.id_transaksi}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 12),

                  // Detail Transaksi
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.bgSecondary,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Pelanggan:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                            Text(trx.customerName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(isQris ? 'Tanggal Transaksi:' : 'Tanggal Bon:', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                            Text(dateFormat.format(trx.date), style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(isQris ? 'Nominal QRIS:' : 'Total Tagihan:', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                            Text(
                              currencyFormat.format(trx.total),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: isQris ? AppColors.qris : AppColors.bon,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  Text(
                    isQris ? 'Pilih Tanggal Verifikasi Masuk:' : 'Pilih Tanggal Pelunasan:',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),

                  // Date Picker Card
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 30)),
                        helpText: isQris ? 'Pilih Tanggal Verifikasi Dana' : 'Pilih Tanggal Pembayaran/Pelunasan',
                      );
                      if (picked != null) {
                        setModalState(() {
                          selectedDate = picked;
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: (isQris ? AppColors.qris : AppColors.primary).withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_month_outlined, color: isQris ? AppColors.qris : AppColors.primary, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              dateFormat.format(selectedDate),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          const Icon(Icons.edit_calendar_outlined, size: 18, color: AppColors.textSecondary),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Tombol Aksi
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Batal'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          icon: isSubmitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Icon(isQris ? Icons.verified_outlined : Icons.check_circle_outline, size: 18),
                          label: Text(isSubmitting
                              ? 'Memproses...'
                              : (isQris ? 'Verifikasi Lunas' : 'Lunasi Sekarang')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isQris ? AppColors.qris : AppColors.lunas,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: isSubmitting
                              ? null
                              : () async {
                                  setModalState(() => isSubmitting = true);
                                  await _executePelunasan(trx, selectedDate);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _executePelunasan(Transaction trx, DateTime tanggalPelunasan) async {
    if (!_isAdmin) return;
    final formattedDate = DateFormat('yyyy-MM-dd').format(tanggalPelunasan);
    final wasQris = trx.isQris;

    try {
      // 1. Simpan ke PelunasanHistoryService lokal HP
      await PelunasanHistoryService.recordSettlement(
        idTransaksi: trx.id_transaksi,
        customerName: trx.customerName,
        total: trx.total,
        tanggalPelunasan: tanggalPelunasan,
      );

      // Update state seketika
      setState(() {
        trx.status = 'LUNAS';
        trx.tanggalPelunasan = tanggalPelunasan;
      });

      final token = await AuthService.getToken();
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      // 2. Update ke Backend API Utama
      final updateUrl = '${ApiConfig.baseUrl}/transaksi/${trx.id_transaksi}';
      try {
        await http.put(
          Uri.parse(updateUrl),
          headers: headers,
          body: jsonEncode({
            'status': 'LUNAS',
            'tanggal_pelunasan': formattedDate,
          }),
        ).timeout(const Duration(seconds: 10));
      } catch (errApi) {
        debugPrint('Catatan API update status: $errApi');
      }

      // 3. Sinkronkan juga ke Supabase Backup
      try {
        final supabase = Supabase.instance.client;
        await supabase
            .from('transaksi')
            .update({
              'status': 'LUNAS',
              'tanggal_pelunasan': formattedDate,
            })
            .eq('id_transaksi', trx.id_transaksi);
      } catch (errSupabase) {
        debugPrint('Catatan: Supabase update status: $errSupabase');
      }

      // Berpindah langsung ke Tab Riwayat Lunas
      _tabController.animateTo(1);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasQris
                ? 'Nota ${trx.id_transaksi} (${trx.customerName}) BERHASIL DIVERIFIKASI LUNAS!'
                : 'Nota ${trx.id_transaksi} (${trx.customerName}) BERHASIL DILUNASI!',
          ),
          backgroundColor: wasQris ? AppColors.qris : AppColors.lunas,
        ),
      );

      // 4. Cetak struk pelunasan otomatis!
      await _autoPrintReceipt(trx);

      fetchTransactions();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal melakukan pelunasan: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _autoPrintReceipt(Transaction trx) async {
    try {
      final printed = await TestPrint().printTransaction(trx);
      if (printed) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Struk Pelunasan berhasil dicetak otomatis!'),
            backgroundColor: AppColors.lunas,
          ),
        );
      } else {
        if (!mounted) return;
        final shouldOpenPrinter = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.print_outlined, color: AppColors.primary),
                SizedBox(width: 8),
                Text('Cetak Struk Pelunasan'),
              ],
            ),
            content: Text(
              'Nota ${trx.id_transaksi} (${trx.customerName}) telah lunas.\n\n'
              'Printer Bluetooth belum tersambung. Ingin menyambungkan printer sekarang untuk mencetak struk?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Nanti Saja'),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.bluetooth_connected, size: 18),
                label: const Text('Buka Pengaturan Printer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        );

        if (shouldOpenPrinter == true && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => Printbluetooth.fromTransaction(transaction: trx),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error auto print receipt: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Monitoring Pelunasan Bon'),
            Text(
              'Kelola Piutang & Catat Tanggal Pelunasan',
              style: TextStyle(
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
            tooltip: 'Segarkan',
            onPressed: fetchTransactions,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          tabs: [
            Tab(
              icon: const Icon(Icons.pending_actions_outlined, size: 20),
              text: 'Menunggu (${_pendingTransactions.length})',
            ),
            Tab(
              icon: const Icon(Icons.history_outlined, size: 20),
              text: 'Riwayat Lunas (${_lunasTransactions.length})',
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Error / Info Bar
                if (_errorMessage != null)
                  Container(
                    width: double.infinity,
                    color: Colors.amber.shade100,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.amber.shade900),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Search Box
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.screenMargin, AppSpacing.screenMargin, AppSpacing.screenMargin, 8),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Cari nama pelanggan atau No. Nota...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => _searchCtrl.clear(),
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),

                // Filter Tipe & Tanggal (Item 3 & Item 5)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMargin),
                    child: Row(
                      children: [
                        // Filter Jenis Pembayaran
                        ChoiceChip(
                          label: const Text('Semua'),
                          selected: _paymentFilter == 'ALL',
                          onSelected: (_) => setState(() => _paymentFilter = 'ALL'),
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: Text('BON (${_allTransactions.where((t) => t.isBon).length})'),
                          selected: _paymentFilter == 'BON',
                          selectedColor: AppColors.bon.withOpacity(0.22),
                          onSelected: (_) => setState(() => _paymentFilter = 'BON'),
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: Text('QRIS (${_allTransactions.where((t) => t.isQris).length})'),
                          selected: _paymentFilter == 'QRIS',
                          selectedColor: AppColors.qris.withOpacity(0.22),
                          onSelected: (_) => setState(() => _paymentFilter = 'QRIS'),
                        ),
                        const SizedBox(width: 10),
                        Container(width: 1, height: 24, color: Colors.grey.shade300),
                        const SizedBox(width: 10),
                        // Filter Tanggal
                        ChoiceChip(
                          label: const Text('Semua Tanggal'),
                          selected: _dateFilterPreset == 'SEMUA',
                          onSelected: (_) => setState(() {
                            _dateFilterPreset = 'SEMUA';
                            _filterDate = null;
                          }),
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: const Text('Hari Ini'),
                          selected: _dateFilterPreset == 'HARI_INI',
                          onSelected: (_) => setState(() {
                            _dateFilterPreset = 'HARI_INI';
                            _filterDate = null;
                          }),
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: const Text('Minggu Ini'),
                          selected: _dateFilterPreset == 'MINGGU_INI',
                          onSelected: (_) => setState(() {
                            _dateFilterPreset = 'MINGGU_INI';
                            _filterDate = null;
                          }),
                        ),
                        const SizedBox(width: 6),
                        ActionChip(
                          avatar: Icon(
                            _dateFilterPreset == 'CUSTOM' ? Icons.check : Icons.calendar_month_outlined,
                            size: 15,
                            color: _dateFilterPreset == 'CUSTOM' ? AppColors.primary : AppColors.textSecondary,
                          ),
                          label: Text(
                            _dateFilterPreset == 'CUSTOM' && _filterDate != null
                                ? DateFormat('dd MMM').format(_filterDate!)
                                : 'Pilih Tanggal',
                            style: TextStyle(
                              color: _dateFilterPreset == 'CUSTOM' ? AppColors.primary : AppColors.textPrimary,
                              fontWeight: _dateFilterPreset == 'CUSTOM' ? FontWeight.w700 : FontWeight.normal,
                              fontSize: 12,
                            ),
                          ),
                          onPressed: _selectCustomDateFilter,
                        ),
                      ],
                    ),
                  ),
                ),

                // Banner Total Piutang Bon & QRIS
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMargin),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE65100), Color(0xFFEF6C00)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    boxShadow: AppShadow.card,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Total Tertunda & Piutang Berjalan',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                currencyFormat.format(_totalPendingAll),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Bon: ${currencyFormat.format(_totalPiutangBon)} • QRIS: ${currencyFormat.format(_totalPendingQris)}',
                              style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '${_pendingTransactions.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Text(
                              'Tertunda',
                              style: TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Konten Tab
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildBonList(currencyFormat),
                      _buildLunasList(currencyFormat),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildBonList(NumberFormat currencyFormat) {
    final list = _pendingTransactions;
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 54, color: Colors.green.shade400),
            const SizedBox(height: 12),
            const Text(
              'Tidak ada transaksi yang tertunda!',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Semua piutang & QRIS telah terverifikasi lunas atau belum ada nota.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: fetchTransactions,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.screenMargin),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (ctx, idx) {
          final trx = list[idx];
          return Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: trx.isQris ? AppColors.qrisBg : AppColors.bonBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: (trx.isQris ? AppColors.qris : AppColors.bon).withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          trx.isQris ? 'MENUNGGU VERIFIKASI (QRIS)' : 'BELUM LUNAS (BON)',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: trx.isQris ? AppColors.qris : AppColors.bon,
                          ),
                        ),
                      ),
                      Text(
                        dateFormat.format(trx.date),
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    trx.customerName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (trx.alamat.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      trx.alamat,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    'No. Nota: ${trx.id_transaksi}',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.primary, fontWeight: FontWeight.w600),
                  ),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            trx.isQris ? 'Nominal QRIS' : 'Total Piutang',
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                          Text(
                            currencyFormat.format(trx.total),
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: trx.isQris ? AppColors.qris : AppColors.bon,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TransactionDetailPage(transaction: trx),
                                ),
                              );
                            },
                            child: const Text('Detail', style: TextStyle(fontSize: 12)),
                          ),
                          const SizedBox(width: 8),
                          if (_isAdmin)
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: trx.isQris ? AppColors.qris : AppColors.lunas,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: Icon(
                                trx.isQris ? Icons.verified_outlined : Icons.check_circle_outline,
                                size: 16,
                              ),
                              label: Text(
                                trx.isQris ? 'Verifikasi' : 'Lunasi',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                              onPressed: () => _showPelunasanDialog(trx),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.lock_outline, size: 13, color: AppColors.textSecondary),
                                  SizedBox(width: 4),
                                  Text(
                                    'Khusus Admin',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLunasList(NumberFormat currencyFormat) {
    final list = _lunasTransactions;
    final dateFormat = DateFormat('dd MMM yyyy');

    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_outlined, size: 54, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'Belum ada riwayat pelunasan.',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              _dateFilterPreset != 'SEMUA' || _searchCtrl.text.isNotEmpty
                  ? 'Tidak ada transaksi lunas yang cocok dengan filter tanggal/pencarian.'
                  : 'Transaksi yang telah dilunasi akan muncul di sini.',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: fetchTransactions,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.screenMargin),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (ctx, idx) {
          final trx = list[idx];
          return Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.lunasBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.lunas.withOpacity(0.3)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_outline, size: 12, color: AppColors.lunas),
                            SizedBox(width: 4),
                            Text(
                              'NOTA LUNAS',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.lunas,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (trx.tanggalPelunasan != null)
                        Text(
                          'Lunas: ${dateFormat.format(trx.tanggalPelunasan!)}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.lunas,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    trx.customerName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (trx.alamat.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      trx.alamat,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    'No. Nota: ${trx.id_transaksi}',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.primary, fontWeight: FontWeight.w600),
                  ),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Total Pembayaran', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                          Text(
                            currencyFormat.format(trx.total),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: AppColors.lunas,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TransactionDetailPage(transaction: trx),
                                ),
                              );
                            },
                            child: const Text('Detail', style: TextStyle(fontSize: 12)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.print, size: 16),
                            label: const Text('Cetak Struk', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            onPressed: () => _autoPrintReceipt(trx),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
