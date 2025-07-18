import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/models/transactionItem.dart';
import 'package:kasir_kutacane/pages/transactionDetail.dart';

class TransactionListPage extends StatefulWidget {
  const TransactionListPage({Key? key}) : super(key: key);

  @override
  State<TransactionListPage> createState() => _TransactionListPageState();
}

class _TransactionListPageState extends State<TransactionListPage> {
  DateTime? _filterDate;
  List<Transaction> _transactions = [];
  List<Transaction> _filteredTransactions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _filterDate = DateTime.now();
    _fetchTransactions();
  }

  Future<void> _fetchTransactions() async {
    const url = 'https://6873b63ec75558e273550195.mockapi.io/transaksi';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);

        final loadedTransactions =
            data.map<Transaction>((json) {
              return Transaction(
                id: json['id_transaksi'],
                customerName: json['customerName'],
                alamat: json['alamat'],
                date: DateTime.parse(json['date']),
                total: (json['total'] as num).toDouble(),
                items:
                    (json['items'] as List<dynamic>).map<TransactionItem>((
                      item,
                    ) {
                      return TransactionItem.fromJson(item);
                    }).toList(),
              );
            }).toList();

        setState(() {
          _transactions = loadedTransactions;
          _applyFilter();
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load transactions');
      }
    } catch (e) {
      debugPrint(e.toString());
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal memuat data: $e')));
    }
  }

  Future<void> _selectFilterDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _filterDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null) {
      setState(() {
        _filterDate = picked;
        _applyFilter();
      });
    }
  }

  void _clearFilter() {
    setState(() {
      _filterDate = null;
      _applyFilter();
    });
  }

  void _applyFilter() {
    if (_filterDate == null) {
      _filteredTransactions = List.from(_transactions);
    } else {
      _filteredTransactions =
          _transactions.where((trx) {
            return trx.date.year == _filterDate!.year &&
                trx.date.month == _filterDate!.month &&
                trx.date.day == _filterDate!.day;
          }).toList();
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daftar Transaksi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: () => _selectFilterDate(context),
          ),
          if (_filterDate != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearFilter,
              tooltip: 'Hapus Filter',
            ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  if (_filterDate != null)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Filter Aktif: '),
                          Text(
                            DateFormat('dd-MM-yyyy').format(_filterDate!),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child:
                        _filteredTransactions.isEmpty
                            ? const Center(child: Text('Tidak ada transaksi.'))
                            : ListView.builder(
                              itemCount: _filteredTransactions.length,
                              itemBuilder: (context, index) {
                                final trx = _filteredTransactions[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 16.0,
                                    vertical: 8.0,
                                  ),
                                  child: ListTile(
                                    title: Text('ID: ${trx.id}'),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('Konsumen: ${trx.customerName}'),
                                        Text('Alamat: ${trx.alamat}'),
                                        Text(
                                          'Tanggal: ${DateFormat('dd-MM-yyyy').format(trx.date)}',
                                        ),
                                        Text(
                                          'Total: ${NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ').format(trx.total)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder:
                                              (context) =>
                                                  TransactionDetailPage(
                                                    transaction: trx,
                                                  ),
                                        ),
                                      );
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
