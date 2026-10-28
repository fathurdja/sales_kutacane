class ApiConfig {
  /// Base URL untuk Development API-v2 (Database: sql_dashboardlo_v2)
  /// Terisolasi dari database production sql_dashboardlo_com
  static const String baseUrl = 'https://laravel.fathurrzqn8n.web.id/api-v2';

  // Auth endpoints
  static Uri get loginUri => Uri.parse('$baseUrl/login');
  static Uri get logoutUri => Uri.parse('$baseUrl/logout');
  static Uri get meUri => Uri.parse('$baseUrl/me');
  static Uri get usersUri => Uri.parse('$baseUrl/users');

  // Products & Stocks endpoints
  static Uri get productsUri => Uri.parse('$baseUrl/products');
  static Uri get masterStocksUri => Uri.parse('$baseUrl/master-stocks');
  static Uri masterStockDetailUri(String tyunit) => Uri.parse('$baseUrl/master-stocks/$tyunit');
  static Uri get stockAwalUri => Uri.parse('$baseUrl/stock-awal');
  static Uri get stockTerjualUri => Uri.parse('$baseUrl/stock-terjual');
  static Uri get stockSummaryUri => Uri.parse('$baseUrl/stock-summary');
  static Uri get stockGroupsUri => Uri.parse('$baseUrl/stock-groups');
  static Uri get updateStockUri => Uri.parse('$baseUrl/update-stock');

  // Transaksi endpoints
  static Uri get transaksiUri => Uri.parse('$baseUrl/transaksi');
  static Uri transaksiDetailUri(String id) => Uri.parse('$baseUrl/transaksi/$id');

  // Customers (Pelanggan) endpoints
  static Uri get customersUri => Uri.parse('$baseUrl/customers');
  static Uri customerDetailUri(int id) => Uri.parse('$baseUrl/customers/$id');
}
