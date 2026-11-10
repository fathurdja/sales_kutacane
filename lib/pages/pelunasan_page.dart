import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/config/api_config.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/models/user_model.dart';
import 'package:kasir_kutacane/pages/customer_report_page.dart';
import 'package:kasir_kutacane/pages/transactionDetail.dart';
import 'package:kasir_kutacane/services/auth_service.dart';
import 'package:kasir_kutacane/services/offline_sync_service.dart';
import 'package:kasir_kutacane/services/pelunasan_history_service.dart';
import 'package:kasir_kutacane/services/print.dart';
import 'package:kasir_kutacane/services/printerBluetooth.dart';
import 'package:kasir_kutacane/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Kelompok ringkasan BON per pelanggan untuk monitoring piutang total & cicilan sebagian
class CustomerBonGroup {
  final String customerName;
  final String alamat;
  final List<Transaction> transactions;
  final double totalOriginalBon;
  final double totalTerbayar;
  final double sisaBon;
  final List<PelunasanPayment> payments;
  final DateTime? lastPaymentDate;

  CustomerBonGroup({
    required this.customerName,
    required this.alamat,
    required this.transactions,
    required this.totalOriginalBon,
    required this.totalTerbayar,
    required this.sisaBon,
    required this.payments,
    this.lastPaymentDate,
  });
}

class PelunasanPage extends StatefulWidget {
  const PelunasanPage({super.key});

  @override
  State<PelunasanPage> createState() => _PelunasanPageState();
}

class _PelunasanPageState extends State<PelunasanPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();

  List<Transaction> _allTransactions = [];
  List<PelunasanPayment> _allPayments = [];
  bool _isLoading = true;
  String? _errorMessage;
  UserModel? _currentUser;

  bool get _isAdmin => _currentUser?.isUserAdmin ?? false;

  // Mode tampilan: 'CUSTOMER' = Per Pelanggan, 'NOTA' = Per Nota Transaksi
  String _pendingViewMode = 'CUSTOMER';

  // Mode riwayat lunas: 'NOTA' = Nota Lunas, 'PAYMENTS' = Riwayat Pembayaran/Cicilan
  String _historyViewMode = 'NOTA';

  // Filter tipe pembayaran: 'ALL', 'BON', 'QRIS'
  String _paymentFilter = 'ALL';

  // Filter tanggal: 'SEMUA', 'HARI_INI', 'MINGGU_INI', 'CUSTOM'
  String _dateFilterPreset = 'SEMUA';
  DateTime? _filterDate;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchCtrl.addListener(() => setState(() {}));
    _loadCurrentUser();
    fetchTransactions();
  }

  Future<void> _loadCurrentUser() async {
    final user = await AuthService.getCurrentUser();
    if (mounted) {
      setState(() => _currentUser = user);
      if (user != null && !user.isUserAdmin) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Menu Monitoring Pelunasan Bon hanya dapat diakses oleh Admin.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> fetchTransactions() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final payments = await PelunasanHistoryService.loadPaymentHistory();
      final token = await AuthService.getToken();
      final headers = {
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      final response = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/transaksi'), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final list = data.map((json) => Transaction.fromJson(json)).toList();

        // Sinkronkan dan lengkapi tanggal_pelunasan dari PelunasanHistoryService
        final historyMap = await PelunasanHistoryService.loadHistory();
        for (final t in list) {
          if (historyMap.containsKey(t.id_transaksi)) {
            final rec = historyMap[t.id_transaksi]!;
            if (t.status.toUpperCase() == 'BON') {
              t.status = 'BON LUNAS';
            }
            t.tanggalPelunasan = rec.tanggalPelunasan;
          } else if (t.status.toUpperCase() == 'LUNAS' && t.tanggalPelunasan == null) {
            t.tanggalPelunasan = t.date;
          }
        }

        // Gabungkan juga dengan transaksi offline lokal jika ada yang berstatus BON
        final pending = await OfflineSyncService.getPendingTransactions();
        for (final p in pending) {
          if (!list.any((t) => t.id_transaksi == p.id_transaksi)) {
            p.isOffline = true;
            list.insert(0, p);
          }
        }

        if (mounted) {
          setState(() {
            _allTransactions = list;
            _allPayments = payments;
            _isLoading = false;
          });
        }
      } else {
        throw Exception('Server mengembalikan kode status ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetch transaksi: $e, mencoba memuat dari offline/Supabase...');
      try {
        final payments = await PelunasanHistoryService.loadPaymentHistory();
        final supabase = Supabase.instance.client;
        final res = await supabase
            .from('transaksi')
            .select('*')
            .order('tanggal', ascending: false);

        final list = (res as List)
            .map((json) => Transaction.fromJson(json))
            .toList();

        final historyMap = await PelunasanHistoryService.loadHistory();
        for (final t in list) {
          if (historyMap.containsKey(t.id_transaksi)) {
            final rec = historyMap[t.id_transaksi]!;
            if (t.status.toUpperCase() == 'BON') {
              t.status = 'BON LUNAS';
            }
            t.tanggalPelunasan = rec.tanggalPelunasan;
          } else if (t.status.toUpperCase() == 'LUNAS' && t.tanggalPelunasan == null) {
            t.tanggalPelunasan = t.date;
          }
        }

        if (mounted) {
          setState(() {
            _allTransactions = list;
            _allPayments = payments;
            _isLoading = false;
            _errorMessage = 'Mode Cadangan Supabase: Menampilkan data tersinkron.';
          });
        }
      } catch (err) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Gagal memuat data transaksi: $e';
          });
        }
      }
    }
  }

  bool _matchesDateFilter(DateTime targetDate) {
    if (_dateFilterPreset == 'SEMUA') return true;

    final now = DateTime.now();
    if (_dateFilterPreset == 'HARI_INI') {
      return targetDate.year == now.year &&
          targetDate.month == now.month &&
          targetDate.day == now.day;
    } else if (_dateFilterPreset == 'MINGGU_INI') {
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      final startOfWeekDate = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
      return targetDate.isAfter(startOfWeekDate.subtract(const Duration(seconds: 1)));
    } else if (_dateFilterPreset == 'CUSTOM' && _filterDate != null) {
      return targetDate.year == _filterDate!.year &&
          targetDate.month == _filterDate!.month &&
          targetDate.day == _filterDate!.day;
    }
    return true;
  }

  Future<void> _selectCustomDateFilter() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Pilih Tanggal Transaksi / Pelunasan',
    );
    if (picked != null) {
      setState(() {
        _filterDate = picked;
        _dateFilterPreset = 'CUSTOM';
      });
    }
  }

  List<Transaction> get _pendingTransactions {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _allTransactions.where((t) {
      final isPending = t.isBon || t.isQris;
      if (!isPending) return false;

      // Filter jenis pembayaran
      if (_paymentFilter == 'BON' && !t.isBon) return false;
      if (_paymentFilter == 'QRIS' && !t.isQris) return false;

      // Filter tanggal nota dibuat
      if (!_matchesDateFilter(t.date)) return false;

      if (q.isEmpty) return true;
      return t.customerName.toLowerCase().contains(q) ||
          t.id_transaksi.toLowerCase().contains(q) ||
          t.alamat.toLowerCase().contains(q);
    }).toList();
  }

  List<Transaction> get _lunasTransactions {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _allTransactions.where((t) {
      final isLunas = t.isLunas || t.isBonLunas;
      if (!isLunas) return false;

      final effectiveDate = t.tanggalPelunasan ?? t.date;
      if (!_matchesDateFilter(effectiveDate)) return false;

      if (q.isEmpty) return true;
      return t.customerName.toLowerCase().contains(q) ||
          t.id_transaksi.toLowerCase().contains(q) ||
          t.alamat.toLowerCase().contains(q);
    }).toList();
  }

  /// Ringkasan BON per nama pelanggan (Akumulasi total tagihan & cicilan yang pernah disetor)
  List<CustomerBonGroup> get _customerBonGroups {
    final q = _searchCtrl.text.trim().toLowerCase();
    final Map<String, List<Transaction>> grouped = {};

    for (final t in _allTransactions) {
      if (!t.isBon) continue;
      if (!_matchesDateFilter(t.date)) continue;
      final key = t.customerName.trim().toLowerCase();
      if (key.isEmpty) continue;
      if (q.isNotEmpty &&
          !key.contains(q) &&
          !t.id_transaksi.toLowerCase().contains(q) &&
          !t.alamat.toLowerCase().contains(q)) {
        continue;
      }
      grouped.putIfAbsent(key, () => []).add(t);
    }

    final List<CustomerBonGroup> result = [];
    for (final entry in grouped.entries) {
      final txList = entry.value;
      final custName = txList.first.customerName;
      final alamat = txList.first.alamat;
      final totalBon = txList.fold(0.0, (sum, t) => sum + t.total);

      // Ambil pembayaran cicilan yang pernah dicatat untuk customer ini
      final custPayments = _allPayments
          .where((p) => p.customerName.trim().toLowerCase() == entry.key)
          .toList();
      final totalPaid = custPayments.fold(0.0, (sum, p) => sum + p.nominalBayar);
      final sisa = (totalBon - totalPaid).clamp(0.0, totalBon);

      if (sisa > 0) {
        result.add(CustomerBonGroup(
          customerName: custName,
          alamat: alamat,
          transactions: txList,
          totalOriginalBon: totalBon,
          totalTerbayar: totalPaid,
          sisaBon: sisa,
          payments: custPayments,
          lastPaymentDate: custPayments.isNotEmpty ? custPayments.first.tanggalPelunasan : null,
        ));
      }
    }

    // Urutkan dari sisa BON terbesar
    result.sort((a, b) => b.sisaBon.compareTo(a.sisaBon));
    return result;
  }

  double get _totalPiutangBon {
    final groups = _customerBonGroups;
    return groups.fold(0.0, (sum, g) => sum + g.sisaBon);
  }

  double get _totalPendingQris {
    return _allTransactions
        .where((t) => t.isQris)
        .fold(0.0, (sum, t) => sum + t.total);
  }

  double get _totalPendingAll => _totalPiutangBon + _totalPendingQris;

  // ===========================================================================
  // DIALOG PELUNASAN PER PELANGGAN (BISA LUNAS SEKALIGUS ATAU SEBAGIAN/CICIL)
  // ===========================================================================
  void _showPelunasanCustomerDialog(CustomerBonGroup group) {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hanya Admin yang dapat memproses pelunasan.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    DateTime selectedDate = DateTime.now();
    bool isFullPayment = true;
    bool isSubmitting = false;
    bool printReceipt = true;
    final nominalCtrl = TextEditingController(text: group.sisaBon.toInt().toString());
    final catatanCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final currencyFormat =
              NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
          final dateFormat = DateFormat('EEEE, dd MMMM yyyy', 'id_ID');

          double enteredAmount = double.tryParse(nominalCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;
          if (isFullPayment) enteredAmount = group.sisaBon;
          final double sisaPreview = (group.sisaBon - enteredAmount).clamp(0.0, group.totalOriginalBon);

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
            child: SingleChildScrollView(
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
                          color: AppColors.lunas.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.payments_rounded, color: AppColors.lunas, size: 26),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Pelunasan Piutang BON Pelanggan',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              'Pelanggan: ${group.customerName} (${group.transactions.length} Nota Aktif)',
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
                  const SizedBox(height: 14),
                  const Divider(),
                  const SizedBox(height: 10),

                  // Ringkasan Keuangan Pelanggan
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.bgSecondary,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total Tagihan BON:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                            Text(currencyFormat.format(group.totalOriginalBon), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        if (group.totalTerbayar > 0) ...[
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Sudah Pernah Dicicil:', style: TextStyle(fontSize: 12, color: AppColors.lunas)),
                              Text('+${currencyFormat.format(group.totalTerbayar)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.lunas)),
                            ],
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Sisa Piutang Saat Ini:', style: TextStyle(fontSize: 12, color: AppColors.bon, fontWeight: FontWeight.bold)),
                            Text(
                              currencyFormat.format(group.sisaBon),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.bon),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),
                  const Text('Pilih Opsi Pembayaran:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),

                  // Opsi 1: Lunaskan Sekaligus
                  RadioListTile<bool>(
                    value: true,
                    groupValue: isFullPayment,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    activeColor: AppColors.lunas,
                    title: const Text('Lunaskan Sekaligus (Bayar Penuh)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                    subtitle: Text('Membayar seluruh sisa tagihan (${currencyFormat.format(group.sisaBon)})'),
                    onChanged: (val) {
                      setModalState(() {
                        isFullPayment = true;
                        nominalCtrl.text = group.sisaBon.toInt().toString();
                      });
                    },
                  ),

                  // Opsi 2: Bayar Sebagian (Cicil)
                  RadioListTile<bool>(
                    value: false,
                    groupValue: isFullPayment,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    activeColor: AppColors.primary,
                    title: const Text('Bayar Sebagian Dulu (Cicil)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                    subtitle: const Text('Tentukan nominal cicilan yang disetor hari ini'),
                    onChanged: (val) {
                      setModalState(() {
                        isFullPayment = false;
                        if (enteredAmount >= group.sisaBon) {
                          nominalCtrl.text = (group.sisaBon > 50000 ? 50000 : group.sisaBon / 2).toInt().toString();
                        }
                      });
                    },
                  ),

                  if (!isFullPayment) ...[
                    const SizedBox(height: 6),
                    TextField(
                      controller: nominalCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Nominal Yang Dibayarkan (Rp)',
                        prefixText: 'Rp ',
                        hintText: 'Contoh: 50000',
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      onChanged: (_) => setModalState(() {}),
                    ),
                    const SizedBox(height: 8),
                    // Quick Chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          if (group.sisaBon > 20000)
                            ActionChip(
                              label: const Text('20 Rb'),
                              onPressed: () {
                                nominalCtrl.text = '20000';
                                setModalState(() {});
                              },
                            ),
                          const SizedBox(width: 6),
                          if (group.sisaBon > 50000)
                            ActionChip(
                              label: const Text('50 Rb'),
                              onPressed: () {
                                nominalCtrl.text = '50000';
                                setModalState(() {});
                              },
                            ),
                          const SizedBox(width: 6),
                          if (group.sisaBon > 100000)
                            ActionChip(
                              label: const Text('100 Rb'),
                              onPressed: () {
                                nominalCtrl.text = '100000';
                                setModalState(() {});
                              },
                            ),
                          const SizedBox(width: 6),
                          ActionChip(
                            label: const Text('50%'),
                            onPressed: () {
                              nominalCtrl.text = (group.sisaBon * 0.5).toInt().toString();
                              setModalState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Sisa Tagihan BON Nanti:', style: TextStyle(fontSize: 12, color: AppColors.primary)),
                          Text(
                            currencyFormat.format(sisaPreview),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 14),
                  const Text('Tanggal Pembayaran Diterima:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),

                  // Date Picker Card
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 30)),
                        helpText: 'Pilih Tanggal Pelunasan / Pembayaran Kas',
                      );
                      if (picked != null) {
                        setModalState(() {
                          selectedDate = picked;
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_month_outlined, color: AppColors.primary, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              dateFormat.format(selectedDate),
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          const Icon(Icons.edit_calendar_outlined, size: 18, color: AppColors.textSecondary),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),
                  TextField(
                    controller: catatanCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Catatan / Keterangan (Opsional)',
                      hintText: 'Contoh: Titip ke Sales 1, Transfer BCA, dll.',
                      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),

                  const SizedBox(height: 10),
                  CheckboxListTile(
                    value: printReceipt,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Cetak Struk Bukti Pembayaran via Bluetooth', style: TextStyle(fontSize: 12.5)),
                    onChanged: (val) => setModalState(() => printReceipt = val ?? true),
                  ),

                  const SizedBox(height: 16),

                  // Tombol Aksi
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Batal'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          icon: isSubmitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.check_circle_outline, size: 18),
                          label: Text(
                            isSubmitting
                                ? 'Menyimpan...'
                                : (isFullPayment
                                    ? 'Lunasi Penuh (${currencyFormat.format(group.sisaBon)})'
                                    : 'Simpan Pembayaran (${currencyFormat.format(enteredAmount)})'),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isFullPayment ? AppColors.lunas : AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: (isSubmitting || (!isFullPayment && enteredAmount <= 0))
                              ? null
                              : () async {
                                  setModalState(() => isSubmitting = true);
                                  await _executeCustomerPelunasan(
                                    group: group,
                                    payAmount: enteredAmount,
                                    tanggalPelunasan: selectedDate,
                                    catatan: catatanCtrl.text.trim(),
                                    printReceipt: printReceipt,
                                  );
                                  if (ctx.mounted) Navigator.pop(ctx);
                                },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ===========================================================================
  // EKSEKUSI PELUNASAN PER PELANGGAN (DENGAN TANGGAL & CETAK STRUK)
  // ===========================================================================
  Future<void> _executeCustomerPelunasan({
    required CustomerBonGroup group,
    required double payAmount,
    required DateTime tanggalPelunasan,
    String? catatan,
    bool printReceipt = true,
  }) async {
    if (!_isAdmin) return;
    final isLunasPenuh = payAmount >= group.sisaBon;
    final double sisaSetelahBayar = (group.sisaBon - payAmount).clamp(0.0, group.totalOriginalBon);

    try {
      // 1. Catat pembayaran di PelunasanHistoryService
      await PelunasanHistoryService.recordPayment(
        customerName: group.customerName,
        nominalBayar: payAmount,
        sisaBon: sisaSetelahBayar,
        tanggalPelunasan: tanggalPelunasan,
        catatan: catatan?.isNotEmpty == true ? catatan : (isLunasPenuh ? 'Pelunasan Penuh' : 'Pembayaran Sebagian (Cicilan)'),
        isLunas: isLunasPenuh,
      );

      // 2. Alokasikan pembayaran ke nota transaksi dari yang terlama ke terbaru
      final sortedTrx = List<Transaction>.from(group.transactions)
        ..sort((a, b) => a.date.compareTo(b.date));

      double remToAllocate = payAmount;
      for (final trx in sortedTrx) {
        if (remToAllocate <= 0) break;
        final paidTrx = await PelunasanHistoryService.getTotalPaidForTransaction(trx.id_transaksi);
        final sisaTrx = (trx.total - paidTrx).clamp(0.0, trx.total);
        if (sisaTrx <= 0) continue;

        if (remToAllocate >= sisaTrx) {
          // Nota ini tertutup penuh
          remToAllocate -= sisaTrx;
          await _executeSingleTrxSettlement(trx, tanggalPelunasan);
        } else {
          // Nota ini tertutup sebagian
          await PelunasanHistoryService.recordPayment(
            customerName: trx.customerName,
            idTransaksi: trx.id_transaksi,
            nominalBayar: remToAllocate,
            sisaBon: sisaTrx - remToAllocate,
            tanggalPelunasan: tanggalPelunasan,
            catatan: 'Cicilan untuk nota ${trx.id_transaksi}',
            isLunas: false,
          );
          remToAllocate = 0;
        }
      }

      // 3. Cetak struk jika dipilih
      if (printReceipt) {
        await _printPaymentReceipt(
          customerName: group.customerName,
          totalBonAwal: group.sisaBon,
          nominalBayar: payAmount,
          sisaBon: sisaSetelahBayar,
          tanggalPelunasan: tanggalPelunasan,
          catatan: catatan,
          isLunas: isLunasPenuh,
        );
      }

      await fetchTransactions();

      if (!mounted) return;
      final currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
      final dateStr = DateFormat('dd MMM yyyy').format(tanggalPelunasan);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isLunasPenuh
                ? 'Semua BON ${group.customerName} sebesar ${currencyFormat.format(payAmount)} BERHASIL DILUNASI pada $dateStr!'
                : 'Pembayaran sebagian ${currencyFormat.format(payAmount)} untuk ${group.customerName} berhasil disimpan pada $dateStr! Sisa BON: ${currencyFormat.format(sisaSetelahBayar)}',
          ),
          backgroundColor: isLunasPenuh ? AppColors.lunas : Colors.orange.shade800,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal memproses pembayaran: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  // ===========================================================================
  // DIALOG PELUNASAN PER NOTA TRANSAKSI TUNGGAL
  // ===========================================================================
  void _showPelunasanDialog(Transaction trx) {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hanya Admin yang dapat memproses pelunasan / verifikasi pembayaran.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    DateTime selectedDate = DateTime.now();
    bool isSubmitting = false;
    bool isFullPayment = true;
    bool printReceipt = true;
    final isQris = trx.isQris;
    final nominalCtrl = TextEditingController(text: trx.total.toInt().toString());
    final catatanCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final currencyFormat =
              NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
          final dateFormat = DateFormat('EEEE, dd MMMM yyyy', 'id_ID');

          double enteredAmount = double.tryParse(nominalCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;
          if (isFullPayment) enteredAmount = trx.total;
          final double sisaPreview = (trx.total - enteredAmount).clamp(0.0, trx.total);

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
            child: SingleChildScrollView(
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
                          color: (isQris ? AppColors.qris : AppColors.lunas).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isQris ? Icons.qr_code_2_rounded : Icons.task_alt_rounded,
                          color: isQris ? AppColors.qris : AppColors.lunas,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isQris ? 'Verifikasi Pembayaran QRIS' : 'Pelunasan Transaksi Bon',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              'Nomor Nota: ${trx.id_transaksi}',
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

                  // Detail Transaksi
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.bgSecondary,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Pelanggan:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                            Text(trx.customerName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(isQris ? 'Tanggal Transaksi:' : 'Tanggal Bon:', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                            Text(DateFormat('dd-MM-yyyy').format(trx.date), style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(isQris ? 'Nominal QRIS:' : 'Total Tagihan:', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                            Text(
                              currencyFormat.format(trx.total),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: isQris ? AppColors.qris : AppColors.bon,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  if (!isQris) ...[
                    const SizedBox(height: 12),
                    RadioListTile<bool>(
                      value: true,
                      groupValue: isFullPayment,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      activeColor: AppColors.lunas,
                      title: const Text('Lunaskan Sekaligus (Penuh)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text('Bayar lunas seluruh nota (${currencyFormat.format(trx.total)})'),
                      onChanged: (val) {
                        setModalState(() {
                          isFullPayment = true;
                          nominalCtrl.text = trx.total.toInt().toString();
                        });
                      },
                    ),
                    RadioListTile<bool>(
                      value: false,
                      groupValue: isFullPayment,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      activeColor: AppColors.primary,
                      title: const Text('Bayar Sebagian Dulu (Cicil)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      onChanged: (val) {
                        setModalState(() {
                          isFullPayment = false;
                        });
                      },
                    ),
                    if (!isFullPayment) ...[
                      const SizedBox(height: 4),
                      TextField(
                        controller: nominalCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Jumlah Cicilan (Rp)',
                          prefixText: 'Rp ',
                          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        onChanged: (_) => setModalState(() {}),
                      ),
                      const SizedBox(height: 6),
                      Text('Sisa tagihan nota nanti: ${currencyFormat.format(sisaPreview)}', style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.bold)),
                    ],
                  ],

                  const SizedBox(height: 14),
                  Text(
                    isQris ? 'Pilih Tanggal Verifikasi Masuk:' : 'Pilih Tanggal Pelunasan:',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),

                  // Date Picker Card
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 30)),
                        helpText: isQris ? 'Pilih Tanggal Verifikasi Dana' : 'Pilih Tanggal Pembayaran/Pelunasan',
                      );
                      if (picked != null) {
                        setModalState(() {
                          selectedDate = picked;
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: (isQris ? AppColors.qris : AppColors.primary).withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_month_outlined, color: isQris ? AppColors.qris : AppColors.primary, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              dateFormat.format(selectedDate),
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          const Icon(Icons.edit_calendar_outlined, size: 18, color: AppColors.textSecondary),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),
                  CheckboxListTile(
                    value: printReceipt,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Cetak Bukti ke Printer Bluetooth', style: TextStyle(fontSize: 12.5)),
                    onChanged: (val) => setModalState(() => printReceipt = val ?? true),
                  ),

                  const SizedBox(height: 20),

                  // Tombol Aksi
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Batal'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          icon: isSubmitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Icon(isQris ? Icons.verified_outlined : Icons.check_circle_outline, size: 18),
                          label: Text(isSubmitting
                              ? 'Memproses...'
                              : (isQris
                                  ? 'Verifikasi Lunas'
                                  : (isFullPayment ? 'Lunasi Sekarang' : 'Simpan Pembayaran'))),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isQris ? AppColors.qris : AppColors.lunas,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: (isSubmitting || (!isFullPayment && enteredAmount <= 0))
                              ? null
                              : () async {
                                  setModalState(() => isSubmitting = true);
                                  await _executePelunasan(
                                    trx: trx,
                                    tanggalPelunasan: selectedDate,
                                    payAmount: enteredAmount,
                                    isFullPayment: isFullPayment,
                                    catatan: catatanCtrl.text.trim(),
                                    printReceipt: printReceipt,
                                  );
                                  if (ctx.mounted) Navigator.pop(ctx);
                                },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _executePelunasan({
    required Transaction trx,
    required DateTime tanggalPelunasan,
    double? payAmount,
    bool isFullPayment = true,
    String? catatan,
    bool printReceipt = true,
  }) async {
    if (!_isAdmin) return;
    final wasQris = trx.isQris;
    final double actualPay = payAmount ?? trx.total;
    final bool isCleared = isFullPayment || actualPay >= trx.total;

    try {
      if (isCleared) {
        await _executeSingleTrxSettlement(trx, tanggalPelunasan);
      } else {
        // Catat cicilan sebagian
        await PelunasanHistoryService.recordPayment(
          customerName: trx.customerName,
          idTransaksi: trx.id_transaksi,
          nominalBayar: actualPay,
          sisaBon: trx.total - actualPay,
          tanggalPelunasan: tanggalPelunasan,
          catatan: catatan?.isNotEmpty == true ? catatan : 'Cicilan untuk nota ${trx.id_transaksi}',
          isLunas: false,
        );
      }

      // Cetak struk jika dipilih
      if (printReceipt) {
        await _printPaymentReceipt(
          customerName: trx.customerName,
          idTransaksi: trx.id_transaksi,
          totalBonAwal: trx.total,
          nominalBayar: actualPay,
          sisaBon: isCleared ? 0.0 : (trx.total - actualPay),
          tanggalPelunasan: tanggalPelunasan,
          catatan: catatan,
          isLunas: isCleared,
        );
      }

      if (isCleared) {
        _tabController.animateTo(1);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasQris
                ? 'Nota ${trx.id_transaksi} (${trx.customerName}) BERHASIL DIVERIFIKASI LUNAS!'
                : (isCleared
                    ? 'Nota ${trx.id_transaksi} (${trx.customerName}) BERHASIL DILUNASI!'
                    : 'Pembayaran sebagian untuk nota ${trx.id_transaksi} berhasil dicatat!'),
          ),
          backgroundColor: wasQris ? AppColors.qris : AppColors.lunas,
        ),
      );

      fetchTransactions();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal melakukan pelunasan: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _executeSingleTrxSettlement(Transaction trx, DateTime tanggalPelunasan) async {
    final formattedDate = DateFormat('yyyy-MM-dd').format(tanggalPelunasan);
    final wasQris = trx.isQris;
    final newStatus = wasQris ? 'LUNAS' : 'BON LUNAS';

    // 1. Simpan ke PelunasanHistoryService lokal HP
    await PelunasanHistoryService.recordSettlement(
      idTransaksi: trx.id_transaksi,
      customerName: trx.customerName,
      total: trx.total,
      tanggalPelunasan: tanggalPelunasan,
    );

    // Update state seketika
    setState(() {
      trx.status = newStatus;
      trx.tanggalPelunasan = tanggalPelunasan;
    });

    final token = await AuthService.getToken();
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    // 2. Update ke Backend API Utama
    final updateUrl = '${ApiConfig.baseUrl}/transaksi/${trx.id_transaksi}';
    try {
      await http.put(
        Uri.parse(updateUrl),
        headers: headers,
        body: jsonEncode({
          'status': newStatus,
          'tanggal_pelunasan': formattedDate,
        }),
      ).timeout(const Duration(seconds: 8));
    } catch (errApi) {
      debugPrint('Catatan API update status: $errApi');
    }

    // 3. Sinkronkan juga ke Supabase Backup
    try {
      final supabase = Supabase.instance.client;
      await supabase
          .from('transaksi')
          .update({
            'status': newStatus,
            'tanggal_pelunasan': formattedDate,
          })
          .eq('id_transaksi', trx.id_transaksi);
    } catch (errSupabase) {
      debugPrint('Catatan: Supabase update status: $errSupabase');
    }
  }

  Future<void> _printPaymentReceipt({
    required String customerName,
    String? idTransaksi,
    required double totalBonAwal,
    required double nominalBayar,
    required double sisaBon,
    required DateTime tanggalPelunasan,
    String? catatan,
    bool isLunas = false,
  }) async {
    try {
      final printed = await TestPrint().printPelunasanPayment(
        customerName: customerName,
        idTransaksi: idTransaksi,
        totalBonAwal: totalBonAwal,
        nominalBayar: nominalBayar,
        sisaBon: sisaBon,
        tanggalPelunasan: tanggalPelunasan,
        catatan: catatan,
        isLunas: isLunas,
      );

      if (printed) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Struk Pembayaran berhasil dicetak otomatis via Bluetooth!'),
            backgroundColor: AppColors.lunas,
          ),
        );
      }
    } catch (e) {
      debugPrint('Print error: $e');
    }
  }

  Future<void> _autoPrintReceipt(Transaction trx) async {
    try {
      final printed = await TestPrint().printTransaction(trx);
      if (printed) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Struk Pelunasan berhasil dicetak otomatis!'),
            backgroundColor: AppColors.lunas,
          ),
        );
      } else {
        if (!mounted) return;
        final shouldOpenPrinter = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.print_outlined, color: AppColors.primary),
                SizedBox(width: 8),
                Text('Cetak Struk Pelunasan'),
              ],
            ),
            content: Text(
              'Nota ${trx.id_transaksi} (${trx.customerName}) telah lunas.\n\n'
              'Printer Bluetooth belum tersambung. Ingin menyambungkan printer sekarang untuk mencetak struk?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Nanti Saja'),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.bluetooth_connected, size: 18),
                label: const Text('Buka Pengaturan Printer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        );

        if (shouldOpenPrinter == true && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => Printbluetooth.fromTransaction(transaction: trx),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error auto print receipt: $e');
    }
  }

  // ===========================================================================
  // BOTTOM SHEET RIWAYAT PEMBAYARAN / CICILAN PELANGGAN
  // ===========================================================================
  void _showPaymentHistorySheet(String customerName) async {
    final payments = await PelunasanHistoryService.getPaymentsForCustomer(customerName);
    if (!mounted) return;

    final currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final dateFormat = DateFormat('EEEE, dd MMM yyyy', 'id_ID');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        padding: const EdgeInsets.all(AppSpacing.screenMargin),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.history_rounded, color: AppColors.primary, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Riwayat Pembayaran BON',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text('Pelanggan: $customerName', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            Expanded(
              child: payments.isEmpty
                  ? const Center(
                      child: Text('Belum ada log pembayaran cicilan tercatat.', style: TextStyle(color: AppColors.textSecondary)),
                    )
                  : ListView.separated(
                      itemCount: payments.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final p = payments[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: (p.isLunas ? AppColors.lunas : AppColors.primary).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  p.isLunas ? Icons.check_circle_outline : Icons.payments_outlined,
                                  color: p.isLunas ? AppColors.lunas : AppColors.primary,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      dateFormat.format(p.tanggalPelunasan),
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      '${p.isLunas ? 'Lunas Penuh' : 'Cicilan'} • Sisa BON: ${currencyFormat.format(p.sisaBon)}',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: p.isLunas ? AppColors.lunas : AppColors.textSecondary,
                                        fontWeight: p.isLunas ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                    if (p.catatan != null && p.catatan!.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text('Ket: ${p.catatan}', style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
                                    ],
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '+${currencyFormat.format(p.nominalBayar)}',
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.lunas),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.print_outlined, size: 18, color: AppColors.primary),
                                    tooltip: 'Cetak Bukti',
                                    onPressed: () {
                                      _printPaymentReceipt(
                                        customerName: p.customerName,
                                        idTransaksi: p.idTransaksi,
                                        totalBonAwal: p.nominalBayar + p.sisaBon,
                                        nominalBayar: p.nominalBayar,
                                        sisaBon: p.sisaBon,
                                        tanggalPelunasan: p.tanggalPelunasan,
                                        catatan: p.catatan,
                                        isLunas: p.isLunas,
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Monitoring Pelunasan Bon'),
            Text(
              'Kelola Piutang, Cicilan & Catat Tanggal Pelunasan',
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
            icon: const Icon(Icons.people_alt_outlined, color: Colors.purple),
            tooltip: 'Laporan Bon Pelanggan',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CustomerReportPage()),
              ).then((_) => fetchTransactions());
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Segarkan',
            onPressed: fetchTransactions,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          tabs: [
            Tab(
              icon: const Icon(Icons.pending_actions_outlined, size: 20),
              text: 'Menunggu (${_pendingTransactions.length})',
            ),
            Tab(
              icon: const Icon(Icons.history_outlined, size: 20),
              text: 'Riwayat Lunas (${_lunasTransactions.length})',
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Error / Info Bar
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

                // Search Box
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.screenMargin, AppSpacing.screenMargin, AppSpacing.screenMargin, 8),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Cari nama pelanggan atau No. Nota...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => _searchCtrl.clear(),
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),

                // Filter Tipe & Tanggal
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMargin),
                    child: Row(
                      children: [
                        // Filter Jenis Pembayaran
                        ChoiceChip(
                          label: const Text('Semua'),
                          selected: _paymentFilter == 'ALL',
                          onSelected: (_) => setState(() => _paymentFilter = 'ALL'),
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: Text('BON (${_allTransactions.where((t) => t.isBon).length})'),
                          selected: _paymentFilter == 'BON',
                          selectedColor: AppColors.bon.withOpacity(0.22),
                          onSelected: (_) => setState(() => _paymentFilter = 'BON'),
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: Text('QRIS (${_allTransactions.where((t) => t.isQris).length})'),
                          selected: _paymentFilter == 'QRIS',
                          selectedColor: AppColors.qris.withOpacity(0.22),
                          onSelected: (_) => setState(() => _paymentFilter = 'QRIS'),
                        ),
                        const SizedBox(width: 10),
                        Container(width: 1, height: 24, color: Colors.grey.shade300),
                        const SizedBox(width: 10),
                        // Filter Tanggal
                        ChoiceChip(
                          label: const Text('Semua Tanggal'),
                          selected: _dateFilterPreset == 'SEMUA',
                          onSelected: (_) => setState(() {
                            _dateFilterPreset = 'SEMUA';
                            _filterDate = null;
                          }),
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: const Text('Hari Ini'),
                          selected: _dateFilterPreset == 'HARI_INI',
                          onSelected: (_) => setState(() {
                            _dateFilterPreset = 'HARI_INI';
                            _filterDate = null;
                          }),
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: const Text('Minggu Ini'),
                          selected: _dateFilterPreset == 'MINGGU_INI',
                          onSelected: (_) => setState(() {
                            _dateFilterPreset = 'MINGGU_INI';
                            _filterDate = null;
                          }),
                        ),
                        const SizedBox(width: 6),
                        ActionChip(
                          avatar: Icon(
                            _dateFilterPreset == 'CUSTOM' ? Icons.check : Icons.calendar_month_outlined,
                            size: 15,
                            color: _dateFilterPreset == 'CUSTOM' ? AppColors.primary : AppColors.textSecondary,
                          ),
                          label: Text(
                            _dateFilterPreset == 'CUSTOM' && _filterDate != null
                                ? DateFormat('dd MMM').format(_filterDate!)
                                : 'Pilih Tanggal',
                            style: TextStyle(
                              color: _dateFilterPreset == 'CUSTOM' ? AppColors.primary : AppColors.textPrimary,
                              fontWeight: _dateFilterPreset == 'CUSTOM' ? FontWeight.w700 : FontWeight.normal,
                              fontSize: 12,
                            ),
                          ),
                          onPressed: _selectCustomDateFilter,
                        ),
                      ],
                    ),
                  ),
                ),

                // Banner Total Piutang Bon & QRIS
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMargin),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE65100), Color(0xFFEF6C00)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    boxShadow: AppShadow.card,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Total Sisa Piutang Berjalan',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                currencyFormat.format(_totalPendingAll),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Sisa BON: ${currencyFormat.format(_totalPiutangBon)} • QRIS: ${currencyFormat.format(_totalPendingQris)}',
                              style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '${_pendingTransactions.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Text(
                              'Nota',
                              style: TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // Konten Tab
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildBonList(currencyFormat),
                      _buildLunasList(currencyFormat),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ===========================================================================
  // TAB MENUNGGU (SUPPORT VIEW PER PELANGGAN & PER NOTA)
  // ===========================================================================
  Widget _buildBonList(NumberFormat currencyFormat) {
    final groups = _customerBonGroups;
    final notaList = _pendingTransactions;

    return Column(
      children: [
        // Mode Selector: Per Pelanggan vs Per Nota
        Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMargin, vertical: 4),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _pendingViewMode = 'CUSTOMER'),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                      color: _pendingViewMode == 'CUSTOMER' ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: _pendingViewMode == 'CUSTOMER'
                          ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4)]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.people_alt_outlined,
                          size: 15,
                          color: _pendingViewMode == 'CUSTOMER' ? AppColors.primary : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Per Pelanggan (${groups.length})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: _pendingViewMode == 'CUSTOMER' ? FontWeight.w700 : FontWeight.w500,
                            color: _pendingViewMode == 'CUSTOMER' ? AppColors.primary : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _pendingViewMode = 'NOTA'),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                      color: _pendingViewMode == 'NOTA' ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: _pendingViewMode == 'NOTA'
                          ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4)]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 15,
                          color: _pendingViewMode == 'NOTA' ? AppColors.primary : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Per Nota (${notaList.length})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: _pendingViewMode == 'NOTA' ? FontWeight.w700 : FontWeight.w500,
                            color: _pendingViewMode == 'NOTA' ? AppColors.primary : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: _pendingViewMode == 'CUSTOMER'
              ? _buildCustomerGroupList(groups, currencyFormat)
              : _buildNotaList(notaList, currencyFormat),
        ),
      ],
    );
  }

  // Sub-list 1: Daftar BON Per Pelanggan
  Widget _buildCustomerGroupList(List<CustomerBonGroup> groups, NumberFormat currencyFormat) {
    if (groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 54, color: Colors.green.shade400),
            const SizedBox(height: 12),
            const Text(
              'Tidak ada pelanggan dengan BON aktif!',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Semua piutang pelanggan telah lunas.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: fetchTransactions,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.screenMargin),
        itemCount: groups.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (ctx, idx) => _buildCustomerBonCard(groups[idx], currencyFormat),
      ),
    );
  }

  Widget _buildCustomerBonCard(CustomerBonGroup g, NumberFormat currencyFormat) {
    final dateFormat = DateFormat('dd MMM yyyy');
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.bon.withOpacity(0.12),
                  child: const Icon(Icons.storefront_rounded, color: AppColors.bon),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        g.customerName,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        g.alamat.isNotEmpty ? g.alamat : 'Gorontalo',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.bonBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.bon.withOpacity(0.3)),
                  ),
                  child: Text(
                    '${g.transactions.length} NOTA BON',
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.bon),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.bgSecondary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total BON Awal', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      Text(currencyFormat.format(g.totalOriginalBon), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  if (g.totalTerbayar > 0) ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text('Sudah Dicicil', style: TextStyle(fontSize: 11, color: AppColors.lunas)),
                        Text('+${currencyFormat.format(g.totalTerbayar)}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.lunas)),
                      ],
                    ),
                  ],
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Sisa Tagihan BON', style: TextStyle(fontSize: 11, color: AppColors.bon, fontWeight: FontWeight.bold)),
                      Text(currencyFormat.format(g.sisaBon), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.bon)),
                    ],
                  ),
                ],
              ),
            ),
            if (g.lastPaymentDate != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.history_rounded, size: 13, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Pembayaran terakhir: ${dateFormat.format(g.lastPaymentDate!)}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ],
            const Divider(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (g.payments.isNotEmpty)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.receipt_long, size: 14),
                    label: Text('Riwayat (${g.payments.length})', style: const TextStyle(fontSize: 11.5)),
                    onPressed: () => _showPaymentHistorySheet(g.customerName),
                  )
                else
                  Text('${g.transactions.length} Nota Aktif', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                if (_isAdmin)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.lunas,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.payments_outlined, size: 16),
                    label: const Text('Bayar / Lunasi', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                    onPressed: () => _showPelunasanCustomerDialog(g),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Sub-list 2: Daftar Per Nota Transaksi
  Widget _buildNotaList(List<Transaction> list, NumberFormat currencyFormat) {
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 54, color: Colors.green.shade400),
            const SizedBox(height: 12),
            const Text(
              'Tidak ada transaksi yang tertunda!',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Semua piutang & QRIS telah terverifikasi lunas atau belum ada nota.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: fetchTransactions,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.screenMargin),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (ctx, idx) {
          final trx = list[idx];
          return Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: trx.isQris ? AppColors.qrisBg : AppColors.bonBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: (trx.isQris ? AppColors.qris : AppColors.bon).withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          trx.isQris ? 'MENUNGGU VERIFIKASI (QRIS)' : 'BELUM LUNAS (BON)',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: trx.isQris ? AppColors.qris : AppColors.bon,
                          ),
                        ),
                      ),
                      Text(
                        dateFormat.format(trx.date),
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    trx.customerName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (trx.alamat.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      trx.alamat,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    'No. Nota: ${trx.id_transaksi}',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.primary, fontWeight: FontWeight.w600),
                  ),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            trx.isQris ? 'Nominal QRIS' : 'Total Piutang',
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                          Text(
                            currencyFormat.format(trx.total),
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: trx.isQris ? AppColors.qris : AppColors.bon,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TransactionDetailPage(transaction: trx),
                                ),
                              );
                            },
                            child: const Text('Detail', style: TextStyle(fontSize: 12)),
                          ),
                          const SizedBox(width: 8),
                          if (_isAdmin)
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: trx.isQris ? AppColors.qris : AppColors.lunas,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: Icon(
                                trx.isQris ? Icons.verified_outlined : Icons.check_circle_outline,
                                size: 16,
                              ),
                              label: Text(
                                trx.isQris ? 'Verifikasi' : 'Lunasi',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                              onPressed: () => _showPelunasanDialog(trx),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ===========================================================================
  // TAB RIWAYAT LUNAS (NOTA LUNAS & LOG PEMBAYARAN CICILAN)
  // ===========================================================================
  Widget _buildLunasList(NumberFormat currencyFormat) {
    return Column(
      children: [
        // Mode Selector: Nota Lunas vs Log Riwayat Pembayaran/Cicilan
        Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMargin, vertical: 4),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _historyViewMode = 'NOTA'),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                      color: _historyViewMode == 'NOTA' ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: _historyViewMode == 'NOTA'
                          ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4)]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 15,
                          color: _historyViewMode == 'NOTA' ? AppColors.primary : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Nota Lunas (${_lunasTransactions.length})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: _historyViewMode == 'NOTA' ? FontWeight.w700 : FontWeight.w500,
                            color: _historyViewMode == 'NOTA' ? AppColors.primary : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _historyViewMode = 'PAYMENTS'),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                      color: _historyViewMode == 'PAYMENTS' ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: _historyViewMode == 'PAYMENTS'
                          ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4)]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.payments_outlined,
                          size: 15,
                          color: _historyViewMode == 'PAYMENTS' ? AppColors.primary : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Log Pembayaran (${_allPayments.length})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: _historyViewMode == 'PAYMENTS' ? FontWeight.w700 : FontWeight.w500,
                            color: _historyViewMode == 'PAYMENTS' ? AppColors.primary : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: _historyViewMode == 'NOTA'
              ? _buildLunasNotaList(currencyFormat)
              : _buildAllPaymentsLogList(currencyFormat),
        ),
      ],
    );
  }

  Widget _buildLunasNotaList(NumberFormat currencyFormat) {
    final list = _lunasTransactions;
    final dateFormat = DateFormat('dd MMM yyyy');

    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_outlined, size: 54, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'Belum ada riwayat pelunasan.',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              _dateFilterPreset != 'SEMUA' || _searchCtrl.text.isNotEmpty
                  ? 'Tidak ada transaksi lunas yang cocok dengan filter tanggal/pencarian.'
                  : 'Transaksi yang telah dilunasi akan muncul di sini.',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: fetchTransactions,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.screenMargin),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (ctx, idx) {
          final trx = list[idx];
          return Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.lunasBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.lunas.withOpacity(0.3)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_outline, size: 12, color: AppColors.lunas),
                            SizedBox(width: 4),
                            Text(
                              'NOTA LUNAS',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.lunas,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (trx.tanggalPelunasan != null)
                        Text(
                          'Lunas: ${dateFormat.format(trx.tanggalPelunasan!)}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.lunas,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    trx.customerName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (trx.alamat.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      trx.alamat,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    'No. Nota: ${trx.id_transaksi}',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.primary, fontWeight: FontWeight.w600),
                  ),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Total Pembayaran', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                          Text(
                            currencyFormat.format(trx.total),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: AppColors.lunas,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TransactionDetailPage(transaction: trx),
                                ),
                              );
                            },
                            child: const Text('Detail', style: TextStyle(fontSize: 12)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.print, size: 16),
                            label: const Text('Cetak Struk', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            onPressed: () => _autoPrintReceipt(trx),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAllPaymentsLogList(NumberFormat currencyFormat) {
    final payments = _allPayments;

    if (payments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 54, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'Belum ada riwayat transaksi pembayaran/cicilan.',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: fetchTransactions,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.screenMargin),
        itemCount: payments.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (ctx, idx) {
          final p = payments[idx];
          return Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (p.isLunas ? AppColors.lunas : AppColors.primary).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          p.isLunas ? 'LUNAS PENUH' : 'PEMBAYARAN SEBAGIAN (CICIL)',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: p.isLunas ? AppColors.lunas : AppColors.primary,
                          ),
                        ),
                      ),
                      Text(
                        DateFormat('dd-MM-yyyy').format(p.tanggalPelunasan),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    p.customerName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  if (p.idTransaksi != null) ...[
                    const SizedBox(height: 2),
                    Text('Nota: ${p.idTransaksi}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                  if (p.catatan != null && p.catatan!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text('Catatan: ${p.catatan}', style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
                  ],
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Sisa BON Setelah Bayar', style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
                          Text(currencyFormat.format(p.sisaBon), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      Row(
                        children: [
                          Text(
                            '+${currencyFormat.format(p.nominalBayar)}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.lunas),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.print_outlined, size: 18, color: AppColors.primary),
                            tooltip: 'Cetak Bukti Pembayaran',
                            onPressed: () {
                              _printPaymentReceipt(
                                customerName: p.customerName,
                                idTransaksi: p.idTransaksi,
                                totalBonAwal: p.nominalBayar + p.sisaBon,
                                nominalBayar: p.nominalBayar,
                                sisaBon: p.sisaBon,
                                tanggalPelunasan: p.tanggalPelunasan,
                                catatan: p.catatan,
                                isLunas: p.isLunas,
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
