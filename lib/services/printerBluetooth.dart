import 'dart:async';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/material.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/models/transactionItem.dart';
import 'package:kasir_kutacane/services/print.dart';
import 'package:kasir_kutacane/theme/app_theme.dart';

class Printbluetooth extends StatefulWidget {
  final List<Map<String, dynamic>> orderItems;
  final String paymentMethod;
  final int total;
  final DateTime date;
  final String customerName;
  final String alamat;
  final String idTransaksi;
  final String status;
  final Transaction? transaction;

  const Printbluetooth({
    super.key,
    required this.orderItems,
    required this.paymentMethod,
    required this.total,
    required this.date,
    required this.customerName,
    required this.alamat,
    required this.idTransaksi,
    required this.status,
    this.transaction,
  });

  // ignore: prefer_initializing_formals
  Printbluetooth.fromTransaction({
    super.key,
    required Transaction transaction,
  })  : transaction = transaction,
        orderItems = transaction.items.map((item) {
          return {
            'items': {
              'name': item.name,
              'harga': item.price,
              'bonus': item.bonus,
            },
            'quantity': item.quantity,
          };
        }).toList(),
        paymentMethod = 'Tunai',
        total = transaction.total.toInt(),
        date = transaction.date,
        customerName = transaction.customerName,
        alamat = transaction.alamat,
        idTransaksi = transaction.id_transaksi,
        status = transaction.status;

  @override
  State<Printbluetooth> createState() => _PrintbluetoothState();
}

typedef PrinterBluetooth = Printbluetooth;

class _PrintbluetoothState extends State<Printbluetooth> {
  final BlueThermalPrinter _bluetooth = BlueThermalPrinter.instance;

  List<BluetoothDevice> _devices = [];
  BluetoothDevice? _device;
  bool _connected = false;
  bool _isConnecting = false;
  bool _isPrinting = false;
  bool _isLoadingDevices = false;
  StreamSubscription? _stateSubscription;
  final TestPrint _testPrint = TestPrint();

  @override
  void initState() {
    super.initState();
    _initBluetooth();
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initBluetooth() async {
    setState(() => _isLoadingDevices = true);

    try {
      final isConnected = await _bluetooth.isConnected ?? false;

      List<BluetoothDevice> devices = [];
      try {
        devices = await _bluetooth.getBondedDevices();
      } catch (e) {
        debugPrint('Error getBondedDevices: $e');
      }

      _stateSubscription?.cancel();
      _stateSubscription = _bluetooth.onStateChanged().listen((state) {
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
        _isLoadingDevices = false;
        // Otomatis pilih perangkat pertama jika ada
        if (_device == null && devices.isNotEmpty) {
          _device = devices.first;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingDevices = false);
      _showSnackbar('Gagal membaca perangkat Bluetooth: $e', isError: true);
    }
  }

  Future<void> _connect() async {
    if (_device == null) {
      _showSnackbar('Pilih printer Bluetooth terlebih dahulu.', isError: true);
      return;
    }

    setState(() => _isConnecting = true);

    try {
      final alreadyConnected = await _bluetooth.isConnected ?? false;
      if (!alreadyConnected) {
        await _bluetooth.connect(_device!);
      }

      // Verifikasi koneksi setelah connect
      final isNowConnected = await _bluetooth.isConnected ?? false;
      if (!mounted) return;

      setState(() {
        _connected = isNowConnected;
        _isConnecting = false;
      });

      if (isNowConnected) {
        _showSnackbar('Berhasil terhubung ke ${_device!.name ?? "Printer"}!');
      } else {
        _showSnackbar(
          'Gagal terhubung. Pastikan printer hidup dan Bluetooth aktif.',
          isError: true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connected = false;
        _isConnecting = false;
      });
      _showSnackbar('Koneksi gagal: $e. Pastikan printer siap.', isError: true);
    }
  }

  Future<void> _disconnect() async {
    try {
      await _bluetooth.disconnect();
      if (!mounted) return;
      setState(() => _connected = false);
      _showSnackbar('Printer Bluetooth terputus.');
    } catch (e) {
      if (!mounted) return;
      _showSnackbar('Gagal memutuskan printer: $e', isError: true);
    }
  }

  Future<void> _handlePrint() async {
    if (_device == null) {
      _showSnackbar(
        'Pilih printer Bluetooth terlebih dahulu.',
        isError: true,
      );
      return;
    }

    // Jika belum terhubung, coba sambungkan otomatis
    if (!_connected) {
      _showSnackbar('Menghubungkan ke ${_device!.name ?? "Printer"}...');
      setState(() => _isConnecting = true);

      try {
        await _bluetooth.connect(_device!);
        final isNowConnected = await _bluetooth.isConnected ?? false;
        if (!mounted) return;

        setState(() {
          _connected = isNowConnected;
          _isConnecting = false;
        });

        if (!isNowConnected) {
          _showSnackbar(
            'Printer belum tersambung. Klik tombol "Sambungkan" terlebih dahulu.',
            isError: true,
          );
          return;
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _connected = false;
          _isConnecting = false;
        });
        _showSnackbar('Gagal menyambungkan: $e', isError: true);
        return;
      }
    }

    setState(() => _isPrinting = true);

    try {
      final trx = widget.transaction ??
          Transaction(
            id: "",
            id_transaksi: widget.idTransaksi,
            customerName: widget.customerName,
            date: widget.date,
            alamat: widget.alamat,
            total: widget.total.toDouble(),
            status: widget.status,
            items: widget.orderItems.map((item) {
              final rawItem = item['items'] as Map<String, dynamic>? ?? {};
              return TransactionItem.fromData(
                name: rawItem['name']?.toString() ?? '',
                price: (rawItem['harga'] as num?)?.toDouble() ?? 0.0,
                quantity: (item['quantity'] as num?)?.toInt() ?? 1,
                bonus: (rawItem['bonus'] as num?)?.toInt() ?? 0,
              );
            }).toList(),
          );

      final success = await _testPrint.printTransaction(trx);
      if (!mounted) return;

      if (success) {
        _showSnackbar('Struk transaksi berhasil dicetak!');
      } else {
        _showSnackbar(
          'Gagal mencetak struk. Pastikan printer terhubung dan kertas cukup.',
          isError: true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackbar('Terjadi kesalahan saat mencetak: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  Future<void> _handleTestPrint() async {
    if (!_connected) {
      _showSnackbar(
        'Sambungkan ke printer terlebih dahulu untuk tes cetak.',
        isError: true,
      );
      return;
    }

    setState(() => _isPrinting = true);
    try {
      final success = await _testPrint.printTestReceipt();
      if (!mounted) return;

      if (success) {
        _showSnackbar('Tes cetak berhasil keluar!');
      } else {
        _showSnackbar('Tes cetak gagal. Periksa koneksi printer.', isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackbar('Gagal tes cetak: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  void _showSnackbar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: isError ? AppColors.error : AppColors.lunas,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Printer Bluetooth'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Segarkan Perangkat',
            onPressed: _isLoadingDevices ? null : _initBluetooth,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenMargin),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card
            _buildStatusCard(),
            const SizedBox(height: 16),

            // Device Selector Card
            _buildDeviceSelectorCard(),
            const SizedBox(height: 16),

            // Action Buttons Card
            _buildActionCard(),
            const SizedBox(height: 20),

            // Troubleshooting & Guide Card
            _buildGuideCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final statusColor = _connected
        ? AppColors.lunas
        : (_isConnecting ? Colors.orange : Colors.grey.shade600);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
        boxShadow: AppShadow.card,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _connected ? Icons.print : Icons.print_disabled,
              color: statusColor,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _connected
                          ? 'Printer Terhubung'
                          : (_isConnecting
                              ? 'Menghubungkan...'
                              : 'Printer Belum Terhubung'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  _device != null
                      ? '${_device!.name ?? "Perangkat"} (${_device!.address})'
                      : 'Belum ada printer yang dipilih',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceSelectorCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: AppShadow.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pilih Printer Termal (Paired)',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Printer harus sudah dipasangkan di Pengaturan Bluetooth HP',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),

          // Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<BluetoothDevice>(
                isExpanded: true,
                value: _device,
                hint: const Text('Pilih perangkat Bluetooth'),
                items: _devices.isEmpty
                    ? [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Tidak ada printer terpasang (Paired)'),
                        ),
                      ]
                    : _devices.map((device) {
                        return DropdownMenuItem(
                          value: device,
                          child: Row(
                            children: [
                              const Icon(Icons.bluetooth,
                                  size: 18, color: AppColors.primary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '${device.name ?? "Unknown"} (${device.address})',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _device = val;
                      _connected = false;
                    });
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Connect / Disconnect Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isConnecting
                      ? null
                      : (_connected ? _disconnect : _connect),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _connected ? AppColors.error : AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: _isConnecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
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
                        ? 'Menghubungkan...'
                        : (_connected ? 'Putuskan Koneksi' : 'Sambungkan'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _isLoadingDevices ? null : _initBluetooth,
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: AppShadow.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tombol Cetak Utama
          ElevatedButton.icon(
            onPressed: _isPrinting ? null : _handlePrint,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
            icon: _isPrinting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.print_rounded, size: 22),
            label: Text(
              _isPrinting ? 'Sedang Mencetak...' : 'CETAK STRUK SEKARANG',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Tombol Tes Cetak Singkat
          OutlinedButton.icon(
            onPressed: (_isPrinting || !_connected) ? null : _handleTestPrint,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.receipt_long, size: 18),
            label: const Text(
              'Tes Cetak Struk Singkat (Uji Koneksi)',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: AppColors.primary),
              SizedBox(width: 8),
              Text(
                'Panduan Penggunaan Printer Bluetooth:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildGuideStep('1', 'Nyalakan Printer Termal Bluetooth (lampu power menyala).'),
          _buildGuideStep('2', 'Pastikan Bluetooth HP aktif dan pasangkan (Pair) printer di Pengaturan Bluetooth HP (PIN pairing biasanya: 0000 atau 1234).'),
          _buildGuideStep('3', 'Buka halaman ini, pilih nama printer Anda pada pilihan di atas, lalu tekan tombol "Sambungkan".'),
          _buildGuideStep('4', 'Tekan tombol "CETAK STRUK SEKARANG" untuk mencetak.'),
        ],
      ),
    );
  }

  Widget _buildGuideStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(top: 2, right: 8),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
