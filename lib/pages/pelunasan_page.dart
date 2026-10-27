import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/config/api_config.dart';
import 'package:kasir_kutacane/models/transaction.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchCtrl.addListener(() => setState(() {}));
    fetchTransactions();
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

  List<Transaction> get _bonTransactions {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _allTransactions.where((t) {
      final isBon = t.status.toUpperCase() == 'BON';
      if (!isBon) return false;
      if (q.isEmpty) return true;
      return t.customerName.toLowerCase().contains(q) ||
          t.id_transaksi.toLowerCase().contains(q) ||
          t.alamat.toLowerCase().contains(q);
    }).toList();
  }

  List<Transaction> get _lunasTransactions {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _allTransactions.where((t) {
      final isLunas = t.status.toUpperCase() == 'LUNAS';
      if (!isLunas) return false;
      if (q.isEmpty) return true;
      return t.customerName.toLowerCase().contains(q) ||
          t.id_transaksi.toLowerCase().contains(q) ||
          t.alamat.toLowerCase().contains(q);
    }).toList();
  }

  double get _totalPiutangBon {
    return _allTransactions
        .where((t) => t.status.toUpperCase() == 'BON')
        .fold(0.0, (sum, t) => sum + t.total);
  }

  void _showPelunasanDialog(Transaction trx) {
    DateTime selectedDate = DateTime.now();
    bool isSubmitting = false;

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
                          color: AppColors.lunas.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.task_alt_rounded,
                          color: AppColors.lunas,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Pelunasan Transaksi Bon',
                              style: TextStyle(
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
                            const Text('Tanggal Bon:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                            Text(dateFormat.format(trx.date), style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total Tagihan:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                            Text(
                              currencyFormat.format(trx.total),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppColors.bon,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  const Text(
                    'Pilih Tanggal Pelunasan:',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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
                        helpText: 'Pilih Tanggal Pembayaran/Pelunasan',
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
                        border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_month_outlined, color: AppColors.primary, size: 20),
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
                              : const Icon(Icons.check_circle_outline, size: 18),
                          label: Text(isSubmitting ? 'Memproses...' : 'Lunasi Sekarang'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.lunas,
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
    final formattedDate = DateFormat('yyyy-MM-dd').format(tanggalPelunasan);

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
            'Nota ${trx.id_transaksi} (${trx.customerName}) BERHASIL DILUNASI!',
          ),
          backgroundColor: AppColors.lunas,
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
              text: 'Belum Lunas (${_bonTransactions.length})',
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

                // Search & Filter Box
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.screenMargin),
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

                // Banner Total Piutang Bon
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Total Piutang Bon Berjalan',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            currencyFormat.format(_totalPiutangBon),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '${_bonTransactions.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Text(
                              'Nota Bon',
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
    final list = _bonTransactions;
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 54, color: Colors.green.shade400),
            const SizedBox(height: 12),
            const Text(
              'Tidak ada transaksi bon yang tertunda!',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Semua piutang telah lunas atau belum ada nota bon.',
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
                          color: AppColors.bonBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.bon.withOpacity(0.3)),
                        ),
                        child: const Text(
                          'BELUM LUNAS (BON)',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.bon,
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
                          const Text('Total Piutang', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                          Text(
                            currencyFormat.format(trx.total),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: AppColors.bon,
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
                              backgroundColor: AppColors.lunas,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.check_circle_outline, size: 16),
                            label: const Text('Lunasi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            onPressed: () => _showPelunasanDialog(trx),
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
            const Text(
              'Transaksi yang telah dilunasi akan muncul di sini.',
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
