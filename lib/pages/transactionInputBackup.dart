

// import 'package:flutter/material.dart';
// import 'package:intl/intl.dart';
// import 'package:kasir_kutacane/models/Item.dart';
// import 'package:kasir_kutacane/models/transaction.dart';
// import 'package:kasir_kutacane/models/transactionItem.dart';
// import 'package:kasir_kutacane/services/mysql_service.dart';

// class TransactionInputPageBackup extends StatefulWidget {
//   final Function(Transaction) onSave;

//   const TransactionInputPageBackup({Key? key, required this.onSave})
//     : super(key: key);

//   @override
//   State<TransactionInputPageBackup> createState() => _TransactionInputPageBackupState();
// }

// class _TransactionInputPageBackupState extends State<TransactionInputPageBackup> {
//   final _formKey = GlobalKey<FormState>();
//   final TextEditingController _customerNameController = TextEditingController();
//   final TextEditingController _alamatCustomer = TextEditingController();
//   final List<TransactionItem> _items = [TransactionItem()];
//   DateTime _selectedDate = DateTime.now();
//   String _transactionId = '';
//   List<Item> _availableItems = [];

//   static int _transactionCounter = 0;
//   int _loadingCount = 0;

//   bool get _isLoading => _loadingCount > 0;

//   void _setLoading(bool value) {
//     setState(() {
//       if (value) {
//         _loadingCount++;
//       } else {
//         _loadingCount = (_loadingCount - 1).clamp(0, double.infinity).toInt();
//       }
//     });
//   }

//   @override
//   void initState() {
//     super.initState();
//     _initializeData();
//   }

//   @override
//   void dispose() {
//     _customerNameController.dispose();
//     _alamatCustomer.dispose();
//     for (final item in _items) {
//       item.dispose();
//     }
//     super.dispose();
//   }

//   Future<void> _initializeData() async {
//     _setLoading(true);
//     await _generateTransactionId();
//     await _fetchItems();
//     _setLoading(false);
//   }

//   Future<void> _generateTransactionId() async {
//     final now = DateTime.now();
//     final formatter = DateFormat('yyyyMMdd');
//     final datePart = formatter.format(now);

//     String newId;
//     bool exists;

//     do {
//       _transactionCounter++;
//       final uniqueNumber = _transactionCounter.toString().padLeft(4, '0');
//       newId = 'Trx-$datePart-$uniqueNumber';
//       exists = await _checkTransactionIdExists(newId);
//     } while (exists);

//     setState(() {
//       _transactionId = newId;
//     });
//   }

//   Future<bool> _checkTransactionIdExists(String id) async {
//     try {
//       return await MySQLService.checkTransactionIdExists(id);
//     } catch (e) {
//       debugPrint('Error checking ID from DB: $e');
//       return false;
//     }
//   }

//   Future<void> _fetchItems() async {
//     try {
//       final items = await MySQLService.getItems();
//       setState(() {
//         _availableItems = items;
//       });
//     } catch (e) {
//       debugPrint('Error fetching items from DB: $e');
//     }
//   }

//   Future<void> _selectDate(BuildContext context) async {
//     final picked = await showDatePicker(
//       context: context,
//       initialDate: _selectedDate,
//       firstDate: DateTime(2000),
//       lastDate: DateTime(2101),
//     );
//     if (picked != null && picked != _selectedDate) {
//       setState(() {
//         _selectedDate = picked;
//       });
//     }
//   }

//   void _addItemField() {
//     setState(() {
//       _items.add(TransactionItem());
//     });
//   }

//   void _removeItemField(int index) {
//     setState(() {
//       _items[index].dispose();
//       _items.removeAt(index);
//     });
//   }

//   double _calculateTotal() {
//     return _items.fold(0.0, (sum, item) => sum + item.subtotal);
//   }

//   Future<void> _saveTransactionToApi(Transaction transaction) async {
//     try {
//       await MySQLService.saveTransactionToDatabase(transaction);
//     } catch (e) {
//       throw Exception('Gagal menyimpan transaksi ke database: $e');
//     }
//   }

//   void _saveTransaction() async {
//     if (!_formKey.currentState!.validate()) return;

//     _formKey.currentState!.save();
//     _setLoading(true);

//     try {
//       bool exists = await _checkTransactionIdExists(_transactionId);
//       if (exists) {
//         await _generateTransactionId();
//       }

//       final newTransaction = Transaction(
//         id: _transactionId,
//         customerName: _customerNameController.text,
//         alamat: _alamatCustomer.text,
//         date: _selectedDate,
//         items: List.from(_items),
//         total: _calculateTotal(),
//       );

//       await _saveTransactionToApi(newTransaction);
//       widget.onSave(newTransaction);

//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text('Transaksi berhasil disimpan ke API!')),
//       );

//       _customerNameController.clear();
//       _alamatCustomer.clear();
//       for (final item in _items) {
//         item.dispose();
//       }
//       setState(() {
//         _items.clear();
//         _items.add(TransactionItem());
//         _selectedDate = DateTime.now();
//       });
//       await _generateTransactionId();
//     } catch (e) {
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(SnackBar(content: Text('Gagal simpan ke API: $e')));
//     } finally {
//       _setLoading(false);
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('Input Transaksi Baru')),
//       body: Stack(
//         children: [
//           Form(
//             key: _formKey,
//             child: SingleChildScrollView(
//               padding: const EdgeInsets.all(16.0),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     'ID Transaksi: $_transactionId',
//                     style: const TextStyle(
//                       fontSize: 18,
//                       fontWeight: FontWeight.bold,
//                     ),
//                   ),
//                   const SizedBox(height: 20),
//                   TextFormField(
//                     controller: _customerNameController,
//                     decoration: const InputDecoration(
//                       labelText: 'Nama Konsumen',
//                       border: OutlineInputBorder(),
//                     ),
//                     validator:
//                         (value) =>
//                             value == null || value.isEmpty
//                                 ? 'Nama kosong'
//                                 : null,
//                   ),
//                   const SizedBox(height: 20),
//                   TextFormField(
//                     controller: _alamatCustomer,
//                     decoration: const InputDecoration(
//                       labelText: 'Alamat Konsumen',
//                       border: OutlineInputBorder(),
//                     ),
//                     maxLines: 3,
//                     validator:
//                         (value) =>
//                             value == null || value.isEmpty
//                                 ? 'Alamat kosong'
//                                 : null,
//                   ),
//                   const SizedBox(height: 20),
//                   Row(
//                     children: [
//                       Expanded(
//                         child: InputDecorator(
//                           decoration: const InputDecoration(
//                             labelText: 'Tanggal Transaksi',
//                             border: OutlineInputBorder(),
//                           ),
//                           child: Text(
//                             DateFormat('dd-MM-yyyy').format(_selectedDate),
//                           ),
//                         ),
//                       ),
//                       IconButton(
//                         icon: const Icon(Icons.calendar_today),
//                         onPressed: () => _selectDate(context),
//                       ),
//                     ],
//                   ),
//                   const SizedBox(height: 20),
//                   const Text(
//                     'Daftar Barang:',
//                     style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//                   ),
//                   const SizedBox(height: 10),
//                   ListView.builder(
//                     shrinkWrap: true,
//                     physics: const NeverScrollableScrollPhysics(),
//                     itemCount: _items.length,
//                     itemBuilder: (context, index) {
//                       return Card(
//                         margin: const EdgeInsets.symmetric(vertical: 8.0),
//                         child: Padding(
//                           padding: const EdgeInsets.all(12.0),
//                           child: Column(
//                             children: [
//                               Row(
//                                 mainAxisAlignment:
//                                     MainAxisAlignment.spaceBetween,
//                                 children: [
//                                   Text(
//                                     'Barang #${index + 1}',
//                                     style: const TextStyle(
//                                       fontWeight: FontWeight.bold,
//                                     ),
//                                   ),
//                                   if (_items.length > 1)
//                                     IconButton(
//                                       icon: const Icon(
//                                         Icons.delete,
//                                         color: Colors.red,
//                                       ),
//                                       onPressed: () => _removeItemField(index),
//                                     ),
//                                 ],
//                               ),
//                               DropdownButtonFormField<Item>(
//                                 decoration: const InputDecoration(
//                                   labelText: 'Nama Barang',
//                                 ),
//                                 isExpanded: true,
//                                 items:
//                                     _availableItems
//                                         .map(
//                                           (item) => DropdownMenuItem<Item>(
//                                             value: item,
//                                             child: Text(item.name),
//                                           ),
//                                         )
//                                         .toList(),
//                                 value: _items[index].selectedItem,
//                                 onChanged: (selected) {
//                                   setState(() {
//                                     _items[index].selectedItem = selected;
//                                     _items[index].nameController.text =
//                                         selected?.name ?? '';
//                                     _items[index].priceController.text =
//                                         selected?.price.toStringAsFixed(0) ??
//                                         '';
//                                   });
//                                 },
//                                 validator:
//                                     (value) =>
//                                         value == null ? 'Pilih barang' : null,
//                               ),
//                               TextFormField(
//                                 controller: _items[index].priceController,
//                                 decoration: const InputDecoration(
//                                   labelText: 'Harga Satuan',
//                                 ),
//                                 readOnly: true,
//                                 keyboardType: TextInputType.number,
//                               ),
//                               TextFormField(
//                                 controller: _items[index].qtyController,
//                                 decoration: const InputDecoration(
//                                   labelText: 'Kuantitas',
//                                 ),
//                                 keyboardType: TextInputType.number,
//                                 onChanged: (_) => setState(() {}),
//                                 validator: (value) {
//                                   final qty = int.tryParse(value ?? '');
//                                   if (qty == null || qty <= 0) {
//                                     return 'Isi kuantitas valid';
//                                   }
//                                   return null;
//                                 },
//                               ),
//                               TextFormField(
//                                 controller: _items[index].bonusController,
//                                 decoration: const InputDecoration(
//                                   labelText: 'Bonus',
//                                 ),
//                                 keyboardType: TextInputType.number,
//                                 onChanged: (_) => setState(() {}),
//                                 validator: (value) {
//                                   if (value == null) return null;
//                                   if (value.isNotEmpty &&
//                                       int.tryParse(value) == null) {
//                                     return 'Bonus harus angka';
//                                   }
//                                   return null;
//                                 },
//                               ),
//                               Align(
//                                 alignment: Alignment.centerRight,
//                                 child: Text(
//                                   'Subtotal: ${NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ').format(_items[index].subtotal)}',
//                                   style: const TextStyle(
//                                     fontWeight: FontWeight.bold,
//                                   ),
//                                 ),
//                               ),
//                             ],
//                           ),
//                         ),
//                       );
//                     },
//                   ),
//                   const SizedBox(height: 10),
//                   Center(
//                     child: ElevatedButton.icon(
//                       onPressed: _addItemField,
//                       icon: const Icon(Icons.add),
//                       label: const Text('Tambah Barang'),
//                     ),
//                   ),
//                   const SizedBox(height: 20),
//                   Align(
//                     alignment: Alignment.centerRight,
//                     child: Text(
//                       'Total: ${NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ').format(_calculateTotal())}',
//                       style: const TextStyle(
//                         fontSize: 20,
//                         fontWeight: FontWeight.bold,
//                       ),
//                     ),
//                   ),
//                   const SizedBox(height: 30),
//                   SizedBox(
//                     width: double.infinity,
//                     child: ElevatedButton(
//                       onPressed: _saveTransaction,
//                       child: const Text(
//                         'Simpan Transaksi',
//                         style: TextStyle(fontSize: 18),
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//           if (_isLoading)
//             Container(
//               color: Colors.black.withOpacity(0.3),
//               child: const Center(child: CircularProgressIndicator()),
//             ),
//         ],
//       ),
//     );
//   }
// }
