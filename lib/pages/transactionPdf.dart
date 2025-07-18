import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class TransactionPdfPage extends StatelessWidget {
  final Transaction transaction;

  const TransactionPdfPage({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Unduh PDF Transaksi')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Preview & Unduh PDF'),
            onPressed: () async {
              final pdf = await generatePdf(transaction);
              await Printing.layoutPdf(
                onLayout: (PdfPageFormat format) async => pdf.save(),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<pw.Document> generatePdf(Transaction transaction) async {
    final pdf = pw.Document();
    final currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      'Kencana Cahaya Amanah',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    pw.Text('JL. Kenangan No. 183 Gorontalo'),
                    pw.SizedBox(height: 10),
                  ],
                ),
              ),
              pw.Text('ID Transaksi: ${transaction.id}'),
              pw.Text('Nama Konsumen: ${transaction.customerName}'),
              pw.Text('Alamat: ${transaction.alamat}'),
              pw.Text(
                'Tanggal: ${DateFormat('dd-MM-yyyy').format(transaction.date)}',
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                'Daftar Barang:',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              ...transaction.items.map(
                (item) => pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(child: pw.Text(item.name)),
                    pw.Text('${item.quantity} x ${currencyFormat.format(item.price)}'),
                    pw.Text(currencyFormat.format(item.subtotal)),
                  ],
                ),
              ),
              pw.Divider(),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  'TOTAL: ${currencyFormat.format(transaction.total)}',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Center(
                child: pw.Text(
                  'Terima Kasih!',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf;
  }
}
