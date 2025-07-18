import 'package:flutter/material.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/pages/transactionInput.dart';
import 'package:kasir_kutacane/pages/transactionlist.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final List<Transaction> _transactions =
      []; // List untuk menyimpan semua transaksi
  int _selectedIndex = 0; // Indeks halaman yang sedang aktif

  // Callback untuk menerima transaksi dari input page
  void _addTransaction(Transaction transaction) {
    setState(() {
      _transactions.add(transaction);
    });
  }

  // Fungsi untuk mengubah indeks saat BottomNavigationBar di-tap
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // List halaman yang akan ditampilkan
    final List<Widget> _pages = [
      TransactionInputPage(onSave: _addTransaction),
      TransactionListPage(),
    ];

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Aplikasi Sales',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: Scaffold(
        body:
            _pages[_selectedIndex], // Menampilkan halaman sesuai indeks yang dipilih
        bottomNavigationBar: BottomNavigationBar(
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.add_shopping_cart),
              label: 'Input Transaksi',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.list_alt),
              label: 'Daftar Transaksi',
            ),
          ],
          currentIndex: _selectedIndex, // Indeks item yang sedang aktif
          selectedItemColor:
              Theme.of(context).primaryColor, // Warna item yang dipilih
          onTap: _onItemTapped, // Callback saat item di-tap
        ),
      ),
    );
  }
}
