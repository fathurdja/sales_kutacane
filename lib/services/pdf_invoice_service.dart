import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/theme/app_theme.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

class PdfInvoiceService {
  static Uint8List? _cachedStampBytes;

  /// Format angka Rupiah murni tanpa dependensi locale intl (aman dari LocaleDataException)
  static String formatRupiah(num number) {
    final parts = number.round().toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
    return 'Rp $parts';
  }

  /// Format tanggal Indonesia murni (misal: 24 Oktober 2026, 21:55 WIB)
  static String formatTanggalIndo(DateTime dt) {
    const bulan = [
      'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
    ];
    final day = dt.day.toString().padLeft(2, '0');
    final month = bulan[dt.month - 1];
    final year = dt.year;
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$day $month $year, $hour:$minute WIB';
  }

  /// Format tanggal ringkas (misal: 24-10-2026 21:55 WIB)
  static String formatTanggalRingkas(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d-$m-$y $h:$min WIB';
  }

  /// Format timestamp aman untuk nama file (misal: 20261024_215500)
  static String formatFileTimestamp(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y$m${d}_$h$min$s';
  }

  /// Memuat berkas stempel resmi sekali saja ke memori untuk performa tinggi
  static Future<Uint8List?> _loadStampBytes() async {
    if (_cachedStampBytes != null) return _cachedStampBytes;
    try {
      final ByteData bytes = await rootBundle.load('assets/images/stempelfixxxxx.png');
      _cachedStampBytes = bytes.buffer.asUint8List();
    } catch (_) {
      try {
        final f = File('assets/images/stempelfixxxxx.png');
        if (await f.exists()) {
          _cachedStampBytes = await f.readAsBytes();
        }
      } catch (_) {}
    }
    return _cachedStampBytes;
  }

  /// Membuat dokumen PDF dengan tata letak profesional & multipage aman
  static Future<pw.Document> generateDocument(Transaction transaction) async {
    final pdf = pw.Document();

    final stampBytes = await _loadStampBytes();
    pw.MemoryImage? stampImage;
    if (stampBytes != null) {
      try {
        stampImage = pw.MemoryImage(stampBytes);
      } catch (e) {
        debugPrint("Gagal decode stempel: $e");
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // Header Toko
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Kencana Cahaya Amanah',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'JL. Kenangan No. 183 Gorontalo / Kutacane',
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                    ),
                    pw.Text(
                      'Layanan Penjualan & Distribusi Air Mineral',
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                    ),
                  ],
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: pw.BoxDecoration(
                    color: transaction.status == 'LUNAS'
                        ? PdfColors.green50
                        : PdfColors.orange50,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                    border: pw.Border.all(
                      color: transaction.status == 'LUNAS'
                          ? PdfColors.green700
                          : PdfColors.orange700,
                      width: 1,
                    ),
                  ),
                  child: pw.Text(
                    transaction.status,
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: transaction.status == 'LUNAS'
                          ? PdfColors.green800
                          : PdfColors.orange800,
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Divider(thickness: 1, color: PdfColors.grey400),
            pw.SizedBox(height: 10),

            // Metadata Transaksi
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('FAKTUR PENJUALAN', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 4),
                      pw.Text('No. Nota: ${transaction.id_transaksi}', style: const pw.TextStyle(fontSize: 10)),
                      pw.Text(
                        'Tanggal : ${formatTanggalIndo(transaction.date)}',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('TUJUAN PENGIRIMAN', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 4),
                      pw.Text('Konsumen: ${transaction.customerName}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Alamat  : ${transaction.alamat}', style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 16),

            // Tabel Daftar Barang
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(1),
                1: pw.FlexColumnWidth(4.5),
                2: pw.FlexColumnWidth(1.5),
                3: pw.FlexColumnWidth(1.5),
                4: pw.FlexColumnWidth(2.5),
                5: pw.FlexColumnWidth(2.5),
              },
              children: [
                // Header Tabel
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    _cell('No', isHeader: true, align: pw.TextAlign.center),
                    _cell('Nama Barang', isHeader: true),
                    _cell('Qty', isHeader: true, align: pw.TextAlign.center),
                    _cell('Bonus', isHeader: true, align: pw.TextAlign.center),
                    _cell('Harga Satuan', isHeader: true, align: pw.TextAlign.right),
                    _cell('Subtotal', isHeader: true, align: pw.TextAlign.right),
                  ],
                ),
                // Baris Item
                ...List.generate(transaction.items.length, (index) {
                  final item = transaction.items[index];
                  final isEven = index % 2 == 0;
                  return pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: isEven ? PdfColors.white : PdfColors.grey50,
                    ),
                    children: [
                      _cell('${index + 1}', align: pw.TextAlign.center),
                      _cell(item.name),
                      _cell('${item.quantity}', align: pw.TextAlign.center),
                      _cell('${item.bonus}', align: pw.TextAlign.center),
                      _cell(formatRupiah(item.price), align: pw.TextAlign.right),
                      _cell(formatRupiah(item.subtotal), align: pw.TextAlign.right),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 14),

            // Ringkasan Pembayaran & Stempel
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                // Catatan / Tanda Terima
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Tanda Terima / Pengirim,', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                    pw.SizedBox(height: 40),
                    pw.Text('(____________________)', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      '* Barang yang sudah dibeli telah dicek & diterima dengan baik.',
                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                    ),
                  ],
                ),
                // Total & Stempel
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.grey100,
                        borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
                      ),
                      child: pw.Row(
                        children: [
                          pw.Text(
                            'TOTAL : ',
                            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                          ),
                          pw.Text(
                            formatRupiah(transaction.total),
                            style: pw.TextStyle(
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.blue800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (stampImage != null) ...[
                      pw.SizedBox(height: 6),
                      pw.Image(
                        stampImage,
                        width: 85,
                        height: 85,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ];
        },
      ),
    );

    return pdf;
  }

  static pw.Widget _cell(
    String text, {
    bool isHeader = false,
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: isHeader ? 9 : 8.5,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: isHeader ? PdfColors.black : PdfColors.grey900,
        ),
      ),
    );
  }

  /// Membuat berkas PDF dan mengembalikan File lokal
  static Future<File> getPdfFile(Transaction transaction) async {
    final pdf = await generateDocument(transaction);
    final cleanCustomer = transaction.customerName
        .trim()
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'[^\w\.-]'), '');
    final dateStr = formatFileTimestamp(transaction.date);
    final fileName = 'Nota_${cleanCustomer.isEmpty ? "Pelanggan" : cleanCustomer}_$dateStr.pdf';

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    final bytes = await pdf.save();
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Membagikan PDF via WhatsApp / Aplikasi Lain dengan penanganan loading aman
  static Future<void> sharePdf({
    required BuildContext context,
    required Transaction transaction,
    VoidCallback? onPdfGenerated,
  }) async {
    try {
      final file = await getPdfFile(transaction);
      // Callback langsung dipanggil begitu file selesai digenerate
      // agar UI tidak menggantung dalam status loading!
      onPdfGenerated?.call();

      final cleanCustomer = transaction.customerName.trim();
      final messageText =
          '📄 *NOTA TRANSAKSI - Kencana Cahaya Amanah*\n\n'
          '• No. Nota  : ${transaction.id_transaksi}\n'
          '• Konsumen  : $cleanCustomer\n'
          '• Alamat    : ${transaction.alamat}\n'
          '• Tanggal   : ${formatTanggalRingkas(transaction.date)}\n'
          '• Status    : ${transaction.status}\n'
          '• Total     : ${formatRupiah(transaction.total)}\n\n'
          'Terima kasih atas kepercayaan Anda bermitra dengan Kencana Cahaya Amanah.';

      final fileName = file.path.split(Platform.pathSeparator).last;
      final xFile = XFile(
        file.path,
        mimeType: 'application/pdf',
        name: fileName,
      );

      try {
        await Share.shareXFiles(
          [xFile],
          text: messageText,
          subject: 'Nota Transaksi $cleanCustomer',
        );
      } catch (shareErr) {
        debugPrint("ShareXFiles gagal ($shareErr), menggunakan fallback Printing.sharePdf...");
        final bytes = await file.readAsBytes();
        await Printing.sharePdf(
          bytes: bytes,
          filename: fileName,
        );
      }
    } catch (e) {
      debugPrint("Error generate / share PDF: $e");
      onPdfGenerated?.call();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal membuat atau membagikan PDF: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Pratinjau langsung di layar smartphone kasir (Bisa Zoom, Print, & Unduh)
  static Future<void> previewPdf({
    required BuildContext context,
    required Transaction transaction,
  }) async {
    try {
      final pdf = await generateDocument(transaction);
      final cleanCustomer = transaction.customerName
          .trim()
          .replaceAll(' ', '_')
          .replaceAll(RegExp(r'[^\w\.-]'), '');
      final fileName = 'Nota_${cleanCustomer.isEmpty ? "Pelanggan" : cleanCustomer}.pdf';

      await Printing.layoutPdf(
        name: fileName,
        onLayout: (PdfPageFormat format) async => pdf.save(),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal membuka preview PDF: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}
