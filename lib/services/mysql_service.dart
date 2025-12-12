// import 'dart:convert';

// import 'package:kasir_kutacane/models/Item.dart';
// import 'package:kasir_kutacane/models/transaction.dart';
// import 'package:kasir_kutacane/models/transactionItem.dart';
// import 'package:mysql1/mysql1.dart';

// class MySQLService {
//   static Future<MySqlConnection> getConnection() async {
//     final settings = ConnectionSettings(
//       host: '10.11.77.144', // ganti dengan IP server MySQL kamu
//       port: 3306,
//       user: 'root',
//       password: 'Abn913689', // ganti password MySQL kamu
//       db: 'dbboneva',
//     );
//     return await MySqlConnection.connect(settings);
//   }

//   static Future<List<Item>> getItems() async {
//     final conn = await getConnection();

//     final results = await conn.query(
//       'SELECT TYUNIT, NTYUNIT, hjual FROM munit',
//     );

//     List<Item> items = [];

//     for (var row in results) {
//       items.add(Item(name: row[1], price: (row[2] as num).toDouble()));
//     }

//     await conn.close();
//     return items;
//   }

//   static Future<bool> checkTransactionIdExists(String idTransaksi) async {
//     final conn = await getConnection();

//     try {
//       final results = await conn.query(
//         'SELECT COUNT(*) as count FROM transaksi WHERE id_transaksi = ?',
//         [idTransaksi],
//       );

//       final row = results.first;
//       final count = row['count'] as int;
//       return count > 0;
//     } catch (e) {
//       print('Error checking transaction ID: $e');
//       return false;
//     } finally {
//       await conn.close();
//     }
//   }

//   static Future<void> saveTransactionToDatabase(Transaction transaction) async {
//     final conn = await getConnection();

//     try {
//       await conn.transaction((txn) async {
//         // 1. Insert ke tabel `transaksi`
//         await txn.query(
//           'INSERT INTO transaksi (id_transaksi, customer_name, alamat, tanggal, total) VALUES (?, ?, ?, ?, ?)',
//           [
//             transaction.id,
//             transaction.customerName,
//             transaction.alamat,
//             transaction.date.toIso8601String(),
//             transaction.total.toInt(),
//           ],
//         );

//         // 2. Insert masing-masing item ke tabel `item_transaksi`
//         for (var item in transaction.items) {
//           await txn.query(
//             'INSERT INTO item_transaksi (id_transaksi, nama_barang, harga, jumlah, bonus, subtotal) VALUES (?, ?, ?, ?, ?, ?)',
//             [
//               transaction.id,
//               item.nameController.text,
//               item.price,
//               item.quantity,
//               item.bonus,
//               item.subtotal.toInt(),
//             ],
//           );
//         }
//       });
//     } catch (e) {
//       print('Error saving transaction to DB: $e');
//       rethrow;
//     } finally {
//       await conn.close();
//     }
//   }

//   static Future<Transaction?> getTransactionById(String idTransaksi) async {
//     final conn = await getConnection();

//     try {
//       // 1. Ambil data transaksi utama
//       final trxResults = await conn.query(
//         'SELECT * FROM transaksi WHERE id_transaksi = ?',
//         [idTransaksi],
//       );

//       if (trxResults.isEmpty) return null;

//       final trxRow = trxResults.first;

//       // 2. Ambil data item transaksi
//       final itemResults = await conn.query(
//         'SELECT nama_barang, harga, jumlah, bonus, subtotal FROM item_transaksi WHERE id_transaksi = ?',
//         [idTransaksi],
//       );

//       final items =
//           itemResults.map((row) {
//             return TransactionItem.fromData(
//               name: row['nama_barang'],
//               price: (row['harga'] as num).toDouble(),
//               quantity: row['jumlah'] as int,
//               bonus: row['bonus'] as int,
//             );
//           }).toList();

//       // 3. Buat objek Transaction
//       return Transaction(
//         // atau pakai trxRow['id'] as int
//         id: trxRow['id_transaksi'],
//         customerName: trxRow['customer_name'],
//         alamat: trxRow['alamat'].toString(),
//         date: DateTime.parse(trxRow['tanggal'].toString()),
//         total: (trxRow['total'] as num).toDouble(),
//         items: items,
//       );
//     } catch (e) {
//       print('Error fetching transaction: $e');
//       return null;
//     } finally {
//       await conn.close();
//     }
//   }

//   Future<List<Transaction>> getTransactions() async {
//     final db = await getConnection();

//     // 1. Ambil semua transaksi
//     final result = await db.query(
//       'SELECT * FROM transaksi ORDER BY tanggal DESC',
//     );

//     // 2. Buat list transaksi lengkap dengan items-nya
//     List<Transaction> transactions = [];

//     for (var row in result) {
//       final idTransaksi = row['id_transaksi'];

//       // 3. Ambil item berdasarkan id_transaksi
//       final itemRows = await db.query(
//         'SELECT * FROM item_transaksi WHERE id_transaksi = ?',
//         [idTransaksi],
//       );

//       // 4. Convert item ke List<TransactionItem>
//       final items =
//           itemRows.map<TransactionItem>((itemRow) {
//             return TransactionItem.fromData(
//               name: itemRow['nama_barang'],
//               price: (itemRow['harga'] as num).toDouble(),
//               quantity: itemRow['jumlah'] as int,
//               bonus: itemRow['bonus'] as int,
//             );
//           }).toList();

//       // 5. Buat object Transaction
//       transactions.add(
//         Transaction(
//           id: row['id_transaksi'],
//           customerName: row['customer_name'],
//           alamat: row['alamat'].toString(),
//           date: DateTime.parse(row['tanggal'].toString()),
//           total: (row['total'] as num).toDouble(),
//           items: items,
//         ),
//       );
//     }

//     return transactions;
//   }
// }
