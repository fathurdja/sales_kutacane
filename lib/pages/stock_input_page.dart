import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/models/Item.dart';
import 'package:kasir_kutacane/services/offline_sync_service.dart';
import 'package:kasir_kutacane/theme/app_theme.dart';
import 'package:kasir_kutacane/widgets/app_widgets.dart';

enum StockFilter { all, outOfStock, lowStock, available }

class StockInputPage extends StatefulWidget {
  const StockInputPage({super.key});

  @override
  State<StockInputPage> createState() => _StockInputPageState();
}

class _StockInputPageState extends State<StockInputPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Item> _products = [];
  List<Item> _filteredProducts = [];
  Map<String, int> _productIdMap = {}; // tyunit -> product id (1..13)
  bool _isLoading = true;
  String? _errorMessage;
  StockFilter _selectedFilter = StockFilter.all;

  @override
  void initState() {
    super.initState();
    _loadStockData();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStockData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Ambil dari master-stocks
      const msUrl = 'https://laravel.fathurrzqn8n.web.id/api/master-stocks';
      final msRes = await http
          .get(Uri.parse(msUrl), headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));

      // 2. Ambil dari products untuk sinkronisasi stock & id
      const prodUrl = 'https://laravel.fathurrzqn8n.web.id/api/products';
      final prodRes = await http
          .get(Uri.parse(prodUrl), headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));

      Map<String, int> stockFromProducts = {};
      Map<String, int> idFromProducts = {};

      if (prodRes.statusCode == 200) {
        final List<dynamic> prodData = jsonDecode(prodRes.body);
        for (var p in prodData) {
          final id = (p['id'] as num?)?.toInt() ?? 0;
          final tyunit = 'BV${id.toString().padLeft(2, '0')}';
          final stock = (p['stock'] as num?)?.toInt() ?? 0;
          stockFromProducts[tyunit] = stock;
          idFromProducts[tyunit] = id;
        }
      }

      if (msRes.statusCode == 200) {
        final body = jsonDecode(msRes.body);
        final List data = body['data'] ?? [];

        final loaded = data.map<Item>((json) {
          final item = Item.fromJson(json);
          // Prioritaskan stok aktif dari produk jika munit bernilai null/0
          final prodStock = stockFromProducts[item.tyunit];
          final finalStock = (item.stock > 0) ? item.stock : (prodStock ?? 0);
          return Item(
            tyunit: item.tyunit,
            name: item.name,
            price: item.price,
            stock: finalStock,
          );
        }).toList();

        if (!mounted) return;
        setState(() {
          _products = loaded;
          _productIdMap = idFromProducts;
          _isLoading = false;
        });
        OfflineSyncService.cacheProducts(loaded);
        _applyFilter();
      } else {
        throw Exception('Server error (${msRes.statusCode})');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _applyFilter() {
    final query = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      _filteredProducts = _products.where((p) {
        // Search query
        if (query.isNotEmpty) {
          final matchName = p.name.toLowerCase().contains(query);
          final matchCode = p.tyunit.toLowerCase().contains(query);
          if (!matchName && !matchCode) return false;
        }

        // Status filter
        switch (_selectedFilter) {
          case StockFilter.all:
            return true;
          case StockFilter.outOfStock:
            return p.stock <= 0;
          case StockFilter.lowStock:
            return p.stock > 0 && p.stock < 20;
          case StockFilter.available:
            return p.stock >= 20;
        }
      }).toList();
    });
  }

  int get _totalStock => _products.fold(0, (sum, p) => sum + p.stock);
  int get _outOfStockCount => _products.where((p) => p.stock <= 0).length;
  int get _lowStockCount =>
      _products.where((p) => p.stock > 0 && p.stock < 20).length;

  int _resolveProductId(Item item) {
    if (_productIdMap.containsKey(item.tyunit)) {
      return _productIdMap[item.tyunit]!;
    }
    // Fallback: ekstrak angka dari BV01 -> 1
    final digits = RegExp(r'\d+').firstMatch(item.tyunit)?.group(0);
    return int.tryParse(digits ?? '1') ?? 1;
  }

  Future<void> _updateStockApi({
    required Item item,
    required int newStock,
  }) async {
    final productId = _resolveProductId(item);

    // 1. Update /api/products/{id}
    final prodUrl =
        'https://laravel.fathurrzqn8n.web.id/api/products/$productId';
    final prodPayload = {
      'name': item.name,
      'price': item.price.toInt(),
      'stock': newStock,
      'stok': newStock,
      'qty': newStock,
    };

    // 2. Update /api/master-stocks/{TYUNIT}
    final msUrl =
        'https://laravel.fathurrzqn8n.web.id/api/master-stocks/${item.tyunit}';
    final msPayload = {
      'TYUNIT': item.tyunit,
      'NTYUNIT': item.name,
      'hjual': item.price.toInt(),
      'stock': newStock,
      'stok': newStock,
      'qty': newStock,
    };

    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    // Jalankan kedua update secara paralel
    final results = await Future.wait([
      http.put(Uri.parse(prodUrl), headers: headers, body: jsonEncode(prodPayload)),
      http.put(Uri.parse(msUrl), headers: headers, body: jsonEncode(msPayload)),
    ]);

    final prodRes = results[0];
    if (prodRes.statusCode != 200 && prodRes.statusCode != 201) {
      throw Exception('Gagal update stock di server (${prodRes.statusCode})');
    }
  }

  void _openStockModal(Item item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _StockInputSheet(
        item: item,
        onSave: (newStock) async {
          String? serverNotice;
          try {
            await _updateStockApi(item: item, newStock: newStock);
          } catch (e) {
            debugPrint("Update stock ke server gagal ($e), disimpan ke cache lokal...");
            serverNotice = 'Stok berhasil diperbarui di HP (Server sync tertunda)';
          }

          setState(() {
            final idx = _products.indexWhere((p) => p.tyunit == item.tyunit);
            if (idx != -1) {
              _products[idx] = Item(
                tyunit: item.tyunit,
                name: item.name,
                price: item.price,
                stock: newStock,
              );
            }
          });
          await OfflineSyncService.cacheProducts(_products);
          _applyFilter();

          if (serverNotice != null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(serverNotice),
                backgroundColor: AppColors.info,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        },
      ),
    );
  }

  void _openBulkStockDialog() {
    final TextEditingController bulkController =
        TextEditingController(text: '100');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.flash_on, color: AppColors.primary),
            SizedBox(width: 8),
            Text(
              'Isi Stok Cepat (Semua)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Setel jumlah stok awal untuk seluruh 13 produk Boneva sekaligus:',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: bulkController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Jumlah Stok per Produk',
                suffixText: 'pcs/unit',
                prefixIcon: Icon(Icons.inventory),
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
            onPressed: () async {
              final val = int.tryParse(bulkController.text.trim()) ?? 0;
              Navigator.pop(ctx);
              _performBulkUpdate(val);
            },
            child: const Text('Terapkan ke Semua'),
          ),
        ],
      ),
    );
  }

  Future<void> _performBulkUpdate(int stockValue) async {
    setState(() => _isLoading = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sedang memperbarui stok seluruh produk...'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      for (final item in _products) {
        await _updateStockApi(item: item, newStock: stockValue);
      }
      await _loadStockData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Berhasil mengisi stok $stockValue untuk seluruh produk!'),
          backgroundColor: AppColors.lunas,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal input stok massal: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Input & Manajemen Stok'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            tooltip: 'Input Cepat Semua Produk',
            onPressed: _products.isEmpty ? null : _openBulkStockDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Segarkan data',
            onPressed: _loadStockData,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadStockData,
        color: AppColors.primary,
        child: Column(
          children: [
            // RINGKASAN STOK HERO CARD
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenMargin,
                AppSpacing.md,
                AppSpacing.screenMargin,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // KPI Mini Cards
                  Row(
                    children: [
                      Expanded(
                        child: _kpiMiniCard(
                          label: 'Total Varian',
                          value: '${_products.length}',
                          icon: Icons.inventory_2_outlined,
                          color: AppColors.primary,
                          bgColor: AppColors.primaryLight,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _kpiMiniCard(
                          label: 'Total Stok',
                          value: '$_totalStock',
                          icon: Icons.layers_outlined,
                          color: AppColors.lunas,
                          bgColor: AppColors.lunasBg,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _kpiMiniCard(
                          label: 'Habis / Kritis',
                          value: '$_outOfStockCount',
                          icon: Icons.warning_amber_rounded,
                          color: _outOfStockCount > 0
                              ? AppColors.error
                              : AppColors.textSecondary,
                          bgColor: _outOfStockCount > 0
                              ? AppColors.errorBg
                              : AppColors.background,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Search Field
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Cari nama produk atau kode (BV01)...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => _searchCtrl.clear(),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // Quick Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _filterChip(
                          label: 'Semua (${_products.length})',
                          filter: StockFilter.all,
                        ),
                        const SizedBox(width: 6),
                        _filterChip(
                          label: 'Habis ($_outOfStockCount)',
                          filter: StockFilter.outOfStock,
                          isWarning: _outOfStockCount > 0,
                        ),
                        const SizedBox(width: 6),
                        _filterChip(
                          label: 'Menipis ($_lowStockCount)',
                          filter: StockFilter.lowStock,
                        ),
                        const SizedBox(width: 6),
                        _filterChip(
                          label:
                              'Tersedia (${_products.length - _outOfStockCount - _lowStockCount})',
                          filter: StockFilter.available,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // LIST PRODUK & STOK
            Expanded(
              child: _isLoading
                  ? const SkeletonList(count: 6)
                  : _errorMessage != null
                      ? _buildErrorView()
                      : _filteredProducts.isEmpty
                          ? EmptyState(
                              icon: Icons.inventory_outlined,
                              title: _searchCtrl.text.isNotEmpty
                                  ? 'Produk Tidak Ditemukan'
                                  : 'Belum Ada Data Master Stock',
                              subtitle: _searchCtrl.text.isNotEmpty
                                  ? 'Tidak ada produk yang cocok dengan "${_searchCtrl.text}"'
                                  : 'Tarik ke bawah untuk memuat ulang data produk.',
                              actionLabel: _searchCtrl.text.isNotEmpty
                                  ? 'Reset Pencarian'
                                  : 'Muat Ulang',
                              onAction: _searchCtrl.text.isNotEmpty
                                  ? () => _searchCtrl.clear()
                                  : _loadStockData,
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(
                                AppSpacing.screenMargin,
                              ),
                              itemCount: _filteredProducts.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: AppSpacing.cardGap),
                              itemBuilder: (context, index) {
                                final item = _filteredProducts[index];
                                return _buildProductStockCard(
                                  item: item,
                                  currencyFormat: currencyFormat,
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpiMiniCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const Spacer(),
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.9),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required StockFilter filter,
    bool isWarning = false,
  }) {
    final isSelected = _selectedFilter == filter;
    final activeBg = isWarning ? AppColors.errorBg : AppColors.primaryLight;
    final activeColor = isWarning ? AppColors.error : AppColors.primary;

    return ActionChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          color: isSelected ? activeColor : AppColors.textSecondary,
        ),
      ),
      backgroundColor: isSelected ? activeBg : AppColors.background,
      side: BorderSide(
        color: isSelected ? activeColor : AppColors.surfaceBorder,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.chipFull),
      ),
      onPressed: () {
        setState(() => _selectedFilter = filter);
        _applyFilter();
      },
    );
  }

  Widget _buildProductStockCard({
    required Item item,
    required NumberFormat currencyFormat,
  }) {
    final isOutOfStock = item.stock <= 0;
    final isLowStock = item.stock > 0 && item.stock < 20;

    final badgeColor = isOutOfStock
        ? AppColors.error
        : isLowStock
            ? AppColors.bon
            : AppColors.lunas;

    final badgeBg = isOutOfStock
        ? AppColors.errorBg
        : isLowStock
            ? AppColors.bonBg
            : AppColors.lunasBg;

    final statusText = isOutOfStock
        ? 'Habis (0)'
        : isLowStock
            ? 'Menipis (${item.stock})'
            : 'Tersedia (${item.stock})';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: isOutOfStock
              ? AppColors.error.withValues(alpha: 0.3)
              : AppColors.surfaceBorder,
        ),
        boxShadow: AppShadow.card,
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Icon / Code Tag
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  item.tyunit,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Title & Price
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      currencyFormat.format(item.price),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              // Stock Status Badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(AppRadius.chipFull),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: badgeColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: badgeColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),

          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.inventory_outlined,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Stok Aktif: ${item.stock} unit',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => _openStockModal(item),
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Input Stok'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  minimumSize: const Size(0, 36),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.chipFull),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            const Text(
              'Gagal Memuat Master Stock',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              '$_errorMessage',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadStockData,
              child: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom Sheet untuk Input / Edit Stok Produk
class _StockInputSheet extends StatefulWidget {
  final Item item;
  final Future<void> Function(int newStock) onSave;

  const _StockInputSheet({
    required this.item,
    required this.onSave,
  });

  @override
  State<_StockInputSheet> createState() => _StockInputSheetState();
}

class _StockInputSheetState extends State<_StockInputSheet> {
  // Mode: 0 = Tambah Stok (Stock In), 1 = Set Total Stok (Stock Opname)
  int _modeIndex = 0;
  final TextEditingController _inputCtrl = TextEditingController(text: '50');
  bool _isSaving = false;

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  int get _parsedInput => int.tryParse(_inputCtrl.text.trim()) ?? 0;

  int get _calculatedNewStock {
    if (_modeIndex == 0) {
      // Tambah stok
      return widget.item.stock + _parsedInput;
    } else {
      // Atur total
      return _parsedInput;
    }
  }

  void _addQuick(int delta) {
    final current = _parsedInput;
    final next = (current + delta).clamp(0, 999999);
    setState(() {
      _inputCtrl.text = next.toString();
    });
  }

  Future<void> _handleSave() async {
    final newStock = _calculatedNewStock;
    if (newStock < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Jumlah stok tidak boleh kurang dari 0'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await widget.onSave(newStock);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Stok ${widget.item.tyunit} (${widget.item.name}) berhasil diupdate menjadi $newStock unit!',
          ),
          backgroundColor: AppColors.lunas,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal update stok: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screenMargin,
        AppSpacing.lg,
        AppSpacing.screenMargin,
        MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.surfaceBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header: Produk Info
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  widget.item.tyunit,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.item.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Stok saat ini di sistem: ${widget.item.stock} unit',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // Segmented Switch Mode
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppRadius.input),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _modeIndex = 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _modeIndex == 0
                            ? AppColors.surface
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: _modeIndex == 0 ? AppShadow.card : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Tambah Stok (+)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: _modeIndex == 0
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: _modeIndex == 0
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _modeIndex = 1;
                      _inputCtrl.text = widget.item.stock.toString();
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _modeIndex == 1
                            ? AppColors.surface
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: _modeIndex == 1 ? AppShadow.card : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Set Total Stok',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: _modeIndex == 1
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: _modeIndex == 1
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // Input Quantity with Steppers
          Row(
            children: [
              IconButton.outlined(
                onPressed: () => _addQuick(-1),
                icon: const Icon(Icons.remove),
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: _modeIndex == 0
                        ? 'Jumlah Masuk (pcs)'
                        : 'Total Stok Fisik',
                    floatingLabelAlignment: FloatingLabelAlignment.center,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              IconButton.outlined(
                onPressed: () => _addQuick(1),
                icon: const Icon(Icons.add),
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Quick Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _quickChip('+10', () => _addQuick(10)),
                const SizedBox(width: 8),
                _quickChip('+25', () => _addQuick(25)),
                const SizedBox(width: 8),
                _quickChip('+50', () => _addQuick(50)),
                const SizedBox(width: 8),
                _quickChip('+100', () => _addQuick(100)),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // Calculation Preview Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppRadius.input),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Hasil Akhir Stok',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      _modeIndex == 0
                          ? '${widget.item.stock} + $_parsedInput'
                          : 'Stok Langsung Diubah',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                Text(
                  '$_calculatedNewStock unit',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // Save Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _handleSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Simpan Stok',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickChip(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
      backgroundColor: AppColors.primaryLight,
      side: const BorderSide(color: AppColors.primaryLight),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.chipFull),
      ),
      onPressed: onTap,
    );
  }
}
