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

      // ====== JUDUL STRUK ======
      final statusUpper = transaction.status.toUpperCase();
      final isLunas = statusUpper == 'LUNAS';
      final isQris = statusUpper == 'QRIS';
      final String judulStruk;
      if (isLunas) {
        judulStruk = "*** NOTA LUNAS ***";
      } else if (isQris) {
        judulStruk = "*** NOTA QRIS (MENUNGGU VERIFIKASI) ***";
      } else {
        judulStruk = "*** NOTA BON (BELUM LUNAS) ***";
      }
      await bluetooth.printCustom(
        judulStruk,
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
      if (isLunas) {
        statusBayarText = "LUNAS";
      } else if (isQris) {
        statusBayarText = "QRIS (CEK ADMIN)";
      } else {
        statusBayarText = "BON (BELUM LUNAS)";
      }
      await bluetooth.printLeftRight(
        "STATUS BAYAR",
        statusBayarText,
        Size.boldMedium.val,
      );
      if (isLunas && transaction.tanggalPelunasan != null) {
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
