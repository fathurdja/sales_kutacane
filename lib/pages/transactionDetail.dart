import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/config/api_config.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/pages/transactionInput.dart';
import 'package:kasir_kutacane/services/auth_service.dart';
import 'package:kasir_kutacane/services/offline_sync_service.dart';
import 'package:kasir_kutacane/services/pelunasan_history_service.dart';
import 'package:kasir_kutacane/services/pdf_invoice_service.dart';
import 'package:kasir_kutacane/services/printerBluetooth.dart';
import 'package:kasir_kutacane/theme/app_theme.dart';
import 'package:kasir_kutacane/widgets/app_widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TransactionDetailPage extends StatefulWidget {
  final Transaction transaction;

  const TransactionDetailPage({super.key, required this.transaction});

  @override
  State<TransactionDetailPage> createState() => _TransactionDetailPageState();
}

class _TransactionDetailPageState extends State<TransactionDetailPage> {
  late Transaction _currentTransaction;
  bool _isGeneratingPdf = false;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _currentTransaction = widget.transaction;
  }

  Future<void> _sharePdf(Transaction transaction) async {
    setState(() => _isGeneratingPdf = true);
    try {
      await PdfInvoiceService.sharePdf(
        context: context,
        transaction: transaction,
        onPdfGenerated: () {
          if (mounted) {
            setState(() => _isGeneratingPdf = false);
          }
        },
      );
    } finally {
      if (mounted) {
        setState(() => _isGeneratingPdf = false);
      }
    }
  }

  Future<void> _previewPdf(Transaction transaction) async {
    await PdfInvoiceService.previewPdf(
      context: context,
      transaction: transaction,
    );
  }

  Future<void> _confirmDeleteTransaction(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: AppColors.error, size: 26),
            SizedBox(width: 8),
            Text('Hapus Transaksi?'),
          ],
        ),
        content: Text(
          'Apakah Anda yakin ingin menghapus nota ${_currentTransaction.id_transaksi} atas nama ${_currentTransaction.customerName}?\n\n'
          'Fitur ini digunakan jika terjadi salah input atau transaksi terinput dua kali oleh sales.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus Transaksi'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final id = _currentTransaction.id_transaksi;
    setState(() => _isDeleting = true);

    try {
      // 1. Hapus dari server API Laravel
      final url = '${ApiConfig.baseUrl}/transaksi/$id';
      final authHeaders = await AuthService.getAuthHeaders();
      try {
        await http.delete(
          Uri.parse(url),
          headers: authHeaders,
        ).timeout(const Duration(seconds: 8));
      } catch (e) {
        debugPrint("API delete error: $e");
      }

      // 2. Hapus dari Supabase
      try {
        final supabase = Supabase.instance.client;
        await supabase.from('transaksi_items').delete().eq('id_transaksi', id);
        await supabase.from('transaksi').delete().eq('id_transaksi', id);
      } catch (errSupabase) {
        debugPrint("Supabase delete error: $errSupabase");
      }

      // 3. Hapus dari offline cache jika ada
      await OfflineSyncService.removePendingTransaction(id);

      // 4. Hapus dari riwayat pelunasan jika ada
      await PelunasanHistoryService.removeSettlement(id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nota $id berhasil dihapus'),
          backgroundColor: AppColors.lunas,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal menghapus transaksi: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
    );

    final isAdmin = AuthService.currentUser?.isAdmin == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail Nota'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Preview & Cetak PDF',
            onPressed: () => _previewPdf(_currentTransaction),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Nota',
            onPressed: () async {
              final updated = await Navigator.push<Transaction>(
                context,
                MaterialPageRoute(
                  builder: (_) => TransactionInputPage(
                    transaction: _currentTransaction,
                    onSave: (t) {},
                  ),
                ),
              );
              if (updated != null) {
                setState(() {
                  _currentTransaction = updated;
                });
              }
            },
          ),
          if (isAdmin)
            IconButton(
              icon: _isDeleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.error),
                    )
                  : const Icon(Icons.delete_outline, color: AppColors.error),
              tooltip: 'Hapus Transaksi (Khusus Admin)',
              onPressed: _isDeleting ? null : () => _confirmDeleteTransaction(context),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.screenMargin),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: AppColors.surfaceBorder),
                  boxShadow: AppShadow.card,
                ),
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // RECEIPT HEADER
                    Center(
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.storefront,
                              color: AppColors.primary,
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Kencana Cahaya Amanah',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'JL. Kenangan No. 183 Gorontalo',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 16),

                    // METADATA ROW
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Nomor Nota',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _currentTransaction.id_transaksi,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        StatusChip(status: _currentTransaction.status),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // KONSUMEN & TANGGAL
                    _infoRow(
                      label: 'Konsumen',
                      value: _currentTransaction.customerName,
                      icon: Icons.person_outline,
                    ),
                    if (_currentTransaction.alamat.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _infoRow(
                        label: 'Alamat',
                        value: _currentTransaction.alamat,
                        icon: Icons.location_on_outlined,
                      ),
                    ],
                    const SizedBox(height: 8),
                    _infoRow(
                      label: 'Waktu',
                      value: DateFormat('dd MMMM yyyy, HH:mm')
                          .format(_currentTransaction.date),
                      icon: Icons.access_time,
                    ),

                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 16),

                    // DAFTAR BARANG
                    Text(
                      'Daftar Barang (${_currentTransaction.items.length})',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),

                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _currentTransaction.items.length,
                      separatorBuilder: (_, __) => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Divider(height: 1),
                      ),
                      itemBuilder: (context, idx) {
                        final item = _currentTransaction.items[idx];
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 5,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Text(
                                        '${item.quantity} x ${currencyFormat.format(item.price)}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      if (item.bonus > 0) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.bonBg,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '+${item.bonus} Bonus',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.bon,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              currencyFormat.format(item.subtotal),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 20),
                    const Divider(thickness: 1.5),
                    const SizedBox(height: 16),

                    // TOTAL AKHIR
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'TOTAL BAYAR',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          currencyFormat.format(_currentTransaction.total),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // STICKY BOTTOM ACTIONS (Cetak Struk & Kirim PDF)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenMargin,
              vertical: 16,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  // Tombol Cetak Struk (Primary)
                  Expanded(
                    flex: 5,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => Printbluetooth.fromTransaction(
                              transaction: _currentTransaction,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 52),
                      ),
                      icon: const Icon(Icons.print, size: 20),
                      label: const Text(
                        'Cetak Struk',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Tombol Kirim PDF (Secondary)
                  Expanded(
                    flex: 4,
                    child: OutlinedButton.icon(
                      onPressed: _isGeneratingPdf
                          ? null
                          : () => _sharePdf(_currentTransaction),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 52),
                      ),
                      icon: _isGeneratingPdf
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.share, size: 20),
                      label: const Text(
                        'Kirim PDF',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
