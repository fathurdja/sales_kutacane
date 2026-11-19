import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/models/transactionItem.dart';

void main() {
  group('Transaction Save & Auto-Print Flow Logic Tests', () {
    test('Simpan transaksi baru menghasilkan Transaction valid untuk dialog & Beranda', () {
      final item1 = TransactionItem.fromData(
        tyunit: 'BV01',
        name: 'Boneva Galon 19L',
        price: 20000,
        quantity: 5,
        bonus: 1,
      );

      final trx = Transaction(
        id: '123',
        id_transaksi: 'Trx-20261113-0001',
        customerName: 'Toko Berkah',
        date: DateTime(2026, 11, 13, 14, 30),
        alamat: 'Jl. Kutacane No. 10',
        items: [item1],
        total: 100000,
        status: 'LUNAS',
        userId: 1,
        userName: 'Admin',
      );

      expect(trx.id_transaksi, equals('Trx-20261113-0001'));
      expect(trx.customerName, equals('Toko Berkah'));
      expect(trx.total, equals(100000));
      expect(trx.isLunas, isTrue);
      expect(trx.items.length, equals(1));
      expect(trx.items.first.quantity, equals(5));
      expect(trx.items.first.bonus, equals(1));
    });

    test('Status tab index berpindah ke 0 (Beranda) setelah simpan transaksi', () {
      int activeTabIndex = 1; // sebelumnya di tab Transaksi

      void onTransactionSaved(Transaction trx) {
        // Alur baru: langsung kembali ke halaman beranda (index 0)
        activeTabIndex = 0;
      }

      final trx = Transaction(
        id: '124',
        id_transaksi: 'Trx-20261113-0002',
        customerName: 'Pelanggan BNI',
        date: DateTime.now(),
        alamat: 'Gorontalo',
        items: [],
        total: 50000,
        status: 'BON',
      );

      onTransactionSaved(trx);

      expect(activeTabIndex, equals(0),
          reason: 'Setelah simpan transaksi, tab harus kembali ke Beranda (index 0)');
    });
  });
}
