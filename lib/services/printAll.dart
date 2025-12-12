import 'package:flutter/material.dart';
import 'dart:async';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/services.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/services/print.dart';

class PrintBluetoothAll extends StatefulWidget {
  final List<Transaction> allTransactions; // ✅ Semua transaksi

  const PrintBluetoothAll({Key? key, required this.allTransactions})
    : super(key: key);

  @override
  _PrintBluetoothAllState createState() => _PrintBluetoothAllState();
}

class _PrintBluetoothAllState extends State<PrintBluetoothAll> {
  BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;

  List<BluetoothDevice> _devices = [];
  BluetoothDevice? _device;
  bool _connected = false;
  TestPrint testPrint = TestPrint();

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  Future<void> initPlatformState() async {
    bool? isConnected = await bluetooth.isConnected;
    List<BluetoothDevice> devices = [];
    try {
      devices = await bluetooth.getBondedDevices();
    } on PlatformException {}

    bluetooth.onStateChanged().listen((state) {
      switch (state) {
        case BlueThermalPrinter.CONNECTED:
          setState(() => _connected = true);
          break;
        case BlueThermalPrinter.DISCONNECTED:
          setState(() => _connected = false);
          break;
        default:
          break;
      }
    });

    if (!mounted) return;
    setState(() {
      _devices = devices;
    });

    if (isConnected == true) {
      setState(() {
        _connected = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Cetak Semua Transaksi")),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ListView(
          children: [
            Row(
              children: [
                const Text("Device: "),
                Expanded(
                  child: DropdownButton<BluetoothDevice>(
                    value: _device,
                    items: _getDeviceItems(),
                    onChanged: (d) => setState(() => _device = d),
                  ),
                ),
                ElevatedButton(
                  onPressed: initPlatformState,
                  child: const Text("Refresh"),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _connected ? Colors.red : Colors.green,
                  ),
                  onPressed: _connected ? _disconnect : _connect,
                  child: Text(_connected ? "Disconnect" : "Connect"),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              "Daftar Transaksi:",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Divider(),
            ...widget.allTransactions.map((trx) {
              return Card(
                child: ListTile(
                  title: Text("ID: ${trx.id_transaksi} - ${trx.customerName}"),
                  subtitle: Text(
                    "Total: Rp ${trx.total.toStringAsFixed(0)} | ${trx.status}",
                  ),
                  trailing: ElevatedButton(
                    onPressed: () {
                      printSingle(trx);
                    },
                    child: const Text("Print"),
                  ),
                ),
              );
            }).toList(),
            const SizedBox(height: 30),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
              onPressed: () {
                for (var trx in widget.allTransactions) {
                  printSingle(trx);
                }
              },
              child: const Text("PRINT SEMUA"),
            ),
          ],
        ),
      ),
    );
  }

  void printSingle(Transaction trx) {
    print('===== STRUK TRANSAKSI =====');
    print('ID: ${trx.id_transaksi}');
    print('Nama: ${trx.customerName}');
    print('Alamat: ${trx.alamat}');
    print('Tanggal: ${trx.date}');
    print('Items:');
    for (var item in trx.items) {
      print(
        '- ${item.name} | Qty: ${item.quantity} | Bonus: ${item.bonus} | Price: ${item.price} | Subtotal: ${item.subtotal}',
      );
    }
    print('PEMBAYARAN: ${trx.status}');
    print('TOTAL: ${trx.total}');
    print('===========================');

    testPrint.printTransaction(trx);
  }

  List<DropdownMenuItem<BluetoothDevice>> _getDeviceItems() {
    List<DropdownMenuItem<BluetoothDevice>> items = [];
    if (_devices.isEmpty) {
      items.add(const DropdownMenuItem(value: null, child: Text("NONE")));
    } else {
      for (var d in _devices) {
        items.add(DropdownMenuItem(value: d, child: Text(d.name ?? "")));
      }
    }
    return items;
  }

  void _connect() {
    if (_device != null) {
      bluetooth.isConnected.then((isConnected) {
        if (isConnected == false) {
          bluetooth.connect(_device!).catchError((_) {
            setState(() => _connected = false);
          });
          setState(() => _connected = true);
        }
      });
    } else {
      show("No device selected.");
    }
  }

  void _disconnect() {
    bluetooth.disconnect();
    setState(() => _connected = false);
  }

  Future show(
    String message, {
    Duration duration = const Duration(seconds: 2),
  }) async {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
