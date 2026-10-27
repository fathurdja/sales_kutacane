import 'dart:async';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/material.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/services/print.dart';
import 'package:kasir_kutacane/theme/app_theme.dart';

class PrintBluetoothAll extends StatefulWidget {
  final List<Transaction> allTransactions;

  const PrintBluetoothAll({super.key, required this.allTransactions});

  @override
  State<PrintBluetoothAll> createState() => _PrintBluetoothAllState();
}

class _PrintBluetoothAllState extends State<PrintBluetoothAll> {
  final BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;

  List<BluetoothDevice> _devices = [];
  BluetoothDevice? _device;
  bool _connected = false;
  bool _isConnecting = false;
  bool _isPrinting = false;
  StreamSubscription? _stateSubscription;
  final TestPrint testPrint = TestPrint();

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    super.dispose();
  }

  Future<void> initPlatformState() async {
    try {
      final isConnected = await bluetooth.isConnected ?? false;
      List<BluetoothDevice> devices = [];
      try {
        devices = await bluetooth.getBondedDevices();
      } catch (e) {
        debugPrint('Error getBondedDevices in PrintBluetoothAll: $e');
      }

      _stateSubscription?.cancel();
      _stateSubscription = bluetooth.onStateChanged().listen((state) {
        if (!mounted) return;
        switch (state) {
          case BlueThermalPrinter.CONNECTED:
            setState(() {
              _connected = true;
              _isConnecting = false;
            });
            break;
          case BlueThermalPrinter.DISCONNECTED:
          case BlueThermalPrinter.DISCONNECT_REQUESTED:
          case BlueThermalPrinter.STATE_OFF:
          case BlueThermalPrinter.ERROR:
            setState(() {
              _connected = false;
              _isConnecting = false;
            });
            break;
          default:
            break;
        }
      });

      if (!mounted) return;
      setState(() {
        _devices = devices;
        _connected = isConnected;
        if (_device == null && devices.isNotEmpty) {
          _device = devices.first;
        }
      });
    } catch (e) {
      debugPrint('Error initPlatformState: $e');
    }
  }

  Future<void> _connect() async {
    if (_device == null) {
      show("Pilih printer terlebih dahulu.", isError: true);
      return;
    }

    setState(() => _isConnecting = true);

    try {
      final isConnected = await bluetooth.isConnected ?? false;
      if (!isConnected) {
        await bluetooth.connect(_device!);
      }
      final verified = await bluetooth.isConnected ?? false;
      if (!mounted) return;

      setState(() {
        _connected = verified;
        _isConnecting = false;
      });

      if (verified) {
        show("Terhubung ke ${_device!.name ?? 'Printer'}!");
      } else {
        show("Gagal terhubung ke printer. Pastikan printer hidup.", isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connected = false;
        _isConnecting = false;
      });
      show("Koneksi gagal: $e", isError: true);
    }
  }

  Future<void> _disconnect() async {
    try {
      await bluetooth.disconnect();
      if (!mounted) return;
      setState(() => _connected = false);
      show("Koneksi printer diputuskan.");
    } catch (e) {
      if (!mounted) return;
      show("Gagal memutuskan: $e", isError: true);
    }
  }

  Future<void> printSingle(Transaction trx) async {
    if (!_connected) {
      show("Sambungkan printer terlebih dahulu sebelum mencetak.", isError: true);
      return;
    }

    setState(() => _isPrinting = true);
    try {
      final ok = await testPrint.printTransaction(trx);
      if (!mounted) return;
      if (ok) {
        show("Nota ${trx.id_transaksi} berhasil dicetak!");
      } else {
        show("Gagal mencetak nota ${trx.id_transaksi}.", isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      show("Error mencetak: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  Future<void> _printAll() async {
    if (!_connected) {
      show("Sambungkan printer terlebih dahulu sebelum mencetak.", isError: true);
      return;
    }

    if (widget.allTransactions.isEmpty) {
      show("Tidak ada transaksi untuk dicetak.", isError: true);
      return;
    }

    setState(() => _isPrinting = true);
    int successCount = 0;

    for (final trx in widget.allTransactions) {
      try {
        final ok = await testPrint.printTransaction(trx);
        if (ok) successCount++;
        // Beri jeda 800ms antar struk agar buffer printer tidak tersendat
        await Future.delayed(const Duration(milliseconds: 800));
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() => _isPrinting = false);
    show("Selesai mencetak $successCount dari ${widget.allTransactions.length} nota.");
  }

  void show(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.lunas,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Cetak Semua Transaksi"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: initPlatformState,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenMargin),
        child: Column(
          children: [
            // Status & Device Selector
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: AppShadow.card,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.bluetooth, color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<BluetoothDevice>(
                            isExpanded: true,
                            value: _device,
                            hint: const Text("Pilih Printer Bluetooth"),
                            items: _devices.isEmpty
                                ? [
                                    const DropdownMenuItem(
                                      value: null,
                                      child: Text("Tidak ada printer terpasang"),
                                    ),
                                  ]
                                : _devices.map((d) {
                                    return DropdownMenuItem(
                                      value: d,
                                      child: Text(
                                        d.name ?? "Unknown",
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                            onChanged: (d) => setState(() {
                              _device = d;
                              _connected = false;
                            }),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                _connected ? AppColors.error : AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onPressed: _isConnecting
                              ? null
                              : (_connected ? _disconnect : _connect),
                          icon: _isConnecting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  _connected
                                      ? Icons.bluetooth_disabled
                                      : Icons.bluetooth_connected,
                                  size: 18,
                                ),
                          label: Text(
                            _isConnecting
                                ? "Menghubungkan..."
                                : (_connected ? "Putuskan" : "Sambungkan"),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Header Daftar Transaksi & Tombol Print Semua
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Daftar Transaksi (${widget.allTransactions.length})",
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: (_isPrinting || !_connected) ? null : _printAll,
                  icon: _isPrinting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.print, size: 18),
                  label: const Text("PRINT SEMUA"),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // List of Transactions
            Expanded(
              child: widget.allTransactions.isEmpty
                  ? const Center(child: Text("Tidak ada transaksi"))
                  : ListView.builder(
                      itemCount: widget.allTransactions.length,
                      itemBuilder: (context, index) {
                        final trx = widget.allTransactions[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(
                              "${trx.id_transaksi} • ${trx.customerName}",
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                            subtitle: Text(
                              "Total: Rp ${trx.total.toStringAsFixed(0)} | Status: ${trx.status}",
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                minimumSize: Size.zero,
                              ),
                              onPressed: _isPrinting ? null : () => printSingle(trx),
                              child: const Text("Print", style: TextStyle(fontSize: 12)),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
