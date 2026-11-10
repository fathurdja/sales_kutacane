import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:kasir_kutacane/enum/print_enum.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:intl/intl.dart';

class TestPrint {
  final BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;

  /// Mencetak satu transaksi lengkap. Mengembalikan true jika berhasil, false jika gagal / belum tersambung.
  Future<bool> printTransaction(Transaction transaction) async {
    final currencyFormat = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    try {
      final isConnected = await bluetooth.isConnected ?? false;
      if (!isConnected) {
        return false;
      }

      await bluetooth.printNewLine();

      // ====== HEADER TOKO ======
      await bluetooth.printCustom(
        "Kencana Cahaya Amanah",
        Size.boldLarge.val,
        Align.center.val,
      );
      await bluetooth.printCustom(
        "JL. Kenangan No. 183 Gorontalo",
        Size.medium.val,
        Align.center.val,
      );
      await bluetooth.printCustom(
        "--------------------------------",
        Size.medium.val,
        Align.center.val,
      );

      // ====== JUDUL STRUK (HEADER) ======
      final statusUpper = transaction.status.toUpperCase();
      final isLunas = statusUpper == 'LUNAS';
      final isQris = statusUpper == 'QRIS';

      // Sesuai nota asli (gambar kiri): Selalu tampilkan STRUK PENJUALAN
      await bluetooth.printCustom(
        "STRUK PENJUALAN",
        Size.boldMedium.val,
        Align.center.val,
      );
      await bluetooth.printCustom(
        "--------------------------------",
        Size.medium.val,
        Align.center.val,
      );

      // ====== INFORMASI TRANSAKSI ======
      await bluetooth.printLeftRight(
        "No. Nota",
        transaction.id_transaksi,
        Size.medium.val,
      );
      await bluetooth.printLeftRight(
        "Tanggal",
        DateFormat('dd-MM-yyyy HH:mm').format(transaction.date),
        Size.medium.val,
      );
      await bluetooth.printLeftRight(
        "Konsumen",
        transaction.customerName,
        Size.medium.val,
      );
      if (transaction.alamat.isNotEmpty) {
        await bluetooth.printLeftRight(
          "Alamat",
          transaction.alamat,
          Size.medium.val,
        );
      }

      await bluetooth.printCustom(
        "--------------------------------",
        Size.medium.val,
        Align.center.val,
      );

      // ====== DAFTAR BARANG (FORMAT RAPI 58MM) ======
      for (final item in transaction.items) {
        // Baris 1: Nama Produk
        await bluetooth.printCustom(
          item.name,
          Size.bold.val,
          Align.left.val,
        );

        // Baris 2: Qty @ Harga di kiri, Subtotal di kanan
        final bonusText = item.bonus > 0 ? " (+${item.bonus} Bns)" : "";
        final qtyDetail = "${item.quantity}x @ ${currencyFormat.format(item.price)}$bonusText";
        final subtotalText = currencyFormat.format(item.subtotal);

        await bluetooth.printLeftRight(
          qtyDetail,
          subtotalText,
          Size.medium.val,
        );
      }

      await bluetooth.printCustom(
        "--------------------------------",
        Size.medium.val,
        Align.center.val,
      );

      // ====== PEMBAYARAN & TOTAL ======
      final String statusBayarText;
      if (statusUpper == 'BON LUNAS' || statusUpper == 'BON_LUNAS') {
        statusBayarText = "BON LUNAS";
      } else if (isLunas) {
        statusBayarText = "LUNAS";
      } else if (isQris) {
        statusBayarText = "QRIS";
      } else {
        statusBayarText = "BON";
      }
      await bluetooth.printLeftRight(
        "STATUS BAYAR",
        statusBayarText,
        Size.boldMedium.val,
      );
      if ((isLunas || statusUpper.contains('LUNAS')) && transaction.tanggalPelunasan != null) {
        await bluetooth.printLeftRight(
          "Tgl Pelunasan",
          DateFormat('dd-MM-yyyy').format(transaction.tanggalPelunasan!),
          Size.medium.val,
        );
      }
      await bluetooth.printLeftRight(
        "TOTAL",
        currencyFormat.format(transaction.total),
        Size.boldLarge.val,
      );

      await bluetooth.printCustom(
        "--------------------------------",
        Size.medium.val,
        Align.center.val,
      );

      // ====== FOOTER ======
      await bluetooth.printCustom(
        "Terima Kasih atas Kunjungan Anda!",
        Size.medium.val,
        Align.center.val,
      );
      await bluetooth.printCustom(
        "Barang yg dibeli tdk dpt ditukar",
        Size.medium.val,
        Align.center.val,
      );

      // Kertas digulung keluar (4 baris feed) agar melewati batas gerigi pemotong
      await bluetooth.printNewLine();
      await bluetooth.printNewLine();
      await bluetooth.printNewLine();
      await bluetooth.printNewLine();

      // Coba potong kertas jika printer mendukung
      try {
        await bluetooth.paperCut();
      } catch (_) {}

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Mencetak bukti pembayaran / pelunasan bon (baik sebagian maupun lunas)
  Future<bool> printPelunasanPayment({
    required String customerName,
    String? idTransaksi,
    required double totalBonAwal,
    required double nominalBayar,
    required double sisaBon,
    required DateTime tanggalPelunasan,
    String? catatan,
    bool isLunas = false,
  }) async {
    final currencyFormat = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    try {
      final isConnected = await bluetooth.isConnected ?? false;
      if (!isConnected) return false;

      await bluetooth.printNewLine();

      // HEADER
      await bluetooth.printCustom("Kencana Cahaya Amanah", Size.boldLarge.val, Align.center.val);
      await bluetooth.printCustom("JL. Kenangan No. 183 Gorontalo", Size.medium.val, Align.center.val);
      await bluetooth.printCustom("--------------------------------", Size.medium.val, Align.center.val);

      // JUDUL
      await bluetooth.printCustom(
        isLunas ? "BUKTI PELUNASAN BON" : "BUKTI PEMBAYARAN BON",
        Size.boldMedium.val,
        Align.center.val,
      );
      await bluetooth.printCustom("--------------------------------", Size.medium.val, Align.center.val);

      // INFO PELUNASAN
      await bluetooth.printLeftRight(
        "Tgl Pelunasan",
        DateFormat('dd-MM-yyyy').format(tanggalPelunasan),
        Size.medium.val,
      );
      await bluetooth.printLeftRight(
        "Pelanggan",
        customerName,
        Size.medium.val,
      );
      if (idTransaksi != null && idTransaksi.isNotEmpty) {
        await bluetooth.printLeftRight("No. Nota", idTransaksi, Size.medium.val);
      }

      await bluetooth.printCustom("--------------------------------", Size.medium.val, Align.center.val);

      // RINCIAN NOMINAL
      await bluetooth.printLeftRight("Total Tagihan", currencyFormat.format(totalBonAwal), Size.medium.val);
      await bluetooth.printLeftRight("Jumlah Dibayar", currencyFormat.format(nominalBayar), Size.bold.val);
      await bluetooth.printLeftRight(
        "Sisa Tagihan",
        currencyFormat.format(sisaBon),
        isLunas ? Size.medium.val : Size.bold.val,
      );

      await bluetooth.printCustom("--------------------------------", Size.medium.val, Align.center.val);

      // STATUS
      await bluetooth.printCustom("STATUS PEMBAYARAN", Size.medium.val, Align.center.val);
      await bluetooth.printCustom(
        isLunas ? "LUNAS (SELESAI)" : "BELUM LUNAS (SEBAGIAN)",
        Size.boldLarge.val,
        Align.center.val,
      );

      if (catatan != null && catatan.isNotEmpty) {
        await bluetooth.printCustom("Ket: $catatan", Size.medium.val, Align.center.val);
      }

      await bluetooth.printCustom("--------------------------------", Size.medium.val, Align.center.val);
      await bluetooth.printCustom("Terima Kasih atas Pembayaran Anda!", Size.medium.val, Align.center.val);
      await bluetooth.printCustom("Simpan struk ini sbg bukti sah", Size.medium.val, Align.center.val);

      await bluetooth.printNewLine();
      await bluetooth.printNewLine();
      await bluetooth.printNewLine();
      await bluetooth.printNewLine();

      try {
        await bluetooth.paperCut();
      } catch (_) {}

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Tes koneksi printer dengan mencetak struk uji coba singkat
  Future<bool> printTestReceipt() async {
    try {
      final isConnected = await bluetooth.isConnected ?? false;
      if (!isConnected) return false;

      await bluetooth.printNewLine();
      await bluetooth.printCustom(
        "TEST PRINTER OK",
        Size.boldLarge.val,
        Align.center.val,
      );
      await bluetooth.printCustom(
        "Kencana Cahaya Amanah",
        Size.medium.val,
        Align.center.val,
      );
      await bluetooth.printCustom(
        "Waktu: ${DateFormat('dd-MM-yyyy HH:mm:ss').format(DateTime.now())}",
        Size.medium.val,
        Align.center.val,
      );
      await bluetooth.printCustom(
        "Koneksi Bluetooth Berhasil!",
        Size.medium.val,
        Align.center.val,
      );
      await bluetooth.printNewLine();
      await bluetooth.printNewLine();
      await bluetooth.printNewLine();
      await bluetooth.printNewLine();

      try {
        await bluetooth.paperCut();
      } catch (_) {}

      return true;
    } catch (_) {
      return false;
    }
  }
}
