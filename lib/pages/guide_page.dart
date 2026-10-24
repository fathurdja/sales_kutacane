import 'package:flutter/material.dart';
import 'package:kasir_kutacane/pages/arsip.dart';
import 'package:kasir_kutacane/pages/dailyreport.dart';
import 'package:kasir_kutacane/pages/stock_input_page.dart';
import 'package:kasir_kutacane/pages/transactionInput.dart';
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
    _tabController = TabController(length: 2, vsync: this);
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
        title: const Text('Panduan & Alur Kasir'),
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
          tabs: const [
            Tab(
              icon: Icon(Icons.timeline, size: 20),
              text: 'Alur Operasional',
            ),
            Tab(
              icon: Icon(Icons.help_center_outlined, size: 20),
              text: 'Tips & Tanya Jawab',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFlowTab(),
          _buildFaqTab(),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 1: ALUR OPERASIONAL (STEP-BY-STEP)
  // ==========================================
  Widget _buildFlowTab() {
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
                      '5 langkah terpadu operasional kasir harian',
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
          'Langkah-Langkah Operasional',
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

        // STEP 1
        _stepCard(
          stepNumber: 1,
          icon: Icons.inventory_2_outlined,
          color: const Color(0xFF3B5BDB),
          bgColor: const Color(0xFFEDF2FF),
          title: 'Periksa & Input Stok Produk',
          description:
              'Sebelum melayani pelanggan, pastikan stok fisik di toko atau gudang sudah terisi pada sistem. Stok ini divalidasi langsung oleh server saat checkout nota.',
          actionLabel: 'Buka Menu Input Stok',
          onAction: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const StockInputPage()),
          ),
          tips:
              'Tips: Gunakan tombol petir (⚡) di halaman stok untuk mengisi 100 stok awal ke seluruh produk dalam 1 klik.',
        ),
        const SizedBox(height: AppSpacing.cardGap),

        // STEP 2
        _stepCard(
          stepNumber: 2,
          icon: Icons.add_circle_outline,
          color: const Color(0xFF12B886),
          bgColor: const Color(0xFFE6FCF5),
          title: 'Buat Nota Penjualan Baru',
          description:
              'Tekan tombol (+) di tengah dock bawah atau tombol "Buat Nota Baru" di Beranda.\n\n'
              '• Masukkan Nama Pelanggan & Alamat pengiriman.\n'
              '• Pilih barang dari 13 produk Master Stock Boneva.\n'
              '• Isi kuantitas pembelian dan bonus (jika ada promo).\n'
              '• Tentukan Status Pembayaran: LUNAS (uang diterima) atau BON (piutang/tempo).',
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
              'ID Transaksi dibuat otomatis secara berurutan dan unik berdasarkan tanggal (misal: Trx-20261024-0001).',
        ),
        const SizedBox(height: AppSpacing.cardGap),

        // STEP 3
        _stepCard(
          stepNumber: 3,
          icon: Icons.print_outlined,
          color: const Color(0xFF7950F2),
          bgColor: const Color(0xFFF3F0FF),
          title: 'Cetak Struk & Kirim Invoice PDF',
          description:
              'Setelah nota berhasil disimpan, aplikasi langsung menampilkan pop-up konfirmasi dengan opsi:\n\n'
              '• Cetak Struk: Hubungkan printer termal Bluetooth 58mm untuk mencetak struk fisik kasir.\n'
              '• Kirim PDF: Buat berkas nota berstempel resmi "Kencana Cahaya Amanah" dan bagikan langsung ke WhatsApp pelanggan.',
          actionLabel: null,
          tips:
              'Koneksikan printer Bluetooth Anda di Tab Lainnya > Pengaturan Printer terlebih dahulu.',
        ),
        const SizedBox(height: AppSpacing.cardGap),

        // STEP 4
        _stepCard(
          stepNumber: 4,
          icon: Icons.bar_chart_outlined,
          color: const Color(0xFFF59F00),
          bgColor: const Color(0xFFFFF4E0),
          title: 'Pantau Transaksi & Laporan Harian',
          description:
              'Masuk ke tab "Transaksi" atau "Laporan" untuk meninjau rekapan:\n\n'
              '• Tab Transaksi: Cari nota, filter hari ini, minggu ini, atau nota berstatus BON.\n'
              '• Tab Laporan: Lihat total omzet per hari, kalender tanggal, serta cetak rekap shift harian.',
          actionLabel: 'Buka Laporan Harian',
          onAction: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  DailyReportDetailPage(selectedDate: DateTime.now()),
            ),
          ),
          tips:
              'Klik pada kartu nota untuk melihat rincian item, mengedit status pembayaran, atau menghapus nota.',
        ),
        const SizedBox(height: AppSpacing.cardGap),

        // STEP 5
        _stepCard(
          stepNumber: 5,
          icon: Icons.archive_outlined,
          color: const Color(0xFFE03131),
          bgColor: const Color(0xFFFFF5F5),
          title: 'Arsipkan Data ke File CSV/Excel',
          description:
              'Lakukan pencadangan berkala untuk pembukuan akuntansi:\n\n'
              '• Export CSV: Buka Tab Transaksi > Ikon Arsip untuk menyimpan seluruh data penjualan ke berkas CSV lokal.\n'
              '• Import Transaksi: Tab Lainnya > Import Transaksi Lama untuk membuka berkas Excel (.xlsx) atau CSV lama.',
          actionLabel: 'Buka Arsip Lokal',
          onAction: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ArchivePage()),
          ),
          tips:
              'Berkas CSV tersimpan aman di direktori aplikasi smartphone Anda dan dapat dibagikan kapan saja.',
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _stepCard({
    required int stepNumber,
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
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
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
  // TAB 2: TIPS & TANYA JAWAB (FAQ)
  // ==========================================
  Widget _buildFaqTab() {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenMargin),
      children: [
        const Text(
          'Pertanyaan Umum & Tips Kasir',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Jawaban praktis seputar penggunaan dan kendala teknis:',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        _faqAccordion(
          question: 'Bagaimana cara mengubah status BON menjadi LUNAS?',
          answer:
              '1. Buka Tab Transaksi (ikon struk).\n'
              '2. Gunakan filter cepat "BON" untuk menampilkan semua pelanggan yang belum membayar.\n'
              '3. Ketuk kartu transaksi yang ingin dilunasi.\n'
              '4. Di halaman Detail Nota, tekan tombol ikon Pensil (Edit Nota) di pojok kanan atas.\n'
              '5. Ubah opsi status pembayaran dari BON menjadi LUNAS, lalu simpan.',
        ),
        const SizedBox(height: AppSpacing.cardGap),

        _faqAccordion(
          question: 'Apa yang harus dilakukan jika muncul "Stock tidak mencukupi"?',
          answer:
              'Server memvalidasi ketersediaan stok produk Boneva secara otomatis sebelum nota disimpan.\n\n'
              'Solusi: Masuk ke halaman "Input Stok" (tersedia di Beranda atau Tab Lainnya), pilih produk yang bersangkutan, lalu tambahkan jumlah stok barang fisik yang ada.',
        ),
        const SizedBox(height: AppSpacing.cardGap),

        _faqAccordion(
          question: 'Bagaimana jika server offline / tidak ada internet saat input nota?',
          answer:
              'Aplikasi Sales Kencana v2 memiliki fitur Local Backup & Offline Queue mandiri:\n\n'
              '1. Transaksi Tetap Berjalan: Jika server mati atau tidak ada sinyal internet, transaksi TIDAK AKAN DIBLOKIR. Nota akan otomatis disimpan ke memori internal HP kasir dengan tanda "OFFLINE".\n'
              '2. Produk Tetap Muncul: Seluruh 13 produk Boneva sudah dicache di HP, sehingga Anda tetap bisa memilih barang dan menentukan harga.\n'
              '3. Cetak Struk & PDF Tetap Berfungsi: Struk termal Bluetooth dan PDF faktur dapat langsung dicetak atau dibagikan ke pelanggan saat itu juga.\n'
              '4. Sinkronisasi Otomatis saat Online: Saat server kembali menyala atau ada koneksi, akan muncul banner "Nota Tersimpan di HP" di Beranda dan Tab Transaksi. Cukup ketuk "Hubungkan / Sinkronkan", seluruh transaksi offline akan langsung terkirim ke database server!',
        ),
        const SizedBox(height: AppSpacing.cardGap),

        _faqAccordion(
          question: 'Cara menghubungkan Printer Termal Bluetooth:',
          answer:
              '1. Pastikan Bluetooth di smartphone Anda aktif dan Printer Termal dalam keadaan menyala (ON).\n'
              '2. Buka Tab Lainnya > pilih Pengaturan Printer.\n'
              '3. Tekan "Cari Perangkat Bluetooth" (Scan).\n'
              '4. Pilih nama printer (misal: RPP02N, Thermal_Printer, MPT-II, dst.) lalu pilih Connect.\n'
              '5. Setelah terhubung, struk dapat langsung dicetak dari dialog simpan atau detail nota.',
        ),
        const SizedBox(height: AppSpacing.cardGap),

        _faqAccordion(
          question: 'Cara mengirim Invoice PDF resmi ke WhatsApp konsumen:',
          answer:
              '1. Setelah menyimpan nota, tekan tombol "Kirim PDF" pada dialog berhasil.\n'
              '2. Atau buka transaksi dari daftar nota > tekan tombol "Kirim PDF Berstempel".\n'
              '3. Aplikasi akan merender PDF ukuran A4/A5 resmi lengkap dengan logo Kencana, rincian barang, dan cap stempel legalitas.\n'
              '4. Pilih aplikasi WhatsApp dan kirim ke kontak konsumen.',
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
          'Aplikasi kasir & distribusi resmi Kencana Cahaya Amanah. Dirancang modern, cepat, dan mudah digunakan.',
      'icon': Icons.storefront,
      'color': const Color(0xFF3B5BDB),
      'bgColor': const Color(0xFFEDF2FF),
      'points': [
        'Sinkronisasi Master Stock Boneva aktif',
        'Pencatatan nota LUNAS & BON terpadu',
        'Cetak struk bluetooth & Invoice PDF stempel',
      ],
    },
    {
      'title': 'Langkah 1: Input & Cek Stok',
      'subtitle':
          'Pastikan barang di gudang sudah tercatat agar validasi checkout berjalan lancar.',
      'icon': Icons.inventory_2_outlined,
      'color': const Color(0xFF12B886),
      'bgColor': const Color(0xFFE6FCF5),
      'points': [
        'Buka menu "Input Stok" dari Beranda',
        'Tambah stok masuk atau setel stok fisik',
        'Gunakan fitur isi massal 100 stok cepat',
      ],
    },
    {
      'title': 'Langkah 2: Buat & Cetak Nota',
      'subtitle':
          'Proses kasir kilat dengan nomor nota otomatis dan pemilihan produk mudah.',
      'icon': Icons.receipt_long,
      'color': const Color(0xFF7950F2),
      'bgColor': const Color(0xFFF3F0FF),
      'points': [
        'Tekan tombol (+) untuk nota baru',
        'Pilih barang & tentukan status LUNAS/BON',
        'Cetak langsung ke printer termal atau kirim PDF',
      ],
    },
    {
      'title': 'Langkah 3: Laporan & Arsip',
      'subtitle':
          'Pantau omzet harian dan amankan riwayat penjualan ke format CSV / Excel.',
      'icon': Icons.insights,
      'color': const Color(0xFFF59F00),
      'bgColor': const Color(0xFFFFF4E0),
      'points': [
        'Cek total omzet harian di Beranda & Tab Laporan',
        'Kelola piutang BON pelanggan dengan mudah',
        'Export data penjualan ke berkas CSV kapan saja',
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
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 540),
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
                      const SizedBox(height: 18),
                      Text(
                        s['title'],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        s['subtitle'],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 18),
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

            const SizedBox(height: 16),

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

            const SizedBox(height: 20),

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
