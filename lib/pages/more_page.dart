import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/config/api_config.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/models/user_model.dart';
import 'package:kasir_kutacane/pages/arsip.dart';
import 'package:kasir_kutacane/pages/guide_page.dart';
import 'package:kasir_kutacane/pages/login_page.dart';
import 'package:kasir_kutacane/pages/pelunasan_page.dart';
import 'package:kasir_kutacane/pages/stock_input_page.dart';
import 'package:kasir_kutacane/pages/uploaddatatransaksi.dart';
import 'package:kasir_kutacane/services/auth_service.dart';
import 'package:kasir_kutacane/services/daily_closing_service.dart';
import 'package:kasir_kutacane/services/offline_sync_service.dart';
import 'package:kasir_kutacane/services/printerBluetooth.dart';
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
          // Profil Pengguna Aktif
          _buildUserProfileCard(context),

          // Section: Panel Admin (Khusus Admin)
          if (AuthService.currentUser?.isAdmin == true) ...[
            _sectionHeader('Panel Administrator'),
            const SizedBox(height: AppSpacing.sm),
            _menuCard(
              context,
              icon: Icons.analytics_outlined,
              title: 'Monitoring Kinerja Sales & Omset',
              subtitle: 'Pantau total transaksi & omset semua akun sales',
              badgeText: 'Admin',
              badgeColor: Colors.purple,
              onTap: () => _showSalesMonitoringModal(context),
            ),
            const SizedBox(height: AppSpacing.xxl),
          ],

          // Section: Piutang & Pembayaran
          _sectionHeader('Piutang & Pembayaran'),
          const SizedBox(height: AppSpacing.sm),
          _menuCard(
            context,
            icon: Icons.receipt_long_rounded,
            title: 'Monitoring & Pelunasan Bon',
            subtitle: 'Daftar transaksi bon & pelunasan dengan tanggal',
            badgeText: 'Piutang',
            badgeColor: AppColors.bon,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PelunasanPage()),
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),

          // Section: Inventori & Stok
          _sectionHeader('Inventori & Stok Produk'),
          const SizedBox(height: AppSpacing.sm),
          _menuCard(
            context,
            icon: Icons.inventory_2_outlined,
            title: AuthService.currentUser?.isAdmin == true
                ? 'Input & Kelola Stok'
                : 'Stok Terjual & Produk',
            subtitle: AuthService.currentUser?.isAdmin == true
                ? 'Update kuota stok awal & monitor fisik produk'
                : 'Lihat akumulasi penjualan & katalog produk (Stok Awal Terisolasi)',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StockInputPage()),
            ),
          ),
          if (AuthService.currentUser?.isAdmin == true) ...[
            const SizedBox(height: AppSpacing.cardGap),
            _menuCard(
              context,
              icon: Icons.event_repeat_rounded,
              title: 'Tutup Buku & Rollover Stok',
              subtitle: 'Arsip transaksi hari ini & set sisa stok jadi stok awal besok',
              onTap: () => _performDailyClosing(context),
            ),
          ],

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
            title: 'Panduan & Peran Kasir',
            subtitle: 'Wewenang Admin & Sales, alur nota, pelunasan & tips',
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
            subtitle: 'Sales Kencana v3 — Kencana Cahaya Amanah',
            onTap: () => _showAboutDialog(context),
          ),

          const SizedBox(height: AppSpacing.xxl),

          // Section: Akun & Sesi
          _sectionHeader('Akun & Sesi'),
          const SizedBox(height: AppSpacing.sm),
          _menuCard(
            context,
            icon: Icons.logout_rounded,
            title: 'Keluar Akun (Logout)',
            subtitle:
                'Keluar dari akun ${AuthService.currentUser?.name ?? ""} dan ganti pengguna',
            badgeText: 'Keluar',
            badgeColor: AppColors.error,
            onTap: () => _confirmLogout(context),
          ),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildUserProfileCard(BuildContext context) {
    final user = AuthService.currentUser;
    if (user == null) return const SizedBox.shrink();

    final isAdmin = user.isAdmin;
    final roleColor = isAdmin ? Colors.purple : AppColors.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: roleColor.withValues(alpha: 0.25)),
        boxShadow: AppShadow.card,
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: roleColor.withValues(alpha: 0.15),
                child: Icon(
                  isAdmin
                      ? Icons.admin_panel_settings_rounded
                      : Icons.person_rounded,
                  color: roleColor,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            user.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: roleColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(
                              color: roleColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            user.role.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: roleColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${user.username} • ${user.email}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: user.canManageStock
                  ? Colors.green.shade50
                  : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  user.canManageStock
                      ? Icons.check_circle_outline
                      : Icons.visibility_outlined,
                  size: 16,
                  color: user.canManageStock
                      ? Colors.green.shade700
                      : Colors.blue.shade700,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    user.canManageStock
                        ? 'Hak Akses Stok: Full Access (Set Stok Awal & Monitor Sales)'
                        : 'Hak Akses Stok: Read-Only (Hanya melihat stok armada sendiri)',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: user.canManageStock
                          ? Colors.green.shade800
                          : Colors.blue.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keluar dari Akun?'),
        content: const Text(
          'Anda akan keluar dari sesi saat ini dan kembali ke halaman login.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await AuthService.logout();
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      }
    }
  }

  void _showSalesMonitoringModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        final currencyFormat =
            NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ');

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: FutureBuilder<List<UserModel>>(
              future: AuthService.fetchUsers(),
              builder: (ctx, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 250,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.error, size: 40),
                        const SizedBox(height: 12),
                        Text(
                          'Gagal memuat daftar sales:\n${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.error),
                        ),
                      ],
                    ),
                  );
                }

                final users = snapshot.data ?? [];
                final totalSemuaOmset = users.fold<double>(
                  0.0,
                  (sum, u) => sum + u.totalOmset,
                );
                final totalSemuaTrx = users.fold<int>(
                  0,
                  (sum, u) => sum + u.totalTransaksi,
                );

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
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.admin_panel_settings_rounded,
                            color: Colors.purple,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Monitoring Tim Sales & Omset',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Data langsung dari backend server',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Ringkasan Total Tim
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.purple.shade700,
                            Colors.purple.shade900,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Total Omset Seluruh Tim',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                currencyFormat.format(totalSemuaOmset),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$totalSemuaTrx Nota',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: users.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (ctx, idx) {
                          final u = users[idx];
                          final isUserAdmin = u.isAdmin;
                          final accent = isUserAdmin
                              ? Colors.purple
                              : AppColors.primary;

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.surfaceBorder,
                              ),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor:
                                      accent.withValues(alpha: 0.12),
                                  child: Icon(
                                    isUserAdmin
                                        ? Icons.admin_panel_settings
                                        : Icons.person,
                                    color: accent,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            u.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: accent.withValues(
                                                  alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              u.role.toUpperCase(),
                                              style: TextStyle(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w800,
                                                color: accent,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${u.username} • ${u.totalTransaksi} transaksi dibuat',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      currencyFormat.format(u.totalOmset),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13.5,
                                        color: accent,
                                      ),
                                    ),
                                    const Text(
                                      'Omset',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        child: const Text('Tutup'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
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
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Printbluetooth(
                        orderItems: const [],
                        paymentMethod: 'Tunai',
                        total: 0,
                        date: DateTime.now(),
                        customerName: 'Uji Coba Printer',
                        alamat: 'Gorontalo',
                        idTransaksi: 'TEST-001',
                        status: 'LUNAS',
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.bluetooth_searching, size: 20),
                label: const Text(
                  'Buka Koneksi & Tes Printer',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Tutup'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  Future<void> _performDailyClosing(BuildContext context) async {
    if (AuthService.currentUser?.isAdmin != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Menu Tutup Buku & Rollover Stok hanya untuk Admin'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    List<Transaction> transactions = [];
    try {
      final pendingOffline = await OfflineSyncService.getPendingTransactions();
      for (final t in pendingOffline) {
        t.isOffline = true;
      }
      try {
        final authHeaders = await AuthService.getAuthHeaders();
        final res = await http.get(
          ApiConfig.transaksiUri,
          headers: authHeaders,
        ).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final List data = jsonDecode(res.body);
          final serverTrx = data.map<Transaction>((e) => Transaction.fromJson(e)).toList();
          final serverIds = serverTrx.map((e) => e.id_transaksi).toSet();
          final unmerged = pendingOffline.where((off) => !serverIds.contains(off.id_transaksi)).toList();
          transactions = [...unmerged, ...serverTrx];
        } else {
          transactions = pendingOffline;
        }
      } catch (_) {
        transactions = pendingOffline;
      }
    } catch (_) {}

    if (context.mounted) {
      Navigator.pop(context); // Dismiss loading
    }

    if (!context.mounted) return;

    final preview = await DailyClosingService.getClosingPreview(transactions);
    if (!context.mounted) return;

    bool rolloverStock = true;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.event_repeat_rounded, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tutup Buku Harian',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Arsip & Rollover Stok Besok',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.receipt_long, color: Colors.blue, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${preview.totalTransactions} Nota Transaksi Hari Ini',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                Text(
                                  'Total Omzet: Rp ${NumberFormat('#,###', 'id_ID').format(preview.totalRevenue.toInt())}',
                                  style: TextStyle(color: Colors.blue.shade800, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Transaksi hari ini otomatis diarsipkan ke CSV (tersimpan aman di menu Arsip).',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.inventory_2_outlined, color: AppColors.primary, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Stok awal besok otomatis diset dari sisa stok hari ini:',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (preview.stockItems.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          children: preview.stockItems.map((item) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(item.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                                  Row(
                                    children: [
                                      Text('Sisa: ${item.sisaStockHariIni}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                      const Icon(Icons.arrow_right_alt, size: 16, color: Colors.grey),
                                      Text(
                                        'Besok: ${item.stockAwalBesok}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: rolloverStock ? Colors.green.shade50 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: rolloverStock ? Colors.green.shade300 : Colors.grey.shade300),
                      ),
                      child: CheckboxListTile(
                        value: rolloverStock,
                        onChanged: (val) {
                          setDialogState(() {
                            rolloverStock = val ?? true;
                          });
                        },
                        title: const Text('Rollover Stok Otomatis', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        subtitle: const Text('Sisa stok jadi stok awal besok & reset counter penjualan ke 0', style: TextStyle(fontSize: 11)),
                        activeColor: Colors.green.shade700,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Setelah proses ini selesai, seluruh transaksi kasir hari ini akan bersih untuk siap digunakan esok hari.',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Batal'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Proses Tutup Buku'),
                  onPressed: () => Navigator.pop(ctx, true),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final result = await DailyClosingService.executeDailyClosing(
        transactions: transactions,
        rolloverStock: rolloverStock,
      );

      if (!context.mounted) return;
      Navigator.pop(context); // Dismiss loading

      if (result.success) {
        _loadOfflineCount();
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.task_alt, color: Colors.green, size: 28),
                SizedBox(width: 10),
                Text('Tutup Buku Berhasil!'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('1. ${result.totalTransactionsArchived} nota transaksi telah berhasil disimpan ke arsip.', style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 4),
                Text('Berkas: ${result.archiveFileName}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
                const SizedBox(height: 10),
                if (rolloverStock) ...[
                  const Text('2. Stok awal besok telah diset dari sisa stok hari ini:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  ...result.rolloverItems.map(
                    (it) => Padding(
                      padding: const EdgeInsets.only(left: 12, bottom: 2),
                      child: Text('• ${it.label}: ${it.stockAwalBesok} unit (Sisa ${it.sisaStockHariIni})', style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text('Counter penjualan harian telah direset ke 0.', style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w500)),
                ],
              ],
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Selesai'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tutup buku gagal: ${result.errorMessage ?? "Error"}'), backgroundColor: AppColors.error),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Terjadi kesalahan: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sales Kencana v3'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Aplikasi POS & Sales Force Automation'),
            SizedBox(height: 8),
            Text(
              'Kencana Cahaya Amanah\n'
              'JL. Kenangan No. 183 Gorontalo\n\n'
              'Versi 3.0.0',
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
