import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/services/pdf_invoice_service.dart';
import 'package:kasir_kutacane/services/printerBluetooth.dart';
import 'package:kasir_kutacane/theme/app_theme.dart';
import 'package:kasir_kutacane/widgets/app_widgets.dart';

class TransactionSuccessDialog extends StatelessWidget {
  final Transaction transaction;

  const TransactionSuccessDialog({
    super.key,
    required this.transaction,
  });

  static Future<void> show(BuildContext context, Transaction transaction) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => TransactionSuccessDialog(transaction: transaction),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    final isOffline = transaction.isOffline;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Icon Sukses
              Center(
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: isOffline ? Colors.amber.shade100 : AppColors.lunasBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isOffline
                        ? Icons.cloud_off_rounded
                        : Icons.check_circle_rounded,
                    color: isOffline ? Colors.amber.shade900 : AppColors.lunas,
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Judul Konfirmasi
              Center(
                child: Text(
                  isOffline
                      ? 'Nota Disimpan Offline'
                      : 'Transaksi Berhasil Disimpan!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 6),

              // Badge Info Auto-Print Struk
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6FCF5),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: const Color(0xFF20C997).withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.print_rounded, size: 14, color: Color(0xFF0CA678)),
                      SizedBox(width: 6),
                      Text(
                        'Struk otomatis dikirim ke printer Bluetooth',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0CA678),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Info Nota & Pelanggan
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.bgSecondary,
                  borderRadius: BorderRadius.circular(AppRadius.input),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          transaction.id_transaksi,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        StatusChip(status: transaction.status),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.person_outline,
                            size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            transaction.customerName,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (transaction.alamat.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.location_on_outlined,
                              size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              transaction.alamat,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.access_time,
                            size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Text(
                          DateFormat('dd MMM yyyy, HH:mm').format(transaction.date),
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Rincian Item Barang
              const Text(
                'Rincian Barang',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),

              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 140),
                child: SingleChildScrollView(
                  child: Column(
                    children: transaction.items.map((item) {
                      final itemSubtotal = item.subtotal;
                      final bonusText =
                          item.bonus > 0 ? ' (+${item.bonus} Bonus)' : '';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    '${item.quantity}x @ ${currencyFormat.format(item.price)}$bonusText',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              currencyFormat.format(itemSubtotal),
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const Divider(height: 16),

              // Total Pembayaran
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total Pembayaran',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    currencyFormat.format(transaction.total),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Tombol Aksi: Cetak Ulang & Kirim PDF
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.button),
                        ),
                      ),
                      icon: const Icon(Icons.print, size: 16),
                      label: const Text(
                        'Cetak Struk',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => Printbluetooth.fromTransaction(
                              transaction: transaction,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        side: const BorderSide(color: AppColors.primary),
                        foregroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.button),
                        ),
                      ),
                      icon: const Icon(Icons.share, size: 16),
                      label: const Text(
                        'Kirim PDF',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                      onPressed: () async {
                        await PdfInvoiceService.sharePdf(
                          context: context,
                          transaction: transaction,
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Tombol Tutup / Selesai
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    foregroundColor: AppColors.textSecondary,
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Selesai & Tutup',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

