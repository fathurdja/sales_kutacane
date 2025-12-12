import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/services/printAll.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

class DailyReportDetailPage extends StatefulWidget {
  final DateTime selectedDate;

  const DailyReportDetailPage({super.key, required this.selectedDate});

  @override
  State<DailyReportDetailPage> createState() => _DailyReportDetailPageState();
}

class _DailyReportDetailPageState extends State<DailyReportDetailPage> {
  bool _loading = true;
  List<Transaction> _filteredTransactions = [];

  @override
  void initState() {
    super.initState();
    _fetchTransactions();
  }

  Future<void> _fetchTransactions() async {
    try {
      final url = Uri.parse(
        "http://6873b63ec75558e273550195.mockapi.io/transaksi",
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final allTransactions =
            data.map((json) => Transaction.fromJson(json)).toList();

        final dateStr = DateFormat('yyyy-MM-dd').format(widget.selectedDate);

        setState(() {
          _filteredTransactions =
              allTransactions.where((trx) {
                return DateFormat('yyyy-MM-dd').format(trx.date) == dateStr;
              }).toList();
          _loading = false;
        });
      } else {
        throw Exception("Gagal fetch transaksi");
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  double get _totalHarian {
    return _filteredTransactions.fold(0.0, (sum, trx) => sum + trx.total);
  }

  Future<pw.Document> generateDailyReport(
    List<Transaction> transactions,
    DateTime date,
  ) async {
    final pdf = pw.Document();
    final currencyFormat = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
    );

    final dailyTransactions =
        transactions
            .where(
              (trx) =>
                  trx.date.year == date.year &&
                  trx.date.month == date.month &&
                  trx.date.day == date.day,
            )
            .toList();

    final totalDaily = dailyTransactions.fold(
      0.0,
      (sum, trx) => sum + trx.total,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                "Laporan Harian",
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text("Tanggal: ${DateFormat('dd-MM-yyyy').format(date)}"),
              pw.SizedBox(height: 20),

              // Header transaksi
              pw.Row(
                children: [
                  pw.Expanded(
                    flex: 3,
                    child: pw.Text(
                      "ID Transaksi",
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                  pw.Expanded(
                    flex: 4,
                    child: pw.Text(
                      "Nama Konsumen",
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                  pw.Expanded(
                    flex: 3,
                    child: pw.Text(
                      "Total",
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                  pw.Expanded(
                    flex: 3,
                    child: pw.Text(
                      "Status",
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                ],
              ),
              pw.Divider(),

              // Isi transaksi + item
              ...dailyTransactions.map(
                (trx) => pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Info transaksi
                    pw.Row(
                      children: [
                        pw.Expanded(flex: 3, child: pw.Text(trx.id_transaksi)),
                        pw.Expanded(flex: 4, child: pw.Text(trx.customerName)),
                        pw.Expanded(
                          flex: 3,
                          child: pw.Text(currencyFormat.format(trx.total)),
                        ),
                        pw.Expanded(flex: 3, child: pw.Text(trx.status)),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    // Header item
                    pw.Row(
                      children: [
                        pw.Expanded(
                          flex: 5,
                          child: pw.Text(
                            "Item",
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Text(
                            "Qty",
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Expanded(
                          flex: 3,
                          child: pw.Text(
                            "Harga",
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Expanded(
                          flex: 3,
                          child: pw.Text(
                            "Subtotal",
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    ...trx.items.map(
                      (item) => pw.Row(
                        children: [
                          pw.Expanded(flex: 5, child: pw.Text(item.name)),
                          pw.Expanded(
                            flex: 2,
                            child: pw.Text("${item.quantity}"),
                          ),
                          pw.Expanded(
                            flex: 3,
                            child: pw.Text(currencyFormat.format(item.price)),
                          ),
                          pw.Expanded(
                            flex: 3,
                            child: pw.Text(
                              currencyFormat.format(item.subtotal),
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.Divider(),
                  ],
                ),
              ),
              pw.SizedBox(height: 15),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  "TOTAL HARIAN: ${currencyFormat.format(totalDaily)}",
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  Future<void> _exportCsv() async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory("${dir.path}/arsip");
    if (!(await folder.exists())) {
      await folder.create(recursive: true);
    }

    final fileName =
        "laporan_harian_${DateFormat('yyyyMMdd').format(widget.selectedDate)}.csv";
    final file = File("${folder.path}/$fileName");

    final buffer = StringBuffer();
    // Tambahkan kolom Tanggal
    buffer.writeln(
      "Tanggal,ID,Customer,Alamat,Status,Total,Item,Qty,Price,Subtotal",
    );

    for (var trx in _filteredTransactions) {
      final trxDate = DateFormat('yyyy-MM-dd').format(trx.date);
      if (trx.items.isEmpty) {
        buffer.writeln(
          "$trxDate,${trx.id_transaksi},${trx.customerName},${trx.alamat},${trx.status},${trx.total},,,,",
        );
      } else {
        for (var item in trx.items) {
          buffer.writeln(
            "$trxDate,${trx.id_transaksi},${trx.customerName},${trx.alamat},${trx.status},${trx.total},${item.name},${item.quantity},${item.price},${item.subtotal}",
          );
        }
      }
    }
    buffer.writeln("TOTAL,,,,$_totalHarian");

    await file.writeAsString(buffer.toString());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Laporan berhasil disimpan di arsip: $fileName"),
        ),
      );
    }
  }

  void _printStruk() {
    if (_filteredTransactions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Tidak ada transaksi untuk dicetak.")),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) =>
                PrintBluetoothAll(allTransactions: _filteredTransactions),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Laporan Harian - ${DateFormat('dd MMM yyyy').format(widget.selectedDate)}",
        ),
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _filteredTransactions.isEmpty
              ? const Center(
                child: Text("Tidak ada transaksi pada tanggal ini"),
              )
              : Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      itemCount: _filteredTransactions.length,
                      itemBuilder: (context, index) {
                        final trx = _filteredTransactions[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            vertical: 6,
                            horizontal: 12,
                          ),
                          child: ListTile(
                            leading: const Icon(Icons.receipt_long),
                            title: Text("${trx.customerName} (${trx.status})"),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Alamat: ${trx.alamat}"),
                                Text("ID: ${trx.id_transaksi}"),
                                ...trx.items.map(
                                  (item) => Text(
                                    "• ${item.name} x${item.quantity} = ${currencyFormat.format(item.subtotal)}",
                                  ),
                                ),
                              ],
                            ),
                            trailing: Text(currencyFormat.format(trx.total)),
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            "TOTAL HARIAN: ${currencyFormat.format(_totalHarian)}",
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    final pdf = await generateDailyReport(
                                      _filteredTransactions,
                                      widget.selectedDate,
                                    );

                                    final String fileName =
                                        'transaksi_${DateFormat('yyyyMMdd').format(widget.selectedDate)}.pdf';

                                    final output =
                                        await getTemporaryDirectory();
                                    final file = File(
                                      '${output.path}/$fileName',
                                    );
                                    await file.writeAsBytes(await pdf.save());

                                    await Share.shareXFiles(
                                      [XFile(file.path)],
                                      text:
                                          'Berikut laporan harian tanggal ${DateFormat('dd-MM-yyyy').format(widget.selectedDate)}',
                                    );
                                  },
                                  icon: const Icon(Icons.picture_as_pdf),
                                  label: const Text("Export PDF"),
                                ),
                                ElevatedButton.icon(
                                  onPressed: _printStruk,
                                  icon: const Icon(Icons.print),
                                  label: const Text("Print Struk"),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: _exportCsv,
                              icon: const Icon(Icons.archive),
                              label: const Text("Arsipkan"),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
    );
  }
}
