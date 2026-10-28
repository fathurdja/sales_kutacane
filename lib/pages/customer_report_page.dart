import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/config/api_config.dart';
import 'package:kasir_kutacane/models/customer_model.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/pages/transactionDetail.dart';
import 'package:kasir_kutacane/services/auth_service.dart';
import 'package:kasir_kutacane/services/customer_api_service.dart';
import 'package:kasir_kutacane/services/pelunasan_history_service.dart';
import 'package:kasir_kutacane/services/print.dart';
import 'package:kasir_kutacane/theme/app_theme.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerFinancialSummary {
  final String customerName;
  final String alamat;
  final String? telepon;
  int totalNota = 0;
  int notaBon = 0;
  int notaLunas = 0;
  double totalOmzet = 0.0;
  double totalLunas = 0.0;
  double totalBon = 0.0;
  final List<Transaction> transactions = [];

  CustomerFinancialSummary({
    required this.customerName,
    this.alamat = '',
    this.telepon,
  });

  bool get hasActiveBon => totalBon > 0;
}

class CustomerReportPage extends StatefulWidget {
  const CustomerReportPage({super.key});

  @override
  State<CustomerReportPage> createState() => _CustomerReportPageState();
}

class _CustomerReportPageState extends State<CustomerReportPage>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  String? _errorMessage;
  final TextEditingController _searchCtrl = TextEditingController();

  List<CustomerFinancialSummary> _allSummaries = [];
  List<CustomerFinancialSummary> _filteredSummaries = [];

  String _filterTab = 'BON_ONLY'; // 'BON_ONLY', 'SEMUA', 'LUNAS_ONLY'
  String _sortBy = 'BON_DESC'; // 'BON_DESC', 'OMZET_DESC', 'NAME_ASC'

  final NumberFormat _currencyFormat =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final DateFormat _dateFormat = DateFormat('dd MMM yyyy, HH:mm');

  @override
  void initState() {
    super.initState();
    _loadReportData();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_applyFilter);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadReportData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Ambil seluruh transaksi dari server utama
      final headers = await AuthService.getAuthHeaders();
      final response = await http
          .get(ApiConfig.transaksiUri, headers: headers)
          .timeout(const Duration(seconds: 10));

      List<Transaction> serverTransactions = [];
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        serverTransactions = data
            .map<Transaction>(
              (json) => Transaction.fromJson(json as Map<String, dynamic>),
            )
            .toList();
      }

      // Sinkronkan status pelunasan dengan file history lokal
      final historyMap = await PelunasanHistoryService.loadHistory();
      for (final t in serverTransactions) {
        if (historyMap.containsKey(t.id_transaksi)) {
          final rec = historyMap[t.id_transaksi]!;
          t.status = 'LUNAS';
          t.tanggalPelunasan = rec.tanggalPelunasan;
        } else if (t.status.toUpperCase() == 'LUNAS' &&
            t.tanggalPelunasan == null) {
          t.tanggalPelunasan = t.date;
        }
      }

      // 2. Ambil master data pelanggan untuk melengkapi alamat & telepon
      final customers = await CustomerApiService.getCachedCustomers();
      final Map<String, Customer> customerMeta = {};
      for (final c in customers) {
        customerMeta[c.name.trim().toLowerCase()] = c;
      }

      // 3. Agregasikan transaksi per nama pelanggan
      final Map<String, CustomerFinancialSummary> grouped = {};

      for (final trx in serverTransactions) {
        final rawName = trx.customerName.trim();
        final key = rawName.toLowerCase();
        if (key.isEmpty) continue;

        if (!grouped.containsKey(key)) {
          final meta = customerMeta[key];
          grouped[key] = CustomerFinancialSummary(
            customerName: meta?.name ?? rawName,
            alamat: meta?.alamat.isNotEmpty == true
                ? meta!.alamat
                : (trx.alamat.isNotEmpty ? trx.alamat : 'Gorontalo'),
            telepon: meta?.telepon,
          );
        }

        final summary = grouped[key]!;
        summary.totalNota++;
        summary.totalOmzet += trx.total;
        summary.transactions.add(trx);

        if (trx.status.toUpperCase() == 'BON') {
          summary.notaBon++;
          summary.totalBon += trx.total;
        } else {
          // LUNAS atau QRIS
          summary.notaLunas++;
          summary.totalLunas += trx.total;
        }
      }

      // Masukkan juga pelanggan master yang belum pernah ada transaksi agar terlihat 0
      for (final c in customers) {
        final key = c.name.trim().toLowerCase();
        if (!grouped.containsKey(key)) {
          grouped[key] = CustomerFinancialSummary(
            customerName: c.name,
            alamat: c.alamat,
            telepon: c.telepon,
          );
        }
      }

      final list = grouped.values.toList();
      for (final item in list) {
        item.transactions.sort((a, b) => b.date.compareTo(a.date));
      }

      if (!mounted) return;
      setState(() {
        _allSummaries = list;
        _isLoading = false;
        _applyFilter();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Gagal memuat rekap laporan pelanggan: $e';
      });
    }
  }

  void _applyFilter() {
    final query = _searchCtrl.text.trim().toLowerCase();

    List<CustomerFinancialSummary> results = _allSummaries.where((s) {
      // 1. Filter Tab
      if (_filterTab == 'BON_ONLY' && !s.hasActiveBon) return false;
      if (_filterTab == 'LUNAS_ONLY' && (s.hasActiveBon || s.totalNota == 0)) {
        return false;
      }

      // 2. Search Query
      if (query.isNotEmpty) {
        final n = s.customerName.toLowerCase();
        final a = s.alamat.toLowerCase();
        final t = (s.telepon ?? '').toLowerCase();
        if (!n.contains(query) && !a.contains(query) && !t.contains(query)) {
          return false;
        }
      }

      return true;
    }).toList();

    // 3. Sorting
    results.sort((a, b) {
      switch (_sortBy) {
        case 'BON_DESC':
          final cmp = b.totalBon.compareTo(a.totalBon);
          if (cmp != 0) return cmp;
          return b.totalOmzet.compareTo(a.totalOmzet);
        case 'OMZET_DESC':
          return b.totalOmzet.compareTo(a.totalOmzet);
        case 'NAME_ASC':
          return a.customerName
              .toLowerCase()
              .compareTo(b.customerName.toLowerCase());
        default:
          return b.totalBon.compareTo(a.totalBon);
      }
    });

    setState(() {
      _filteredSummaries = results;
    });
  }

  // ===========================================================================
  // MODAL DETAIL NOTA PELANGGAN & PELUNASAN CEPAT
  // ===========================================================================
  void _showCustomerDetailSheet(CustomerFinancialSummary summary) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.88,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.screenMargin),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: summary.hasActiveBon
                            ? AppColors.error.withValues(alpha: 0.12)
                            : AppColors.lunas.withValues(alpha: 0.12),
                        child: Icon(
                          Icons.storefront_rounded,
                          color: summary.hasActiveBon
                              ? AppColors.error
                              : AppColors.lunas,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              summary.customerName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              summary.alamat.isNotEmpty
                                  ? summary.alamat
                                  : 'Gorontalo',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (summary.hasActiveBon)
                        IconButton(
                          icon: const Icon(Icons.share_outlined,
                              color: AppColors.primary),
                          tooltip: 'Bagikan Rincian Tagihan',
                          onPressed: () => _shareBonSummary(summary),
                        ),
                    ],
                  ),
                ),

                // Kartu Ringkasan Keuangan Pelanggan
                Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenMargin,
                  ),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.surfaceBorder),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _metricColumn(
                          'Sisa Piutang (BON)',
                          _currencyFormat.format(summary.totalBon),
                          '${summary.notaBon} Nota Belum Lunas',
                          AppColors.error,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 38,
                        color: AppColors.surfaceBorder,
                      ),
                      Expanded(
                        child: _metricColumn(
                          'Sudah Terbayar',
                          _currencyFormat.format(summary.totalLunas),
                          '${summary.notaLunas} Nota Lunas',
                          AppColors.lunas,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 38,
                        color: AppColors.surfaceBorder,
                      ),
                      Expanded(
                        child: _metricColumn(
                          'Total Omzet',
                          _currencyFormat.format(summary.totalOmzet),
                          '${summary.totalNota} Total Nota',
                          AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenMargin),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Riwayat Nota Transaksi Pelanggan Ini:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // Daftar Seluruh Transaksi Pelanggan
                Expanded(
                  child: summary.transactions.isEmpty
                      ? const Center(
                          child: Text(
                            'Belum ada transaksi tercatat untuk pelanggan ini.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(AppSpacing.screenMargin),
                          itemCount: summary.transactions.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (ctx, i) {
                            final trx = summary.transactions[i];
                            final isBon = trx.status.toUpperCase() == 'BON';

                            return Container(
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isBon
                                      ? AppColors.error.withValues(alpha: 0.3)
                                      : AppColors.surfaceBorder,
                                ),
                              ),
                              child: ListTile(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => TransactionDetailPage(
                                        transaction: trx,
                                      ),
                                    ),
                                  );
                                },
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 4,
                                ),
                                title: Row(
                                  children: [
                                    Text(
                                      trx.id_transaksi,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isBon
                                            ? AppColors.error.withValues(alpha: 0.12)
                                            : AppColors.lunas.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        trx.status.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: isBon
                                              ? AppColors.error
                                              : AppColors.lunas,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 3),
                                    Text(
                                      _dateFormat.format(trx.date),
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    if (trx.items.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        trx.items
                                            .map((it) => '${it.name} x${it.quantity}')
                                            .join(', '),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Text(
                                          _currencyFormat.format(trx.total),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13.5,
                                            color: isBon
                                                ? AppColors.error
                                                : AppColors.textPrimary,
                                          ),
                                        ),
                                        const Spacer(),
                                        if (isBon)
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: AppColors.lunas,
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 4,
                                              ),
                                              minimumSize: Size.zero,
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            ),
                                            icon: const Icon(Icons.check_circle_outline, size: 14),
                                            label: const Text(
                                              'Lunasi Bon',
                                              style: TextStyle(fontSize: 11),
                                            ),
                                            onPressed: () async {
                                              await _processPelunasan(trx, summary);
                                              setSheetState(() {});
                                            },
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _metricColumn(String title, String val, String sub, Color color) {
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(
          val,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          sub,
          style: const TextStyle(fontSize: 9.5, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  // ===========================================================================
  // PELUNASAN TRANSAKSI LANGSUNG DARI LAPORAN
  // ===========================================================================
  Future<void> _processPelunasan(
    Transaction trx,
    CustomerFinancialSummary summary,
  ) async {
    DateTime selectedDate = DateTime.now();

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      helpText: 'Tentukan Tanggal Pelunasan Kas',
    );

    if (pickedDate == null) return;
    selectedDate = pickedDate;

    bool printReceipt = true;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return AlertDialog(
            title: const Text('Konfirmasi Pelunasan Bon'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lunasi Nota: ${trx.id_transaksi}\n'
                  'Pelanggan: ${trx.customerName}\n'
                  'Nominal: ${_currencyFormat.format(trx.total)}\n'
                  'Tanggal Pelunasan: ${DateFormat('dd MMMM yyyy').format(selectedDate)}',
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Cetak Struk Tanda Lunas ke Printer',
                    style: TextStyle(fontSize: 13),
                  ),
                  value: printReceipt,
                  onChanged: (val) {
                    setDlgState(() => printReceipt = val ?? true);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.lunas,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Simpan & Lunasi'),
              ),
            ],
          );
        },
      ),
    );

    if (confirm != true) return;

    // Lakukan update pelunasan
    final formattedPelunasan = DateFormat('yyyy-MM-dd').format(selectedDate);
    final updatePayload = {
      'status': 'LUNAS',
      'tanggal_pelunasan': formattedPelunasan,
    };

    try {
      final headers = await AuthService.getAuthHeaders();
      await http.put(
        ApiConfig.transaksiDetailUri(trx.id_transaksi),
        headers: headers,
        body: jsonEncode(updatePayload),
      ).timeout(const Duration(seconds: 8));

      // Update Supabase
      try {
        final supabase = Supabase.instance.client;
        await supabase.from('transaksi').update({
          'status': 'LUNAS',
          'tanggal_pelunasan': formattedPelunasan,
        }).eq('id_transaksi', trx.id_transaksi);
      } catch (_) {}

      // Catat di riwayat lokal
      await PelunasanHistoryService.recordSettlement(
        idTransaksi: trx.id_transaksi,
        customerName: trx.customerName,
        total: trx.total,
        tanggalPelunasan: selectedDate,
      );

      // Cetak struk jika dipilih
      if (printReceipt) {
        trx.status = 'LUNAS';
        trx.tanggalPelunasan = selectedDate;
        try {
          await TestPrint().printTransaction(trx);
        } catch (_) {}
      }

      // Perbarui objek di memori
      setState(() {
        trx.status = 'LUNAS';
        trx.tanggalPelunasan = selectedDate;
        summary.notaBon = (summary.notaBon - 1).clamp(0, 9999);
        summary.notaLunas += 1;
        summary.totalBon = (summary.totalBon - trx.total).clamp(0, 999999999);
        summary.totalLunas += trx.total;
        _applyFilter();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Nota ${trx.id_transaksi} (${summary.customerName}) berhasil dilunasi!',
            ),
            backgroundColor: AppColors.lunas,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memperbarui pelunasan: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _shareBonSummary(CustomerFinancialSummary summary) {
    final buffer = StringBuffer();
    buffer.writeln('*RINCIAN TAGIHAN BON / PIUTANG BONEVA*');
    buffer.writeln('Pelanggan: ${summary.customerName}');
    buffer.writeln('Alamat: ${summary.alamat}');
    buffer.writeln('----------------------------------------');

    final bonList =
        summary.transactions.where((t) => t.status.toUpperCase() == 'BON').toList();
    for (int i = 0; i < bonList.length; i++) {
      final t = bonList[i];
      buffer.writeln(
        '${i + 1}. Nota: ${t.id_transaksi} (${DateFormat('dd/MM/yyyy').format(t.date)})\n'
        '   Total: ${_currencyFormat.format(t.total)}',
      );
    }

    buffer.writeln('----------------------------------------');
    buffer.writeln('*TOTAL SISA BON: ${_currencyFormat.format(summary.totalBon)}*');
    buffer.writeln('Terima kasih atas kerja samanya.');

    Share.share(buffer.toString(), subject: 'Tagihan Piutang ${summary.customerName}');
  }

  @override
  Widget build(BuildContext context) {
    // PROTEKSI ROLE KHUSUS ADMIN (Sesuai Permintaan User: "khusus untuk admin saja yah menu ini , jangan buka untuk sales")
    if (AuthService.currentUser?.isAdmin != true) {
      return Scaffold(
        appBar: AppBar(title: const Text('Laporan Pelanggan')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.lock_person_outlined,
                  size: 72,
                  color: AppColors.error,
                ),
                const SizedBox(height: 18),
                const Text(
                  'Akses Dibatasi Khusus Administrator',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Laporan rekapitulasi BON dan LUNAS per pelanggan hanya dapat diakses oleh akun Admin untuk keperluan kontrol piutang & monitoring armada.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Kembali'),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Hitung Akumulasi Total Keseluruhan
    double grandTotalBon = 0.0;
    double grandTotalLunas = 0.0;
    int totalTokoBon = 0;

    for (final s in _allSummaries) {
      grandTotalBon += s.totalBon;
      grandTotalLunas += s.totalLunas;
      if (s.hasActiveBon) totalTokoBon++;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan Bon & Lunas Pelanggan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Muat ulang data',
            onPressed: _loadReportData,
          ),
        ],
      ),
      body: Column(
        children: [
          // Header Ringkasan Keuangan Global
          Container(
            padding: const EdgeInsets.all(AppSpacing.screenMargin),
            color: AppColors.surface,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.error.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.error_outline_rounded,
                                  size: 16,
                                  color: AppColors.error,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Sisa Bon Belum Lunas',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.error,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _currencyFormat.format(grandTotalBon),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.error,
                              ),
                            ),
                            Text(
                              '$totalTokoBon Toko Menunggak',
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.lunas.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.lunas.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.check_circle_outline_rounded,
                                  size: 16,
                                  color: AppColors.lunas,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Total Omzet Lunas',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.lunas,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _currencyFormat.format(grandTotalLunas),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.lunas,
                              ),
                            ),
                            Text(
                              '${_allSummaries.length} Total Toko',
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: AppSpacing.sm),

                // Search Bar
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Cari nama toko/pelanggan...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 20),
                            onPressed: () => _searchCtrl.clear(),
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.sm),

                // Filter Tabs & Sorting
                Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _filterChip('Punya Bon ($totalTokoBon)', 'BON_ONLY'),
                            const SizedBox(width: 6),
                            _filterChip('Semua (${_allSummaries.length})', 'SEMUA'),
                            const SizedBox(width: 6),
                            _filterChip('Lunas Semua', 'LUNAS_ONLY'),
                          ],
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.sort_rounded, size: 20),
                      tooltip: 'Urutkan data',
                      onSelected: (val) {
                        setState(() {
                          _sortBy = val;
                          _applyFilter();
                        });
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'BON_DESC',
                          child: Text('Sisa BON Terbesar'),
                        ),
                        const PopupMenuItem(
                          value: 'OMZET_DESC',
                          child: Text('Total Omzet Terbesar'),
                        ),
                        const PopupMenuItem(
                          value: 'NAME_ASC',
                          child: Text('Nama Pelanggan (A - Z)'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1, thickness: 1, color: AppColors.surfaceBorder),

          // Daftar Ringkasan Pelanggan
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline,
                                  size: 48, color: AppColors.error),
                              const SizedBox(height: 12),
                              Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: AppColors.error),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _loadReportData,
                                child: const Text('Coba Lagi'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _filteredSummaries.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _filterTab == 'BON_ONLY'
                                      ? Icons.celebration_rounded
                                      : Icons.search_off_rounded,
                                  size: 56,
                                  color: _filterTab == 'BON_ONLY'
                                      ? AppColors.lunas
                                      : AppColors.textSecondary,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _filterTab == 'BON_ONLY'
                                      ? 'Luar biasa! Tidak ada toko yang memiliki tunggakan BON.'
                                      : 'Data pelanggan tidak ditemukan',
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadReportData,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(
                                AppSpacing.screenMargin,
                              ),
                              itemCount: _filteredSummaries.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (ctx, i) {
                                final summary = _filteredSummaries[i];

                                return Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.card),
                                    border: Border.all(
                                      color: summary.hasActiveBon
                                          ? AppColors.error.withValues(alpha: 0.35)
                                          : AppColors.surfaceBorder,
                                      width: summary.hasActiveBon ? 1.5 : 1.0,
                                    ),
                                    boxShadow: AppShadow.card,
                                  ),
                                  child: InkWell(
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.card),
                                    onTap: () =>
                                        _showCustomerDetailSheet(summary),
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              CircleAvatar(
                                                radius: 18,
                                                backgroundColor: summary.hasActiveBon
                                                    ? AppColors.error
                                                        .withValues(alpha: 0.12)
                                                    : AppColors.lunas
                                                        .withValues(alpha: 0.12),
                                                child: Text(
                                                  summary.customerName.isNotEmpty
                                                      ? summary.customerName
                                                          .substring(0, 1)
                                                          .toUpperCase()
                                                      : '?',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: summary.hasActiveBon
                                                        ? AppColors.error
                                                        : AppColors.lunas,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      summary.customerName,
                                                      style: const TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 15,
                                                        color: AppColors.textPrimary,
                                                      ),
                                                    ),
                                                    Text(
                                                      summary.alamat.isNotEmpty
                                                          ? summary.alamat
                                                          : 'Gorontalo',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: AppColors
                                                            .textSecondary,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const Icon(
                                                Icons.chevron_right_rounded,
                                                color: AppColors.textSecondary,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: summary.hasActiveBon
                                                  ? AppColors.error
                                                      .withValues(alpha: 0.05)
                                                  : AppColors.bgSecondary,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceBetween,
                                              children: [
                                                Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    const Text(
                                                      'Sisa BON (Piutang):',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: AppColors
                                                            .textSecondary,
                                                      ),
                                                    ),
                                                    Text(
                                                      _currencyFormat
                                                          .format(summary.totalBon),
                                                      style: TextStyle(
                                                        fontSize: 14.5,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: summary.hasActiveBon
                                                            ? AppColors.error
                                                            : AppColors.lunas,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.end,
                                                  children: [
                                                    Text(
                                                      'Lunas: ${_currencyFormat.format(summary.totalLunas)}',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: AppColors.lunas,
                                                      ),
                                                    ),
                                                    Text(
                                                      '${summary.totalNota} Nota (${summary.notaBon} Bon)',
                                                      style: const TextStyle(
                                                        fontSize: 10.5,
                                                        color: AppColors
                                                            .textSecondary,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final isSelected = _filterTab == value;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          color: isSelected ? Colors.white : AppColors.textPrimary,
        ),
      ),
      selected: isSelected,
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.bgSecondary,
      onSelected: (_) {
        setState(() {
          _filterTab = value;
          _applyFilter();
        });
      },
    );
  }
}

