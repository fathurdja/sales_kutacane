import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/pages/transactionDetail.dart';

class CsvExcelToJsonPage extends StatefulWidget {
  @override
  _CsvExcelToJsonPageState createState() => _CsvExcelToJsonPageState();
}

class _CsvExcelToJsonPageState extends State<CsvExcelToJsonPage> {
  List<Map<String, dynamic>> transaksiList = [];

  Future<void> _pickAndParseFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx'],
      withData: true,
    );

    if (result == null) return;

    Uint8List? fileBytes = result.files.single.bytes;
    String? extension = result.files.single.extension;

    if (fileBytes == null) return;

    List<List<dynamic>> table = [];

    // 🔹 CSV
    if (extension == "csv") {
      final csvString = utf8.decode(fileBytes);
      table = const CsvToListConverter(eol: '\n').convert(csvString);
    }
    // 🔹 Excel
    else if (extension == "xlsx") {
      final excel = Excel.decodeBytes(fileBytes);
      final sheet = excel.tables[excel.tables.keys.first]!;
      table =
          sheet.rows
              .map((row) => row.map((e) => e?.value?.toString() ?? "").toList())
              .toList();
    }

    if (table.isEmpty) return;

    // Ambil header
    final headers = table.first.map((e) => e.toString()).toList();
    final rows = table.skip(1);

    Map<String, Map<String, dynamic>> grouped = {};

    for (var row in rows) {
      // skip TOTAL row
      if (row.isEmpty || row[0].toString().toUpperCase() == 'TOTAL') continue;

      Map<String, dynamic> rowData = {};
      final qtyKeys = ['Qty', 'quantity'];
      final doubleKeys = ['Price', 'Subtotal', 'Total', 'total'];
      final intKeys = ['Bonus', 'bonus'];

      for (int i = 0; i < headers.length; i++) {
        final key = headers[i];
        final val = row[i].toString(); // pastikan val selalu String
        if (qtyKeys.contains(key)) {
          rowData[key] = int.tryParse(val) ?? 0;
        } else if (doubleKeys.contains(key)) {
          rowData[key] = double.tryParse(val) ?? 0.0;
        } else if (intKeys.contains(key)) {
          rowData[key] = int.tryParse(val) ?? 0;
        } else {
          rowData[key] = val; // string
        }
      }

      final trxId = rowData['ID'] ?? rowData['id_transaksi'] ?? '';

      if (!grouped.containsKey(trxId)) {
        grouped[trxId] = {
          "id_transaksi": rowData['ID']?.toString() ?? "",
          "customerName": rowData['Customer']?.toString() ?? "",
          "alamat": rowData['Alamat']?.toString() ?? "",
          "date":
              rowData['date']?.toString() ?? DateTime.now().toIso8601String(),
          "items": [],
          "total": rowData['Total'] ?? 0.0,
          "status": rowData['Status']?.toString() ?? "-",
          "id": trxId?.toString() ?? trxId,
        };
      }

      grouped[trxId]!['items'].add({
        "name": rowData['Item'] ?? "",
        "quantity": rowData['Qty'] ?? 0,
        "price": rowData['Price'] ?? 0.0,
        "subtotal": (rowData['Price'] ?? 0.0) * (rowData['Qty'] ?? 0),
        "bonus": rowData['Bonus'] ?? 0,
      });
    }

    setState(() {
      transaksiList = grouped.values.toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("CSV/Excel to JSON Viewer")),
      body: Column(
        children: [
          ElevatedButton(
            onPressed: _pickAndParseFile,
            child: Text("Upload CSV/Excel"),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: transaksiList.length,
              itemBuilder: (context, index) {
                final trxJson = transaksiList[index];
                final trx = Transaction.fromJson(trxJson);

                return Card(
                  margin: EdgeInsets.all(8),
                  child: ListTile(
                    title: Text("${trx.id_transaksi} - ${trx.customerName}"),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Alamat: ${trx.alamat}"),
                        Text("Total: ${trx.total} | Status: ${trx.status}"),
                        ...trx.items.map(
                          (item) => Text(
                            "• ${item.name} x${item.quantity} = ${item.subtotal}",
                          ),
                        ),
                      ],
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (context) =>
                                  TransactionDetailPage(transaction: trx),
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
