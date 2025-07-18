import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:kasir_kutacane/enum/print_enum.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:intl/intl.dart';

class TestPrint {
  final BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;

  Future<void> printTransaction(Transaction transaction) async {
    final currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ');

    final isConnected = await bluetooth.isConnected;
    if (isConnected != true) {
      print('Printer belum terhubung!');
      return;
    }

    bluetooth.printNewLine();

    // ====== HEADER ======
    bluetooth.printCustom(
      "Kencana Cahaya Amanah",
      Size.boldLarge.val,
      Align.center.val,
    );
    bluetooth.printCustom(
      "JL. Kenangan No. 183 Gorontalo",
      Size.medium.val,
      Align.center.val,
    );

    bluetooth.printNewLine();
    bluetooth.printCustom("STRUK TRANSAKSI", Size.boldLarge.val, Align.center.val);
    bluetooth.printNewLine();

    // ====== INFORMASI TRANSAKSI ======
    bluetooth.printLeftRight("ID", transaction.id, Size.medium.val);
    bluetooth.printLeftRight(
      "Tanggal",
      DateFormat('dd-MM-yyyy').format(transaction.date),
      Size.medium.val,
    );
    bluetooth.printLeftRight("Konsumen", transaction.customerName, Size.medium.val);
    bluetooth.printLeftRight("Alamat", transaction.alamat, Size.medium.val);

    bluetooth.printNewLine();
    bluetooth.printCustom("Daftar Barang:", Size.bold.val, Align.left.val);

    // ====== ITEMS ======
    for (final item in transaction.items) {
      bluetooth.printLeftRight(
        "${item.name} x${item.quantity}",
        currencyFormat.format(item.subtotal),
        Size.medium.val,
      );
    }

    bluetooth.printNewLine();
    bluetooth.printLeftRight(
      "TOTAL",
      currencyFormat.format(transaction.total),
      Size.boldLarge.val,
    );

    bluetooth.printNewLine();
    bluetooth.printCustom("Terima Kasih!", Size.bold.val, Align.center.val);
    bluetooth.printNewLine();
    bluetooth.printNewLine();
  }
}
