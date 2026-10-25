import 'package:flutter/material.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/pages/dailyreport.dart';
import 'package:kasir_kutacane/pages/home_page.dart';
import 'package:kasir_kutacane/pages/more_page.dart';
import 'package:kasir_kutacane/pages/transactionInput.dart';
import 'package:kasir_kutacane/pages/transactionlistBackup.dart';
import 'package:kasir_kutacane/pages/login_page.dart';
import 'package:kasir_kutacane/services/auth_service.dart';
import 'package:kasir_kutacane/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null);
  await Supabase.initialize(
    url: 'https://louzejtmywrwwdsxkuqb.supabase.co',
    anonKey: 'sb_publishable_UuumrgOaVGxuhGUcII3R3Q_SJzr7wY0',
  );
  await AuthService.init();
  runApp(const MyApp());
}

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Sales Kencana v2',
      theme: AppTheme.lightTheme,
      home: AuthService.currentUser != null
          ? const MainNavigationScreen()
          : const LoginPage(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;
  final GlobalKey<HomePageState> _homeKey = GlobalKey<HomePageState>();
  final GlobalKey<TransactionListPageBackupState> _transactionListKey =
      GlobalKey<TransactionListPageBackupState>();

  void _changeTab(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  // Callback untuk menerima transaksi dari input page
  void _addTransaction(Transaction transaction) {
    // Navigasi kembali ke tab Transaksi (index 1) setelah simpan
    setState(() {
      _selectedIndex = 1;
    });
    _homeKey.currentState?.fetchTodayTransactions();
    _transactionListKey.currentState?.fetchTransactions();
  }

  // Buka halaman Input Nota Baru
  Future<void> _openNewTransaction() async {
    final newTrx = await Navigator.of(context).push<Transaction>(
      MaterialPageRoute(
        builder: (_) => TransactionInputPage(
          onSave: _addTransaction,
          onNavigateTab: _changeTab,
        ),
      ),
    );

    _homeKey.currentState?.fetchTodayTransactions();
    _transactionListKey.currentState?.fetchTransactions();

    if (newTrx != null) {
      _addTransaction(newTrx);
    }
  }

  @override
  Widget build(BuildContext context) {
    // List halaman yang ditampilkan — sesuai Design Brief Section 7
    final List<Widget> pages = [
      HomePage(key: _homeKey, onCreateNota: _openNewTransaction),
      TransactionListPageBackup(
        key: _transactionListKey,
        onCreateNota: _openNewTransaction,
      ),
      const SizedBox(), // placeholder untuk FAB tengah
      DailyReportDetailPage(selectedDate: DateTime.now()),
      const MorePage(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex == 2 ? 0 : _selectedIndex,
        children: pages,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openNewTransaction,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(
                icon: Icons.home_outlined,
                activeIcon: Icons.home,
                label: 'Beranda',
                index: 0,
              ),
              _navItem(
                icon: Icons.receipt_long_outlined,
                activeIcon: Icons.receipt_long,
                label: 'Transaksi',
                index: 1,
              ),
              // Spasi untuk FAB
              const SizedBox(width: 56),
              _navItem(
                icon: Icons.bar_chart_outlined,
                activeIcon: Icons.bar_chart,
                label: 'Laporan',
                index: 3,
              ),
              _navItem(
                icon: Icons.more_horiz_outlined,
                activeIcon: Icons.more_horiz,
                label: 'Lainnya',
                index: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int index,
  }) {
    final isActive = _selectedIndex == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _changeTab(index),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                isActive ? activeIcon : icon,
                key: ValueKey('$index-$isActive'),
                size: 24,
                color:
                    isActive ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color:
                    isActive ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
