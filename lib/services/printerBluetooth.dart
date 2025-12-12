import 'package:flutter/material.dart';
import 'dart:async';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/services.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/models/transactionItem.dart';
import 'package:kasir_kutacane/services/print.dart';

class Printbluetooth extends StatefulWidget {
  final List<Map<String, dynamic>> orderItems;
  final String paymentMethod;
  final int total;
  final DateTime date;
  final String customerName;
  final String alamat;
  final String idTransaksi;
  final String status;


  Printbluetooth({
    required this.orderItems,
    required this.paymentMethod,
    required this.total,
    required this.date,
    required this.customerName,
    required this.alamat,
    required this.idTransaksi,
    required this.status,
  });
  @override
  _MyAppState createState() => new _MyAppState();
}

class _MyAppState extends State<Printbluetooth> {
  BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;

  List<BluetoothDevice> _devices = [];
  BluetoothDevice? _device;
  bool _connected = false;
  TestPrint testPrint = TestPrint();

  @override
  void initState() {
    super.initState();
    initPlatformState();
    print(widget.orderItems);
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
          setState(() {
            _connected = true;
            print("bluetooth device state: connected");
          });
          break;
        case BlueThermalPrinter.DISCONNECTED:
          setState(() {
            _connected = false;
            print("bluetooth device state: disconnected");
          });
          break;
        case BlueThermalPrinter.DISCONNECT_REQUESTED:
          setState(() {
            _connected = false;
            print("bluetooth device state: disconnect requested");
          });
          break;
        case BlueThermalPrinter.STATE_TURNING_OFF:
          setState(() {
            _connected = false;
            print("bluetooth device state: bluetooth turning off");
          });
          break;
        case BlueThermalPrinter.STATE_OFF:
          setState(() {
            _connected = false;
            print("bluetooth device state: bluetooth off");
          });
          break;
        case BlueThermalPrinter.STATE_ON:
          setState(() {
            _connected = false;
            print("bluetooth device state: bluetooth on");
          });
          break;
        case BlueThermalPrinter.STATE_TURNING_ON:
          setState(() {
            _connected = false;
            print("bluetooth device state: bluetooth turning on");
          });
          break;
        case BlueThermalPrinter.ERROR:
          setState(() {
            _connected = false;
            print("bluetooth device state: error");
          });
          break;
        default:
          print(state);
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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: Text('Blue Thermal Printer')),
        body: Padding(
          padding: const EdgeInsets.all(8.0),
          child: ListView(
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  const SizedBox(width: 10),
                  const Text(
                    'Device:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 30),
                  Expanded(
                    child: DropdownButton(
                      items: _getDeviceItems(),
                      onChanged:
                          (BluetoothDevice? value) =>
                              setState(() => _device = value),
                      value: _device,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.brown,
                    ),
                    onPressed: () {
                      initPlatformState();
                    },
                    child: const Text(
                      'Refresh',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _connected ? Colors.red : Colors.green,
                    ),
                    onPressed: _connected ? _disconnect : _connect,
                    child: Text(
                      _connected ? 'Disconnect' : 'Connect',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(
                  left: 10.0,
                  right: 10.0,
                  top: 50,
                ),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.brown,
                  ),
                  onPressed: () {
                    final trx = Transaction(
                      id: "",
                      id_transaksi: widget.idTransaksi,
                      customerName: widget.customerName,
                      date: widget.date,
                      alamat: widget.alamat,
                      total: widget.total.toDouble(),
                      status: widget.status,
                      items:
                          widget.orderItems.map((item) {
                            return TransactionItem.fromData(
                              name:
                                  item['items']['name'], // ✅ Ambil dari nested map
                              price:
                                  (item['items']['harga'] as num)
                                      .toDouble(), // ✅ Pastikan double
                              quantity: item['quantity'],
                              bonus:
                                  item['items']['bonus'], // ✅ Key-nya quantity
                            );
                          }).toList(),
                    );
                    print('===== STRUK TRANSAKSI =====');
                    print('ID: ${trx.id}');
                    print('Nama: ${trx.customerName}');
                    print('Alamat: ${trx.alamat}');
                    print('Tanggal: ${trx.date}');
                    print('Items:');
                    for (var item in trx.items) {
                      print(
                        '- ${item.name} | Qty: ${item.quantity}|Bonus: ${item.bonus}| Price: ${item.price} | Subtotal: ${item.subtotal}',
                      );
                    }
                    print('PEMBAYARAN: ${trx.status}');
                    print('TOTAL: ${trx.total}');

                    print('===========================');

                    testPrint.printTransaction(trx);
                  },

                  child: const Text(
                    'PRINT STRUK',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text(
                  'Kembali',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<DropdownMenuItem<BluetoothDevice>> _getDeviceItems() {
    List<DropdownMenuItem<BluetoothDevice>> items = [];
    if (_devices.isEmpty) {
      items.add(DropdownMenuItem(child: Text('NONE')));
    } else {
      _devices.forEach((device) {
        items.add(
          DropdownMenuItem(child: Text(device.name ?? ""), value: device),
        );
      });
    }
    return items;
  }

  void _connect() {
    if (_device != null) {
      bluetooth.isConnected.then((isConnected) {
        if (isConnected == false) {
          bluetooth.connect(_device!).catchError((error) {
            setState(() => _connected = false);
          });
          setState(() => _connected = true);
        }
      });
    } else {
      show('No device selected.');
    }
  }

  void _disconnect() {
    bluetooth.disconnect();
    setState(() => _connected = false);
  }

  Future show(
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) async {
    await new Future.delayed(new Duration(milliseconds: 100));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        duration: duration,
      ),
    );
  }
}
