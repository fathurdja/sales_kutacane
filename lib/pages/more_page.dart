import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/pages/arsip.dart';
import 'package:kasir_kutacane/pages/guide_page.dart';
import 'package:kasir_kutacane/pages/stock_input_page.dart';
import 'package:kasir_kutacane/pages/uploaddatatransaksi.dart';
import 'package:kasir_kutacane/services/offline_sync_service.dart';
import 'package:kasir_kutacane/theme/app_theme.dart';

class MorePage extends StatefulWidget {
  const MorePage({super.key});

  @override
  State<MorePage> createState() => _MorePageState();
}

class _MorePageState extends State<MorePage> {
  int _pendingOfflineCount = 0;

  @override
  void initState() {
    super.initState();
    _loadOfflineCount();
  }

  Future<void> _loadOfflineCount() async {
    try {
      final count = await OfflineSyncService.getPendingCount();
      if (!mounted) return;
      setState(() {
        _pendingOfflineCount = count;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lainnya'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenMargin),
        children: [
          // Section: Inventori & Stok
          _sectionHeader('Inventori & Stok Produk'),
          const SizedBox(height: AppSpacing.sm),
          _menuCard(
            context,
            icon: Icons.inventory_2_outlined,
            title: 'Input & Kelola Stok',
            subtitle: 'Update jumlah stok produk Boneva (Master Stock)',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StockInputPage()),
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),

          // Section: Data, Offline & Arsip
          _sectionHeader('Data, Offline & Arsip'),
          const SizedBox(height: AppSpacing.sm),
          _menuCard(
            context,
            icon: Icons.cloud_sync_outlined,
            title: 'Sinkronisasi Data Offline',
            subtitle: _pendingOfflineCount > 0
                ? '$_pendingOfflineCount nota tersimpan di HP belum terkirim'
                : 'Semua transaksi offline sudah terhubung ke server',
            badgeText: _pendingOfflineCount > 0
                ? '$_pendingOfflineCount Offline'
                : 'Tersinkron',
            badgeColor: _pendingOfflineCount > 0
                ? Colors.amber.shade800
                : AppColors.lunas,
            onTap: () => _showOfflineSyncSheet(context),
          ),
          const SizedBox(height: AppSpacing.cardGap),
          _menuCard(
            context,
            icon: Icons.archive_outlined,
            title: 'Arsip Transaksi',
            subtitle: 'Kelola berkas CSV arsip lokal',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ArchivePage()),
            ),
          ),
          const SizedBox(height: AppSpacing.cardGap),
          _menuCard(
            context,
            icon: Icons.upload_file_outlined,
            title: 'Import Transaksi Lama',
            subtitle: 'Buka file CSV atau Excel (.xlsx)',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CsvExcelToJsonPage()),
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),

          // Section: Perangkat
          _sectionHeader('Perangkat'),
          const SizedBox(height: AppSpacing.sm),
          _menuCard(
            context,
            icon: Icons.print_outlined,
            title: 'Pengaturan Printer',
            subtitle: 'Hubungkan printer Bluetooth termal',
            onTap: () {
              _showPrinterBottomSheet(context);
            },
          ),

          const SizedBox(height: AppSpacing.xxl),

          // Section: Informasi & Bantuan
          _sectionHeader('Informasi & Bantuan'),
          const SizedBox(height: AppSpacing.sm),
          _menuCard(
            context,
            icon: Icons.menu_book_outlined,
            title: 'Panduan & Alur Kasir',
            subtitle: 'Langkah operasional, alur transaksi & tips teknis',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GuidePage()),
            ),
          ),
          const SizedBox(height: AppSpacing.cardGap),
          _menuCard(
            context,
            icon: Icons.info_outline,
            title: 'Tentang Aplikasi',
            subtitle: 'Sales Kencana v2 — Kencana Cahaya Amanah',
            onTap: () => _showAboutDialog(context),
          ),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _menuCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    String? badgeText,
    Color? badgeColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.surfaceBorder),
          boxShadow: AppShadow.card,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 22, color: AppColors.primary),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (badgeText != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (badgeColor ?? AppColors.primary)
                                .withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(AppRadius.chipFull),
                            border: Border.all(
                              color: (badgeColor ?? AppColors.primary)
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            badgeText,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: badgeColor ?? AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: AppColors.textSecondary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  void _showOfflineSyncSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        bool syncing = false;
        String? syncError;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final currencyFormat =
                NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ');

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: FutureBuilder<List<Transaction>>(
                  future: OfflineSyncService.getPendingTransactions(),
                  builder: (context, snapshot) {
                    final pending = snapshot.data ?? [];

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceBorder,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: pending.isNotEmpty
                                    ? Colors.amber.shade100
                                    : AppColors.lunasBg,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                pending.isNotEmpty
                                    ? Icons.cloud_off_rounded
                                    : Icons.cloud_done_rounded,
                                color: pending.isNotEmpty
                                    ? Colors.amber.shade900
                                    : AppColors.lunas,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    pending.isNotEmpty
                                        ? '${pending.length} Nota Belum Terkirim'
                                        : 'Semua Nota Terhubung',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    pending.isNotEmpty
                                        ? 'Tersimpan aman di memori smartphone'
                                        : 'Data lokal sinkron dengan server',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        if (pending.isEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(20),
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.card),
                              border:
                                  Border.all(color: AppColors.surfaceBorder),
                            ),
                            child: const Column(
                              children: [
                                Icon(Icons.check_circle_outline,
                                    color: AppColors.lunas, size: 40),
                                SizedBox(height: 10),
                                Text(
                                  'Tidak ada antrean nota offline.',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Jika server sempat downtime saat Anda transaksi, nota otomatis tersimpan di sini.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(sheetCtx),
                              child: const Text('Tutup'),
                            ),
                          ),
                        ] else ...[
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 280),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: pending.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (ctx, idx) {
                                final item = pending[idx];
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.input),
                                    border: Border.all(
                                        color: AppColors.surfaceBorder),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.customerName.isNotEmpty
                                                  ? item.customerName
                                                  : 'Tanpa Nama',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${item.id_transaksi} • ${DateFormat('dd MMM HH:mm').format(item.date)}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        currencyFormat.format(item.total),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          if (syncError != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              syncError!,
                              style: const TextStyle(
                                color: AppColors.error,
                                fontSize: 12,
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.lg),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              onPressed: syncing
                                  ? null
                                  : () async {
                                      setSheetState(() {
                                        syncing = true;
                                        syncError = null;
                                      });

                                      try {
                                        final res = await OfflineSyncService
                                            .syncPendingTransactions();
                                        if (res.success > 0) {
                                          await _loadOfflineCount();
                                          if (ctx.mounted) {
                                            Navigator.pop(sheetCtx);
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  '${res.success} nota berhasil dihubungkan ke server!',
                                                ),
                                                backgroundColor:
                                                    AppColors.lunas,
                                              ),
                                            );
                                          }
                                        } else if (res.failed > 0) {
                                          setSheetState(() {
                                            syncing = false;
                                            syncError = res.errors.firstOrNull ??
                                                'Gagal menghubungkan ke server';
                                          });
                                        }
                                      } catch (err) {
                                        setSheetState(() {
                                          syncing = false;
                                          syncError = err.toString();
                                        });
                                      }
                                    },
                              icon: syncing
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.sync, size: 20),
                              label: Text(
                                syncing
                                    ? 'Menyinkronkan ke Server...'
                                    : 'Sinkronkan Semua Sekarang (${pending.length} Nota)',
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showPrinterBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.surfaceBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const Icon(
              Icons.print_outlined,
              size: 48,
              color: AppColors.primary,
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Printer Bluetooth',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Hubungkan printer termal Bluetooth dari halaman cetak struk. '
              'Pastikan Bluetooth perangkat Anda sudah aktif dan printer sudah dipasangkan (paired).',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Mengerti'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sales Kencana v2'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Aplikasi POS & Sales Force Automation'),
            SizedBox(height: 8),
            Text(
              'Kencana Cahaya Amanah\n'
              'JL. Kenangan No. 183 Gorontalo\n\n'
              'Versi 2.0.0',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }
}
