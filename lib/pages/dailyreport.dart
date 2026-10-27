import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/config/api_config.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/models/user_model.dart';
import 'package:kasir_kutacane/pages/pelunasan_page.dart';
import 'package:kasir_kutacane/pages/transactionDetail.dart';
import 'package:kasir_kutacane/services/auth_service.dart';
import 'package:kasir_kutacane/services/offline_sync_service.dart';
import 'package:kasir_kutacane/services/pelunasan_history_service.dart';
import 'package:kasir_kutacane/services/printAll.dart';
import 'package:kasir_kutacane/theme/app_theme.dart';
import 'package:kasir_kutacane/widgets/app_widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DailyReportDetailPage extends StatefulWidget {
  final DateTime selectedDate;

  const DailyReportDetailPage({super.key, required this.selectedDate});

  @override
  State<DailyReportDetailPage> createState() => _DailyReportDetailPageState();
}

class _DailyReportDetailPageState extends State<DailyReportDetailPage> {
  late DateTime _currentDate;
  bool _isAllDates = false;
  bool _loading = true;
  List<Transaction> _allTransactions = [];
  List<Transaction> _filteredTransactions = [];
  String _statusFilter = 'SEMUA'; // 'SEMUA', 'LUNAS', 'QRIS', 'BON', 'ALL_BON'
  UserModel? _currentUser;
  List<UserModel> _salesUsers = [];
  int? _selectedSalesUserId;

  bool get _isAdmin => _currentUser?.isUserAdmin ?? false;

  @override
  void initState() {
    super.initState();
    _currentDate = widget.selectedDate;
    _loadCurrentUser();
    _fetchTransactions();
  }

  Future<void> _loadCurrentUser() async {
    final user = await AuthService.getCurrentUser();
    if (!mounted) return;
    setState(() {
      _currentUser = user;
      // Item 4: Tutup Laporan All Time untuk sales, batasi ke hari ini
      if (user != null && !user.isUserAdmin) {
        _isAllDates = false;
        _currentDate = DateTime.now();
        _applyDateFilter();
      }
    });

    if (user != null && user.isUserAdmin) {
      try {
        final users = await AuthService.fetchUsers();
        if (!mounted) return;
        setState(() => _salesUsers = users);
      } catch (e) {
        debugPrint('Error fetching sales users in daily report: $e');
      }
    }
  }

  Future<void> _fetchTransactions() async {
    setState(() => _loading = true);
    try {
      final headers = await AuthService.getAuthHeaders();
      final url = ApiConfig.transaksiUri;
      final response = await http
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 8));

      List<Transaction> loaded = [];

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        loaded = data
            .map<Transaction>(
              (json) => Transaction.fromJson(json as Map<String, dynamic>),
            )
            .toList();
      } else {
        throw Exception("Server error (${response.statusCode})");
      }

      // Sinkronkan status pelunasan dengan PelunasanHistoryService
      final historyMap = await PelunasanHistoryService.loadHistory();
      for (final t in loaded) {
        if (historyMap.containsKey(t.id_transaksi)) {
          final rec = historyMap[t.id_transaksi]!;
          t.status = 'LUNAS';
          t.tanggalPelunasan = rec.tanggalPelunasan;
        } else if (t.status.toUpperCase() == 'LUNAS' && t.tanggalPelunasan == null) {
          t.tanggalPelunasan = t.date;
        }
      }

      // Gabungkan juga dengan transaksi offline lokal jika ada
      final pending = await OfflineSyncService.getPendingTransactions();
      for (final p in pending) {
        if (!loaded.any((t) => t.id_transaksi == p.id_transaksi)) {
          p.isOffline = true;
          loaded.insert(0, p);
        }
      }

      if (!mounted) return;
      setState(() {
        _allTransactions = loaded;
        _applyDateFilter();
        _loading = false;
      });
    } catch (e) {
      debugPrint("Gagal memuat transaksi utama ($e), mencoba cadangan Supabase/offline...");
      try {
        final supabase = Supabase.instance.client;
        final res = await supabase
            .from('transaksi')
            .select('*')
            .order('tanggal', ascending: false);

        final loaded = (res as List)
            .map((json) => Transaction.fromJson(json as Map<String, dynamic>))
            .toList();

        final historyMap = await PelunasanHistoryService.loadHistory();
        for (final t in loaded) {
          if (historyMap.containsKey(t.id_transaksi)) {
            final rec = historyMap[t.id_transaksi]!;
            t.status = 'LUNAS';
            t.tanggalPelunasan = rec.tanggalPelunasan;
          } else if (t.status.toUpperCase() == 'LUNAS' && t.tanggalPelunasan == null) {
            t.tanggalPelunasan = t.date;
          }
        }

        final pending = await OfflineSyncService.getPendingTransactions();
        for (final p in pending) {
          if (!loaded.any((t) => t.id_transaksi == p.id_transaksi)) {
            p.isOffline = true;
            loaded.insert(0, p);
          }
        }

        if (!mounted) return;
        setState(() {
          _allTransactions = loaded;
          _applyDateFilter();
          _loading = false;
        });
      } catch (err) {
        if (!mounted) return;
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Gagal memuat transaksi: $e"),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _applyDateFilter() {
    // Item 4: Jika sales, kunci selalu ke tanggal hari ini (All Time ditutup)
    if (!_isAdmin) {
      _isAllDates = false;
      final now = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(now);
      _filteredTransactions = _allTransactions.where((trx) {
        return DateFormat('yyyy-MM-dd').format(trx.date) == todayStr;
      }).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      return;
    }

    List<Transaction> list;
    if (_isAllDates) {
      list = List.from(_allTransactions);
    } else {
      final dateStr = DateFormat('yyyy-MM-dd').format(_currentDate);
      list = _allTransactions.where((trx) {
        return DateFormat('yyyy-MM-dd').format(trx.date) == dateStr;
      }).toList();
    }

    // Filter Sales jika dipilih oleh Admin
    if (_selectedSalesUserId != null) {
      list = list.where((trx) => trx.userId == _selectedSalesUserId).toList();
    }

    _filteredTransactions = list..sort((a, b) => b.date.compareTo(a.date));
  }

  void _onDateSelected(DateTime date) {
    if (!_isAdmin) return;
    setState(() {
      _isAllDates = false;
      _currentDate = date;
      _statusFilter = 'SEMUA';
      _applyDateFilter();
    });
  }

  Future<void> _pickArbitraryDate() async {
    if (!_isAdmin) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: _currentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      _onDateSelected(picked);
    }
  }

  List<Transaction> get _lunasTransactions =>
      _filteredTransactions.where((t) => t.status.toUpperCase() == 'LUNAS').toList();

  List<Transaction> get _qrisTransactions =>
      _filteredTransactions.where((t) => t.status.toUpperCase() == 'QRIS').toList();

  List<Transaction> get _bonTransactions =>
      _filteredTransactions.where((t) => t.status.toUpperCase() == 'BON').toList();

  /// Seluruh transaksi BON yang belum lunas di seluruh sistem (Monitoring Bon)
  List<Transaction> get _allActiveBonTransactions =>
      _allTransactions.where((t) => t.status.toUpperCase() == 'BON').toList();

  double get _omzetLunas =>
      _lunasTransactions.fold(0.0, (sum, trx) => sum + trx.total);

  double get _omzetQris =>
      _qrisTransactions.fold(0.0, (sum, trx) => sum + trx.total);

  double get _omzetBon =>
      _bonTransactions.fold(0.0, (sum, trx) => sum + trx.total);

  double get _totalPiutangBonBerjalan =>
      _allActiveBonTransactions.fold(0.0, (sum, trx) => sum + trx.total);

  double get _totalKeseluruhan =>
      _filteredTransactions.fold(0.0, (sum, trx) => sum + trx.total);

  List<Transaction> get _displayedTransactions {
    if (_statusFilter == 'LUNAS') {
      return _lunasTransactions;
    } else if (_statusFilter == 'QRIS') {
      return _qrisTransactions;
    } else if (_statusFilter == 'BON') {
      return _bonTransactions;
    } else if (_statusFilter == 'ALL_BON') {
      return _allActiveBonTransactions;
    }
    return _filteredTransactions;
  }

  Future<pw.Document> generateDailyReport(
    List<Transaction> transactions,
    DateTime date, {
    bool isAllDates = false,
  }) async {
    final pdf = pw.Document();
    final currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ');

    final lunasList = transactions.where((t) => t.status.toUpperCase() == 'LUNAS').toList();
    final qrisList = transactions.where((t) => t.status.toUpperCase() == 'QRIS').toList();
    final bonList = transactions.where((t) => t.status.toUpperCase() == 'BON').toList();
    final totalLunas = lunasList.fold(0.0, (sum, trx) => sum + trx.total);
    final totalQris = qrisList.fold(0.0, (sum, trx) => sum + trx.total);
    final totalBon = bonList.fold(0.0, (sum, trx) => sum + trx.total);
    final totalDaily = transactions.fold(0.0, (sum, trx) => sum + trx.total);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                isAllDates
                    ? "LAPORAN REKAPITULASI TRANSAKSI (SEMUA TANGGAL)"
                    : "LAPORAN HARIAN TRANSAKSI",
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text("Kencana Cahaya Amanah"),
              pw.Text(isAllDates
                  ? "Periode: Semua Tanggal"
                  : "Tanggal: ${DateFormat('dd MMMM yyyy').format(date)}"),
              pw.Divider(thickness: 1),
              pw.SizedBox(height: 8),
            ],
          );
        },
        build: (context) {
          return [
            // KOTAK RINGKASAN OMZET LUNAS, QRIS & PIUTANG BON
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 14),
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    "RINGKASAN OMZET & PIUTANG",
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("• Omzet Lunas (Tunai) [${lunasList.length} Nota]:", style: const pw.TextStyle(fontSize: 10, color: PdfColors.green900)),
                      pw.Text(currencyFormat.format(totalLunas), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                    ],
                  ),
                  pw.SizedBox(height: 3),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("• Omzet QRIS [${qrisList.length} Nota]:", style: const pw.TextStyle(fontSize: 10, color: PdfColors.blue900)),
                      pw.Text(currencyFormat.format(totalQris), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                    ],
                  ),
                  pw.SizedBox(height: 3),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("• Piutang Bon (${isAllDates ? 'Semua Tanggal' : 'Tanggal Ini'}) [${bonList.length} Nota]:", style: const pw.TextStyle(fontSize: 10, color: PdfColors.orange900)),
                      pw.Text(currencyFormat.format(totalBon), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.orange900)),
                    ],
                  ),
                  if (!isAllDates && _allActiveBonTransactions.isNotEmpty) ...[
                    pw.SizedBox(height: 3),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text("• Total Piutang Bon Berjalan (Monitoring Bon) [${_allActiveBonTransactions.length} Nota]:", style: const pw.TextStyle(fontSize: 10, color: PdfColors.amber900)),
                        pw.Text(currencyFormat.format(_totalPiutangBonBerjalan), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.amber900)),
                      ],
                    ),
                  ],
                  pw.Divider(thickness: 0.5, color: PdfColors.grey400),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("TOTAL KESELURUHAN OMZET [${transactions.length} Nota]:", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                      pw.Text(currencyFormat.format(totalDaily), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
                    ],
                  ),
                ],
              ),
            ),

            ...transactions.map(
              (trx) => pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 8),
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          "${trx.id_transaksi} • ${trx.customerName}",
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text(
                          "${trx.status == 'LUNAS' ? 'LUNAS' : 'BON'} - ${currencyFormat.format(trx.total)}",
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            color: trx.status == 'LUNAS' ? PdfColors.green800 : PdfColors.orange800,
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    ...trx.items.map(
                      (item) => pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text("  • ${item.name} (${item.quantity}x + ${item.bonus} bonus)"),
                          pw.Text(currencyFormat.format(item.subtotal)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                "TOTAL KESELURUHAN: ${currencyFormat.format(totalDaily)}",
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
              ),
            ),
          ];
        },
      ),
    );

    return pdf;
  }

  Future<void> _exportPdf() async {
    final exportList = _displayedTransactions;
    if (exportList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Tidak ada transaksi untuk diekspor")),
      );
      return;
    }

    try {
      final pdf = await generateDailyReport(
        exportList,
        _currentDate,
        isAllDates: _isAllDates || _statusFilter == 'ALL_BON',
      );
      final fileName = _statusFilter == 'ALL_BON'
          ? 'laporan_piutang_bon_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf'
          : (_isAllDates
              ? 'laporan_semua_tanggal_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf'
              : 'laporan_${DateFormat('yyyyMMdd').format(_currentDate)}.pdf');
      final output = await getTemporaryDirectory();
      final file = File('${output.path}/$fileName');
      final bytes = await pdf.save();
      await file.writeAsBytes(bytes);

      try {
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/pdf', name: fileName)],
          text: _statusFilter == 'ALL_BON'
              ? 'Laporan Piutang Bon (Monitoring Bon)'
              : (_isAllDates
                  ? 'Laporan transaksi semua tanggal'
                  : 'Laporan harian tanggal ${DateFormat('dd-MM-yyyy').format(_currentDate)}'),
        );
      } catch (shareErr) {
        debugPrint("ShareXFiles laporan gagal ($shareErr), fallback ke Printing.sharePdf...");
        await Printing.sharePdf(bytes: bytes, filename: fileName);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Gagal export PDF: $e"), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _exportCsv() async {
    final exportList = _displayedTransactions;
    if (exportList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Tidak ada transaksi untuk diarsipkan")),
      );
      return;
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory("${dir.path}/arsip");
      if (!(await folder.exists())) {
        await folder.create(recursive: true);
      }

      final fileName = _statusFilter == 'ALL_BON'
          ? "laporan_piutang_bon_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv"
          : (_isAllDates
              ? "laporan_semua_tanggal_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv"
              : "laporan_${DateFormat('yyyyMMdd').format(_currentDate)}.csv");
      final file = File("${folder.path}/$fileName");

      final buffer = StringBuffer();
      buffer.writeln("Tanggal,ID Transaksi,Konsumen,Alamat,Status,Total Nota,Barang,Qty,Bonus,Harga,Subtotal");

      for (var trx in exportList) {
        final trxDate = DateFormat('yyyy-MM-dd HH:mm').format(trx.date);
        for (var item in trx.items) {
          buffer.writeln(
            '"$trxDate","${trx.id_transaksi}","${trx.customerName}","${trx.alamat}","${trx.status}",${trx.total},"${item.name}",${item.quantity},${item.bonus},${item.price},${item.subtotal}',
          );
        }
      }
      buffer.writeln("");
      buffer.writeln("RINGKASAN OMZET & PIUTANG,,,,,,,,,");
      buffer.writeln("TOTAL OMZET LUNAS,,,,,$_omzetLunas,(${_lunasTransactions.length} Nota Lunas)");
      buffer.writeln("TOTAL OMZET QRIS,,,,,$_omzetQris,(${_qrisTransactions.length} Nota QRIS)");
      buffer.writeln("TOTAL PIUTANG BON (TANGGAL INI),,,,,$_omzetBon,(${_bonTransactions.length} Nota Bon)");
      buffer.writeln("TOTAL PIUTANG BON BERJALAN (MONITORING BON),,,,,$_totalPiutangBonBerjalan,(${_allActiveBonTransactions.length} Nota Bon Aktif)");
      buffer.writeln("TOTAL KESELURUHAN OMZET,,,,,$_totalKeseluruhan,(${_filteredTransactions.length} Total Nota)");

      await file.writeAsString(buffer.toString());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Laporan berhasil disimpan di arsip: $fileName")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Gagal arsip CSV: $e"), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _printAllStruk() async {
    final listToPrint = _displayedTransactions;
    final count = listToPrint.length;
    if (count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Tidak ada transaksi untuk dicetak.")),
      );
      return;
    }

    final targetDesc = _statusFilter == 'ALL_BON'
        ? 'Semua Piutang Bon (${_allActiveBonTransactions.length} Nota)'
        : (_isAllDates
            ? 'Semua Tanggal ($count Nota)'
            : 'tanggal ${DateFormat('dd MMMM yyyy').format(_currentDate)}');

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cetak Semua Struk?'),
        content: Text(
          'Anda akan mencetak $count struk transaksi secara berurutan untuk $targetDesc. '
          'Pastikan printer Bluetooth siap dan kertas cukup.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Cetak $count Struk'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PrintBluetoothAll(allTransactions: listToPrint),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ');

    return Scaffold(
      appBar: AppBar(
        title: Text(!_isAdmin
            ? 'Laporan Hari Ini'
            : (_isAllDates ? 'Laporan (Semua Tanggal)' : 'Laporan Harian')),
        actions: [
          if (_allActiveBonTransactions.isNotEmpty && _isAdmin)
            IconButton(
              icon: const Icon(Icons.pending_actions_rounded, color: AppColors.bon),
              tooltip: 'Monitoring Bon (${_allActiveBonTransactions.length} Nota)',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PelunasanPage()),
                ).then((_) => _fetchTransactions());
              },
            ),
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.calendar_month_outlined),
              tooltip: 'Pilih Tanggal',
              onPressed: _pickArbitraryDate,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchTransactions,
        color: AppColors.primary,
        child: Column(
          children: [
            // HORIZONTAL DATE STRIP ATAU BANNER HARI INI
            if (_isAdmin)
              _buildHorizontalDateStrip()
            else
              Container(
                margin: const EdgeInsets.fromLTRB(AppSpacing.screenMargin, 10, AppSpacing.screenMargin, 0),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.today_rounded, size: 20, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Laporan Hari Ini (Khusus Sales)',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                          Text(
                            DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(DateTime.now()),
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Hari Ini',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Filter Sales Khusus Admin
            if (_isAdmin && _salesUsers.isNotEmpty)
              Container(
                margin: const EdgeInsets.fromLTRB(AppSpacing.screenMargin, 8, AppSpacing.screenMargin, 4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      const Text(
                        'Sales: ',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      ChoiceChip(
                        label: const Text('Semua Sales'),
                        selected: _selectedSalesUserId == null,
                        onSelected: (_) {
                          setState(() {
                            _selectedSalesUserId = null;
                            _applyDateFilter();
                          });
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
                              setState(() {
                                _selectedSalesUserId = u.id;
                                _applyDateFilter();
                              });
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),

            Expanded(
              child: _loading
                  ? const SkeletonList(count: 4)
                  : ListView(
                      padding: const EdgeInsets.all(AppSpacing.screenMargin),
                      children: [
                        // KARTU RINGKASAN OMZET (LUNAS, BON, & TOTAL KESELURUHAN)
                        _buildOmzetBreakdown(currencyFormat),

                        const SizedBox(height: AppSpacing.lg),

                        // ACTION BAR: Export PDF, CSV, Cetak Semua
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _exportPdf,
                                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                                label: const Text('PDF'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppRadius.button),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _exportCsv,
                                icon: const Icon(Icons.archive_outlined, size: 18),
                                label: const Text('CSV'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppRadius.button),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _printAllStruk,
                                icon: const Icon(Icons.print, size: 18),
                                label: const Text('Cetak'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppRadius.button),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: AppSpacing.lg),

                        // FILTER CHIPS: SEMUA / HANYA LUNAS / HANYA BON / SEMUA PIUTANG BON
                        _buildFilterChips(),

                        const SizedBox(height: AppSpacing.md),

                        // DAFTAR TRANSAKSI
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _statusFilter == 'ALL_BON'
                                  ? 'Semua Piutang Bon (${_displayedTransactions.length})'
                                  : 'Transaksi (${_displayedTransactions.length})',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              _statusFilter == 'ALL_BON'
                                  ? 'Monitoring Bon Aktif'
                                  : (_isAllDates
                                      ? 'Semua Tanggal'
                                      : DateFormat('dd MMM yyyy').format(_currentDate)),
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),

                        if (_displayedTransactions.isEmpty)
                          EmptyStateWidget(
                            icon: Icons.event_busy_outlined,
                            title: 'Tidak Ada Transaksi',
                            subtitle: _statusFilter == 'ALL_BON'
                                ? 'Tidak ada transaksi piutang bon yang terdeteksi di sistem.'
                                : _filteredTransactions.isEmpty
                                    ? (_isAllDates
                                        ? 'Tidak ada riwayat transaksi yang tercatat di sistem.'
                                        : 'Tidak ada transaksi yang tercatat pada tanggal ${DateFormat('dd MMMM yyyy').format(_currentDate)}.')
                                    : 'Tidak ada transaksi berstatus ${_statusFilter == 'LUNAS' ? 'LUNAS' : (_statusFilter == 'QRIS' ? 'QRIS' : 'BON')} pada tanggal ini.',
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _displayedTransactions.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: AppSpacing.cardGap),
                            itemBuilder: (context, index) {
                              final trx = _displayedTransactions[index];
                              return TransactionCard(
                                transaction: trx,
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
                              );
                            },
                          ),

                        const SizedBox(height: 40),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOmzetBreakdown(NumberFormat currencyFormat) {
    return Column(
      children: [
        // 1. KARTU TOTAL KESELURUHAN OMSET
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            gradient: AppColors.omzetGradient,
            borderRadius: BorderRadius.circular(AppRadius.card),
            boxShadow: AppShadow.elevated,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isAdmin
                            ? Icons.account_balance_wallet_outlined
                            : Icons.receipt_long_rounded,
                        color: Colors.white70,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isAdmin ? 'Total Keseluruhan Omzet' : 'Rekap Transaksi Hari Ini',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _isAdmin && _isAllDates
                          ? 'Semua Tanggal • ${_filteredTransactions.length} Nota'
                          : '${DateFormat('dd MMM').format(_currentDate)} • ${_filteredTransactions.length} Nota',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: Text(
                  _isAdmin
                      ? currencyFormat.format(_totalKeseluruhan)
                      : '${_filteredTransactions.length} Nota',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _isAdmin
                    ? 'Lunas: ${_lunasTransactions.length} Nota (${currencyFormat.format(_omzetLunas)}) • QRIS: ${_qrisTransactions.length} Nota (${currencyFormat.format(_omzetQris)}) • Bon: ${_bonTransactions.length} Nota (${currencyFormat.format(_omzetBon)})'
                    : 'Lunas: ${_lunasTransactions.length} Nota • QRIS: ${_qrisTransactions.length} Nota • Bon: ${_bonTransactions.length} Nota',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // 2. KARTU RINCIAN 3-PILIHAN: LUNAS (TUNAI), QRIS, & PIUTANG BON
        Row(
          children: [
            // KARTU LUNAS (TUNAI)
            Expanded(
              child: _buildBreakdownItemCard(
                title: 'Lunas',
                countText: '${_lunasTransactions.length} Nota',
                amountText: _isAdmin ? currencyFormat.format(_omzetLunas) : null,
                icon: Icons.check_circle_outline,
                color: AppColors.lunas,
                bgColor: AppColors.lunasBg,
                isSelected: _statusFilter == 'LUNAS',
                onTap: () => setState(() => _statusFilter = _statusFilter == 'LUNAS' ? 'SEMUA' : 'LUNAS'),
              ),
            ),
            const SizedBox(width: 8),
            // KARTU QRIS
            Expanded(
              child: _buildBreakdownItemCard(
                title: 'QRIS',
                countText: '${_qrisTransactions.length} Nota',
                amountText: _isAdmin ? currencyFormat.format(_omzetQris) : null,
                icon: Icons.qr_code_2_rounded,
                color: AppColors.qris,
                bgColor: AppColors.qrisBg,
                isSelected: _statusFilter == 'QRIS',
                onTap: () => setState(() => _statusFilter = _statusFilter == 'QRIS' ? 'SEMUA' : 'QRIS'),
              ),
            ),
            const SizedBox(width: 8),
            // KARTU BON
            Expanded(
              child: _buildBreakdownItemCard(
                title: 'Bon',
                countText: '${_bonTransactions.length} Nota',
                amountText: _isAdmin ? currencyFormat.format(_omzetBon) : null,
                icon: Icons.pending_actions_rounded,
                color: AppColors.bon,
                bgColor: AppColors.bonBg,
                isSelected: _statusFilter == 'BON',
                onTap: () => setState(() => _statusFilter = _statusFilter == 'BON' ? 'SEMUA' : 'BON'),
              ),
            ),
          ],
        ),

        // 3. KARTU MONITORING BON / TOTAL PIUTANG BON BERJALAN (KHUSUS ADMIN)
        if (_isAdmin && _allActiveBonTransactions.isNotEmpty) ...[
          const SizedBox(height: 10),
          InkWell(
            onTap: () {
              setState(() {
                _statusFilter = _statusFilter == 'ALL_BON' ? 'SEMUA' : 'ALL_BON';
              });
            },
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _statusFilter == 'ALL_BON'
                    ? AppColors.bon.withOpacity(0.18)
                    : const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color: _statusFilter == 'ALL_BON'
                      ? AppColors.bon
                      : Colors.amber.shade600.withOpacity(0.6),
                  width: _statusFilter == 'ALL_BON' ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.bon.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.account_balance_rounded,
                      size: 20,
                      color: AppColors.bon,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Total Piutang Bon Berjalan',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.bon,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.bon,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${_allActiveBonTransactions.length} Nota Aktif',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          currencyFormat.format(_totalPiutangBonBerjalan),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: AppColors.bon,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Sesuai data Monitoring Bon. Ketuk untuk lihat daftar nota bon.',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.bon),
                    tooltip: 'Buka Monitoring Bon (Pelunasan)',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PelunasanPage()),
                      ).then((_) => _fetchTransactions());
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBreakdownItemCard({
    required String title,
    required String countText,
    String? amountText,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.18) : bgColor,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: isSelected ? color : color.withOpacity(0.35),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                Icon(icon, size: 15, color: color),
              ],
            ),
            const SizedBox(height: 6),
            if (amountText != null && amountText.isNotEmpty) ...[
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  amountText,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                countText,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ] else ...[
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  countText,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Nota Terbuat',
                style: TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          FilterChip(
            label: Text('Semua (${_filteredTransactions.length})'),
            selected: _statusFilter == 'SEMUA',
            onSelected: (_) => setState(() => _statusFilter = 'SEMUA'),
            selectedColor: AppColors.primary,
            labelStyle: TextStyle(
              color: _statusFilter == 'SEMUA' ? Colors.white : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
            ),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: Text('Hanya Lunas (${_lunasTransactions.length})'),
            selected: _statusFilter == 'LUNAS',
            onSelected: (_) => setState(() => _statusFilter = 'LUNAS'),
            selectedColor: AppColors.lunas,
            labelStyle: TextStyle(
              color: _statusFilter == 'LUNAS' ? Colors.white : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
            ),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: Text('QRIS (${_qrisTransactions.length})'),
            selected: _statusFilter == 'QRIS',
            onSelected: (_) => setState(() => _statusFilter = 'QRIS'),
            selectedColor: AppColors.qris,
            labelStyle: TextStyle(
              color: _statusFilter == 'QRIS' ? Colors.white : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
            ),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: Text(_isAllDates ? 'Nota Bon (${_bonTransactions.length})' : 'Bon Tanggal Ini (${_bonTransactions.length})'),
            selected: _statusFilter == 'BON',
            onSelected: (_) => setState(() => _statusFilter = 'BON'),
            selectedColor: AppColors.bon,
            labelStyle: TextStyle(
              color: _statusFilter == 'BON' ? Colors.white : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
            ),
          ),
          if (_allActiveBonTransactions.isNotEmpty) ...[
            const SizedBox(width: 8),
            FilterChip(
              avatar: const Icon(Icons.pending_actions, size: 14, color: AppColors.bon),
              label: Text('Semua Piutang Bon (${_allActiveBonTransactions.length})'),
              selected: _statusFilter == 'ALL_BON',
              onSelected: (_) => setState(() => _statusFilter = 'ALL_BON'),
              selectedColor: AppColors.bon.withOpacity(0.25),
              side: BorderSide(
                color: _statusFilter == 'ALL_BON' ? AppColors.bon : AppColors.bon.withOpacity(0.4),
                width: _statusFilter == 'ALL_BON' ? 1.5 : 1,
              ),
              labelStyle: const TextStyle(
                color: AppColors.bon,
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHorizontalDateStrip() {
    final now = DateTime.now();
    // 14 hari ke belakang sampai hari ini
    final dates = List.generate(15, (index) {
      return now.subtract(Duration(days: 14 - index));
    });

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: SizedBox(
        height: 68,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMargin),
          itemCount: dates.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            if (index == 0) {
              final isSelected = _isAllDates;
              return InkWell(
                onTap: () {
                  setState(() {
                    _isAllDates = true;
                    _statusFilter = 'SEMUA';
                    _applyDateFilter();
                  });
                },
                borderRadius: BorderRadius.circular(14),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 64,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.surfaceBorder,
                      width: 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.calendar_view_month_rounded,
                        size: 16,
                        color: isSelected
                            ? Colors.white.withOpacity(0.9)
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Semua',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: isSelected ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Tanggal',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w500,
                          color: isSelected
                              ? Colors.white.withOpacity(0.85)
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final date = dates[index - 1];
            final isSelected = !_isAllDates &&
                DateFormat('yyyy-MM-dd').format(date) ==
                    DateFormat('yyyy-MM-dd').format(_currentDate);
            final isToday = DateFormat('yyyy-MM-dd').format(date) ==
                DateFormat('yyyy-MM-dd').format(now);

            return InkWell(
              onTap: () => _onDateSelected(date),
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 54,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : isToday
                            ? AppColors.primary.withValues(alpha: 0.5)
                            : AppColors.surfaceBorder,
                    width: isToday && !isSelected ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      DateFormat('EEE').format(date),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.85)
                            : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('d').format(date),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: isSelected ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
