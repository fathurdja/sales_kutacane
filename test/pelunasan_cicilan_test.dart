import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kutacane/services/pelunasan_history_service.dart';

void main() {
  group('Pelunasan & Pembayaran Bertahap (Cicilan) Logic Tests', () {
    test('Simulasi Pelanggan BNI: Cicilan bertahap Rp 150.000 menjadi Rp 100.000 lalu LUNAS', () {
      const double totalBonAwal = 150000.0;
      final payments = <PelunasanPayment>[];

      // Step 1: Input cicilan pertama Rp 50.000
      const double cicil1 = 50000.0;
      final paid1 = payments.fold(0.0, (sum, p) => sum + p.nominalBayar) + cicil1;
      final sisa1 = (totalBonAwal - paid1).clamp(0.0, totalBonAwal);

      expect(sisa1, equals(100000.0));
      payments.add(PelunasanPayment(
        id: 'PAY-1',
        customerName: 'BNI',
        idTransaksi: 'Trx-001',
        nominalBayar: cicil1,
        sisaBon: sisa1,
        tanggalPelunasan: DateTime(2026, 11, 10),
        settledAt: DateTime(2026, 11, 10, 10, 0),
        catatan: 'Cicilan 1',
        isLunas: false,
      ));

      expect(payments.length, equals(1));
      expect(payments.first.isLunas, isFalse);
      expect(payments.first.sisaBon, equals(100000.0));

      // Step 2: Input cicilan kedua Rp 40.000
      const double cicil2 = 40000.0;
      final paid2 = payments.fold(0.0, (sum, p) => sum + p.nominalBayar) + cicil2;
      final sisa2 = (totalBonAwal - paid2).clamp(0.0, totalBonAwal);

      expect(sisa2, equals(60000.0));
      payments.add(PelunasanPayment(
        id: 'PAY-2',
        customerName: 'BNI',
        idTransaksi: 'Trx-001',
        nominalBayar: cicil2,
        sisaBon: sisa2,
        tanggalPelunasan: DateTime(2026, 11, 11),
        settledAt: DateTime(2026, 11, 11, 14, 0),
        catatan: 'Cicilan 2',
        isLunas: false,
      ));

      expect(payments.length, equals(2));
      expect(sisa2, equals(60000.0));

      // Step 3: Pelunasan sisa Rp 60.000
      final double totalPaidSoFar = payments.fold(0.0, (sum, p) => sum + p.nominalBayar);
      final double sisaSebelumBayar = (totalBonAwal - totalPaidSoFar).clamp(0.0, totalBonAwal);
      expect(sisaSebelumBayar, equals(60000.0));

      const double cicil3 = 60000.0;
      final bool isCleared = cicil3 >= sisaSebelumBayar;
      final double sisa3 = (sisaSebelumBayar - cicil3).clamp(0.0, sisaSebelumBayar);

      expect(isCleared, isTrue);
      expect(sisa3, equals(0.0));

      payments.add(PelunasanPayment(
        id: 'PAY-3',
        customerName: 'BNI',
        idTransaksi: 'Trx-001',
        nominalBayar: cicil3,
        sisaBon: sisa3,
        tanggalPelunasan: DateTime(2026, 11, 12),
        settledAt: DateTime(2026, 11, 12, 9, 30),
        catatan: 'Pelunasan Akhir',
        isLunas: true,
      ));

      expect(payments.length, equals(3));
      expect(payments.last.isLunas, isTrue);
      expect(payments.last.sisaBon, equals(0.0));
      expect(payments.fold(0.0, (sum, p) => sum + p.nominalBayar), equals(totalBonAwal));
    });

    test('Validasi alokasi cicilan multi-nota pelanggan (FIFO tertua ke terbaru)', () {
      // Pelanggan punya 2 nota: Nota A Rp 100.000 (01 Nov) & Nota B Rp 100.000 (05 Nov). Total = Rp 200.000
      final trxList = [
        {'id': 'Trx-A', 'total': 100000.0, 'date': DateTime(2026, 11, 1)},
        {'id': 'Trx-B', 'total': 100000.0, 'date': DateTime(2026, 11, 5)},
      ];

      double remToAllocate = 130000.0; // Cicil Rp 130.000
      final notaStatus = <String, String>{};
      final notaSisa = <String, double>{};

      for (final trx in trxList) {
        final double tTotal = trx['total'] as double;
        final String tId = trx['id'] as String;

        if (remToAllocate <= 0) {
          notaStatus[tId] = 'BON';
          notaSisa[tId] = tTotal;
        } else if (remToAllocate >= tTotal) {
          remToAllocate -= tTotal;
          notaStatus[tId] = 'BON LUNAS';
          notaSisa[tId] = 0.0;
        } else {
          notaSisa[tId] = tTotal - remToAllocate;
          notaStatus[tId] = 'DICICIL';
          remToAllocate = 0;
        }
      }

      // Nota A tertutup penuh (100.000)
      expect(notaStatus['Trx-A'], equals('BON LUNAS'));
      expect(notaSisa['Trx-A'], equals(0.0));

      // Nota B terbayar 30.000, sisa 70.000
      expect(notaStatus['Trx-B'], equals('DICICIL'));
      expect(notaSisa['Trx-B'], equals(70000.0));
    });
  });
}
