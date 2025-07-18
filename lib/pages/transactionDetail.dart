import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/models/transaction.dart';

import 'package:kasir_kutacane/services/printerBluetooth.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;

class TransactionDetailPage extends StatelessWidget {
  final Transaction transaction;

  const TransactionDetailPage({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
    );

    return Scaffold(
      appBar: AppBar(title: Text('Detail Transaksi: ${transaction.id}')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: const [
                  Text(
                    'Kencana Cahaya Amanah',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                  Text('JL. Kenangan No. 183 Gorontalo'),
                  SizedBox(height: 20),
                ],
              ),
            ),
            Text('ID Transaksi: ${transaction.id}'),
            Text('Nama Konsumen: ${transaction.customerName}'),
            Text('Alamat: ${transaction.alamat}'),
            Text(
              'Tanggal: ${DateFormat('dd-MM-yyyy').format(transaction.date)}',
            ),
            const SizedBox(height: 20),
            const Text(
              'Daftar Barang:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            ...transaction.items.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text('${item.name}')),
                    Text(
                      '${item.quantity} x ${currencyFormat.format(item.price)}',
                    ),
                    Text(currencyFormat.format(item.subtotal)),
                  ],
                ),
              ),
            ),
            const Divider(thickness: 1.0),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Total: ${currencyFormat.format(transaction.total)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.print),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (context) => Printbluetooth(
                                orderItems:
                                    transaction.items.map((item) {
                                      return {
                                        'product': {
                                          'name': item.name,
                                          'harga': item.price,
                                        },
                                        'quantity': item.quantity,
                                      };
                                    }).toList(),
                                paymentMethod: 'Tunai',
                                total: transaction.total.toInt(),
                                customerName: transaction.customerName,
                                alamat: transaction.alamat,
                                idTransaksi: transaction.id,
                                date: transaction.date,
                              ),
                        ),
                      );
                    },

                    label: const Text('Cetak'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf),
                    onPressed: () async {
                      final pdf = await generatePdf(transaction);
                      await Printing.layoutPdf(
                        onLayout: (PdfPageFormat format) async => pdf.save(),
                      );
                    },
                    label: const Text('Unduh PDF'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<pw.Document> generatePdf(Transaction transaction) async {
    final pdf = pw.Document();
    final currencyFormat = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
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
                'Kencana Cahaya Amanah',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text('JL. Kenangan No. 183 Gorontalo'),
              pw.SizedBox(height: 20),
              pw.Text('ID Transaksi: ${transaction.id}'),
              pw.Text('Nama Konsumen: ${transaction.customerName}'),
              pw.Text('Alamat: ${transaction.alamat}'),
              pw.Text(
                'Tanggal: ${DateFormat('dd-MM-yyyy HH:mm').format(transaction.date)}',
              ),
              pw.SizedBox(height: 20),
              pw.Text(
                'Daftar Barang',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              pw.SizedBox(height: 8),

              /// Tabel barang
              pw.Column(
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(vertical: 4),
                    child: pw.Row(
                      children: [
                        pw.Expanded(
                          flex: 4,
                          child: pw.Text(
                            'Nama Barang',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Text(
                            'Qty',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Expanded(
                          flex: 3,
                          child: pw.Text(
                            'Harga',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Expanded(
                          flex: 3,
                          child: pw.Text(
                            'Subtotal',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.Divider(),

                  /// Rows items
                  ...transaction.items.map(
                    (item) => pw.Container(
                      padding: const pw.EdgeInsets.symmetric(vertical: 2),
                      child: pw.Row(
                        children: [
                          pw.Expanded(flex: 4, child: pw.Text(item.name)),
                          pw.Expanded(
                            flex: 2,
                            child: pw.Text('${item.quantity}'),
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
                  ),
                ],
              ),

              pw.Divider(thickness: 1),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  'TOTAL: ${currencyFormat.format(transaction.total)}',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 30),
              pw.Align(
                alignment: pw.Alignment.center,
                child: pw.Text(
                  'Terima Kasih telah berbelanja!',
                  style: pw.TextStyle(fontStyle: pw.FontStyle.italic),
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
