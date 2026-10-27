import 'package:flutter/material.dart';
import 'package:kasir_kutacane/pages/arsip.dart';
import 'package:kasir_kutacane/pages/dailyreport.dart';
import 'package:kasir_kutacane/pages/pelunasan_page.dart';
import 'package:kasir_kutacane/pages/stock_input_page.dart';
import 'package:kasir_kutacane/pages/transactionInput.dart';
import 'package:kasir_kutacane/services/auth_service.dart';
import 'package:kasir_kutacane/theme/app_theme.dart';

class GuidePage extends StatefulWidget {
  const GuidePage({super.key});

  @override
  State<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends State<GuidePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panduan & Peran Kasir'),
        actions: [
          IconButton(
            icon: const Icon(Icons.slideshow_outlined),
            tooltip: 'Mulai Tur Visual',
            onPressed: () => showAppTourDialog(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          isScrollable: false,
          tabs: const [
            Tab(
              icon: Icon(Icons.badge_outlined, size: 20),
              text: 'Peran Pengguna',
            ),
            Tab(
              icon: Icon(Icons.timeline, size: 20),
              text: 'Alur Operasional',
            ),
            Tab(
              icon: Icon(Icons.help_center_outlined, size: 20),
              text: 'Tanya Jawab',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildRolesTab(),
          _buildFlowTab(),
          _buildFaqTab(),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 1: PERAN PENGGUNA (ADMIN VS SALES)
  // ==========================================
  Widget _buildRolesTab() {
    final currentUser = AuthService.currentUser;
    final isAdmin = currentUser?.isAdmin == true;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenMargin),
      children: [
        // CURRENT USER STATUS CARD
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isAdmin
                  ? [const Color(0xFF6741D9), const Color(0xFF7950F2)]
                  : [AppColors.primary, const Color(0xFF0C9488)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppRadius.card),
            boxShadow: AppShadow.elevated,
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isAdmin ? Icons.admin_panel_settings : Icons.badge_outlined,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          isAdmin ? 'AKUN ADMIN' : 'AKUN SALES ARMADA',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'AKTIF',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      currentUser?.name ?? 'Pengguna Kasir',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isAdmin
                          ? 'Wewenang Penuh: Kelola Stok, Monitoring Tim & Rekap Omzet'
                          : 'Operasional Lapangan: Buat Nota, Tagih Bon & Pantau Omzet Sendiri',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        // SECTION HEADER
        const Text(
          'Dua Peran Utama dalam Aplikasi',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Aplikasi memisahkan wewenang secara ketat antara Manajemen (Admin) dan Operasional Lapangan (Sales):',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // CARD PERAN 1: ADMIN
        _roleCard(
          roleTitle: '1. Peran ADMIN (Manajemen & Gudang)',
          badgeText: 'HAK AKSES PENUH',
          badgeColor: const Color(0xFF6741D9),
          badgeBgColor: const Color(0xFFF3F0FF),
          themeColor: const Color(0xFF6741D9),
          icon: Icons.admin_panel_settings_rounded,
          summary:
              'Admin bertanggung jawab atas pengaturan stok fisik, pengawasan performa penjualan seluruh armada sales, serta pembukuan keuangan.',
          duties: [
            {
              'title': 'Kelola Stok Awal & Stok Masuk',
              'desc':
                  'Admin dapat menetapkan "Set Stok Awal" (mereset baseline fisik) serta menambah "Stok Masuk" (menambah stok sisa tanpa mengurangi barang yang telah terjual).'
            },
            {
              'title': 'Visibilitas Angka Kuota Stok',
              'desc':
                  'Admin dapat melihat angka nominal stok gudang secara detail (contoh: "Stok Tersedia: 105") baik di Beranda, Manajemen Stok, maupun formulir Nota.'
            },
            {
              'title': 'Laporan Omzet Terpisah (Lunas vs Bon)',
              'desc':
                  'Di menu Laporan Harian, Admin melihat rincian terpisah antara: Total Omzet Keseluruhan, Omzet Lunas (Uang Kas Masuk), dan Omzet Bon (Piutang Belum Bayar).'
            },
            {
              'title': 'Monitoring Seluruh Sales Armada',
              'desc':
                  'Admin dapat memfilter dan menganalisis rekap penjualan per sales user untuk memantau performa masing-masing armada di lapangan.'
            },
            {
              'title': 'Pelunasan Bon & Status Failover Cloud',
              'desc':
                  'Admin dapat mengakses menu Pelunasan untuk konfirmasi piutang toko, serta memantau status koneksi server utama vs server cadangan Supabase.'
            },
          ],
        ),
        const SizedBox(height: AppSpacing.xl),

        // CARD PERAN 2: SALES
        _roleCard(
          roleTitle: '2. Peran SALES (Armada & Kasir Lapangan)',
          badgeText: 'OPERASIONAL NOTA',
          badgeColor: AppColors.primary,
          badgeBgColor: AppColors.primaryLight,
          themeColor: AppColors.primary,
          icon: Icons.storefront_rounded,
          summary:
              'Sales fokus melayani pelanggan, mencatat transaksi penjualan di toko/lapangan, menagih bon, dan mencetak struk fisik via Bluetooth.',
          duties: [
            {
              'title': 'Pembuatan Nota Cepat & Validasi Stok',
              'desc':
                  'Sales membuat nota untuk toko dengan opsi pembayaran LUNAS atau BON. Sistem otomatis memblokir pembuatan nota jika stok produk 0.'
            },
            {
              'title': 'Perlindungan Privasi Stok Gudang',
              'desc':
                  'Sales TIDAK DAPAT melihat nominal stok gudang yang di-input admin. Di layar sales hanya tertera status ketersediaan: "Stok Tersedia" atau "Stok Habis (0)".'
            },
            {
              'title': 'Pantau Omzet & Unit Terjual Sendiri',
              'desc':
                  'Sales tetap dapat melihat omzet hasil penjualan pribadinya hari ini serta jumlah produk yang telah terjual untuk mengetahui target harian.'
            },
            {
              'title': 'Menu Pelunasan Bon di Toko',
              'desc':
                  'Saat menagih piutang di toko pelanggan, Sales dapat membuka menu Pelunasan, mengisi tanggal pelunasan, dan langsung mencetak struk fisik tanda lunas.'
            },
            {
              'title': 'Mode Offline & Sinkronisasi Otomatis',
              'desc':
                  'Jika sales berada di daerah blank spot tanpa sinyal internet, nota tetap tersimpan di memori HP dan otomatis terkirim begitu terhubung internet.'
            },
          ],
        ),
        const SizedBox(height: AppSpacing.xxl),

        // SECTION: TABEL MATRIKS HAK AKSES
        const Text(
          'Matriks Perbandingan Hak Akses',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Ringkasan komparasi fitur yang dapat diakses oleh Admin vs Sales:',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        _permissionMatrixTable(),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _roleCard({
    required String roleTitle,
    required String badgeText,
    required Color badgeColor,
    required Color badgeBgColor,
    required Color themeColor,
    required IconData icon,
    required String summary,
    required List<Map<String, String>> duties,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.surfaceBorder),
        boxShadow: AppShadow.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: badgeBgColor.withValues(alpha: 0.6),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.card - 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: themeColor.withValues(alpha: 0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: themeColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    roleTitle,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: themeColor,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(AppRadius.chipFull),
                  ),
                  child: Text(
                    badgeText,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'Fitur & Wewenang Utama:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                ...duties.map((duty) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            size: 16,
                            color: themeColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textPrimary,
                                  height: 1.4,
                                ),
                                children: [
                                  TextSpan(
                                    text: '${duty['title']}: ',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  TextSpan(
                                    text: duty['desc'],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _permissionMatrixTable() {
    final rows = [
      {
        'feature': 'Set Stok Awal (Reset Baseline)',
        'admin': true,
        'sales': false,
        'note': 'Hanya Admin'
      },
      {
        'feature': 'Tambah Stok Masuk (Akumulatif)',
        'admin': true,
        'sales': false,
        'note': 'Hanya Admin'
      },
      {
        'feature': 'Lihat Angka Sisa Stok Gudang',
        'admin': true,
        'sales': false,
        'note': 'Sales: status saja'
      },
      {
        'feature': 'Buat Nota Penjualan (Lunas / Bon)',
        'admin': true,
        'sales': true,
        'note': 'Semua Peran'
      },
      {
        'feature': 'Validasi Blokir Stok 0',
        'admin': true,
        'sales': true,
        'note': 'Semua Peran'
      },
      {
        'feature': 'Cetak Struk Bluetooth & PDF Stempel',
        'admin': true,
        'sales': true,
        'note': 'Semua Peran'
      },
      {
        'feature': 'Menu Pelunasan Bon & Cetak Bukti',
        'admin': true,
        'sales': true,
        'note': 'Semua Peran'
      },
      {
        'feature': 'Lihat Omzet Penjualan Pribadi',
        'admin': true,
        'sales': true,
        'note': 'Semua Peran'
      },
      {
        'feature': 'Lihat Omzet Terpisah (Lunas vs Bon)',
        'admin': true,
        'sales': true,
        'note': 'Di Laporan Harian'
      },
      {
        'feature': 'Filter Rekap Seluruh Sales Armada',
        'admin': true,
        'sales': false,
        'note': 'Hanya Admin'
      },
      {
        'feature': 'Ekspor Data CSV & Riwayat Arsip',
        'admin': true,
        'sales': true,
        'note': 'Semua Peran'
      },
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.surfaceBorder),
        boxShadow: AppShadow.card,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(4.5),
            1: FlexColumnWidth(2.0),
            2: FlexColumnWidth(2.0),
          },
          border: TableBorder(
            horizontalInside: BorderSide(
              color: AppColors.surfaceBorder.withValues(alpha: 0.6),
              width: 1,
            ),
          ),
          children: [
            // Header Row
            TableRow(
              decoration: const BoxDecoration(
                color: Color(0xFFF1F5F9),
              ),
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text(
                    'Fitur Aplikasi',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: Text(
                    'Admin',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.purple.shade700,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: Text(
                    'Sales',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
            // Data Rows
            ...rows.map((r) {
              final adminCan = r['admin'] as bool;
              final salesCan = r['sales'] as bool;

              return TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r['feature'] as String,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          r['note'] as String,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Center(
                      child: Icon(
                        adminCan
                            ? Icons.check_circle_rounded
                            : Icons.cancel_rounded,
                        color: adminCan
                            ? const Color(0xFF12B886)
                            : const Color(0xFFFA5252),
                        size: 18,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Center(
                      child: Icon(
                        salesCan
                            ? Icons.check_circle_rounded
                            : Icons.cancel_rounded,
                        color: salesCan
                            ? const Color(0xFF12B886)
                            : const Color(0xFFFA5252),
                        size: 18,
                      ),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TAB 2: ALUR OPERASIONAL (STEP-BY-STEP)
  // ==========================================
  Widget _buildFlowTab() {
    final isAdmin = AuthService.currentUser?.isAdmin == true;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenMargin),
      children: [
        // HERO CARD: Tur Visual
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            gradient: AppColors.omzetGradient,
            borderRadius: BorderRadius.circular(AppRadius.card),
            boxShadow: AppShadow.elevated,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_stories,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Alur Kerja Sales Kencana',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '6 langkah terpadu operasional kasir & penjualan',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () => showAppTourDialog(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: const Size(0, 36),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.chipFull),
                  ),
                ),
                child: const Text(
                  'Tur Visual',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        // SECTION HEADER
        const Text(
          'Langkah-Langkah Operasional Kasir',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Ikuti urutan langkah di bawah ini untuk kelancaran transaksi:',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // STEP 1: KELOLA STOK (KHUSUS ADMIN)
        _stepCard(
          stepNumber: 1,
          tagText: 'KHUSUS ADMIN',
          tagColor: Colors.purple,
          icon: Icons.inventory_2_outlined,
          color: const Color(0xFF3B5BDB),
          bgColor: const Color(0xFFEDF2FF),
          title: 'Input & Tambah Stok Produk (Gudang)',
          description:
              'Sebelum armada sales berangkat atau kasir melayani toko, pastikan stok fisik di gudang tercatat di sistem:\n\n'
              '• Set Stok Awal: Menetapkan jumlah stok dasar fisik dari awal (mereset baseline).\n'
              '• Tambah Stok Masuk: Jika ada pasokan baru, gunakan form ini. Jumlah baru akan DITAMBAHKAN ke sisa stok tanpa mengurangi jumlah barang yang sudah terjual sebelumnya.\n\n'
              'Catatan untuk Sales: Akun Sales tidak perlu menginput stok. Stok yang di-input Admin menjadi kuota bersama yang divalidasi server saat checkout.',
          actionLabel: isAdmin ? 'Buka Menu Input Stok' : null,
          onAction: isAdmin
              ? () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StockInputPage()),
                  )
              : null,
          tips:
              'Admin dapat menggunakan tombol petir (⚡) untuk mengisi 100 stok awal ke semua produk dalam 1 klik.',
        ),
        const SizedBox(height: AppSpacing.cardGap),

        // STEP 2: BUAT NOTA
        _stepCard(
          stepNumber: 2,
          tagText: 'SEMUA PERAN',
          tagColor: AppColors.primary,
          icon: Icons.add_circle_outline,
          color: const Color(0xFF12B886),
          bgColor: const Color(0xFFE6FCF5),
          title: 'Buat Nota Penjualan Baru',
          description:
              'Tekan tombol (+) di tengah dock bawah atau tombol "Buat Nota Baru" di Beranda:\n\n'
              '• Masukkan Nama Pelanggan / Toko & Alamat pengiriman.\n'
              '• Pilih barang dari 13 produk Master Stock Boneva.\n'
              '• Tentukan kuantitas pembelian & bonus promo.\n'
              '• Validasi Stok Otomatis: Jika stok barang 0, sistem TIDAK BISA membuat nota.\n'
              '• Pilih Status Pembayaran: LUNAS (uang kas diterima) atau BON (piutang/tempo).',
          actionLabel: 'Coba Input Nota Baru',
          onAction: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TransactionInputPage(
                onSave: (_) {},
              ),
            ),
          ),
          tips:
              'Nomor nota otomatis berurutan (contoh: Trx-20261027-0001). Nota BON otomatis diberi label merah "NOTA BON" di cetakan struk.',
        ),
        const SizedBox(height: AppSpacing.cardGap),

        // STEP 3: CETAK STRUK & PDF
        _stepCard(
          stepNumber: 3,
          tagText: 'SEMUA PERAN',
          tagColor: AppColors.primary,
          icon: Icons.print_outlined,
          color: const Color(0xFF7950F2),
          bgColor: const Color(0xFFF3F0FF),
          title: 'Cetak Struk Kasir & Kirim Invoice PDF',
          description:
              'Setelah nota berhasil disimpan, aplikasi langsung menampilkan pop-up konfirmasi:\n\n'
              '• Cetak Struk: Hubungkan printer termal Bluetooth 58mm untuk mencetak struk fisik kasir seketika.\n'
              '• Kirim PDF Berstempel: Buat berkas faktur resmi lengkap dengan logo KCA dan stempel basah legalitas, lalu bagikan langsung ke WhatsApp pelanggan.\n'
              '• Identitas Nota: Pada struk dan PDF tertulis jelas apakah statusnya "NOTA LUNAS" atau "NOTA BON".',
          actionLabel: null,
          tips:
              'Hubungkan printer Bluetooth Anda di menu Lainnya > Pengaturan Printer sebelum mulai bertransaksi.',
        ),
        const SizedBox(height: AppSpacing.cardGap),

        // STEP 4: MONITORING & PELUNASAN BON
        _stepCard(
          stepNumber: 4,
          tagText: 'MENU BARU',
          tagColor: const Color(0xFFE03131),
          icon: Icons.payment_outlined,
          color: const Color(0xFFE03131),
          bgColor: const Color(0xFFFFF5F5),
          title: 'Monitoring & Pelunasan Bon Piutang',
          description:
              'Kelola penagihan nota piutang yang belum terbayar di menu "Pelunasan":\n\n'
              '1. Buka menu Pelunasan (tersedia di Beranda atau Tab Lainnya).\n'
              '2. Cari nama toko atau nomor nota bon yang ingin dilunasi.\n'
              '3. Tekan tombol "Pelunasan" berwarna hijau pada kartu transaksi.\n'
              '4. Pilih Tanggal Pelunasan sesuai saat uang kas diterima.\n'
              '5. Tekan "Simpan Pelunasan" -> Aplikasi langsung otomatis mencetak struk bukti pelunasan dengan keterangan Tanggal Pelunasan!',
          actionLabel: AuthService.currentUser?.isAdmin == true
              ? 'Buka Monitoring Pelunasan'
              : null,
          onAction: AuthService.currentUser?.isAdmin == true
              ? () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PelunasanPage()),
                  )
              : null,
          tips:
              'Riwayat pelunasan tersinkronisasi ganda ke database server dan memori lokal HP sehingga aman dari kehilangan data.',
        ),
        const SizedBox(height: AppSpacing.cardGap),

        // STEP 5: LAPORAN & OMZET
        _stepCard(
          stepNumber: 5,
          tagText: 'SEMUA PERAN',
          tagColor: AppColors.primary,
          icon: Icons.bar_chart_outlined,
          color: const Color(0xFFF59F00),
          bgColor: const Color(0xFFFFF4E0),
          title: 'Pantau Omzet & Laporan Penjualan',
          description:
              'Tinjau performa keuangan harian di Tab Laporan:\n\n'
              '• Pemisahan Omzet Kasir: Laporan menampilkan Total Omzet, Omzet Lunas (Uang Kas Masuk), dan Omzet Belum Lunas (Bon Piutang).\n'
              '• Rekap Per Sales (Khusus Admin): Filter omzet dan unit terjual berdasarkan masing-masing sales armada.\n'
              '• Rekap Per Unit: Lihat berapa banyak dus/botol Boneva yang terjual per varian.\n'
              '• Cetak Rekap Shift: Cetak ringkasan kasir harian ke printer termal.',
          actionLabel: 'Buka Laporan Harian',
          onAction: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  DailyReportDetailPage(selectedDate: DateTime.now()),
            ),
          ),
          tips:
              'Sales dapat melihat omzet dan total barang terjual miliknya sendiri untuk memantau target harian.',
        ),
        const SizedBox(height: AppSpacing.cardGap),

        // STEP 6: ARSIP & CADANGAN CLOUD
        _stepCard(
          stepNumber: 6,
          tagText: 'FAILOVER AMAN',
          tagColor: const Color(0xFF0C9488),
          icon: Icons.cloud_sync_outlined,
          color: const Color(0xFF0C9488),
          bgColor: const Color(0xFFE6FCF5),
          title: 'Cadangan Supabase, Offline Queue & Arsip CSV',
          description:
              'Aplikasi memiliki proteksi multi-lapis agar data penjualan tidak pernah hilang:\n\n'
              '• Dual-Server Failover: Jika server utama Laravel mengalami kendala, data transaksi otomatis masuk ke database cadangan Supabase Cloud.\n'
              '• Offline Queue: Jika bertransaksi di blank spot tanpa internet, nota tersimpan di HP dan otomatis sinkron saat ada koneksi.\n'
              '• Arsip Lokal CSV: Unduh berkas CSV rekapan transaksi di Tab Transaksi > Ikon Arsip untuk pembukuan Excel.',
          actionLabel: 'Buka Arsip Lokal',
          onAction: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ArchivePage()),
          ),
          tips:
              'Status koneksi server utama dan database cadangan dapat dipantau langsung di bagian atas Beranda.',
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _stepCard({
    required int stepNumber,
    required String tagText,
    required Color tagColor,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required String title,
    required String description,
    required String? actionLabel,
    VoidCallback? onAction,
    String? tips,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.surfaceBorder),
        boxShadow: AppShadow.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step Badge + Header
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$stepNumber',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: tagColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            tagText,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: tagColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Deskripsi
          Text(
            description,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textPrimary,
              height: 1.5,
            ),
          ),

          // Tips Box
          if (tips != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.lightbulb_outline,
                    size: 16,
                    color: AppColors.bon,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tips,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Tombol Coba Aksi
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: Text(actionLabel),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  side: BorderSide(color: color),
                  foregroundColor: color,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==========================================
  // TAB 3: TIPS & TANYA JAWAB (FAQ)
  // ==========================================
  Widget _buildFaqTab() {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenMargin),
      children: [
        const Text(
          'Pertanyaan Umum & Solusi Kendala',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Jawaban praktis seputar wewenang peran, stok, nota, dan pelunasan:',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        _faqAccordion(
          question: 'Apa perbedaan mendasar akun Admin dan Sales?',
          answer:
              '• Admin: Bertindak sebagai manajemen & logistik gudang. Menginput stok awal, menambah pasokan stok, memantau omzet seluruh sales armada, dan melihat pembagian omzet lunas vs bon secara terpisah.\n\n'
              '• Sales: Bertindak sebagai pelaksana penjualan lapangan. Membuat nota penjualan toko, menagih bon di lapangan, serta mencetak struk fisik. Sales tidak dapat melihat angka nominal stok gudang demi keamanan privasi perusahaan, namun tetap bisa melihat omzet dan unit yang telah ia jual.',
        ),
        const SizedBox(height: AppSpacing.cardGap),

        _faqAccordion(
          question:
              'Mengapa akun Sales tidak bisa melihat angka nominal stok gudang?',
          answer:
              'Hal ini merupakan aturan bisnis (*business rule*) untuk menjaga kerahasiaan inventaris gudang pusat. Sales hanya diberikan indikator status ketersediaan:\n\n'
              '• "Stok Tersedia" (warna hijau): Barang siap dipesan.\n'
              '• "Stok Habis (0)" (warna merah): Barang tidak dapat dicheckout.\n\n'
              'Dengan demikian, sales tetap memiliki kepastian barang ada atau tidak tanpa mengetahui total isi gudang perusahaan.',
        ),
        const SizedBox(height: AppSpacing.cardGap),

        _faqAccordion(
          question:
              'Apa yang terjadi jika stok barang 0 saat kasir ingin buat nota?',
          answer:
              'Sistem secara ketat MEMBLOKIR checkout nota apabila stok produk bernilai 0. Tombol simpan akan menolak transaksi dan menampilkan pesan peringatan.\n\n'
              'Solusi: Hubungi Admin untuk menginput tambahan stok masuk fisik di menu Manajemen Stok.',
        ),
        const SizedBox(height: AppSpacing.cardGap),

        _faqAccordion(
          question:
              'Bagaimana cara Admin menambah stok baru tanpa mengurangi barang yang sudah laku?',
          answer:
              'Aplikasi menyediakan 2 formulir berbeda di menu Manajemen Stok:\n\n'
              '1. Form "Tambah Stok Masuk" (Disarankan untuk barang datang): Jumlah yang diinput akan langsung DITAMBAHKAN ke sisa stok yang ada saat ini. Data penjualan lalu sama sekali tidak terganggu.\n\n'
              '2. Form "Setel Stok Awal": Digunakan hanya saat pertama kali instalasi atau stock opname fisik ulang untuk menetapkan angka dasar awal produk.',
        ),
        const SizedBox(height: AppSpacing.cardGap),

        _faqAccordion(
          question: 'Bagaimana alur melunasi transaksi BON sekarang?',
          answer:
              'Pelunasan bon kini memiliki menu khusus "Pelunasan" (bisa diakses di Beranda atau Tab Lainnya):\n\n'
              '1. Buka menu Pelunasan untuk melihat daftar transaksi bon yang belum terbayar.\n'
              '2. Cari nama toko pelanggan yang sedang ditagih.\n'
              '3. Tekan tombol hijau "Pelunasan".\n'
              '4. Pilih tanggal pembayaran saat uang diterima.\n'
              '5. Tekan "Simpan Pelunasan" -> Sistem langsung mengupdate status menjadi LUNAS, mencatat tanggal pelunasan, dan otomatis mencetak struk tanda lunas ke printer Bluetooth!',
        ),
        const SizedBox(height: AppSpacing.cardGap),

        _faqAccordion(
          question:
              'Apakah struk fisik dan invoice PDF membedakan NOTA BON dan NOTA LUNAS?',
          answer:
              'Ya! Pada struk kasir termal 58mm maupun faktur PDF resmi:\n\n'
              '• Jika belum lunas, tertera tulisan tegas: "NOTA BON".\n'
              '• Jika sudah lunas, tertera tulisan: "NOTA LUNAS".\n'
              '• Jika nota tersebut berasal dari pelunasan bon, struk akan mencantumkan baris khusus "Tgl Pelunasan: [Tanggal Bayar]" sebagai bukti sah.',
        ),
        const SizedBox(height: AppSpacing.cardGap),

        _faqAccordion(
          question:
              'Bagaimana jika server utama mati atau tidak ada sinyal internet?',
          answer:
              'Aplikasi Sales Kencana v3 memiliki proteksi ganda:\n\n'
              '1. Failover Supabase: Saat server Laravel bermasalah, aplikasi otomatis mengirim data ke Supabase Cloud PostgreSQL.\n'
              '2. Offline Queue: Jika tidak ada internet sama sekali, nota disimpan di memori HP dan struk Bluetooth tetap bisa dicetak langsung di toko. Begitu HP mendapat koneksi internet, data otomatis terkirim ke server!',
        ),
        const SizedBox(height: AppSpacing.cardGap),

        _faqAccordion(
          question: 'Bagaimana cara menghubungkan printer termal Bluetooth?',
          answer:
              '1. Pastikan Bluetooth di smartphone menyala dan printer termal dalam kondisi ON.\n'
              '2. Buka Tab Lainnya > pilih Pengaturan Printer.\n'
              '3. Tekan "Cari Perangkat Bluetooth" (Scan).\n'
              '4. Pilih nama printer Anda (contoh: RPP02N, Thermal_Printer, MPT-II, dll.) lalu tekan Connect.\n'
              '5. Setelah status "Terhubung", printer siap mencetak struk nota dan bukti pelunasan.',
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _faqAccordion({
    required String question,
    required String answer,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.surfaceBorder),
        boxShadow: AppShadow.card,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.question_answer_outlined,
              size: 18,
              color: AppColors.primary,
            ),
          ),
          title: Text(
            question,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  answer,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// ONBOARDING TOUR MODAL CAROUSEL
// ==========================================
void showAppTourDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => const _AppTourModal(),
  );
}

class _AppTourModal extends StatefulWidget {
  const _AppTourModal();

  @override
  State<_AppTourModal> createState() => _AppTourModalState();
}

class _AppTourModalState extends State<_AppTourModal> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, dynamic>> _slides = [
    {
      'title': 'Selamat Datang di Sales Kencana',
      'subtitle':
          'Sistem Kasir & Distribusi Boneva resmi UD. Kencana Cahaya Amanah dengan peran Admin & Sales terintegrasi.',
      'icon': Icons.storefront,
      'color': const Color(0xFF3B5BDB),
      'bgColor': const Color(0xFFEDF2FF),
      'points': [
        'Dua peran terpadu: Manajemen Admin & Sales Lapangan',
        'Validasi kuota stok ketat (blokir jika 0)',
        'Cetak struk Bluetooth 58mm & PDF faktur berstempel',
      ],
    },
    {
      'title': 'Peran Admin vs Sales Armada',
      'subtitle':
          'Pembagian wewenang yang aman untuk menjaga privasi stok dan kelancaran operasional.',
      'icon': Icons.badge_outlined,
      'color': const Color(0xFF7950F2),
      'bgColor': const Color(0xFFF3F0FF),
      'points': [
        'Admin: Kelola stok gudang, pantau omzet tim & rekap',
        'Sales: Buat nota, tagih bon toko & cetak struk',
        'Privasi: Angka stok gudang terlindungi dari sales',
      ],
    },
    {
      'title': 'Langkah 1: Input & Tambah Stok',
      'subtitle':
          'Admin menginput stok awal dan pasokan stok baru tanpa memotong data barang terjual.',
      'icon': Icons.inventory_2_outlined,
      'color': const Color(0xFF12B886),
      'bgColor': const Color(0xFFE6FCF5),
      'points': [
        'Form "Tambah Stok Masuk" akumulatif ke stok sisa',
        'Isi cepat 100 stok massal dengan tombol petir',
        'Stok tersinkronisasi ke server utama & failover cloud',
      ],
    },
    {
      'title': 'Langkah 2: Buat Nota & Cetak',
      'subtitle':
          'Kasir kilat dengan status NOTA LUNAS atau NOTA BON serta nomor nota otomatis.',
      'icon': Icons.receipt_long,
      'color': const Color(0xFFF59F00),
      'bgColor': const Color(0xFFFFF4E0),
      'points': [
        'Pilih 13 varian produk Boneva & bonus promo',
        'Otomatis tertera label "NOTA BON" atau "NOTA LUNAS"',
        'Cetak langsung ke printer kasir atau kirim PDF WhatsApp',
      ],
    },
    {
      'title': 'Langkah 3: Menu Pelunasan Bon',
      'subtitle':
          'Monitoring piutang pelanggan dan pelunasan seketika dengan cetak bukti struk otomatis.',
      'icon': Icons.payment_outlined,
      'color': const Color(0xFFE03131),
      'bgColor': const Color(0xFFFFF5F5),
      'points': [
        'Daftar nota piutang bon siap ditagih di lapangan',
        'Tentukan tanggal uang kas diterima',
        'Otomatis langsung cetak struk tanda lunas di printer',
      ],
    },
    {
      'title': 'Langkah 4: Laporan & Failover Cloud',
      'subtitle':
          'Rekap omzet terpisah (Lunas vs Bon) serta ketahanan data dengan Supabase & Offline Queue.',
      'icon': Icons.insights,
      'color': const Color(0xFF0C9488),
      'bgColor': const Color(0xFFE6FCF5),
      'points': [
        'Admin melihat pemisahan omzet kas vs piutang bon',
        'Sales memantau omzet & jumlah unit terjual pribadi',
        'Transaksi offline otomatis tersinkron begitu online',
      ],
    },
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: Column(
          children: [
            // Slide Content
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (idx) => setState(() => _currentPage = idx),
                itemBuilder: (ctx, index) {
                  final s = _slides[index];
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: s['bgColor'],
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          s['icon'],
                          size: 38,
                          color: s['color'],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        s['title'],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        s['subtitle'],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.surfaceBorder),
                        ),
                        child: Column(
                          children: (s['points'] as List<String>)
                              .map(
                                (pt) => Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 3),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.check_circle_rounded,
                                        size: 16,
                                        color: s['color'],
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          pt,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 14),

            // Indicator Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _slides.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _currentPage == i ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _currentPage == i
                        ? AppColors.primary
                        : AppColors.surfaceBorder,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 18),

            // Navigation Buttons
            Row(
              children: [
                if (_currentPage < _slides.length - 1) ...[
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Lewati'),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Lanjut'),
                        SizedBox(width: 6),
                        Icon(Icons.arrow_forward, size: 16),
                      ],
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Mulai Gunakan Kasir'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
