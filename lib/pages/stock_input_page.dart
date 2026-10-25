import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/models/Item.dart';
import 'package:kasir_kutacane/models/stock_group.dart';
import 'package:kasir_kutacane/models/user_model.dart';
import 'package:kasir_kutacane/services/auth_service.dart';
import 'package:kasir_kutacane/services/offline_sync_service.dart';
import 'package:kasir_kutacane/services/stock_api_service.dart';
import 'package:kasir_kutacane/theme/app_theme.dart';

class StockInputPage extends StatefulWidget {
  const StockInputPage({super.key});

  @override
  State<StockInputPage> createState() => _StockInputPageState();
}

class _StockInputPageState extends State<StockInputPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();

  List<StockGroup> _stockGroups = [];
  List<Item> _allProducts = [];
  List<Item> _filteredProducts = [];
  Map<String, dynamic> _terjualData = {};
  int? _adminSelectedUserId;
  List<UserModel> _salesUsers = [];

  bool _isLoading = true;
  String? _errorMessage;
  String _selectedTerjualKelompok = 'ALL';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchCtrl.addListener(_applyProductFilter);
    _loadAllStockData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllStockData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (AuthService.currentUser?.isAdmin == true && _salesUsers.isEmpty) {
        try {
          _salesUsers = await AuthService.fetchUsers();
        } catch (_) {}
      }

      final results = await Future.wait([
        StockApiService.fetchStockSummary(userId: _adminSelectedUserId),
        StockApiService.fetchProducts(),
        StockApiService.fetchStockTerjual(),
      ]);

      final groups = results[0] as List<StockGroup>;
      final products = results[1] as List<Item>;
      final terjual = results[2] as Map<String, dynamic>;

      if (!mounted) return;
      setState(() {
        _stockGroups = groups;
        _allProducts = products;
        _terjualData = terjual;
        _isLoading = false;
      });

      // Simpan ke cache offline HP
      await OfflineSyncService.cacheProducts(products);
      _applyProductFilter();
    } catch (e) {
      debugPrint("Gagal memuat data dari server ($e), memuat cache offline...");
      final cached = await OfflineSyncService.getCachedProducts();
      if (!mounted) return;
      setState(() {
        _allProducts = cached;
        _isLoading = false;
        _errorMessage = cached.isNotEmpty
            ? 'Mode Offline: Menampilkan data stok tersimpan di HP.'
            : 'Gagal menghubungi server: $e';
      });
      _applyProductFilter();
    }
  }

  void _applyProductFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filteredProducts = List.from(_allProducts);
      } else {
        _filteredProducts = _allProducts.where((p) {
          return p.name.toLowerCase().contains(q) ||
              p.tyunit.toLowerCase().contains(q) ||
              p.kelompok.toLowerCase().contains(q);
        }).toList();
      }
    });
  }

  // ===========================================================================
  // MODAL & AKSI: SET STOK AWAL KELOMPOK
  // ===========================================================================
  void _openSetStockAwalDialog(StockGroup group) {
    if (AuthService.currentUser?.canManageStock != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Akses Ditolak: User biasa hanya memiliki hak akses melihat stok.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final stockCtrl = TextEditingController(text: group.stockAwal.toString());
    bool resetTerjual = false;
    bool isSubmitting = false;
    int? targetUserId = _adminSelectedUserId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Container(
            padding: EdgeInsets.only(
              left: AppSpacing.screenMargin,
              right: AppSpacing.screenMargin,
              top: AppSpacing.xl,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.xl,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _getGroupColor(group.kelompok).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _getGroupIcon(group.kelompok),
                        color: _getGroupColor(group.kelompok),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Set Stok Awal: ${group.displayName}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            'Kelompok Komoditas Fisik [${group.kelompok}]',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),

                // Info Status Saat Ini
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.bgSecondary,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _miniStat('Stok Awal', '${group.stockAwal}', group.unitName),
                      Container(width: 1, height: 32, color: Colors.grey.shade300),
                      _miniStat('Terjual', '${group.totalTerjual}', group.unitName),
                      Container(width: 1, height: 32, color: Colors.grey.shade300),
                      _miniStat('Sisa Fisik', '${group.sisaStock}', group.unitName),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Selector Alokasi Armada Sales (Khusus Admin)
                if (AuthService.currentUser?.isAdmin == true && _salesUsers.isNotEmpty) ...[
                  const Text(
                    'Alokasikan Kuota Untuk Sales:',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text('Semua Sales (Global)'),
                          selected: targetUserId == null,
                          onSelected: (sel) {
                            setModalState(() => targetUserId = null);
                          },
                        ),
                        const SizedBox(width: 6),
                        ..._salesUsers.map((u) {
                          final isSel = targetUserId == u.id;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              avatar: Icon(Icons.person, size: 14, color: isSel ? Colors.white : Colors.grey.shade700),
                              label: Text(u.name),
                              selected: isSel,
                              onSelected: (sel) {
                                setModalState(() => targetUserId = sel ? u.id : null);
                              },
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                const Text(
                  'Jumlah Kuota Stok Masuk',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: stockCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  autofocus: true,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.inventory_2_outlined),
                    suffixText: group.unitName,
                    suffixStyle: const TextStyle(fontWeight: FontWeight.w600),
                    hintText: 'Contoh: 100',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.input),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Opsi Quick Buttons
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ActionChip(
                      backgroundColor: Colors.blue.shade50,
                      avatar: const Icon(Icons.history_rounded, size: 16, color: Colors.blue),
                      label: Text(
                        'Sisa Hari Ini (${group.sisaStock} ${group.unitName})',
                        style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      onPressed: () {
                        setModalState(() {
                          final sisa = group.sisaStock < 0 ? 0 : group.sisaStock;
                          stockCtrl.text = sisa.toString();
                          resetTerjual = true;
                        });
                      },
                    ),
                    ...[50, 100, 150, 200].map((qty) {
                      return ActionChip(
                        label: Text('$qty ${group.unitName}'),
                        onPressed: () {
                          setModalState(() {
                            stockCtrl.text = qty.toString();
                          });
                        },
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 16),

                // Switch Reset Terjual
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Reset Counter Penjualan ke 0?',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.amber.shade900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Aktifkan jika ganti shift atau mulai hari baru agar hitungan terjual dimulai dari nol.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.amber.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: resetTerjual,
                        activeColor: AppColors.primary,
                        onChanged: (val) {
                          setModalState(() => resetTerjual = val);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Tombol Simpan
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                    icon: isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: Text(
                      isSubmitting ? 'Menyimpan...' : 'Simpan Kuota Stok Awal',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            final inputQty = int.tryParse(stockCtrl.text.trim());
                            if (inputQty == null || inputQty < 0) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Masukkan jumlah stok yang valid!'),
                                  backgroundColor: AppColors.error,
                                ),
                              );
                              return;
                            }

                            setModalState(() => isSubmitting = true);
                            try {
                              await StockApiService.setStockAwal(
                                kelompok: group.kelompok,
                                stockAwal: inputQty,
                                resetTerjual: resetTerjual,
                                userId: targetUserId,
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (mounted) {
                                final targetUserObj = _salesUsers
                                    .where((u) => u.id == targetUserId)
                                    .firstOrNull;
                                final forText = targetUserObj != null
                                    ? ' (Khusus ${targetUserObj.name})'
                                    : ' (Global)';
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Stok awal ${group.displayName} berhasil diset ke $inputQty ${group.unitName}$forText',
                                    ),
                                    backgroundColor: AppColors.lunas,
                                  ),
                                );
                                _loadAllStockData();
                              }
                            } catch (e) {
                              setModalState(() => isSubmitting = false);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Gagal menyimpan: $e'),
                                    backgroundColor: AppColors.error,
                                  ),
                                );
                              }
                            }
                          },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ===========================================================================
  // MODAL: RESET TERJUAL
  // ===========================================================================
  void _confirmResetTerjual({String? kelompok}) {
    if (AuthService.currentUser?.canManageStock != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Akses Ditolak: User biasa hanya memiliki hak akses melihat stok.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final title = kelompok != null
        ? 'Reset Penjualan $kelompok'
        : 'Reset Seluruh Penjualan Hari Ini';
    final desc = kelompok != null
        ? 'Counter barang terjual untuk kelompok $kelompok akan kembali ke 0. Kuota sisa stok akan dihitung ulang.'
        : 'Seluruh counter barang terjual hari ini akan dikembalikan ke 0 untuk semua produk.';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
          ],
        ),
        content: Text(desc, style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await StockApiService.resetStockTerjual(
                  kelompok: kelompok,
                  userId: _adminSelectedUserId,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Counter terjual berhasil direset ke 0!'),
                      backgroundColor: AppColors.lunas,
                    ),
                  );
                  _loadAllStockData();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Gagal reset: $e'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            child: const Text('Ya, Reset ke 0'),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // MODAL: EDIT HARGA MASTER PRODUK
  // ===========================================================================
  void _openEditProductDialog(Item item) {
    if (AuthService.currentUser?.canManageStock != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Akses Ditolak: User biasa hanya memiliki hak akses melihat stok.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final priceCtrl = TextEditingController(text: item.price.toInt().toString());
    final nameCtrl = TextEditingController(text: item.name);
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.edit_note, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Edit Produk (${item.tyunit})',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Nama Varian:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(isDense: true),
                ),
                const SizedBox(height: 12),
                const Text('Harga Jual (Rp):', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                TextField(
                  controller: priceCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(isDense: true, prefixText: 'Rp '),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.bgSecondary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Kelompok: ${item.kelompok} • Sisa Kuota Fisik: ${item.sisaKuota}',
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
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
                        final newPrice = int.tryParse(priceCtrl.text.trim()) ?? item.price.toInt();
                        setDialogState(() => isSaving = true);
                        try {
                          await StockApiService.updateMasterProduct(
                            tyunit: item.tyunit,
                            name: nameCtrl.text.trim(),
                            price: newPrice,
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Varian ${item.tyunit} berhasil diperbarui!'),
                                backgroundColor: AppColors.lunas,
                              ),
                            );
                            _loadAllStockData();
                          }
                        } catch (e) {
                          setDialogState(() => isSaving = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Gagal edit: $e'), backgroundColor: AppColors.error),
                            );
                          }
                        }
                      },
                child: Text(isSaving ? 'Menyimpan...' : 'Simpan'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ===========================================================================
  // BUILD UI UTAMA
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Manajemen Stok & Kuota'),
            Text(
              'Stok Awal Fisik & Terjual per Varian',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Stok',
            onPressed: _loadAllStockData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.inventory_2_outlined, size: 20), text: 'Stok Awal'),
            Tab(icon: Icon(Icons.point_of_sale_outlined, size: 20), text: 'Stok Terjual'),
            Tab(icon: Icon(Icons.list_alt_outlined, size: 20), text: 'Master Produk'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_errorMessage != null)
                  Container(
                    width: double.infinity,
                    color: Colors.amber.shade100,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.amber.shade900),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildTabStokAwal(),
                      _buildTabStokTerjual(),
                      _buildTabMasterProduk(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ===========================================================================
  // TAB 1: STOK AWAL (KUOTA KOMODITAS FISIK)
  // ===========================================================================
  Widget _buildTabStokAwal() {
    return RefreshIndicator(
      onRefresh: _loadAllStockData,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenMargin),
        children: [
          // Filter Armada (Khusus Admin)
          if (AuthService.currentUser?.isAdmin == true) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.purple.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.tune_rounded, size: 16, color: Colors.purple),
                      SizedBox(width: 8),
                      Text(
                        'Monitor Kuota Stok per Armada (Admin):',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.purple,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text('Semua Armada (Global)'),
                          selected: _adminSelectedUserId == null,
                          selectedColor: Colors.purple.shade600,
                          labelStyle: TextStyle(
                            color: _adminSelectedUserId == null
                                ? Colors.white
                                : Colors.purple.shade800,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              setState(() => _adminSelectedUserId = null);
                              _loadAllStockData();
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        ..._salesUsers.map((u) {
                          final isSel = _adminSelectedUserId == u.id;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              avatar: Icon(
                                Icons.person,
                                size: 14,
                                color: isSel ? Colors.white : Colors.purple,
                              ),
                              label: Text(u.name),
                              selected: isSel,
                              selectedColor: Colors.purple.shade600,
                              labelStyle: TextStyle(
                                color: isSel ? Colors.white : Colors.purple.shade800,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                              onSelected: (selected) {
                                setState(() =>
                                    _adminSelectedUserId = selected ? u.id : null);
                                _loadAllStockData();
                              },
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ] else ...[
            // Banner Read-Only & Isolasi untuk Sales Biasa
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, color: Colors.blue, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Mode Stok Terisolasi: Anda melihat sisa kuota khusus armada ${AuthService.currentUser?.name ?? "Sales"}. Transaksi Anda tidak mengurangi kuota armada lain.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade900,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Banner Panduan Singkat Arsitektur Stok Baru
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withOpacity(0.5),
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.primary.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline, color: AppColors.primary, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sistem Kuota Komoditas Fisik',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Stok fisik diinput per kelompok komoditas (misal 100 galon). Penjualan seluruh varian harga galon otomatis memotong kuota fisik tersebut.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textPrimary.withOpacity(0.85),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (_stockGroups.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  'Belum ada data kelompok komoditas di server.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            ..._stockGroups.map((group) => _buildStockGroupCard(group)),
        ],
      ),
    );
  }

  Widget _buildStockGroupCard(StockGroup group) {
    final groupColor = _getGroupColor(group.kelompok);
    final iconData = _getGroupIcon(group.kelompok);
    final percent = group.persentaseTersedia;

    Color statusColor;
    String statusText;
    if (group.sisaStock <= 0) {
      statusColor = AppColors.error;
      statusText = 'HABIS';
    } else if (percent < 0.2) {
      statusColor = Colors.orange.shade800;
      statusText = 'MENIPIS';
    } else {
      statusColor = AppColors.lunas;
      statusText = 'AMAN';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      elevation: 1.5,
      child: Column(
        children: [
          // Header Card
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: groupColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(iconData, color: groupColor, size: 24),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.displayName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${group.kelompok} • ${group.jumlahProduk} Varian Harga',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: statusColor,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 3 Metrik Utama: Stok Awal | Terjual | Sisa
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  decoration: BoxDecoration(
                    color: AppColors.bgSecondary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _stockMetricBox(
                          label: 'Stok Awal',
                          value: '${group.stockAwal}',
                          unit: group.unitName,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Container(width: 1, height: 36, color: Colors.grey.shade300),
                      Expanded(
                        child: _stockMetricBox(
                          label: 'Terjual',
                          value: '${group.totalTerjual}',
                          unit: group.unitName,
                          color: Colors.orange.shade800,
                        ),
                      ),
                      Container(width: 1, height: 36, color: Colors.grey.shade300),
                      Expanded(
                        child: _stockMetricBox(
                          label: 'Sisa Fisik',
                          value: '${group.sisaStock}',
                          unit: group.unitName,
                          color: statusColor,
                          isBold: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Progress Bar Persentase
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: percent,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                          minHeight: 8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${(percent * 100).toInt()}% Tersedia',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Tombol Aksi: Set Kuota Stok Awal (Khusus Admin / canManageStock)
                if (AuthService.currentUser?.canManageStock == true)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: groupColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      label: Text(
                        'Set / Tambah Kuota ${group.unitName}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      onPressed: () => _openSetStockAwalDialog(group),
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 11, horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_outline,
                            size: 16, color: Colors.grey.shade600),
                        const SizedBox(width: 8),
                        Text(
                          'Akses Read-Only • Kuota Diatur Administrator',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Accordion / Rincian Varian Produk di Dalam Kelompok Ini
          if (group.rincianProduk.isNotEmpty) ...[
            const Divider(height: 1),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: Text(
                  'Lihat ${group.rincianProduk.length} Varian Harga & Penjualan',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                children: [
                  Container(
                    color: AppColors.bgSecondary.withOpacity(0.5),
                    child: Column(
                      children: group.rincianProduk.map((v) {
                        final currencyFormat = NumberFormat.currency(
                          locale: 'id_ID',
                          symbol: 'Rp ',
                          decimalDigits: 0,
                        );
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: groupColor.withOpacity(0.15),
                            child: Text(
                              v.tyunit.replaceAll('BV', ''),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: groupColor,
                              ),
                            ),
                          ),
                          title: Text(
                            v.namaProduk,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '${v.tyunit} • ${currencyFormat.format(v.harga)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: v.terjual > 0 ? Colors.green.shade50 : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: v.terjual > 0 ? Colors.green.shade300 : Colors.grey.shade300,
                              ),
                            ),
                            child: Text(
                              'Terjual: ${v.terjual}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: v.terjual > 0 ? Colors.green.shade800 : Colors.grey.shade600,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 2: STOK TERJUAL (AKUMULASI PENJUALAN PER VARIAN)
  // ===========================================================================
  Widget _buildTabStokTerjual() {
    final currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final totalTerjualSemua = _terjualData['total_terjual_keseluruhan'] ?? 0;
    final List items = (_terjualData['items'] as List?) ?? [];

    final filteredItems = _selectedTerjualKelompok == 'ALL'
        ? items
        : items.where((i) => i['kelompok'] == _selectedTerjualKelompok).toList();

    return RefreshIndicator(
      onRefresh: _loadAllStockData,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenMargin),
        children: [
          // Banner Total Terjual Hari Ini
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E88E5), Color(0xFF1565C0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total Terjual Hari Ini',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$totalTerjualSemua Unit',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Akumulasi seluruh varian Boneva',
                      style: TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                  ],
                ),
                if (AuthService.currentUser?.canManageStock == true)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('Reset Hari Ini'),
                    onPressed: () => _confirmResetTerjual(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Filter Tab Kelompok
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('Semua Komoditas', 'ALL'),
                _filterChip('Galon', 'GALON'),
                _filterChip('Botol 600ml', 'BOTOL_600'),
                _filterChip('Botol 1.5L', 'BOTOL_1500'),
                _filterChip('Gelas', 'GELAS'),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Daftar Produk Terjual
          if (filteredItems.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text('Belum ada data barang terjual.', style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            ...filteredItems.map((item) {
              final terjual = item['terjual'] ?? 0;
              final harga = item['harga'] ?? 0;
              final omzet = terjual * harga;
              final kelompok = item['kelompok'] ?? '';
              final color = _getGroupColor(kelompok);

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color.withOpacity(0.12),
                    child: Text(
                      item['tyunit']?.toString().replaceAll('BV', '') ?? '',
                      style: TextStyle(color: color, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(
                    item['nama_produk']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                  ),
                  subtitle: Text(
                    '${item['tyunit']} • ${currencyFormat.format(harga)} / unit',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$terjual terjual',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: terjual > 0 ? Colors.green.shade800 : AppColors.textSecondary,
                        ),
                      ),
                      if (terjual > 0)
                        Text(
                          currencyFormat.format(omzet),
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String code) {
    final isSelected = _selectedTerjualKelompok == code;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: AppColors.primary,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : AppColors.textPrimary,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          fontSize: 12,
        ),
        onSelected: (val) {
          if (val) setState(() => _selectedTerjualKelompok = code);
        },
      ),
    );
  }

  // ===========================================================================
  // TAB 3: MASTER 13 PRODUK
  // ===========================================================================
  Widget _buildTabMasterProduk() {
    final currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return Column(
      children: [
        // Search Bar
        Padding(
          padding: const EdgeInsets.all(AppSpacing.screenMargin),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Cari produk atau kode unit (misal: BV01, Galon)...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        _applyProductFilter();
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),

        // List Produk
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadAllStockData,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMargin),
              itemCount: _filteredProducts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, idx) {
                final item = _filteredProducts[idx];
                final color = _getGroupColor(item.kelompok);

                return Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 1,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: color.withOpacity(0.12),
                      child: Text(
                        item.tyunit.replaceAll('BV', ''),
                        style: TextStyle(color: color, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(
                      item.name,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                    ),
                    subtitle: Text(
                      '${item.tyunit} • Kelompok: ${item.kelompok}\nSisa Kuota: ${item.sisaKuota} | Terjual: ${item.terjual}',
                      style: const TextStyle(fontSize: 11.5, height: 1.3),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          currencyFormat.format(item.price),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            color: AppColors.primary,
                          ),
                        ),
                        if (AuthService.currentUser?.canManageStock == true) ...[
                          const SizedBox(height: 2),
                          InkWell(
                            onTap: () => _openEditProductDialog(item),
                            child: const Text(
                              'Edit Harga',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.blue,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    onTap: AuthService.currentUser?.canManageStock == true
                        ? () => _openEditProductDialog(item)
                        : null,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // HELPER WIDGETS & COLORS
  // ===========================================================================
  Widget _stockMetricBox({
    required String label,
    required String value,
    required String unit,
    required Color color,
    bool isBold = false,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 2),
        RichText(
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          text: TextSpan(
            text: value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w700,
              color: color,
            ),
            children: [
              TextSpan(
                text: ' $unit',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _miniStat(String label, String value, String unit) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        const SizedBox(height: 2),
        Text('$value $unit', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Color _getGroupColor(String kelompok) {
    switch (kelompok.toUpperCase()) {
      case 'GALON':
        return const Color(0xFF0288D1); // Light Blue / Cyan Ocean
      case 'BOTOL_600':
        return const Color(0xFF00897B); // Teal
      case 'BOTOL_1500':
        return const Color(0xFF5E35B1); // Deep Purple
      case 'GELAS':
        return const Color(0xFFE65100); // Amber / Deep Orange
      default:
        return AppColors.primary;
    }
  }

  IconData _getGroupIcon(String kelompok) {
    switch (kelompok.toUpperCase()) {
      case 'GALON':
        return Icons.water_drop_outlined;
      case 'BOTOL_600':
        return Icons.local_drink_outlined;
      case 'BOTOL_1500':
        return Icons.wine_bar_outlined;
      case 'GELAS':
        return Icons.crop_square_outlined;
      default:
        return Icons.inventory_2_outlined;
    }
  }
}
