import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kutacane/models/Item.dart';
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
  });
}
