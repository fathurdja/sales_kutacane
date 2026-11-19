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
import 'package:kasir_kutacane/services/print.dart';
import 'package:kasir_kutacane/services/stock_api_service.dart';
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
  List<PelunasanPayment> _trxPayments = [];

  @override
  void initState() {
    super.initState();
    _currentTransaction = widget.transaction;
    _loadTrxPayments();
  }

  Future<void> _loadTrxPayments() async {
    try {
      final payments = await PelunasanHistoryService.loadPaymentHistory();
      final filtered = payments
          .where((p) => p.idTransaksi != null && p.idTransaksi == _currentTransaction.id_transaksi)
          .toList()
        ..sort((a, b) => a.tanggalPelunasan.compareTo(b.tanggalPelunasan));

      if (mounted) {
        setState(() {
          _trxPayments = filtered;
          final totalPaid = filtered.fold<double>(0.0, (sum, p) => sum + p.nominalBayar);
          if (totalPaid > 0 && totalPaid < _currentTransaction.total && !_currentTransaction.isSettled) {
            _currentTransaction.status = 'SUDAH DIBAYAR SEBAGIAN';
          }
        });
      }
    } catch (_) {}
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(
          context,
          _currentTransaction != widget.transaction ? _currentTransaction : null,
        );
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(
            onPressed: () => Navigator.pop(
              context,
              _currentTransaction != widget.transaction ? _currentTransaction : null,
            ),
          ),
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
                  // Sinkronkan data produk & stok terbaru dari server
                  StockApiService.fetchProducts();
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

                    // INFORMASI PELUNASAN / CICILAN BON
                    if (_trxPayments.isNotEmpty ||
                        _currentTransaction.isBon ||
                        _currentTransaction.isBonLunas ||
                        _currentTransaction.isDicicil) ...[
                      const SizedBox(height: 20),
                      const Divider(thickness: 1.5),
                      const SizedBox(height: 14),
                      _buildBonPaymentDetailsCard(currencyFormat),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // STICKY BOTTOM ACTIONS (Cetak Struk, Kirim PDF, & Bayar/Lunasi jika belum lunas)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenMargin,
              vertical: 12,
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
                  if (!_currentTransaction.isSettled) ...[
                    // Tombol Bayar / Lunasi (Prioritas Utama untuk transaksi pending/cicil)
                    Expanded(
                      flex: 4,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          final double totalPaid = _trxPayments.fold<double>(
                              0.0, (sum, p) => sum + p.nominalBayar);
                          final double sisa = (_currentTransaction.total - totalPaid)
                              .clamp(0.0, _currentTransaction.total);
                          _showPelunasanModal(sisa > 0 ? sisa : _currentTransaction.total);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.lunas,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.button),
                          ),
                        ),
                        icon: const Icon(Icons.payments_outlined, size: 18),
                        label: const Text(
                          'Bayar / Lunasi',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Tombol Cetak Struk
                    Expanded(
                      flex: 3,
                      child: OutlinedButton.icon(
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
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.button),
                          ),
                        ),
                        icon: const Icon(Icons.print, size: 16),
                        label: const Text(
                          'Struk',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Tombol Kirim PDF
                    Expanded(
                      flex: 3,
                      child: OutlinedButton.icon(
                        onPressed: _isGeneratingPdf
                            ? null
                            : () => _sharePdf(_currentTransaction),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.button),
                          ),
                        ),
                        icon: _isGeneratingPdf
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.share, size: 16),
                        label: const Text(
                          'PDF',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    // Transaksi Lunas: Tombol Cetak Struk (Primary) & Kirim PDF
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.button),
                          ),
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
                    Expanded(
                      flex: 4,
                      child: OutlinedButton.icon(
                        onPressed: _isGeneratingPdf
                            ? null
                            : () => _sharePdf(_currentTransaction),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.button),
                          ),
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
                ],
              ),
            ),
          ),
        ],
      ),
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

  Widget _buildBonPaymentDetailsCard(NumberFormat currencyFormat) {
    final double totalPaid =
        _trxPayments.fold<double>(0.0, (sum, p) => sum + p.nominalBayar);
    final double totalBon = _currentTransaction.total;
    final double sisaPiutang =
        (totalBon - totalPaid).clamp(0.0, totalBon);
    final bool isLunasPenuh = sisaPiutang <= 0 && totalPaid > 0;
    final bool isSebagian = totalPaid > 0 && sisaPiutang > 0;
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    final Color cardBg = isLunasPenuh
        ? const Color(0xFFE6FCF5)
        : (isSebagian ? const Color(0xFFFFF4E6) : AppColors.bgSecondary);
    final Color borderColor = isLunasPenuh
        ? const Color(0xFF0CA678).withValues(alpha: 0.3)
        : (isSebagian ? Colors.orange.shade300 : Colors.grey.shade300);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      isLunasPenuh
                          ? Icons.check_circle_rounded
                          : (isSebagian ? Icons.payments_rounded : Icons.pending_actions_rounded),
                      size: 20,
                      color: isLunasPenuh
                          ? const Color(0xFF0CA678)
                          : (isSebagian ? Colors.orange.shade900 : AppColors.bon),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Rincian Cicilan & Pelunasan',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isLunasPenuh
                      ? const Color(0xFF0CA678)
                      : (isSebagian ? Colors.orange.shade800 : AppColors.bon),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isLunasPenuh
                      ? 'LUNAS PENUH'
                      : (isSebagian ? 'SUDAH DICICIL' : 'BELUM LUNAS (BON)'),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // Baris 1: Total Bon Awal
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Tagihan BON:',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  currencyFormat.format(totalBon),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Baris 2: Sudah Dibayar Sebagian
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Sudah Dibayar:',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${currencyFormat.format(totalPaid)} dari ${currencyFormat.format(totalBon)}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: totalPaid > 0 ? const Color(0xFF0CA678) : AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Baris 3: Sisa Piutang
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Sisa Tagihan BON:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.bon,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  currencyFormat.format(sisaPiutang),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.bon,
                  ),
                ),
              ),
            ],
          ),

          // Tombol Bayar / Lunasi langsung di kartu jika belum lunas
          if (!_currentTransaction.isSettled) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.lunas,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.payments_outlined, size: 16),
                label: Text(
                  isSebagian ? 'Bayar Cicilan / Lunasi Sisa' : 'Bayar / Lunasi BON',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                ),
                onPressed: () => _showPelunasanModal(sisaPiutang > 0 ? sisaPiutang : totalBon),
              ),
            ),
          ],

          // List Riwayat Pembayaran (Tanggal & Nominal Cicilan)
          if (_trxPayments.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Riwayat Tanggal Pembayaran (${_trxPayments.length}):',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            ..._trxPayments.asMap().entries.map((entry) {
              final idx = entry.key + 1;
              final p = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.orange.shade100,
                      child: Text(
                        '$idx',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dateFormat.format(p.tanggalPelunasan),
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Dibayar ${currencyFormat.format(p.nominalBayar)} • Sisa: ${currencyFormat.format(p.sisaBon)}',
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (p.catatan != null && p.catatan!.isNotEmpty)
                            Text(
                              'Ket: ${p.catatan}',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontStyle: FontStyle.italic,
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.print_outlined, size: 18, color: AppColors.primary),
                      tooltip: 'Cetak Bukti Cicilan',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        TestPrint().printPelunasanPayment(
                          customerName: p.customerName,
                          idTransaksi: p.idTransaksi,
                          totalBonAwal: totalBon,
                          nominalBayar: p.nominalBayar,
                          sisaBon: p.sisaBon,
                          tanggalPelunasan: p.tanggalPelunasan,
                          catatan: p.catatan,
                          isLunas: p.isLunas,
                        );
                      },
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Future<void> _showPelunasanModal(double sisaTrx) async {
    final currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    DateTime selectedDate = DateTime.now();
    bool isFullPayment = true;
    final nominalCtrl = TextEditingController(text: sisaTrx.toInt().toString());
    final catatanCtrl = TextEditingController();
    bool printReceipt = true;
    bool isSubmitting = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final double enteredAmount = isFullPayment
                ? sisaTrx
                : (double.tryParse(nominalCtrl.text.replaceAll('.', '').replaceAll(',', '').trim()) ?? 0.0);
            final bool isOverPay = enteredAmount > sisaTrx;

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Row(
                      children: [
                        Icon(Icons.payments_rounded, color: AppColors.lunas, size: 24),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Pelunasan / Cicilan Nota',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_currentTransaction.id_transaksi} • ${_currentTransaction.customerName}',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),

                    // Box Ringkasan Sisa
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.bgSecondary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Sisa Tagihan BON:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                          Text(
                            currencyFormat.format(sisaTrx),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.bon),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Pilih Mode Pembayaran
                    const Text('Metode Pembayaran:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('Lunas Penuh', style: TextStyle(fontSize: 12))),
                            selected: isFullPayment,
                            selectedColor: AppColors.lunas.withValues(alpha: 0.15),
                            onSelected: (val) {
                              if (val) {
                                setModalState(() {
                                  isFullPayment = true;
                                  nominalCtrl.text = sisaTrx.toInt().toString();
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('Cicilan Sebagian', style: TextStyle(fontSize: 12))),
                            selected: !isFullPayment,
                            selectedColor: Colors.orange.shade100,
                            onSelected: (val) {
                              if (val) {
                                setModalState(() {
                                  isFullPayment = false;
                                  nominalCtrl.clear();
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Nominal Cicilan jika sebagian
                    if (!isFullPayment) ...[
                      const Text('Nominal Pembayaran:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: nominalCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          prefixText: 'Rp ',
                          hintText: 'Masukkan jumlah cicilan',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          errorText: isOverPay ? 'Nominal melebihi sisa tagihan!' : null,
                        ),
                        onChanged: (_) => setModalState(() {}),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Tanggal Pembayaran
                    const Text('Tanggal Pembayaran:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: modalCtx,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 30)),
                        );
                        if (picked != null) {
                          setModalState(() => selectedDate = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 16, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Text(
                              DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(selectedDate),
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Catatan
                    TextField(
                      controller: catatanCtrl,
                      decoration: InputDecoration(
                        labelText: 'Catatan (Opsional)',
                        hintText: 'Contoh: Titipan cicilan toko',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Checkbox Cetak Bukti
                    CheckboxListTile(
                      value: printReceipt,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Cetak Bukti ke Printer Bluetooth', style: TextStyle(fontSize: 12.5)),
                      onChanged: (val) => setModalState(() => printReceipt = val ?? true),
                    ),
                    const SizedBox(height: 14),

                    // Tombol Aksi
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(modalCtx),
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                            child: const Text('Batal'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isFullPayment ? AppColors.lunas : AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: isSubmitting
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.check, size: 18),
                            label: Text(
                              isSubmitting ? 'Menyimpan...' : (isFullPayment ? 'Lunasi Penuh' : 'Simpan Cicilan'),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onPressed: (isSubmitting || (!isFullPayment && (enteredAmount <= 0 || isOverPay)))
                                ? null
                                : () async {
                                    setModalState(() => isSubmitting = true);
                                    await _executeDetailPayment(
                                      payAmount: enteredAmount,
                                      tanggalPelunasan: selectedDate,
                                      isFull: isFullPayment,
                                      sisaTrx: sisaTrx,
                                      catatan: catatanCtrl.text.trim(),
                                      printReceipt: printReceipt,
                                    );
                                    if (modalCtx.mounted) Navigator.pop(modalCtx);
                                  },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _executeDetailPayment({
    required double payAmount,
    required DateTime tanggalPelunasan,
    required bool isFull,
    required double sisaTrx,
    String? catatan,
    bool printReceipt = true,
  }) async {
    final double actualPay = payAmount;
    final bool isCleared = isFull || actualPay >= sisaTrx;
    final double sisaSetelahBayar = (sisaTrx - actualPay).clamp(0.0, sisaTrx);

    try {
      if (isCleared) {
        // Catat settlement penuh
        await PelunasanHistoryService.recordSettlement(
          idTransaksi: _currentTransaction.id_transaksi,
          customerName: _currentTransaction.customerName,
          total: _currentTransaction.total,
          tanggalPelunasan: tanggalPelunasan,
        );
        setState(() {
          _currentTransaction.status = 'BON LUNAS';
          _currentTransaction.tanggalPelunasan = tanggalPelunasan;
        });
      } else {
        // Catat cicilan sebagian
        await PelunasanHistoryService.recordPayment(
          customerName: _currentTransaction.customerName,
          idTransaksi: _currentTransaction.id_transaksi,
          nominalBayar: actualPay,
          sisaBon: sisaSetelahBayar,
          tanggalPelunasan: tanggalPelunasan,
          catatan: catatan?.isNotEmpty == true ? catatan : 'Cicilan untuk nota ${_currentTransaction.id_transaksi}',
          isLunas: false,
        );
        setState(() {
          _currentTransaction.status = 'SUDAH DIBAYAR SEBAGIAN';
        });
      }

      // Cetak struk bukti jika dipilih
      if (printReceipt) {
        await TestPrint().printPelunasanPayment(
          customerName: _currentTransaction.customerName,
          idTransaksi: _currentTransaction.id_transaksi,
          totalBonAwal: sisaTrx,
          nominalBayar: actualPay,
          sisaBon: sisaSetelahBayar,
          tanggalPelunasan: tanggalPelunasan,
          catatan: catatan,
          isLunas: isCleared,
        );
      }

      await _loadTrxPayments();

      if (!mounted) return;
      final currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isCleared
                ? 'Nota ${_currentTransaction.id_transaksi} BERHASIL DILUNASI!'
                : 'Pembayaran sebagian ${currencyFormat.format(actualPay)} berhasil dicatat! Sisa BON: ${currencyFormat.format(sisaSetelahBayar)}',
          ),
          backgroundColor: isCleared ? AppColors.lunas : Colors.orange.shade800,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mencatat pembayaran: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}
