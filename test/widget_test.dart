import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kutacane/models/Item.dart';
import 'package:kasir_kutacane/models/stock_group.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/models/transactionItem.dart';
import 'package:kasir_kutacane/services/offline_sync_service.dart';

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

      expect(item.stock, 22);
      expect(item.kelompok, 'GALON');
      expect(item.kuota, 755);
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
      expect(trx.items.length, 1);
      expect(trx.total, 26000);
    });
  });
}
