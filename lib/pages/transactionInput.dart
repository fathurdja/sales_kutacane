import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/models/transactionItem.dart';

class TransactionInputPage extends StatefulWidget {
  final Function(Transaction) onSave;

  const TransactionInputPage({Key? key, required this.onSave})
      : super(key: key);

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

  static int _transactionCounter = 0;
  bool _isCheckingId = false;

  @override
  void initState() {
    super.initState();
    _generateTransactionId();
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

  Future<bool> _checkTransactionIdExists(String id) async {
    const apiUrl = 'https://6873b63ec75558e273550195.mockapi.io/transaksi';
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
    const url = 'https://6873b63ec75558e273550195.mockapi.io/transaksi';

    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'id_transaksi': transaction.id,
        'customerName': transaction.customerName,
        'alamat': transaction.alamat,
        'date': transaction.date.toIso8601String(),
        'items': transaction.items
            .map(
              (item) => {
                'name': item.nameController.text,
                'price': item.price,
                'quantity': item.quantity,
                'subtotal': item.subtotal,
              },
            )
            .toList(),
        'total': transaction.total,
      }),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'Gagal menyimpan transaksi ke API. Code: ${response.statusCode}',
      );
    }
  }

  void _saveTransaction() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      setState(() {
        _isCheckingId = true;
      });

      bool exists = await _checkTransactionIdExists(_transactionId);
      if (exists) {
        await _generateTransactionId();
      }

      final newTransaction = Transaction(
        id: _transactionId,
        customerName: _customerNameController.text,
        alamat: _alamatCustomer.text,
        date: _selectedDate,
        items: List.from(_items),
        total: _calculateTotal(),
      );

      try {
        await _saveTransactionToApi(newTransaction);
        widget.onSave(newTransaction);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaksi berhasil disimpan ke API!')),
        );

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
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal simpan ke API: $e')));
      } finally {
        setState(() {
          _isCheckingId = false;
        });
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
                              TextFormField(
                                controller: _items[index].nameController,
                                decoration: const InputDecoration(
                                  labelText: 'Nama Barang',
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Nama barang tidak boleh kosong';
                                  }
                                  return null;
                                },
                              ),
                              TextFormField(
                                controller: _items[index].priceController,
                                decoration: const InputDecoration(
                                  labelText: 'Harga Satuan',
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setState(() {}),
                                validator: (value) {
                                  if (value == null ||
                                      double.tryParse(value) == null ||
                                      double.parse(value) <= 0) {
                                    return 'Harga harus angka positif';
                                  }
                                  return null;
                                },
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
                      onPressed: _saveTransaction,
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
}
