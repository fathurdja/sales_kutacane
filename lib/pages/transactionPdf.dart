import 'package:flutter/material.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/services/pdf_invoice_service.dart';

class TransactionPdfPage extends StatelessWidget {
  final Transaction transaction;

  const TransactionPdfPage({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Unduh PDF Transaksi')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Preview & Unduh PDF'),
            onPressed: () async {
              await PdfInvoiceService.previewPdf(
                context: context,
                transaction: transaction,
              );
            },
          ),
        ),
      ),
    );
  }
}
