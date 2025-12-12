import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/models/transaction.dart';

import 'package:kasir_kutacane/services/printerBluetooth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';

import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

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
                    Text('Qty: ${item.quantity} Bonus: ${item.bonus} |  '),
                    Text(currencyFormat.format(item.subtotal)),
                  ],
                ),
              ),
            ),
            const Divider(thickness: 1.0),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Pembayaran: ${transaction.status}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
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
                                        'items': {
                                          'name': item.name,
                                          'harga': item.price,
                                          'bonus': item.bonus,
                                        },
                                        'quantity': item.quantity,
                                      };
                                    }).toList(),
                                paymentMethod: 'Tunai',
                                total: transaction.total.toInt(),
                                customerName: transaction.customerName,
                                alamat: transaction.alamat,
                                idTransaksi: transaction.id_transaksi,
                                date: transaction.date,
                                status: transaction.status,
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
                      final String fileName =
                          '${transaction.customerName}_${DateFormat('yyyyMMdd').format(transaction.date)}.pdf'
                              .replaceAll(' ', '_'); // Hindari spasi di nama file

                      // Simpan ke temporary directory
                      final output = await getTemporaryDirectory();
                      final file = File('${output.path}/$fileName');
                      await file.writeAsBytes(await pdf.save());

                      // Share ke WhatsApp (via share sheet)
                      await Share.shareXFiles(
                        [XFile(file.path)],
                        text:
                            'Berikut struk transaksi untuk ${transaction.customerName}',
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

   
    final ByteData bytes = await rootBundle.load(
      'assets/images/stempelfixxxxx.png',
    );
    final Uint8List byteList = bytes.buffer.asUint8List();

    final image = pw.MemoryImage(byteList);

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
                          flex: 2,
                          child: pw.Text(
                            'Bonus',
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
                          pw.Expanded(flex: 2, child: pw.Text('${item.bonus}')),
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
                  'PEMBAYARAN: ${transaction.status}',
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
               pw.SizedBox(height: 15),
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
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Image(image, width: 100),
              ),
              pw.SizedBox(height: 15),
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
