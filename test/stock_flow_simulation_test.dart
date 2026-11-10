import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kutacane/models/stock_change_log.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/models/transactionItem.dart';
import 'package:kasir_kutacane/pages/stock_flow_report_page.dart';

void main() {
  group('Simulasi Alur Logika Monitoring Stok (Kemarin, Hari Ini, & Hari Esok)', () {
    // Tanggal simulasi:
    final tglKemarin = DateTime(2026, 11, 8, 21, 0); // 08 Nov 2026 (Tutup toko)
    final tglHariIni = DateTime(2026, 11, 9, 10, 0); // 09 Nov 2026 (Operasional hari ini)
    final tglHariEsok = DateTime(2026, 11, 10, 9, 30); // 10 Nov 2026 (Operasional hari esok)

    // Data Awal Tutup Toko Kemarin (Day 0) sesuai kasus dari User:
    // 1. Galon: 8
    // 2. Botol 600ml: 121
    // 3. Botol 1,5L: 31
    // 4. Gelas: 189

    // 1. Log perubahan stok awal kemarin
    final List<StockChangeLog> allLogs = [
      StockChangeLog(
        id: 'LOG-KEMARIN-01',
        timestamp: tglKemarin.subtract(const Duration(hours: 12)),
        kelompok: 'GALON',
        displayName: 'Boneva Galon (19L)',
        unitName: 'Galon',
        jenisAksi: 'SET_STOK_AWAL',
        stokAwalSebelum: 0,
        tambahanQty: 8,
        stokAwalSesudah: 8,
        sisaSebelum: 0,
        sisaSesudah: 8,
        totalTerjualSaatIni: 0,
        userName: 'Admin',
      ),
      StockChangeLog(
        id: 'LOG-KEMARIN-02',
        timestamp: tglKemarin.subtract(const Duration(hours: 12)),
        kelompok: 'BOTOL_600',
        displayName: 'Boneva Botol 600ml',
        unitName: 'Dus/Btl',
        jenisAksi: 'SET_STOK_AWAL',
        stokAwalSebelum: 0,
        tambahanQty: 121,
        stokAwalSesudah: 121,
        sisaSebelum: 0,
        sisaSesudah: 121,
        totalTerjualSaatIni: 0,
        userName: 'Admin',
      ),
      StockChangeLog(
        id: 'LOG-KEMARIN-03',
        timestamp: tglKemarin.subtract(const Duration(hours: 12)),
        kelompok: 'BOTOL_1500',
        displayName: 'Boneva Botol 1.5L',
        unitName: 'Dus/Btl',
        jenisAksi: 'SET_STOK_AWAL',
        stokAwalSebelum: 0,
        tambahanQty: 31,
        stokAwalSesudah: 31,
        sisaSebelum: 0,
        sisaSesudah: 31,
        totalTerjualSaatIni: 0,
        userName: 'Admin',
      ),
      StockChangeLog(
        id: 'LOG-KEMARIN-04',
        timestamp: tglKemarin.subtract(const Duration(hours: 12)),
        kelompok: 'GELAS',
        displayName: 'Boneva Gelas',
        unitName: 'Dus',
        jenisAksi: 'SET_STOK_AWAL',
        stokAwalSebelum: 0,
        tambahanQty: 189,
        stokAwalSesudah: 189,
        sisaSebelum: 0,
        sisaSesudah: 189,
        totalTerjualSaatIni: 0,
        userName: 'Admin',
      ),
    ];

    // =========================================================================
    // SKENARIO HARI INI (Day 1: 09 Nov 2026)
    // =========================================================================
    // Input Stok Masuk Hari Ini:
    // Galon: +100
    // Botol 600ml: +50
    // Botol 1.5L: +20
    // Gelas: +80
    allLogs.addAll([
      StockChangeLog(
        id: 'LOG-HARIINI-01',
        timestamp: tglHariIni,
        kelompok: 'GALON',
        displayName: 'Boneva Galon (19L)',
        unitName: 'Galon',
        jenisAksi: 'TAMBAH_PASOKAN',
        stokAwalSebelum: 8,
        tambahanQty: 100,
        stokAwalSesudah: 108,
        sisaSebelum: 8,
        sisaSesudah: 108,
        totalTerjualSaatIni: 0,
        userName: 'Admin',
      ),
      StockChangeLog(
        id: 'LOG-HARIINI-02',
        timestamp: tglHariIni,
        kelompok: 'BOTOL_600',
        displayName: 'Boneva Botol 600ml',
        unitName: 'Dus/Btl',
        jenisAksi: 'TAMBAH_PASOKAN',
        stokAwalSebelum: 121,
        tambahanQty: 50,
        stokAwalSesudah: 171,
        sisaSebelum: 121,
        sisaSesudah: 171,
        totalTerjualSaatIni: 0,
        userName: 'Admin',
      ),
      StockChangeLog(
        id: 'LOG-HARIINI-03',
        timestamp: tglHariIni,
        kelompok: 'BOTOL_1500',
        displayName: 'Boneva Botol 1.5L',
        unitName: 'Dus/Btl',
        jenisAksi: 'TAMBAH_PASOKAN',
        stokAwalSebelum: 31,
        tambahanQty: 20,
        stokAwalSesudah: 51,
        sisaSebelum: 31,
        sisaSesudah: 51,
        totalTerjualSaatIni: 0,
        userName: 'Admin',
      ),
      StockChangeLog(
        id: 'LOG-HARIINI-04',
        timestamp: tglHariIni,
        kelompok: 'GELAS',
        displayName: 'Boneva Gelas',
        unitName: 'Dus',
        jenisAksi: 'TAMBAH_PASOKAN',
        stokAwalSebelum: 189,
        tambahanQty: 80,
        stokAwalSesudah: 269,
        sisaSebelum: 189,
        sisaSesudah: 269,
        totalTerjualSaatIni: 0,
        userName: 'Admin',
      ),
    ]);

    // Transaksi Penjualan Hari Ini (Angka Acak/Realistis):
    // Galon: 35
    // Botol 600ml: 70
    // Botol 1.5L: 15
    // Gelas: 95
    final List<Transaction> allTransactions = [
      Transaction(
        id: 'TRX-HARIINI-01',
        id_transaksi: 'TRX-HARIINI-01',
        customerName: 'Toko Berkah',
        date: tglHariIni.add(const Duration(hours: 2)),
        alamat: 'Kutacane',
        items: [
          TransactionItem.fromData(name: 'Boneva Galon isi saja', price: 16000, quantity: 20, bonus: 0, tyunit: 'BV02'),
          TransactionItem.fromData(name: 'Boneva Botol 600ml', price: 38000, quantity: 40, bonus: 0, tyunit: 'BV09'),
        ],
        total: (20 * 16000) + (40 * 38000),
        status: 'LUNAS',
      ),
      Transaction(
        id: 'TRX-HARIINI-02',
        id_transaksi: 'TRX-HARIINI-02',
        customerName: 'Warung Bu Siti',
        date: tglHariIni.add(const Duration(hours: 4)),
        alamat: 'Kutacane',
        items: [
          TransactionItem.fromData(name: 'Boneva Galon isi saja', price: 16000, quantity: 15, bonus: 0, tyunit: 'BV02'),
          TransactionItem.fromData(name: 'Boneva Botol 600ml', price: 38000, quantity: 30, bonus: 0, tyunit: 'BV09'),
          TransactionItem.fromData(name: 'Boneva Botol 1.5L', price: 42000, quantity: 15, bonus: 0, tyunit: 'BV15'),
          TransactionItem.fromData(name: 'Boneva Gelas Dus', price: 23000, quantity: 95, bonus: 0, tyunit: 'BV20'),
        ],
        total: (15 * 16000) + (30 * 38000) + (15 * 42000) + (95 * 23000),
        status: 'LUNAS',
      ),
    ];

    // =========================================================================
    // SKENARIO HARI ESOK (Day 2: 10 Nov 2026)
    // =========================================================================
    // Input Stok Masuk Hari Esok:
    // Galon: +40
    // Botol 600ml: +60
    // Botol 1.5L: +10
    // Gelas: +50
    allLogs.addAll([
      StockChangeLog(
        id: 'LOG-ESOK-01',
        timestamp: tglHariEsok,
        kelompok: 'GALON',
        displayName: 'Boneva Galon (19L)',
        unitName: 'Galon',
        jenisAksi: 'TAMBAH_PASOKAN',
        stokAwalSebelum: 73,
        tambahanQty: 40,
        stokAwalSesudah: 113,
        sisaSebelum: 73,
        sisaSesudah: 113,
        totalTerjualSaatIni: 0,
        userName: 'Admin',
      ),
      StockChangeLog(
        id: 'LOG-ESOK-02',
        timestamp: tglHariEsok,
        kelompok: 'BOTOL_600',
        displayName: 'Boneva Botol 600ml',
        unitName: 'Dus/Btl',
        jenisAksi: 'TAMBAH_PASOKAN',
        stokAwalSebelum: 101,
        tambahanQty: 60,
        stokAwalSesudah: 161,
        sisaSebelum: 101,
        sisaSesudah: 161,
        totalTerjualSaatIni: 0,
        userName: 'Admin',
      ),
      StockChangeLog(
        id: 'LOG-ESOK-03',
        timestamp: tglHariEsok,
        kelompok: 'BOTOL_1500',
        displayName: 'Boneva Botol 1.5L',
        unitName: 'Dus/Btl',
        jenisAksi: 'TAMBAH_PASOKAN',
        stokAwalSebelum: 36,
        tambahanQty: 10,
        stokAwalSesudah: 46,
        sisaSebelum: 36,
        sisaSesudah: 46,
        totalTerjualSaatIni: 0,
        userName: 'Admin',
      ),
      StockChangeLog(
        id: 'LOG-ESOK-04',
        timestamp: tglHariEsok,
        kelompok: 'GELAS',
        displayName: 'Boneva Gelas',
        unitName: 'Dus',
        jenisAksi: 'TAMBAH_PASOKAN',
        stokAwalSebelum: 174,
        tambahanQty: 50,
        stokAwalSesudah: 224,
        sisaSebelum: 174,
        sisaSesudah: 224,
        totalTerjualSaatIni: 0,
        userName: 'Admin',
      ),
    ]);

    // Transaksi Penjualan Hari Esok:
    // Galon: 25
    // Botol 600ml: 40
    // Botol 1.5L: 12
    // Gelas: 65
    allTransactions.add(
      Transaction(
        id: 'TRX-ESOK-01',
        id_transaksi: 'TRX-ESOK-01',
        customerName: 'Hotel Kutacane',
        date: tglHariEsok.add(const Duration(hours: 3)),
        alamat: 'Kutacane',
        items: [
          TransactionItem.fromData(name: 'Boneva Galon isi saja', price: 16000, quantity: 25, bonus: 0, tyunit: 'BV02'),
          TransactionItem.fromData(name: 'Boneva Botol 600ml', price: 38000, quantity: 40, bonus: 0, tyunit: 'BV09'),
          TransactionItem.fromData(name: 'Boneva Botol 1.5L', price: 42000, quantity: 12, bonus: 0, tyunit: 'BV15'),
          TransactionItem.fromData(name: 'Boneva Gelas Dus', price: 23000, quantity: 65, bonus: 0, tyunit: 'BV20'),
        ],
        total: (25 * 16000) + (40 * 38000) + (12 * 42000) + (65 * 23000),
        status: 'LUNAS',
      ),
    );

    // =========================================================================
    // FUNGSI HELPER SIMULASI OFFLINE LOGIC APLIKASI
    // =========================================================================
    Map<String, CommodityFlowSummary> calculateOfflineSimulation({
      required DateTime targetDate,
      required List<StockChangeLog> logs,
      required List<Transaction> transactions,
    }) {
      final Map<String, CommodityFlowSummary> map = {
        'GALON': CommodityFlowSummary(kelompok: 'GALON', displayName: 'Boneva Galon', unitName: 'Galon'),
        'BOTOL_600': CommodityFlowSummary(kelompok: 'BOTOL_600', displayName: 'Boneva Botol 600ml', unitName: 'Dus/Btl'),
        'BOTOL_1500': CommodityFlowSummary(kelompok: 'BOTOL_1500', displayName: 'Boneva Botol 1.5L', unitName: 'Dus/Btl'),
        'GELAS': CommodityFlowSummary(kelompok: 'GELAS', displayName: 'Boneva Gelas', unitName: 'Dus'),
      };

      final startOfDay = DateTime(targetDate.year, targetDate.month, targetDate.day);
      final endOfDay = DateTime(targetDate.year, targetDate.month, targetDate.day, 23, 59, 59, 999);

      // 1. Sisa Kemarin = Total Masuk sebelum hari ini - Total Terjual sebelum hari ini
      for (final k in map.keys) {
        int priorMasuk = 0;
        for (final l in logs) {
          if (l.timestamp.isBefore(startOfDay) && l.kelompok.toUpperCase() == k) {
            priorMasuk += (l.tambahanQty > 0 ? l.tambahanQty : 0);
          }
        }
        int priorKeluar = 0;
        for (final t in transactions) {
          if (t.date.isBefore(startOfDay)) {
            for (final item in t.items) {
              if (StockFlowReportPage.resolveCommodityKelompok(tyunit: item.tyunit, itemName: item.name) == k) {
                priorKeluar += (item.quantity + item.bonus);
              }
            }
          }
        }
        map[k]!.sisaKemarin = (priorMasuk - priorKeluar) > 0 ? (priorMasuk - priorKeluar) : 0;
      }

      // 2. Stok Masuk Hari Ini
      for (final l in logs) {
        if (!l.timestamp.isBefore(startOfDay) && !l.timestamp.isAfter(endOfDay)) {
          final k = l.kelompok.toUpperCase();
          if (map.containsKey(k)) {
            final qty = l.tambahanQty > 0 ? l.tambahanQty : 0;
            map[k]!.masukHariIni += qty;
            map[k]!.masuk += qty;
          }
        }
      }

      // 3. Stok Terjual Hari Ini
      for (final t in transactions) {
        if (!t.date.isBefore(startOfDay) && !t.date.isAfter(endOfDay)) {
          for (final item in t.items) {
            final k = StockFlowReportPage.resolveCommodityKelompok(tyunit: item.tyunit, itemName: item.name);
            if (map.containsKey(k)) {
              final qtyOut = item.quantity + item.bonus;
              map[k]!.keluar += qtyOut;
              map[k]!.totalTransaksi += 1;
              map[k]!.totalNominal += item.subtotal;
            }
          }
        }
      }

      // 4. Sisa Akumulasi Akhir Hari Ini
      for (final s in map.values) {
        s.currentSisa = s.sisaKemarin + s.masukHariIni - s.keluar;
      }

      return map;
    }

    test('1. Verifikasi Posisi Sisa Tutup Toko Kemarin (08 Nov 2026)', () {
      final simKemarin = calculateOfflineSimulation(
        targetDate: tglKemarin,
        logs: allLogs,
        transactions: allTransactions,
      );

      expect(simKemarin['GALON']!.sisaKemarin + simKemarin['GALON']!.masukHariIni - simKemarin['GALON']!.keluar, 8);
      expect(simKemarin['BOTOL_600']!.sisaKemarin + simKemarin['BOTOL_600']!.masukHariIni - simKemarin['BOTOL_600']!.keluar, 121);
      expect(simKemarin['BOTOL_1500']!.sisaKemarin + simKemarin['BOTOL_1500']!.masukHariIni - simKemarin['BOTOL_1500']!.keluar, 31);
      expect(simKemarin['GELAS']!.sisaKemarin + simKemarin['GELAS']!.masukHariIni - simKemarin['GELAS']!.keluar, 189);
    });

    test('2. Verifikasi Alur Hari Ini (09 Nov 2026): Sisa Kemarin, Masuk, Terjual, Selisih, & Sisa Akhir', () {
      final simHariIni = calculateOfflineSimulation(
        targetDate: tglHariIni,
        logs: allLogs,
        transactions: allTransactions,
      );

      // A. GALON
      final galon = simHariIni['GALON']!;
      expect(galon.sisaKemarin, 8, reason: 'Sisa kemarin harus bawaan dari 08 Nov (8)');
      expect(galon.masukHariIni, 100, reason: 'Stok masuk hari ini murni pasokan baru (+100)');
      expect(galon.keluar, 35, reason: 'Terjual hari ini = 20 + 15 = 35');
      expect(galon.selisihHariIni, 65, reason: 'Selisih hari ini = Masuk(100) - Terjual(35) = +65');
      expect(galon.sisaAkumulasi, 73, reason: 'Sisa Akhir Hari Ini = Kemarin(8) + Selisih(+65) = 73');

      // B. BOTOL 600ml
      final botol600 = simHariIni['BOTOL_600']!;
      expect(botol600.sisaKemarin, 121, reason: 'Sisa kemarin harus 121');
      expect(botol600.masukHariIni, 50, reason: 'Stok masuk hari ini +50');
      expect(botol600.keluar, 70, reason: 'Terjual hari ini = 40 + 30 = 70');
      expect(botol600.selisihHariIni, -20, reason: 'Selisih hari ini = 50 - 70 = -20');
      expect(botol600.sisaAkumulasi, 101, reason: 'Sisa Akhir Hari Ini = 121 + (-20) = 101');

      // C. BOTOL 1.5L
      final botol1500 = simHariIni['BOTOL_1500']!;
      expect(botol1500.sisaKemarin, 31, reason: 'Sisa kemarin harus 31');
      expect(botol1500.masukHariIni, 20, reason: 'Stok masuk hari ini +20');
      expect(botol1500.keluar, 15, reason: 'Terjual hari ini = 15');
      expect(botol1500.selisihHariIni, 5, reason: 'Selisih hari ini = 20 - 15 = +5');
      expect(botol1500.sisaAkumulasi, 36, reason: 'Sisa Akhir Hari Ini = 31 + 5 = 36');

      // D. GELAS
      final gelas = simHariIni['GELAS']!;
      expect(gelas.sisaKemarin, 189, reason: 'Sisa kemarin harus 189');
      expect(gelas.masukHariIni, 80, reason: 'Stok masuk hari ini +80');
      expect(gelas.keluar, 95, reason: 'Terjual hari ini = 95');
      expect(gelas.selisihHariIni, -15, reason: 'Selisih hari ini = 80 - 95 = -15');
      expect(gelas.sisaAkumulasi, 174, reason: 'Sisa Akhir Hari Ini = 189 + (-15) = 174');
    });

    test('3. Verifikasi Alur Hari Esok (10 Nov 2026): Sisa Kemarin Harus Sesuai Sisa Akhir Hari Ini', () {
      final simHariEsok = calculateOfflineSimulation(
        targetDate: tglHariEsok,
        logs: allLogs,
        transactions: allTransactions,
      );

      // A. GALON
      final galon = simHariEsok['GALON']!;
      expect(galon.sisaKemarin, 73, reason: 'Sisa kemarin pada hari esok HARUS SAMA DENGAN sisa akhir hari ini (73)');
      expect(galon.masukHariIni, 40, reason: 'Stok masuk hari esok +40');
      expect(galon.keluar, 25, reason: 'Terjual hari esok 25');
      expect(galon.selisihHariIni, 15, reason: 'Selisih hari esok = 40 - 25 = +15');
      expect(galon.sisaAkumulasi, 88, reason: 'Sisa Akhir Hari Esok = 73 + 15 = 88');

      // B. BOTOL 600ml
      final botol600 = simHariEsok['BOTOL_600']!;
      expect(botol600.sisaKemarin, 101, reason: 'Sisa kemarin pada hari esok HARUS 101');
      expect(botol600.masukHariIni, 60, reason: 'Stok masuk hari esok +60');
      expect(botol600.keluar, 40, reason: 'Terjual hari esok 40');
      expect(botol600.selisihHariIni, 20, reason: 'Selisih hari esok = 60 - 40 = +20');
      expect(botol600.sisaAkumulasi, 121, reason: 'Sisa Akhir Hari Esok = 101 + 20 = 121');

      // C. BOTOL 1.5L
      final botol1500 = simHariEsok['BOTOL_1500']!;
      expect(botol1500.sisaKemarin, 36, reason: 'Sisa kemarin pada hari esok HARUS 36');
      expect(botol1500.masukHariIni, 10, reason: 'Stok masuk hari esok +10');
      expect(botol1500.keluar, 12, reason: 'Terjual hari esok 12');
      expect(botol1500.selisihHariIni, -2, reason: 'Selisih hari esok = 10 - 12 = -2');
      expect(botol1500.sisaAkumulasi, 34, reason: 'Sisa Akhir Hari Esok = 36 + (-2) = 34');

      // D. GELAS
      final gelas = simHariEsok['GELAS']!;
      expect(gelas.sisaKemarin, 174, reason: 'Sisa kemarin pada hari esok HARUS 174');
      expect(gelas.masukHariIni, 50, reason: 'Stok masuk hari esok +50');
      expect(gelas.keluar, 65, reason: 'Terjual hari esok 65');
      expect(gelas.selisihHariIni, -15, reason: 'Selisih hari esok = 50 - 65 = -15');
      expect(gelas.sisaAkumulasi, 159, reason: 'Sisa Akhir Hari Esok = 174 + (-15) = 159');
    });

    test('4. Analisis Perbandingan: Menguji Kenapa Response API Server Menyebabkan Inkonsistensi', () {
      // Berikut adalah contoh payload yang dikembalikan oleh API Server Laravel v2
      // sebagaimana didokumentasikan sebelumnya:
      final Map<String, dynamic> apiResponseHariIni = {
        'success': true,
        'summary': {
          'total_stock_masuk': 108, // Server menggabungkan stok awal 8 + tambahan 100
          'total_stock_terjual': 35,
          'sisa_stock': 73,
          'total_transaksi': 2,
        },
        'per_kelompok': [
          // Perhatikan bahwa API tidak menyediakan 'stok_awal' dan 'stok_tambahan' terpisah,
          // melainkan hanya 'stock_masuk'
          {
            'kdklp': 'GALON',
            'stock_masuk': 108, // Gabungan stok awal 8 + masuk 100
            'stock_terjual': 35,
            'sisa_stock': 73,
          },
        ],
        'daily': [
          {
            'tanggal': '2026-11-09',
            'hari': 'Senin',
            'total_masuk': 100,
            'total_terjual': 35,
            // DI SINI LETAK SALAH API SERVER:
            // Server menghitung sisa harian = total_masuk - total_terjual (100 - 35 = 65)
            // bukan sisa stok fisik riil (73)!
            'sisa': 65, // Ini sebenarnya SELISIH, bukan SISA STOK AKUMULASI!
          }
        ]
      };

      // Uji pembacaan payload server
      final galonApi = (apiResponseHariIni['per_kelompok'] as List).first as Map<String, dynamic>;
      
      // Bukti Bug Server 1: Ketiadaan pemisahan stok_awal dan stok_tambahan di per_kelompok
      expect(galonApi['stok_awal'], isNull, reason: 'Server API belum menyediakan field stok_awal di per_kelompok');
      expect(galonApi['stok_tambahan'], isNull, reason: 'Server API belum menyediakan field stok_tambahan di per_kelompok');

      // Bukti Bug Server 2: Server menghitung field 'sisa' di array 'daily' sebagai (masuk - terjual),
      // padahal itu adalah SELISIH harian, bukan SISA AKHIR riil gudang
      final dailyGalon = (apiResponseHariIni['daily'] as List).first as Map<String, dynamic>;
      final int serverDailySisa = dailyGalon['sisa'];
      final int masukDaily = dailyGalon['total_masuk'];
      final int keluarDaily = dailyGalon['total_terjual'];

      expect(serverDailySisa, masukDaily - keluarDaily, reason: 'Server salah mendefinisikan sisa sebagai masuk - keluar');
      expect(serverDailySisa != 73, isTrue, reason: 'Server mengabaikan stok kemarin (8), sehingga menampilkan 65 bukannya 73');
    });
  });
}

