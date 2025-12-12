import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/models/transactionItem.dart';
import 'package:kasir_kutacane/pages/transactionDetail.dart';
import 'package:kasir_kutacane/pages/transactionInput.dart';
import 'package:path_provider/path_provider.dart';

class TransactionListPageBackup extends StatefulWidget {
  const TransactionListPageBackup({Key? key}) : super(key: key);

  @override
  State<TransactionListPageBackup> createState() =>
      _TransactionListPageBackupState();
}

class _TransactionListPageBackupState extends State<TransactionListPageBackup> {
  DateTime? _filterDate;
  List<Transaction> _transactions = [];
  List<Transaction> _filteredTransactions = [];
  bool _isLoading = true;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _filterDate = DateTime.now();
    _fetchTransactions();
  }

  Future<void> _fetchTransactions() async {
    const url = 'http://6873b63ec75558e273550195.mockapi.io/transaksi';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);

        final loadedTransactions =
            data.map<Transaction>((json) {
              return Transaction(
                id: json['id'],
                id_transaksi: json['id_transaksi'],
                customerName: json['customerName'],
                alamat: json['alamat'],
                date: safeParseDate(json['date']),
                total: (json['total'] as num).toDouble(),
                status: json['status'] ?? '-',
                items:
                    (json['items'] as List<dynamic>)
                        .map<TransactionItem>(
                          (item) => TransactionItem.fromJson(item),
                        )
                        .toList(),
              );
            }).toList();

        // 🔥 Urutkan transaksi dari terbaru -> terlama
        loadedTransactions.sort((a, b) => b.date.compareTo(a.date));

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

  DateTime safeParseDate(String value) {
    try {
      return DateTime.parse(value);
    } catch (e) {
      // Coba perbaiki format microseconds
      try {
        // Pisahkan bagian date dan microsecond
        final parts = value.split('.');
        if (parts.length == 2) {
          final main = parts[0];
          String micro = parts[1];

          // Hapus karakter aneh seperti Z, ', ", spasi
          micro = micro.replaceAll(RegExp(r'[^0-9]'), '');

          // Potong microsecond menjadi 6 digit maksimal
          if (micro.length > 6) {
            micro = micro.substring(0, 6);
          }

          final fixed = "$main.$micro";
          return DateTime.parse(fixed);
        }
      } catch (_) {}

      return DateTime.now(); // fallback
    }
  }

  Future<void> _deleteTransaction(String id) async {
    final url = 'http://6873b63ec75558e273550195.mockapi.io/transaksi/$id';

    try {
      final response = await http.delete(Uri.parse(url));
      if (response.statusCode == 200) {
        setState(() {
          _transactions.removeWhere((trx) => trx.id == id);
          _applyFilter();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaksi berhasil dihapus')),
        );
      } else {
        throw Exception('Gagal menghapus transaksi');
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _exportToCSV() async {
    setState(() {
      _isProcessing = true; // tampilkan loading
    });

    try {
      // Ambil direktori penyimpanan lokal
      final dir = await getApplicationDocumentsDirectory();
      final path = "${dir.path}/arsip";
      final folder = Directory(path);

      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }

      // Buat nama file dengan format aman
      final timestamp = DateFormat("yyyyMMdd_HHmmss").format(DateTime.now());
      final fileName = "transaksi_$timestamp.csv";
      final file = File("$path/$fileName");

      // Header CSV
      List<List<dynamic>> rows = [
        [
          "ID",
          "Customer",
          "Alamat",
          "date",
          "total",
          "status",
          "Item",
          "Price",
          "Qty",
          "Bonus",
        ],
      ];

      // Isi data transaksi
      for (var trx in _transactions) {
        for (var item in trx.items) {
          rows.add([
            trx.id_transaksi,
            trx.customerName,
            trx.alamat,
            trx.date.toIso8601String(),
            trx.total,
            trx.status,
            item.name,
            item.price,
            item.quantity,
            item.bonus,
          ]);
        }
      }

      // Simpan ke file CSV
      String csvData = const ListToCsvConverter().convert(rows);
      await file.writeAsString(csvData);

      // Setelah berhasil export, hapus semua data di API
      await _deleteAllTransactions();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Data berhasil diarsipkan ke $fileName")),
        );
      }
    } catch (e) {
      debugPrint("Error export CSV: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error export: $e")));
      }
    } finally {
      setState(() {
        _isProcessing = false; // sembunyikan loading
      });
    }
  }

  Future<void> _deleteAllTransactions() async {
    try {
      const url = 'http://6873b63ec75558e273550195.mockapi.io/transaksi';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);

        for (var trx in data) {
          final deleteUrl = "$url/${trx['id']}";
          await http.delete(Uri.parse(deleteUrl));
        }

        setState(() {
          _transactions.clear();
          _filteredTransactions.clear();
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Semua transaksi berhasil dihapus dari API'),
            ),
          );
        }
      } else {
        throw Exception('Gagal mengambil data dari API untuk dihapus');
      }
    } catch (e) {
      debugPrint("Error hapus semua: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error hapus semua: $e')));
      }
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
            icon: const Icon(Icons.archive),
            tooltip: "Arsipkan ke CSV",
            onPressed: _exportToCSV,
          ),
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
          _isLoading || _isProcessing
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
                                    title: Text(
                                      '${trx.id_transaksi}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('Konsumen: ${trx.customerName}'),
                                        Text('Alamat: ${trx.alamat}'),
                                        Text(
                                          'Tanggal: ${DateFormat('dd-MM-yyyy').format(trx.date)}',
                                        ),
                                        Text('Pembayaran: ${trx.status}'),
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
                                    // 🔥 Tombol hapus di pojok kanan
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            Icons.edit,
                                            color: Colors.blue,
                                          ),
                                          onPressed: () async {
                                            final updatedTransaction = await Navigator.of(
                                              context,
                                            ).push<Transaction>(
                                              MaterialPageRoute(
                                                builder:
                                                    (
                                                      context,
                                                    ) => TransactionInputPage(
                                                      transaction:
                                                          trx, // kirim data transaksi
                                                      onSave: (trx) async {
                                                        await _fetchTransactions();
                                                        setState(() {});
                                                      }, // nanti kita akan handle reload
                                                    ),
                                              ),
                                            );

                                            if (updatedTransaction != null) {
                                              // replace transaksi lama dengan versi baru
                                              setState(() {
                                                final index = _transactions
                                                    .indexWhere(
                                                      (t) =>
                                                          t.id ==
                                                          updatedTransaction.id,
                                                    );
                                                if (index != -1) {
                                                  _transactions[index] =
                                                      updatedTransaction;
                                                  _applyFilter();
                                                }
                                              });
                                            }
                                          },
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete,
                                            color: Colors.red,
                                          ),
                                          onPressed: () {
                                            showDialog(
                                              context: context,
                                              builder:
                                                  (ctx) => AlertDialog(
                                                    title: const Text(
                                                      'Konfirmasi',
                                                    ),
                                                    content: const Text(
                                                      'Apakah Anda yakin ingin menghapus transaksi ini?',
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed:
                                                            () =>
                                                                Navigator.of(
                                                                  ctx,
                                                                ).pop(),
                                                        child: const Text(
                                                          'Batal',
                                                        ),
                                                      ),
                                                      TextButton(
                                                        onPressed: () {
                                                          Navigator.of(
                                                            ctx,
                                                          ).pop();
                                                          _deleteTransaction(
                                                            trx.id,
                                                          );
                                                        },
                                                        child: const Text(
                                                          'Hapus',
                                                          style: TextStyle(
                                                            color: Colors.red,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
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
