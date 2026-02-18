import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/models/Item.dart';
import 'package:kasir_kutacane/models/master.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/models/transactionItem.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TransactionInputPage extends StatefulWidget {
  final Function(Transaction) onSave;
  final Transaction? transaction;
  final Function(int)? onNavigateTab;

  const TransactionInputPage({
    Key? key,
    required this.onSave,
    this.transaction,
    this.onNavigateTab,
  }) : super(key: key);

  @override
  State<TransactionInputPage> createState() => _TransactionInputPageState();
}

class _TransactionInputPageState extends State<TransactionInputPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _alamatCustomer = TextEditingController();
  final List<TransactionItem> _items = [TransactionItem()];
  DateTime _selectedDate = DateTime.now();
  String _transactionId = '';
  List<Item> _products = [];
  bool _isLoadingProducts = false;

  static int _transactionCounter = 0;
  bool _isCheckingId = false;
  String _paymentStatus = 'LUNAS';

  @override
  void initState() {
    super.initState();
    _fetchProducts();
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
          ),
        );
      }
    } else {
      _generateTransactionId();
    }
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _alamatCustomer.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
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

    setState(() {
      _transactionId = newId;
    });
  }

  Future<void> _fetchProducts() async {
    const url = 'https://laravel.fathurrzqn8n.web.id/api/master-stocks';

    setState(() => _isLoadingProducts = true);

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List data = body['data'];

        setState(() {
          _products = data.map<Item>((e) => Item.fromJson(e)).toList();
        });
      }
    } catch (e) {
      debugPrint("Error ambil produk: $e");
    } finally {
      setState(() => _isLoadingProducts = false);
    }
  }

  Future<bool> _checkTransactionIdExists(String id) async {
    const apiUrl = 'https://laravel.fathurrzqn8n.web.id/api/transaksi';
    setState(() {
      _isCheckingId = true;
    });

    try {
      final response = await http.get(Uri.parse('$apiUrl?search=$id'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.any((trx) => trx['id_transaksi'] == id);
      }
    } catch (e) {
      debugPrint('Error checking ID: $e');
    } finally {
      setState(() {
        _isCheckingId = false;
      });
    }
    return false;
  }

  Future<void> _saveToSupabase(Transaction transaction) async {
    final supabase = Supabase.instance.client;

    try {
      // 1. Simpan Header Transaksi
      await supabase.from('transaksi').insert({
        'id_transaksi': transaction.id_transaksi,
        'customer_name':
            transaction.customerName, // Pastikan nama kolom sama dengan di DB
        'alamat': transaction.alamat,
        'tanggal':
            transaction.date
                .toIso8601String(), // Pastikan nama kolom sama dengan di DB
        'total': transaction.total.toInt(),
        'status': _paymentStatus,
        'is_backup': true,
      });

      // 2. Simpan Items
      final itemsJson =
          transaction.items
              .map(
                (item) => {
                  'id_transaksi': transaction.id_transaksi,
                  'tyunit':
                      item.tyunit, // WAJIB ADA karena Foreign Key ke tabel munit
                  'nama_barang': item.nameController.text,
                  'harga': item.price.toInt(),
                  'quantity': item.quantity,
                  'bonus': item.bonus,
                  'subtotal': item.subtotal.toInt(),
                },
              )
              .toList();

      await supabase.from('transaksi_items').insert(itemsJson);
    } on PostgrestException catch (error) {
      // Ini akan menangkap error spesifik dari database Supabase (PostgreSQL)
      debugPrint("=== SUPABASE DATABASE ERROR ===");
      debugPrint("Message: ${error.message}"); // Pesan error manusiawi
      debugPrint(
        "Code: ${error.code}",
      ); // Kode error (misal: 23503 untuk FK error)
      debugPrint("Details: ${error.details}"); // Detail teknis
      debugPrint("Hint: ${error.hint}"); // Saran perbaikan dari DB
      rethrow; // Tetap lempar agar fungsi pemanggil tahu kalau gagal
    } catch (e) {
      // Menangkap error umum (koneksi internet, dll)
      debugPrint("=== UNKNOWN ERROR ===");
      debugPrint(e.toString());
      rethrow;
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
    setState(() {
      _items[index].dispose();
      _items.removeAt(index);
    });
  }

  double _calculateTotal() {
    return _items.fold(0.0, (sum, item) => sum + item.subtotal);
  }

  Future<void> _saveTransactionToApi(Transaction transaction) async {
    const url = 'https://laravel.fathurrzqn8n.web.id/api/transaksi';

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },

        body: jsonEncode({
          'id_transaksi':
              transaction.id_transaksi, // tetap pakai id_transaksi lama
          'customerName': transaction.customerName,
          'alamat': transaction.alamat,
          'date': transaction.date.toIso8601String(),
          'total': transaction.total,
          'status': _paymentStatus,
          'items':
              transaction.items
                  .map(
                    (item) => {
                      'tyunit': item.tyunit, // tambahkan ini
                      'name': item.nameController.text,
                      'price': item.price,
                      'quantity': item.quantity,
                      'bonus': item.bonus,
                      'subtotal': item.subtotal,
                    },
                  )
                  .toList(),
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        print(response.body);
        throw Exception(
          'Gagal menyimpan transaksi ke API. Code: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint("Laravel Gagal, mencoba backup ke Supabase: $e");

      try {
        await _saveToSupabase(transaction);
        debugPrint("Berhasil simpan ke Supabase (Backup Mode)");
      } catch (supabaseError) {
        throw Exception('Semua server (Utama & Backup) tidak dapat dijangkau.');
      }
    }

    // 🔹 Simpan data baru
  }

  void _saveTransaction() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      setState(() => _isCheckingId = true);

      // 🔹 Kalau tambah baru, pastikan generate ID unik
      if (widget.transaction == null) {
        bool exists = await _checkTransactionIdExists(_transactionId);
        if (exists) {
          await _generateTransactionId();
        }
      }

      final newTransaction = Transaction(
        id: '', // biarkan kosong, karena MockAPI generate baru
        id_transaksi: widget.transaction?.id_transaksi ?? _transactionId,
        customerName: _customerNameController.text,
        alamat: _alamatCustomer.text,
        date: _selectedDate,
        items: List.from(_items),
        total: _calculateTotal(),
        status: _paymentStatus,
      );

      try {
        await _saveTransactionToApi(newTransaction);
        widget.onSave(newTransaction);

        widget.onNavigateTab?.call(1);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaksi berhasil disimpan ke API!')),
        );

        // reset form hanya kalau transaksi baru, bukan edit
        if (widget.transaction == null) {
          _customerNameController.clear();
          _alamatCustomer.clear();
          for (final item in _items) {
            item.dispose();
          }
          setState(() {
            _items.clear();
            _items.add(TransactionItem());
            _selectedDate = DateTime.now();
          });
          await _generateTransactionId();
        } else {
          Navigator.pop(context, newTransaction);
        }
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal simpan ke API: $e')));
      } finally {
        setState(() => _isCheckingId = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Input Transaksi Baru')),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ID Transaksi: $_transactionId',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _customerNameController,
                    decoration: const InputDecoration(
                      labelText: 'Nama Konsumen',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Nama konsumen tidak boleh kosong';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _alamatCustomer,
                    decoration: const InputDecoration(
                      labelText: 'Alamat Konsumen',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Alamat tidak boleh kosong';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Tanggal Transaksi',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            DateFormat('dd-MM-yyyy').format(_selectedDate),
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.calendar_today),
                        onPressed: () => _selectDate(context),
                      ),
                    ],
                  ),

                  // const SizedBox(height: 20),
                  // DropdownButtonFormField<String>(
                  //   value: _paymentStatus,
                  //   decoration: const InputDecoration(
                  //     labelText: 'Status Pembayaran',
                  //     border: OutlineInputBorder(),
                  //   ),
                  //   items: const [
                  //     DropdownMenuItem(value: 'LUNAS', child: Text('LUNAS')),
                  //     DropdownMenuItem(value: 'BON', child: Text('BON')),
                  //   ],
                  //   onChanged: (value) {
                  //     if (value != null) {
                  //       setState(() {
                  //         _paymentStatus = value;
                  //       });
                  //     }
                  //   },
                  // ),
                  const SizedBox(height: 20),
                  const Text(
                    'Daftar Barang:',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Barang #${index + 1}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (_items.length > 1)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                      ),
                                      onPressed: () => _removeItemField(index),
                                    ),
                                ],
                              ),
                              DropdownButtonFormField<Item>(
                                value: _items[index].selectedItem,
                                decoration: const InputDecoration(
                                  labelText: 'Nama Barang',
                                ),
                                items:
                                    _products.map((product) {
                                      return DropdownMenuItem<Item>(
                                        value: product,
                                        child: Text(product.name),
                                      );
                                    }).toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _items[index].selectedItem = value;
                                    _items[index].nameController.text =
                                        value?.name ?? '';
                                    _items[index].priceController.text =
                                        value?.price.toString() ?? '0';
                                    _items[index].tyunit = value?.tyunit ?? '';
                                  });
                                },
                                validator:
                                    (value) =>
                                        value == null
                                            ? 'Pilih barang dulu'
                                            : null,
                              ),

                              TextFormField(
                                controller: _items[index].priceController,
                                decoration: const InputDecoration(
                                  labelText: 'Harga Satuan',
                                ),
                                readOnly: true,
                              ),

                              TextFormField(
                                controller: _items[index].qtyController,
                                decoration: const InputDecoration(
                                  labelText: 'Kuantitas',
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setState(() {}),
                                validator: (value) {
                                  if (value == null ||
                                      int.tryParse(value) == null ||
                                      int.parse(value) <= 0) {
                                    return 'Kuantitas harus angka positif';
                                  }
                                  return null;
                                },
                              ),
                              TextFormField(
                                controller: _items[index].bonusController,
                                decoration: const InputDecoration(
                                  labelText: 'Bonus',
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setState(() {}),
                                validator: (value) {
                                  if (value == null) return null;
                                  if (value.isNotEmpty &&
                                      int.tryParse(value) == null) {
                                    return 'Bonus harus angka';
                                  }
                                  return null;
                                },
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  'Subtotal: ${NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ').format(_items[index].subtotal)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: _addItemField,
                      icon: const Icon(Icons.add),
                      label: const Text('Tambah Barang Lain'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Total Keseluruhan: ${NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ').format(_calculateTotal())}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        await _showPaymentStatusDialog(); // user pilih status dulu
                        _saveTransaction(); // kemudian simpan
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text(
                        'Simpan Transaksi',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isCheckingId)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Future<void> _showPaymentStatusDialog() async {
    String tempStatus = _paymentStatus;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text("Pilih Status Pembayaran"),
          content: StatefulBuilder(
            builder: (context, setStateDialog) {
              return DropdownButtonFormField<String>(
                value: tempStatus,
                items: const [
                  DropdownMenuItem(value: 'LUNAS', child: Text('LUNAS')),
                  DropdownMenuItem(value: 'BON', child: Text('BON')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setStateDialog(() {
                      tempStatus = value;
                    });
                  }
                },
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Batal"),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _paymentStatus = tempStatus; // hanya dari popup!
                });
                Navigator.pop(context);
              },
              child: const Text("OK"),
            ),
          ],
        );
      },
    );
  }
}
