import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ArchivePage extends StatefulWidget {
  const ArchivePage({Key? key}) : super(key: key);

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  List<FileSystemEntity> _files = [];

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = "${dir.path}/arsip";
    final folder = Directory(path);

    if (await folder.exists()) {
      final files = folder.listSync();
      setState(() {
        _files = files.whereType<File>().toList();
      });
    }
  }

  // void _openFile(File file) {
  //   OpenFile.open(file.path);
  // }

  Future<void> _deleteFile(File file) async {
    try {
      await file.delete();
      _loadFiles(); // reload list setelah delete
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("${file.path.split('/').last} berhasil dihapus"),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Gagal menghapus file: $e")));
      }
    }
  }

  Future<void> _deleteAllFiles() async {
    try {
      for (var file in _files) {
        await file.delete();
      }
      _loadFiles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Semua arsip berhasil dihapus")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gagal menghapus semua arsip: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Arsip Transaksi"),
        actions: [
          if (_files.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_forever),
              tooltip: "Hapus semua arsip",
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder:
                      (ctx) => AlertDialog(
                        title: const Text("Konfirmasi"),
                        content: const Text(
                          "Yakin ingin menghapus semua arsip?",
                        ),
                        actions: [
                          TextButton(
                            child: const Text("Batal"),
                            onPressed: () => Navigator.pop(ctx, false),
                          ),
                          ElevatedButton(
                            child: const Text("Hapus"),
                            onPressed: () => Navigator.pop(ctx, true),
                          ),
                        ],
                      ),
                );
                if (confirm == true) {
                  await _deleteAllFiles();
                }
              },
            ),
        ],
      ),
      body:
          _files.isEmpty
              ? const Center(child: Text("Belum ada arsip."))
              : ListView.builder(
                itemCount: _files.length,
                itemBuilder: (context, index) {
                  final file = _files[index] as File;
                  final fileName = file.path.split("/").last;

                  return ListTile(
                    leading: const Icon(Icons.insert_drive_file),
                    title: Text(fileName),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.download),
                          tooltip: "Bagikan file",
                          onPressed: () async {
                            try {
                              await Share.shareXFiles(
                                [XFile(file.path)],
                                text:
                                    "Berikut arsip laporan transaksi: $fileName",
                              );
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text("Gagal membagikan file: $e"),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          tooltip: "Hapus file",
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder:
                                  (ctx) => AlertDialog(
                                    title: const Text("Konfirmasi"),
                                    content: Text(
                                      "Yakin ingin menghapus $fileName?",
                                    ),
                                    actions: [
                                      TextButton(
                                        child: const Text("Batal"),
                                        onPressed:
                                            () => Navigator.pop(ctx, false),
                                      ),
                                      ElevatedButton(
                                        child: const Text("Hapus"),
                                        onPressed:
                                            () => Navigator.pop(ctx, true),
                                      ),
                                    ],
                                  ),
                            );
                            if (confirm == true) {
                              await _deleteFile(file);
                            }
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
    );
  }
}
