import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kutacane/models/Item.dart';
import 'package:kasir_kutacane/models/stock_change_log.dart';
import 'package:kasir_kutacane/models/stock_group.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/models/transactionItem.dart';
import 'package:kasir_kutacane/pages/stock_flow_report_page.dart';
import 'package:kasir_kutacane/services/offline_sync_service.dart';
import 'package:kasir_kutacane/services/pending_stock_sync_service.dart';

void main() {
  group('Tyunit & Commodity Group Resolution Tests', () {
    test('Resolves proper commodity group from Item code', () {
      final galonItem = Item.fromJson({'TYUNIT': 'BV06', 'NTYUNIT': 'Boneva Galon + isi', 'hjual': 75000});
      expect(galonItem.kelompok, 'GALON');

      final botol600Item = Item.fromJson({'TYUNIT': 'BV09', 'NTYUNIT': 'Boneva Botol 600 Ml', 'hjual': 37000});
      expect(botol600Item.kelompok, 'BOTOL_600');

      final botol1500Item = Item.fromJson({'TYUNIT': 'BV15', 'NTYUNIT': 'Boneva Botol 1,5 L', 'hjual': 41000});
      expect(botol1500Item.kelompok, 'BOTOL_1500');

      final gelasItem = Item.fromJson({'TYUNIT': 'BV20', 'NTYUNIT': 'Boneva Gelas', 'hjual': 22000});
      expect(gelasItem.kelompok, 'GELAS');
    });

    test('Resolves tyunit correctly even when empty or defaulted to BV01', () {
      // Boneva Gelas with price 22000 should resolve to BV20
      final codeGelas = OfflineSyncService.resolveItemTyunit('BV01', 'Boneva Gelas', 22000);
      expect(codeGelas, 'BV20');

      // Boneva Botol 600 with price 40000 should resolve to BV13
      final codeBotol600 = OfflineSyncService.resolveItemTyunit(null, 'Boneva Botol 600 Ml', 40000);
      expect(codeBotol600, 'BV13');

      // Boneva Galon isi saja with price 13000 should resolve to BV02
      final codeGalon13k = OfflineSyncService.resolveItemTyunit('BV01', 'Boneva Galon isi saja', 13000);
      expect(codeGalon13k, 'BV02');
    });

    test('Parses Item stock correctly with fallback when sisa_kuota is 0', () {
      final item = Item.fromJson({
        'tyunit': 'BV02',
        'ntyunit': 'Boneva Galon isi saja',
        'hjual': 13000,
        'stock': 22,
        'kdklp': 'GALON',
        'kuota': 755,
        'terjual': 298,
        'sisa_kuota': 0,
      });

      expect(item.name, 'Boneva Galon isi saja');
      expect(item.stock, 22);
      expect(item.kelompok, 'GALON');
      expect(item.kuota, 755);
    });

    test('Parses Item from Supabase lowercase schema correctly', () {
      final supabaseItem = Item.fromJson({
        'tyunit': 'BV01',
        'ntyunit': 'Boneva Galon Kosong',
        'hjual': 60000,
        'stock': 15,
        'kdklp': 'GALON',
      });

      expect(supabaseItem.name, 'Boneva Galon Kosong');
      expect(supabaseItem.price, 60000);
      expect(supabaseItem.stock, 15);
      expect(supabaseItem.kelompok, 'GALON');
    });

    test('StockGroup formatting helpers return expected labels', () {
      expect(StockGroup.getDisplayName('GALON'), 'Boneva Galon (19L)');
      expect(StockGroup.getUnitName('GALON'), 'Galon');

      expect(StockGroup.getDisplayName('BOTOL_600'), 'Boneva Botol 600ml');
      expect(StockGroup.getUnitName('BOTOL_600'), 'Dus/Btl');

      expect(StockGroup.getDisplayName('BOTOL_1500'), 'Boneva Botol 1.5L');
      expect(StockGroup.getUnitName('BOTOL_1500'), 'Dus/Btl');

      expect(StockGroup.getDisplayName('GELAS'), 'Boneva Gelas');
      expect(StockGroup.getUnitName('GELAS'), 'Dus');
    });

    test('Transaction parsing and status methods work as intended', () {
      final trx = Transaction(
        id: 'Trx-20261031-0001',
        id_transaksi: 'Trx-20261031-0001',
        customerName: 'Toko Boneva',
        date: DateTime.now(),
        alamat: 'Gorontalo',
        items: [
          TransactionItem.fromData(name: 'Boneva Galon', price: 13000, quantity: 2, bonus: 0, tyunit: 'BV02')
        ],
        total: 26000,
        status: 'LUNAS',
        isOffline: true,
      );

      expect(trx.isLunas, isTrue);
      expect(trx.isBon, isFalse);
      expect(trx.isBonLunas, isFalse);
      expect(trx.isSettled, isTrue);
      expect(trx.items.length, 1);
      expect(trx.total, 26000);

      final bonLunasTrx = Transaction(
        id: 'Trx-20261031-0002',
        id_transaksi: 'Trx-20261031-0002',
        customerName: 'Kantin SMA 1',
        date: DateTime.now(),
        alamat: 'Gorontalo',
        items: [],
        total: 50000,
        status: 'BON LUNAS',
      );

      expect(bonLunasTrx.isBonLunas, isTrue);
      expect(bonLunasTrx.isBon, isFalse);
      expect(bonLunasTrx.isLunas, isFalse);
      expect(bonLunasTrx.isSettled, isTrue);
    });

    test('StockChangeLog serializes and deserializes accurately', () {
      final log = StockChangeLog(
        id: 'LOG-12345',
        timestamp: DateTime(2026, 11, 3, 10, 30),
        kelompok: 'GALON',
        displayName: 'Boneva Galon (19L)',
        unitName: 'Galon',
        jenisAksi: 'TAMBAH_PASOKAN',
        stokAwalSebelum: 100,
        tambahanQty: 50,
        stokAwalSesudah: 150,
        sisaSebelum: 40,
        sisaSesudah: 90,
        totalTerjualSaatIni: 60,
        userName: 'Admin',
        keterangan: 'Restock pagi',
      );

      final json = log.toJson();
      final parsed = StockChangeLog.fromJson(json);

      expect(parsed.id, 'LOG-12345');
      expect(parsed.kelompok, 'GALON');
      expect(parsed.tambahanQty, 50);
      expect(parsed.sisaSebelum, 40);
      expect(parsed.sisaSesudah, 90);
      expect(parsed.userName, 'Admin');
      expect(parsed.jenisAksi, 'TAMBAH_PASOKAN');
    });

    test('StockFlowReportPage resolution and summary calculations work accurately', () {
      expect(StockFlowReportPage.resolveCommodityKelompok(tyunit: 'BV02', itemName: 'Boneva Galon isi saja'), 'GALON');
      expect(StockFlowReportPage.resolveCommodityKelompok(tyunit: null, itemName: 'Boneva Galon 19L'), 'GALON');
      expect(StockFlowReportPage.resolveCommodityKelompok(tyunit: 'BV09', itemName: 'Boneva Botol 600 Ml'), 'BOTOL_600');
      expect(StockFlowReportPage.resolveCommodityKelompok(tyunit: null, itemName: 'Botol 1,5L'), 'BOTOL_1500');
      expect(StockFlowReportPage.resolveCommodityKelompok(tyunit: 'BV20', itemName: 'Boneva Gelas'), 'GELAS');

      final summary = CommodityFlowSummary(
        kelompok: 'GALON',
        displayName: 'Boneva Galon (19L)',
        unitName: 'Galon',
        masuk: 100,
        keluar: 40,
        currentSisa: 60,
      );

      expect(summary.net, 60);

      final record = DailyStockFlowRecord(date: DateTime(2026, 11, 3));
      record.totalMasuk = 50;
      record.totalKeluar = 30;
      record.logCount = 2;
      record.transactionCount = 10;

      expect(record.net, 20);
      expect(record.hasActivity, isTrue);
    });

    test('PendingStockEntry serializes, deserializes, and queues offline entries properly', () async {
      final entry = PendingStockEntry(
        id: 'STOCK-MASUK-999',
        timestamp: DateTime(2026, 11, 10, 8, 30),
        kdklp: 'GALON',
        jenisAksi: 'TAMBAH_PASOKAN',
        jumlah: 100,
        resetTerjual: false,
        keterangan: 'Pasokan offline darurat',
      );

      final json = entry.toJson();
      expect(json['id'], 'STOCK-MASUK-999');
      expect(json['kdklp'], 'GALON');
      expect(json['jenis_aksi'], 'TAMBAH_PASOKAN');
      expect(json['jumlah'], 100);

      final parsed = PendingStockEntry.fromJson(json);
      expect(parsed.id, 'STOCK-MASUK-999');
      expect(parsed.kdklp, 'GALON');
      expect(parsed.jenisAksi, 'TAMBAH_PASOKAN');
      expect(parsed.jumlah, 100);
      expect(parsed.keterangan, 'Pasokan offline darurat');

      // Test add and remove from queue
      await PendingStockSyncService.addPendingEntry(entry);
      final list = await PendingStockSyncService.getPendingEntries();
      expect(list.any((e) => e.id == 'STOCK-MASUK-999'), isTrue);

      await PendingStockSyncService.removePendingEntry('STOCK-MASUK-999');
      final listAfter = await PendingStockSyncService.getPendingEntries();
      expect(listAfter.any((e) => e.id == 'STOCK-MASUK-999'), isFalse);
    });
  });
}
