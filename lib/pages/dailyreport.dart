import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/pages/transactionDetail.dart';
import 'package:kasir_kutacane/services/printAll.dart';
import 'package:kasir_kutacane/theme/app_theme.dart';
import 'package:kasir_kutacane/widgets/app_widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

class DailyReportDetailPage extends StatefulWidget {
  final DateTime selectedDate;

  const DailyReportDetailPage({super.key, required this.selectedDate});

  @override
  State<DailyReportDetailPage> createState() => _DailyReportDetailPageState();
}

class _DailyReportDetailPageState extends State<DailyReportDetailPage> {
  late DateTime _currentDate;
  bool _loading = true;
  List<Transaction> _allTransactions = [];
  List<Transaction> _filteredTransactions = [];

  @override
  void initState() {
    super.initState();
    _currentDate = widget.selectedDate;
    _fetchTransactions();
  }

  Future<void> _fetchTransactions() async {
    setState(() => _loading = true);
    try {
      final url = Uri.parse("https://laravel.fathurrzqn8n.web.id/api/transaksi");
      final response = await http
          .get(url, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final loaded = data
            .map<Transaction>(
              (json) => Transaction.fromJson(json as Map<String, dynamic>),
            )
            .toList();

        if (!mounted) return;
        setState(() {
          _allTransactions = loaded;
          _applyDateFilter();
          _loading = false;
        });
      } else {
        throw Exception("Server error (${response.statusCode})");
      }
    } catch (e) {
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

  void _applyDateFilter() {
    final dateStr = DateFormat('yyyy-MM-dd').format(_currentDate);
    _filteredTransactions = _allTransactions.where((trx) {
      return DateFormat('yyyy-MM-dd').format(trx.date) == dateStr;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  void _onDateSelected(DateTime date) {
    setState(() {
      _currentDate = date;
      _applyDateFilter();
    });
  }

  Future<void> _pickArbitraryDate() async {
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

  double get _totalHarian {
    return _filteredTransactions.fold(0.0, (sum, trx) => sum + trx.total);
  }

  int get _jumlahBon {
    return _filteredTransactions.where((t) => t.status.toUpperCase() == 'BON').length;
  }

  Future<pw.Document> generateDailyReport(
    List<Transaction> transactions,
    DateTime date,
  ) async {
    final pdf = pw.Document();
    final currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ');

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
                "LAPORAN HARIAN TRANSAKSI",
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text("Kencana Cahaya Amanah"),
              pw.Text("Tanggal: ${DateFormat('dd MMMM yyyy').format(date)}"),
              pw.Divider(thickness: 1),
              pw.SizedBox(height: 8),
            ],
          );
        },
        build: (context) {
          return [
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
                          "${trx.status} - ${currencyFormat.format(trx.total)}",
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
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
                "TOTAL OMZET: ${currencyFormat.format(totalDaily)}",
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
    if (_filteredTransactions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Tidak ada transaksi untuk diekspor")),
      );
      return;
    }

    try {
      final pdf = await generateDailyReport(_filteredTransactions, _currentDate);
      final fileName = 'laporan_${DateFormat('yyyyMMdd').format(_currentDate)}.pdf';
      final output = await getTemporaryDirectory();
      final file = File('${output.path}/$fileName');
      final bytes = await pdf.save();
      await file.writeAsBytes(bytes);

      try {
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/pdf', name: fileName)],
          text: 'Laporan harian tanggal ${DateFormat('dd-MM-yyyy').format(_currentDate)}',
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
    if (_filteredTransactions.isEmpty) {
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

      final fileName = "laporan_${DateFormat('yyyyMMdd').format(_currentDate)}.csv";
      final file = File("${folder.path}/$fileName");

      final buffer = StringBuffer();
      buffer.writeln("Tanggal,ID Transaksi,Konsumen,Alamat,Status,Total Nota,Barang,Qty,Bonus,Harga,Subtotal");

      for (var trx in _filteredTransactions) {
        final trxDate = DateFormat('yyyy-MM-dd HH:mm').format(trx.date);
        for (var item in trx.items) {
          buffer.writeln(
            '"$trxDate","${trx.id_transaksi}","${trx.customerName}","${trx.alamat}","${trx.status}",${trx.total},"${item.name}",${item.quantity},${item.bonus},${item.price},${item.subtotal}',
          );
        }
      }
      buffer.writeln("TOTAL OMZET,,,,,$_totalHarian");

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
    final count = _filteredTransactions.length;
    if (count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Tidak ada transaksi untuk dicetak.")),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cetak Semua Struk?'),
        content: Text(
          'Anda akan mencetak $count struk transaksi secara berurutan untuk tanggal '
          '${DateFormat('dd MMMM yyyy').format(_currentDate)}. Pastikan printer Bluetooth siap dan kertas cukup.',
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
        builder: (_) => PrintBluetoothAll(allTransactions: _filteredTransactions),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan Harian'),
        actions: [
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
            // HORIZONTAL DATE STRIP
            _buildHorizontalDateStrip(),

            Expanded(
              child: _loading
                  ? const SkeletonList(count: 4)
                  : ListView(
                      padding: const EdgeInsets.all(AppSpacing.screenMargin),
                      children: [
                        // KARTU OMZET HARI INI
                        OmzetSummaryCard(
                          totalOmzet: _totalHarian,
                          jumlahNota: _filteredTransactions.length,
                          jumlahBon: _jumlahBon,
                          formattedOmzet: currencyFormat.format(_totalHarian),
                        ),

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

                        const SizedBox(height: AppSpacing.xl),

                        // DAFTAR TRANSAKSI
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Transaksi (${_filteredTransactions.length})',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              DateFormat('dd MMM yyyy').format(_currentDate),
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),

                        if (_filteredTransactions.isEmpty)
                          EmptyStateWidget(
                            icon: Icons.event_busy_outlined,
                            title: 'Tidak Ada Transaksi',
                            subtitle:
                                'Tidak ada transaksi yang tercatat pada tanggal ${DateFormat('dd MMMM yyyy').format(_currentDate)}.',
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _filteredTransactions.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: AppSpacing.cardGap),
                            itemBuilder: (context, index) {
                              final trx = _filteredTransactions[index];
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
          itemCount: dates.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final date = dates[index];
            final isSelected = DateFormat('yyyy-MM-dd').format(date) ==
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
