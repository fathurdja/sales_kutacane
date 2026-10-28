import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/config/api_config.dart';
import 'package:kasir_kutacane/models/Item.dart';
import 'package:kasir_kutacane/models/customer_model.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/models/transactionItem.dart';
import 'package:kasir_kutacane/pages/stock_input_page.dart';
import 'package:kasir_kutacane/services/auth_service.dart';
import 'package:kasir_kutacane/services/customer_api_service.dart';
import 'package:kasir_kutacane/services/offline_sync_service.dart';
import 'package:kasir_kutacane/services/pdf_invoice_service.dart';
import 'package:kasir_kutacane/services/pelunasan_history_service.dart';
import 'package:kasir_kutacane/services/printerBluetooth.dart';
import 'package:kasir_kutacane/services/stock_api_service.dart';
import 'package:kasir_kutacane/theme/app_theme.dart';
import 'package:kasir_kutacane/widgets/app_widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StockQuotaException implements Exception {
  final String message;
  StockQuotaException(this.message);
  @override
  String toString() => message;
}

enum SaveDestination {
  primaryServer,
  supabaseBackup,
  offlineLocal,
}

class TransactionInputPage extends StatefulWidget {
  final Function(Transaction) onSave;
  final Transaction? transaction;
  final Function(int)? onNavigateTab;

  const TransactionInputPage({
    super.key,
    required this.onSave,
    this.transaction,
    this.onNavigateTab,
  });

  @override
  State<TransactionInputPage> createState() => _TransactionInputPageState();
}

class _TransactionInputPageState extends State<TransactionInputPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _alamatCustomer = TextEditingController();
  final List<TransactionItem> _items = [TransactionItem()];

  // Master Pelanggan & Dropdown Autocomplete
  List<Customer> _masterCustomers = [];
  List<Customer> _customerSuggestions = [];
  bool _showCustomerDropdown = false;
  final FocusNode _customerFocusNode = FocusNode();

  DateTime _selectedDate = DateTime.now();
  String _transactionId = '';
  List<Item> _products = [];
  bool _isLoadingProducts = false;
  bool _isSaving = false;
  String _paymentStatus = 'LUNAS';

  static int _transactionCounter = 0;

  @override
  void initState() {
    super.initState();
    _fetchProducts();
    _fetchCustomers();
    if (widget.transaction != null) {
      _transactionId = widget.transaction!.id_transaksi;
      _customerNameController.text = widget.transaction!.customerName;
      _alamatCustomer.text = widget.transaction!.alamat;
      _selectedDate = widget.transaction!.date;
      _paymentStatus = widget.transaction!.status;
      _items.clear();
      for (var item in widget.transaction!.items) {
        _items.add(
          TransactionItem.fromData(
            name: item.name,
            price: item.price,
            quantity: item.quantity,
            bonus: item.bonus,
            tyunit: item.tyunit,
          ),
        );
      }
    } else {
      _generateTransactionId();
    }
  }

  @override
  void dispose() {
    _customerFocusNode.dispose();
    _customerNameController.dispose();
    _alamatCustomer.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchCustomers() async {
    try {
      final list = await CustomerApiService.fetchCustomers();
      if (!mounted) return;
      setState(() {
        _masterCustomers = list;
      });
    } catch (e) {
      debugPrint("Error fetching master customers in transaction input: $e");
    }
  }

  void _onCustomerNameChanged(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() {
        _customerSuggestions = [];
        _showCustomerDropdown = false;
      });
      return;
    }

    final filtered = _masterCustomers.where((c) {
      return c.name.toLowerCase().contains(q) ||
          c.alamat.toLowerCase().contains(q);
    }).toList();

    setState(() {
      _customerSuggestions = filtered;
      _showCustomerDropdown = true;
    });
  }

  void _selectCustomer(Customer c) {
    setState(() {
      _customerNameController.text = c.name;
      if (c.alamat.isNotEmpty) {
        _alamatCustomer.text = c.alamat;
      }
      _showCustomerDropdown = false;
    });
    FocusScope.of(context).unfocus();
  }

  void _openAddNewCustomerDialog(String initialName) {
    setState(() => _showCustomerDropdown = false);
    final nameCtrl = TextEditingController(text: initialName);
    final alamatCtrl = TextEditingController(
      text: _alamatCustomer.text.trim().isNotEmpty
          ? _alamatCustomer.text.trim()
          : 'Gorontalo',
    );
    final teleponCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.dialog),
            ),
            title: const Row(
              children: [
                Icon(Icons.person_add_alt_1_rounded, color: AppColors.primary),
                SizedBox(width: 8),
                Text('Tambah Pelanggan Baru', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nama Pelanggan / Toko *',
                        prefixIcon: Icon(Icons.storefront_outlined, size: 20),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Nama pelanggan wajib diisi';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: alamatCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Alamat Pelanggan *',
                        prefixIcon: Icon(Icons.location_on_outlined, size: 20),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Alamat pelanggan wajib diisi';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: teleponCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'No. Telepon / WhatsApp (Opsional)',
                        prefixIcon: Icon(Icons.phone_outlined, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: isSaving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setDlgState(() => isSaving = true);
                        try {
                          final newCust = await CustomerApiService.addCustomer(
                            name: nameCtrl.text.trim(),
                            alamat: alamatCtrl.text.trim(),
                            telepon: teleponCtrl.text.trim(),
                          );
                          if (!mounted) return;
                          setState(() {
                            _masterCustomers.removeWhere((c) =>
                                c.name.toLowerCase() ==
                                newCust.name.toLowerCase());
                            _masterCustomers.add(newCust);
                            _customerNameController.text = newCust.name;
                            _alamatCustomer.text = newCust.alamat;
                            _showCustomerDropdown = false;
                          });
                          if (ctx.mounted) Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Pelanggan "${newCust.name}" berhasil didaftarkan!',
                              ),
                              backgroundColor: AppColors.lunas,
                            ),
                          );
                        } catch (e) {
                          setDlgState(() => isSaving = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Gagal menambah pelanggan: $e'),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Simpan & Gunakan'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _generateTransactionId() async {
    final now = DateTime.now();
    final formatter = DateFormat('yyyyMMdd');
    final datePart = formatter.format(now);

    String newId;
    bool exists = true;

    do {
      _transactionCounter++;
      final uniqueNumber = _transactionCounter.toString().padLeft(4, '0');
      newId = 'Trx-$datePart-$uniqueNumber';
      exists = await _checkTransactionIdExists(newId);
    } while (exists);

    if (!mounted) return;
    setState(() {
      _transactionId = newId;
    });
  }

  Future<void> _fetchProducts() async {
    setState(() => _isLoadingProducts = true);

    try {
      // Ambil daftar 13 produk lengkap dengan sisa kuota komoditas terbaru dari backend
      final items = await StockApiService.fetchProducts();
      if (items.isNotEmpty) {
        await OfflineSyncService.cacheProducts(items);
        if (!mounted) return;
        setState(() {
          _products = items;
          _isLoadingProducts = false;
        });
        return;
      }
    } catch (e) {
      debugPrint("Koneksi server gagal/offline, memuat cache produk lokal: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoadingProducts = false);
      }
    }

    // Jika server sedang offline / downtime, gunakan cache lokal HP
    final cached = await OfflineSyncService.getCachedProducts();
    if (mounted) {
      setState(() {
        _products = cached;
        _isLoadingProducts = false;
      });
    }
  }

  String _resolveTyunit(TransactionItem item) {
    if (item.tyunit != null &&
        item.tyunit!.trim().isNotEmpty &&
        item.tyunit!.trim().toUpperCase() != 'BV01') {
      return item.tyunit!.trim().toUpperCase();
    }
    return OfflineSyncService.resolveItemTyunit(
      item.tyunit,
      item.nameController.text,
      item.price,
      _products,
    );
  }

  Future<bool> _checkTransactionIdExists(String id) async {
    // 1. Cek dari antrean transaksi lokal HP
    try {
      final pending = await OfflineSyncService.getPendingTransactions();
      if (pending.any((trx) => trx.id_transaksi == id)) {
        return true;
      }
    } catch (_) {}

    // 2. Cek ke server utama jika sedang terkoneksi
    final apiUrl = '${ApiConfig.baseUrl}/transaksi';
    try {
      final response = await http
          .get(
            Uri.parse('$apiUrl?search=$id'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.any((trx) => trx['id_transaksi'] == id);
      }
    } catch (e) {
      debugPrint('Error checking ID (offline mode): $e');
    }
    return false;
  }

  Future<void> _saveToSupabase(Transaction transaction) async {
    final supabase = Supabase.instance.client;
    final user = AuthService.currentUser;
    await supabase.from('transaksi').insert({
      'id_transaksi': transaction.id_transaksi,
      'customer_name': transaction.customerName,
      'alamat': transaction.alamat,
      'tanggal': transaction.date.toIso8601String(),
      'total': transaction.total.toInt(),
      'status': _paymentStatus,
      'is_backup': true,
      'sales_name': user?.name,
    });

    final itemsJson = transaction.items
        .map(
          (item) => {
            'id_transaksi': transaction.id_transaksi,
            'tyunit': _resolveTyunit(item),
            'nama_barang': item.nameController.text,
            'harga': item.price.toInt(),
            'quantity': item.quantity,
            'bonus': item.bonus,
            'subtotal': item.subtotal.toInt(),
          },
        )
        .toList();

    await supabase.from('transaksi_items').insert(itemsJson);
  }

  Future<SaveDestination> _saveTransactionToApi(Transaction transaction) async {
    final isEditing = widget.transaction != null;
    if (isEditing) {
      // MODE EDIT TRANSAKSI:
      // Update data transaksi yang ada via PUT tanpa mengurangi kuota stok lagi
      final updateUrl = '${ApiConfig.baseUrl}/transaksi/${transaction.id_transaksi}';
      final formattedPelunasan = _paymentStatus == 'LUNAS'
          ? DateFormat('yyyy-MM-dd').format(DateTime.now())
          : null;

      final editPayload = {
        'status': _paymentStatus,
        'customer_name': transaction.customerName,
        'customerName': transaction.customerName,
        'alamat': transaction.alamat,
        'total': transaction.total.truncateToDouble() == transaction.total
            ? transaction.total.toInt()
            : transaction.total,
        if (_paymentStatus == 'LUNAS')
          'tanggal_pelunasan': formattedPelunasan,
      };

      try {
        final headers = await AuthService.getAuthHeaders();
        await http.put(
          Uri.parse(updateUrl),
          headers: headers,
          body: jsonEncode(editPayload),
        ).timeout(const Duration(seconds: 8));
      } catch (e) {
        debugPrint("API edit PUT failed ($e).");
      }

      // Sinkronkan juga ke Supabase
      try {
        final supabase = Supabase.instance.client;
        await supabase.from('transaksi').update({
          'status': _paymentStatus,
          'customer_name': transaction.customerName,
          'alamat': transaction.alamat,
          'total': transaction.total.toInt(),
          if (_paymentStatus == 'LUNAS')
            'tanggal_pelunasan': formattedPelunasan,
        }).eq('id_transaksi', transaction.id_transaksi);
      } catch (errSupabase) {
        debugPrint("Supabase edit update error: $errSupabase");
      }

      // Kelola PelunasanHistoryService lokal
      if (_paymentStatus == 'LUNAS') {
        transaction.tanggalPelunasan = DateTime.now();
        await PelunasanHistoryService.recordSettlement(
          idTransaksi: transaction.id_transaksi,
          customerName: transaction.customerName,
          total: transaction.total,
          tanggalPelunasan: DateTime.now(),
        );
      } else {
        transaction.tanggalPelunasan = null;
        await PelunasanHistoryService.removeSettlement(transaction.id_transaksi);
      }

      transaction.isOffline = false;
      return SaveDestination.primaryServer;
    }

    final url = '${ApiConfig.baseUrl}/transaksi';

    final formattedDate =
        DateFormat('yyyy-MM-dd HH:mm:ss').format(transaction.date);

    final currentUser = AuthService.currentUser;
    if (transaction.userId == null && currentUser != null) {
      transaction.userId = currentUser.id;
      transaction.userName = currentUser.name;
    }

    final payload = {
      'id_transaksi': transaction.id_transaksi,
      'customerName': transaction.customerName,
      'alamat': transaction.alamat,
      'date': formattedDate,
      'user_id': transaction.userId,
      'user_name': transaction.userName,
      'total': transaction.total.truncateToDouble() == transaction.total
          ? transaction.total.toInt()
          : transaction.total,
      'status': _paymentStatus,
      'items': transaction.items.map((item) {
        final tyunit = _resolveTyunit(item);
        final price = item.price.truncateToDouble() == item.price
            ? item.price.toInt()
            : item.price;
        final subtotal = item.subtotal.truncateToDouble() == item.subtotal
            ? item.subtotal.toInt()
            : item.subtotal;
        return {
          'tyunit': tyunit,
          'price': price,
          'quantity': item.quantity,
          'bonus': item.bonus,
          'subtotal': subtotal,
        };
      }).toList(),
    };

    // 1. Coba kirim langsung ke Server Utama (Laravel)
    try {
      final headers = await AuthService.getAuthHeaders();
      final response = await http
          .post(
            Uri.parse(url),
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200 || response.statusCode == 201) {
        transaction.isOffline = false;
        await _decrementLocalStock(transaction.items);
        return SaveDestination.primaryServer;
      }

      String errorMessage = 'Server merespon status ${response.statusCode}';
      try {
        final resJson = jsonDecode(response.body);
        if (resJson is Map && resJson.containsKey('message')) {
          errorMessage = resJson['message'].toString();
        }
      } catch (_) {}

      // Jika kuota stok komoditas fisik kurang (HTTP 400), jangan failover ke offline!
      // Kasir harus diberi peringatan kuota secara transparan.
      if (response.statusCode == 400 ||
          errorMessage.toLowerCase().contains('kuota') ||
          errorMessage.toLowerCase().contains('melebihi')) {
        throw StockQuotaException(errorMessage);
      }

      debugPrint("Server utama merespon error ($errorMessage). Melakukan failover...");
      throw Exception(errorMessage);
    } catch (e) {
      if (e is StockQuotaException) {
        rethrow;
      }
      debugPrint("Server utama gagal ($e). Mencoba ke Supabase...");
      // 2. Coba simpan ke server cadangan Supabase jika online
      try {
        await _saveToSupabase(transaction);
        transaction.isOffline = false;
        await _decrementLocalStock(transaction.items);
        return SaveDestination.supabaseBackup;
      } catch (supabaseError) {
        debugPrint(
            "Supabase juga tidak dapat dijangkau ($supabaseError). Masuk ke Mode Offline Lokal...");
      }

      // 3. OFFLINE BACKUP LOKAL (Paling aman):
      // Simpan ke berkas JSON lokal di smartphone kasir agar transaksi tidak pernah hilang
      try {
        transaction.isOffline = true;
        await OfflineSyncService.saveOfflineTransaction(transaction);
        await _decrementLocalStock(transaction.items);
        return SaveDestination.offlineLocal;
      } catch (localError) {
        throw Exception(
            'Gagal menyimpan nota baik di server maupun lokal: $localError');
      }
    }
  }

  Future<void> _decrementLocalStock(List<TransactionItem> items) async {
    try {
      final cached = await OfflineSyncService.getCachedProducts();
      if (cached.isEmpty) return;

      bool changed = false;
      for (final item in items) {
        final tyunit = _resolveTyunit(item);
        final matchedItem = cached.firstWhere(
          (p) =>
              p.tyunit.toLowerCase() == tyunit.toLowerCase() ||
              p.name.toLowerCase() == item.nameController.text.toLowerCase(),
          orElse: () => Item(tyunit: '', name: '', price: 0),
        );

        if (matchedItem.tyunit.isNotEmpty) {
          final totalDeducted = item.quantity + item.bonus;
          final targetKelompok = matchedItem.kelompok;

          // Kurangi kuota seluruh item yang memiliki kelompok komoditas sama
          for (int i = 0; i < cached.length; i++) {
            if (cached[i].tyunit == matchedItem.tyunit ||
                (targetKelompok.isNotEmpty && cached[i].kelompok == targetKelompok)) {
              final newStock = (cached[i].stock - totalDeducted).clamp(0, 999999);
              final newSisa = (cached[i].sisaKuota - totalDeducted).clamp(0, 999999);
              final newTerjual = cached[i].terjual +
                  (cached[i].tyunit == matchedItem.tyunit ? totalDeducted : 0);

              cached[i] = Item(
                tyunit: cached[i].tyunit,
                name: cached[i].name,
                price: cached[i].price,
                stock: newStock,
                kelompok: cached[i].kelompok,
                kuota: cached[i].kuota,
                terjual: newTerjual,
                sisaKuota: newSisa,
              );
              changed = true;
            }
          }
        }
      }

      if (changed) {
        await OfflineSyncService.cacheProducts(cached);
        if (mounted) {
          setState(() {
            _products = cached;
          });
        }
      }
    } catch (e) {
      debugPrint("Gagal update stok lokal setelah transaksi: $e");
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  void _addItemField() {
    setState(() {
      _items.add(TransactionItem());
    });
  }

  void _removeItemField(int index) {
    if (_items.length <= 1) return;
    setState(() {
      _items[index].dispose();
      _items.removeAt(index);
    });
  }

  double _calculateTotal() {
    return _items.fold(0.0, (sum, item) => sum + item.subtotal);
  }

  void _openProductPicker(int index) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ProductPickerSheet(
        products: _products,
        isLoading: _isLoadingProducts,
        onSelect: (product) {
          setState(() {
            _items[index].selectedItem = product;
            _items[index].nameController.text = product.name;
            _items[index].priceController.text = product.price.toString();
            _items[index].tyunit = product.tyunit;
          });
        },
      ),
    );
  }

  Future<void> _saveTransaction() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    for (int i = 0; i < _items.length; i++) {
      if (_items[i].nameController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Silakan pilih produk untuk Barang #${i + 1}'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
    }

    // Validasi kuantitas item minimal 1
    for (int i = 0; i < _items.length; i++) {
      final item = _items[i];
      final requestedQty = item.quantity + item.bonus;
      if (requestedQty <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Jumlah untuk Barang #${i + 1} minimal 1'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
    }

    // 1 & 2. Validasi Kuota Stok Gudang (HANYA UNTUK TRANSAKSI BARU)
    // Saat mengedit transaksi lama (misal: ubah BON/QRIS ke LUNAS), stok sudah berkurang saat nota dibuat
    final isEditing = widget.transaction != null;
    if (!isEditing) {
      // Validasi Stok per Item
      for (int i = 0; i < _items.length; i++) {
        final item = _items[i];
        final tyunit = _resolveTyunit(item);
        final matched = _products.firstWhere(
          (p) =>
              p.tyunit.toLowerCase() == tyunit.toLowerCase() ||
              p.name.toLowerCase() == item.nameController.text.trim().toLowerCase(),
          orElse: () => Item(
            tyunit: tyunit,
            name: item.nameController.text,
            price: item.price,
            stock: 0,
          ),
        );

        final availableStock = matched.stock;
        final requestedQty = item.quantity + item.bonus;

        if (availableStock <= 0) {
          _showStockQuotaWarning(
            'Produk "${item.nameController.text}" tidak dapat dibuatkan nota karena stoknya 0 (Habis).\n\n'
            'Harap lakukan input stok awal armada terlebih dahulu atau hapus barang ini dari nota.',
          );
          return;
        }

        if (requestedQty > availableStock) {
          _showStockQuotaWarning(
            'Jumlah pesanan untuk "${item.nameController.text}" ($requestedQty item termasuk bonus) '
            'melebihi stok yang tersedia ($availableStock item).\n\n'
            'Harap kurangi jumlah pesanan atau lakukan penambahan stok awal.',
          );
          return;
        }
      }

      // Validasi per Kelompok Komoditas Fisik Agregat
      final Map<String, int> groupTotalRequested = {};
      for (final item in _items) {
        final tyunit = _resolveTyunit(item);
        final matched = _products.firstWhere(
          (p) =>
              p.tyunit.toLowerCase() == tyunit.toLowerCase() ||
              p.name.toLowerCase() == item.nameController.text.trim().toLowerCase(),
          orElse: () => Item(
            tyunit: tyunit,
            name: item.nameController.text,
            price: item.price,
            stock: 0,
          ),
        );
        final gKey = matched.kelompok.toUpperCase();
        if (gKey.isNotEmpty) {
          groupTotalRequested[gKey] =
              (groupTotalRequested[gKey] ?? 0) + item.quantity + item.bonus;
        }
      }

      for (final entry in groupTotalRequested.entries) {
        final gKey = entry.key;
        final totalRequested = entry.value;
        final matchedProduct = _products.firstWhere(
          (p) => p.kelompok.toUpperCase() == gKey,
          orElse: () => Item(tyunit: '', name: '', price: 0, stock: 0),
        );
        final groupStock = matchedProduct.stock;
        if (groupStock <= 0) {
          _showStockQuotaWarning(
            'Kelompok komoditas "$gKey" memiliki stok 0 (Habis).\n\n'
            'Tidak dapat membuat nota untuk kelompok ini sebelum stok awal diisi.',
          );
          return;
        }
        if (totalRequested > groupStock) {
          _showStockQuotaWarning(
            'Total permintaan komoditas "$gKey" dalam nota ini ($totalRequested item) '
            'melebihi sisa stok armada yang tersedia ($groupStock item).\n\n'
            'Harap sesuaikan jumlah barang.',
          );
          return;
        }
      }
    }

    setState(() => _isSaving = true);

    if (widget.transaction == null) {
      final exists = await _checkTransactionIdExists(_transactionId);
      if (exists) {
        await _generateTransactionId();
      }
    }

    // Pastikan setiap item memiliki kode tyunit spesifik sebelum disimpan
    for (final it in _items) {
      it.tyunit = _resolveTyunit(it);
    }

    final newTransaction = Transaction(
      id: widget.transaction?.id ?? '',
      id_transaksi: widget.transaction?.id_transaksi ?? _transactionId,
      customerName: _customerNameController.text.trim(),
      alamat: _alamatCustomer.text.trim(),
      date: _selectedDate,
      items: List.from(_items),
      total: _calculateTotal(),
      status: _paymentStatus,
      userId: AuthService.currentUser?.id,
      userName: AuthService.currentUser?.name,
    );

    try {
      final destination = await _saveTransactionToApi(newTransaction);
      if (!mounted) return;

      widget.onSave(newTransaction);
      _showSuccessDialog(newTransaction, destination);
    } on StockQuotaException catch (sqe) {
      if (!mounted) return;
      _showStockQuotaWarning(sqe.message);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal menyimpan nota: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showStockQuotaWarning(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.inventory_2_outlined, color: AppColors.error, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Kuota Stok Tidak Cukup',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: const TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.amber),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Silakan sesuaikan jumlah barang nota atau input penambahan kuota stok awal.',
                      style: TextStyle(fontSize: 11.5, color: Colors.brown),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Sesuaikan Jumlah'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.add_box_outlined, size: 16),
            label: const Text('Input Stok Awal'),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StockInputPage()),
              ).then((_) => _fetchProducts());
            },
          ),
        ],
      ),
    );
  }

  void _resetForm() {
    _customerNameController.clear();
    _alamatCustomer.clear();
    for (final item in _items) {
      item.dispose();
    }
    setState(() {
      _items.clear();
      _items.add(TransactionItem());
      _selectedDate = DateTime.now();
      _paymentStatus = 'LUNAS';
    });
    _generateTransactionId();
  }

  void _showSuccessDialog(Transaction transaction, SaveDestination destination) {
    final currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ');

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: destination == SaveDestination.offlineLocal
                        ? Colors.amber.shade100
                        : AppColors.lunasBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    destination == SaveDestination.offlineLocal
                        ? Icons.cloud_off_rounded
                        : Icons.check_circle_rounded,
                    color: destination == SaveDestination.offlineLocal
                        ? Colors.amber.shade900
                        : AppColors.lunas,
                    size: 38,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  destination == SaveDestination.offlineLocal
                      ? 'Nota Disimpan Secara Offline!'
                      : 'Nota Berhasil Disimpan!',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${transaction.id_transaksi} • ${transaction.customerName}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  currencyFormat.format(transaction.total),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                if (destination == SaveDestination.offlineLocal) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      border: Border.all(color: Colors.amber.shade400),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.offline_pin_rounded,
                            size: 16, color: Colors.amber.shade900),
                        const SizedBox(width: 6),
                        Text(
                          'Tersimpan di Memori HP (Mode Offline)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Server offline/downtime. Nota tetap aman tersimpan di HP & siap disinkronkan saat server kembali online.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ] else if (destination == SaveDestination.supabaseBackup) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.backupBg,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_done, size: 14, color: AppColors.backup),
                        SizedBox(width: 6),
                        Text(
                          'Tersimpan di Server Cadangan (Supabase)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.backup,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                // Tombol Aksi: Cetak Struk & Kirim PDF
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.button),
                          ),
                        ),
                        icon: const Icon(Icons.print, size: 20),
                        label: const Text('Cetak Struk'),
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => Printbluetooth.fromTransaction(
                                transaction: transaction,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.button),
                          ),
                        ),
                        icon: const Icon(Icons.share, size: 20),
                        label: const Text('Kirim PDF'),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await _sharePdfInvoice(transaction);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      if (widget.transaction != null) {
                        Navigator.pop(context, transaction);
                      } else {
                        _resetForm();
                        widget.onNavigateTab?.call(1);
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context, transaction);
                        }
                      }
                    },
                    child: const Text('Selesai / Kembali'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _sharePdfInvoice(Transaction transaction) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Menyiapkan faktur PDF resmi...'),
        duration: Duration(seconds: 1),
      ),
    );
    await PdfInvoiceService.sharePdf(
      context: context,
      transaction: transaction,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.transaction != null ? 'Edit Transaksi' : 'Nota Baru'),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(AppRadius.chipFull),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.tag, size: 14, color: AppColors.primary),
                const SizedBox(width: 4),
                Text(
                  _transactionId.isEmpty ? 'Memuat ID...' : _transactionId,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.screenMargin),
                children: [
                  // Banner Peringatan jika semua stok 0
                  if (_products.isNotEmpty && _products.every((p) => p.stock <= 0)) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: AppSpacing.md),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: Colors.red.shade700, size: 26),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Perhatian: Seluruh Stok Komoditas Habis (0)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: Colors.red.shade800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Stok armada belum diisi atau kuota sudah habis. Harap input stok awal terlebih dahulu agar dapat membuat nota.',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const StockInputPage(),
                              ),
                            ).then((_) => _fetchProducts()),
                            child: const Text(
                              'Input Stok',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // CARD: Data Konsumen & Pembayaran
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(color: AppColors.surfaceBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Informasi Konsumen',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        // Input Nama Konsumen dengan Dropdown Autocomplete Master Pelanggan
                        TextFormField(
                          controller: _customerNameController,
                          focusNode: _customerFocusNode,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: 'Nama Konsumen *',
                            hintText: 'Ketik inisial toko/pelanggan...',
                            prefixIcon: const Icon(Icons.person_outline, size: 20),
                            suffixIcon: _customerNameController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _customerNameController.clear();
                                      _onCustomerNameChanged('');
                                    },
                                  )
                                : const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary),
                          ),
                          onChanged: _onCustomerNameChanged,
                          onTap: () {
                            if (_customerNameController.text.trim().isNotEmpty) {
                              _onCustomerNameChanged(_customerNameController.text);
                            }
                          },
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Nama konsumen wajib diisi';
                            }
                            return null;
                          },
                        ),

                        // Dropdown Saran dari Master Pelanggan & Tombol Tambah Pelanggan
                        if (_showCustomerDropdown) ...[
                          const SizedBox(height: 6),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 220),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.35),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: ListView(
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    color: AppColors.bgSecondary,
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.storefront_rounded,
                                          size: 14,
                                          color: AppColors.textSecondary,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          _customerSuggestions.isNotEmpty
                                              ? '${_customerSuggestions.length} Pelanggan Master Cocok:'
                                              : 'Pelanggan tidak ada di Master',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                        const Spacer(),
                                        InkWell(
                                          onTap: () => setState(() =>
                                              _showCustomerDropdown = false),
                                          child: const Icon(
                                            Icons.close,
                                            size: 16,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  ..._customerSuggestions.map((c) {
                                    return ListTile(
                                      dense: true,
                                      leading: CircleAvatar(
                                        radius: 13,
                                        backgroundColor: AppColors.primary
                                            .withValues(alpha: 0.12),
                                        child: Text(
                                          c.name.isNotEmpty
                                              ? c.name[0].toUpperCase()
                                              : '?',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                      title: Text(
                                        c.name,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      subtitle: Text(
                                        c.alamat.isNotEmpty
                                            ? c.alamat
                                            : 'Gorontalo',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: const Icon(
                                        Icons.north_west_rounded,
                                        size: 14,
                                        color: AppColors.textSecondary,
                                      ),
                                      onTap: () => _selectCustomer(c),
                                    );
                                  }),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.08),
                                      border: const Border(
                                        top: BorderSide(
                                          color: AppColors.surfaceBorder,
                                        ),
                                      ),
                                    ),
                                    child: ListTile(
                                      dense: true,
                                      leading: const CircleAvatar(
                                        radius: 13,
                                        backgroundColor: AppColors.primary,
                                        child: Icon(
                                          Icons.add,
                                          size: 15,
                                          color: Colors.white,
                                        ),
                                      ),
                                      title: Text(
                                        _customerNameController.text
                                                .trim()
                                                .isNotEmpty
                                            ? '+ Tambah "${_customerNameController.text.trim()}" ke Master'
                                            : '+ Tambah Pelanggan Baru...',
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                      subtitle: const Text(
                                        'Simpan otomatis ke Master Pelanggan',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      onTap: () => _openAddNewCustomerDialog(
                                        _customerNameController.text.trim(),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: _alamatCustomer,
                          decoration: const InputDecoration(
                            labelText: 'Alamat Konsumen * (Wajib Diisi)',
                            hintText: 'Contoh: Jl. Ahmad Yani No. 12, Kutacane',
                            helperText:
                                '* Catatan: Alamat wajib diisi untuk keperluan nota & pengiriman.',
                            helperStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                            prefixIcon:
                                Icon(Icons.location_on_outlined, size: 20),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Alamat konsumen wajib diisi';
                            }
                            if (value.trim().length < 3) {
                              return 'Alamat konsumen minimal 3 karakter';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                        // Tanggal Transaksi
                        InkWell(
                          onTap: () => _selectDate(context),
                          borderRadius: BorderRadius.circular(AppRadius.input),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(AppRadius.input),
                              border: Border.all(color: AppColors.surfaceBorder),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.calendar_today_outlined,
                                  size: 18,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Tanggal: ${DateFormat('dd MMMM yyyy').format(_selectedDate)}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const Spacer(),
                                const Text(
                                  'Ubah',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        // Status Pembayaran: Segmented Control
                        const Text(
                          'Status Pembayaran',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        PaymentSegmentedControl(
                          selectedStatus: _paymentStatus,
                          onChanged: (status) {
                            setState(() {
                              _paymentStatus = status;
                            });
                          },
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _paymentStatus == 'LUNAS'
                              ? '• Nota LUNAS: Pembayaran tunai telah diterima kasir.'
                              : (_paymentStatus == 'QRIS'
                                  ? '• Nota QRIS: Pembayaran non-tunai/QRIS. Menunggu verifikasi mutasi rekening oleh Admin.'
                                  : '• Nota BON: Pembayaran tempo/piutang. Masuk ke monitoring bon untuk ditagih.'),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: _paymentStatus == 'LUNAS'
                                ? AppColors.lunas
                                : (_paymentStatus == 'QRIS'
                                    ? const Color(0xFF1971C2)
                                    : AppColors.bon),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  // Header Bagian Daftar Barang
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Daftar Barang (${_items.length})',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _addItemField,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Tambah Baris'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // List Item Kartu
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.cardGap),
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return Container(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          border: Border.all(color: AppColors.surfaceBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Card Header: Nomor Barang & Tombol Hapus
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 24,
                                      height: 24,
                                      alignment: Alignment.center,
                                      decoration: const BoxDecoration(
                                        color: AppColors.primaryLight,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        '${index + 1}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Barang',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                                if (_items.length > 1)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: AppColors.error,
                                      size: 20,
                                    ),
                                    tooltip: 'Hapus barang ini',
                                    onPressed: () => _removeItemField(index),
                                  ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),

                            // Pilih Produk Tappable Sheet
                            InkWell(
                              onTap: () => _openProductPicker(index),
                              borderRadius: BorderRadius.circular(AppRadius.input),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.background,
                                  borderRadius: BorderRadius.circular(AppRadius.input),
                                  border: Border.all(color: AppColors.surfaceBorder),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.inventory_2_outlined,
                                          size: 18,
                                          color: AppColors.textSecondary,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            item.nameController.text.isEmpty
                                                ? 'Pilih Produk dari Master Stock...'
                                                : item.nameController.text,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: item.nameController.text.isEmpty
                                                  ? FontWeight.w400
                                                  : FontWeight.w600,
                                              color: item.nameController.text.isEmpty
                                                  ? AppColors.textSecondary
                                                  : AppColors.textPrimary,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const Icon(
                                          Icons.arrow_drop_down,
                                          color: AppColors.textSecondary,
                                        ),
                                      ],
                                    ),
                                    if (item.nameController.text.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Builder(
                                        builder: (_) {
                                          final tyunit = _resolveTyunit(item);
                                          final matched = _products.firstWhere(
                                            (p) =>
                                                p.tyunit.toLowerCase() ==
                                                    tyunit.toLowerCase() ||
                                                p.name.toLowerCase() ==
                                                    item.nameController.text
                                                        .trim()
                                                        .toLowerCase(),
                                            orElse: () => Item(
                                              tyunit: tyunit,
                                              name: item.nameController.text,
                                              price: item.price,
                                              stock: item.selectedItem?.stock ?? 0,
                                            ),
                                          );
                                          final availableStock =
                                              item.selectedItem?.stock ??
                                                  matched.stock;
                                          return Row(
                                            children: [
                                              Text(
                                                'Kode: $tyunit',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.textSecondary,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 1.5,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: availableStock > 0
                                                      ? AppColors.success
                                                          .withValues(alpha: 0.12)
                                                      : AppColors.error
                                                          .withValues(alpha: 0.12),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  availableStock > 0 ? (AuthService.currentUser?.isAdmin == true ? 'Stok Tersedia: $availableStock' : 'Stok Tersedia') : 'Stok Habis (0)',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: availableStock > 0
                                                        ? AppColors.success
                                                        : AppColors.error,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: AppSpacing.md),

                            // Baris: Harga Satuan, Qty, dan Bonus
                            Row(
                              children: [
                                // Harga Satuan
                                Expanded(
                                  flex: 3,
                                  child: TextFormField(
                                    controller: item.priceController,
                                    decoration: const InputDecoration(
                                      labelText: 'Harga (Rp)',
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                    ),
                                    readOnly: true,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Kuantitas
                                Expanded(
                                  flex: 2,
                                  child: TextFormField(
                                    controller: item.qtyController,
                                    decoration: const InputDecoration(
                                      labelText: 'Jumlah *',
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                    ),
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    onChanged: (_) => setState(() {}),
                                    validator: (v) {
                                      if (v == null ||
                                          int.tryParse(v) == null ||
                                          int.parse(v) <= 0) {
                                        return 'Min 1';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Bonus
                                Expanded(
                                  flex: 2,
                                  child: TextFormField(
                                    controller: item.bonusController,
                                    decoration: InputDecoration(
                                      labelText: 'Bonus',
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                      suffixIcon: item.bonus > 0
                                          ? const Icon(
                                              Icons.card_giftcard,
                                              size: 16,
                                              color: AppColors.bon,
                                            )
                                          : null,
                                    ),
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(fontSize: 14),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: AppSpacing.md),

                            // Subtotal Item
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                if (item.bonus > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.bonBg,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '+${item.bonus} Bonus',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.bon,
                                      ),
                                    ),
                                  )
                                else
                                  const SizedBox(),
                                Text(
                                  'Subtotal: ${currencyFormat.format(item.subtotal)}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: AppSpacing.md),

                  // Tombol Tambah Barang Besar (Thumb-friendly)
                  OutlinedButton.icon(
                    onPressed: _addItemField,
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    label: const Text('Tambah Barang Lain'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),

                  const SizedBox(height: 100), // Spasi untuk sticky bottom
                ],
              ),
            ),

            // STICKY BOTTOM BAR (Total & Tombol Simpan)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenMargin,
                vertical: 16,
              ),
              decoration: BoxDecoration(
                color: AppColors.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Total Keseluruhan',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            alignment: Alignment.centerLeft,
                            fit: BoxFit.scaleDown,
                            child: Text(
                              currencyFormat.format(_calculateTotal()),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 5,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveTransaction,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 52),
                          backgroundColor: AppColors.primary,
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Simpan Nota',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom Sheet untuk memilih produk dari Master Stock
class _ProductPickerSheet extends StatefulWidget {
  final List<Item> products;
  final bool isLoading;
  final ValueChanged<Item> onSelect;

  const _ProductPickerSheet({
    required this.products,
    required this.isLoading,
    required this.onSelect,
  });

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Item> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.products;
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch() {
    final query = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filtered = widget.products;
      } else {
        _filtered = widget.products.where((p) {
          return p.name.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ');

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.surfaceBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.screenMargin),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pilih Produk',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Cari nama produk...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => _searchCtrl.clear(),
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: widget.isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 48,
                              color: AppColors.textSecondary.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Produk tidak ditemukan',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, idx) {
                          final product = _filtered[idx];
                          final isOutOfStock = product.stock <= 0;

                          return Opacity(
                            opacity: isOutOfStock ? 0.55 : 1.0,
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 4,
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      product.name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        color: isOutOfStock
                                            ? AppColors.textSecondary
                                            : AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  if (isOutOfStock)
                                    Container(
                                      margin: const EdgeInsets.only(left: 6),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.errorBg,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                            color: AppColors.error
                                                .withValues(alpha: 0.3)),
                                      ),
                                      child: const Text(
                                        'HABIS (0)',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.error,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Row(
                                  children: [
                                    Text(
                                      product.tyunit.isEmpty
                                          ? '-'
                                          : product.tyunit,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    if (product.kelompok.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary
                                              .withValues(alpha: 0.08),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.2)),
                                        ),
                                        child: Text(
                                          product.kelompok,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isOutOfStock
                                            ? AppColors.error
                                                .withValues(alpha: 0.12)
                                            : AppColors.success
                                                .withValues(alpha: 0.12),
                                        borderRadius:
                                            BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        isOutOfStock
                                            ? 'Stok: 0 (Kosong)'
                                            : (AuthService.currentUser?.isAdmin == true ? 'Sisa Kuota: ${product.stock}' : 'Stok Tersedia'),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: isOutOfStock
                                              ? AppColors.error
                                              : AppColors.success,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              trailing: Text(
                                currencyFormat.format(product.price),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: isOutOfStock
                                      ? AppColors.textSecondary
                                      : AppColors.primary,
                                ),
                              ),
                              onTap: isOutOfStock
                                  ? () {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Stok "${product.name}" sedang habis (0). Harap input stok awal terlebih dahulu.',
                                          ),
                                          backgroundColor: AppColors.error,
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  : () {
                                      widget.onSelect(product);
                                      Navigator.pop(ctx);
                                    },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
