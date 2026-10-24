# Kasir Kutacane v2 (Sales Kencana v2)

Aplikasi Point of Sale (POS) & Sales Force Automation berbasis Flutter untuk operasional penjualan, pencatatan transaksi, cetak struk termal Bluetooth (ESC/POS), dan manajemen laporan harian toko/distributor **Kencana Cahaya Amanah**.

---

## 🚀 Fitur Utama

- **Pencatatan Transaksi Cepat**: Pembuatan ID transaksi otomatis, integrasi stok produk dari server, dan dukungan skema bonus barang.
- **Failover Database Ganda**: Terkoneksi ke **Laravel REST API** sebagai server utama dan **Supabase PostgreSQL** sebagai backup otomatis saat offline/server down.
- **Pencetakan Struk Thermal Bluetooth**: Cetak nota kasir instan via printer termal Bluetooth (ESC/POS) baik per transaksi maupun cetak massal (*batch print*).
- **Faktur PDF Resmi & Berbagi ke WhatsApp**: Render faktur/struk A4 lengkap dengan stempel resmi usaha dan integrasi share sheet ke WhatsApp.
- **Laporan Harian & Analitik**: Rekapitulasi omzet harian, export laporan ke PDF A4 formal dan CSV.
- **Manajemen Arsip & Import File**: Import file CSV/Excel (`.xlsx`) transaksi historis dan arsip lokal.

---

## 📖 Dokumentasi Lengkap

Analisis mendalam mengenai arsitektur sistem, alur data (*data flow*), audit kode, temuan teknis, dan panduan lengkap dapat dilihat pada:
👉 **[DOKUMENTASI_SISTEM.md](file:///d:/aplikasi/newFlutter/kasir_kutacane_v2/DOKUMENTASI_SISTEM.md)**

---

## 🛠️ Cara Menjalankan

```bash
# Ambil dependensi
flutter pub get

# Jalankan aplikasi (hubungkan perangkat Android)
flutter run

# Build APK Release
flutter build apk --release
```

