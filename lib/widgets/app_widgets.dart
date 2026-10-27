import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kasir_kutacane/models/transaction.dart';
import 'package:kasir_kutacane/theme/app_theme.dart';

typedef EmptyStateWidget = EmptyState;

/// Chip status pembayaran (LUNAS / BON) dan mode cadangan.
/// Selalu menampilkan ikon + teks sesuai prinsip aksesibilitas.
class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final isLunas = status.toUpperCase() == 'LUNAS';
    final isQris = status.toUpperCase() == 'QRIS';
    final isCadangan = status.toUpperCase() == 'CADANGAN';

    final Color bg;
    final Color fg;
    final IconData icon;

    if (isCadangan) {
      bg = AppColors.backupBg;
      fg = AppColors.backup;
      icon = Icons.cloud_outlined;
    } else if (isLunas) {
      bg = AppColors.lunasBg;
      fg = AppColors.lunas;
      icon = Icons.check_circle_outline;
    } else if (isQris) {
      bg = const Color(0xFFE7F5FF);
      fg = const Color(0xFF1971C2);
      icon = Icons.qr_code_2_rounded;
    } else {
      bg = AppColors.bonBg;
      fg = AppColors.bon;
      icon = Icons.schedule;
    }

    final displayText = isCadangan
        ? 'CADANGAN'
        : (isLunas
            ? 'NOTA LUNAS'
            : (isQris ? 'NOTA QRIS' : 'NOTA BON'));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.chipFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            displayText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: fg,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kartu ringkasan omzet dengan gradient — hanya digunakan di Beranda & Laporan.
class OmzetSummaryCard extends StatelessWidget {
  final double totalOmzet;
  final int jumlahNota;
  final int jumlahBon;
  final String formattedOmzet;

  const OmzetSummaryCard({
    super.key,
    required this.totalOmzet,
    required this.jumlahNota,
    required this.jumlahBon,
    required this.formattedOmzet,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: AppColors.omzetGradient,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadow.elevated,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up, color: Colors.white70, size: 18),
              const SizedBox(width: 6),
              Text(
                'Omzet Hari Ini',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              formattedOmzet,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _miniStat(Icons.receipt_long, '$jumlahNota Nota'),
              const SizedBox(width: 20),
              _miniStat(Icons.schedule, '$jumlahBon BON'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 16),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Kartu transaksi untuk daftar (menampilkan info penting secara ringkas).
class TransactionCard extends StatelessWidget {
  final Transaction? transaction;
  final String? idTransaksi;
  final String? customerName;
  final String? alamat;
  final DateTime? date;
  final double? total;
  final String? status;
  final String? formattedTotal;
  final String? formattedDate;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  final bool? isOffline;

  const TransactionCard({
    super.key,
    this.transaction,
    this.idTransaksi,
    this.customerName,
    this.alamat,
    this.date,
    this.total,
    this.status,
    this.isOffline,
    this.formattedTotal,
    this.formattedDate,
    this.onTap,
    this.onLongPress,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ');
    final effectiveCustomer = transaction?.customerName ?? customerName ?? '-';
    final effectiveId = transaction?.id_transaksi ?? idTransaksi ?? '-';
    final effectiveDate = transaction?.date ?? date ?? DateTime.now();
    final effectiveStatus = transaction?.status ?? status ?? '-';
    final effectiveAlamat = transaction?.alamat ?? alamat ?? '';
    final effectiveIsOffline =
        isOffline ?? transaction?.isOffline ?? false;
    final effectiveTotalStr =
        formattedTotal ?? currencyFormat.format(transaction?.total ?? total ?? 0);
    final effectiveDateStr =
        formattedDate ?? DateFormat('dd MMM yyyy').format(effectiveDate);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: effectiveIsOffline
                ? Colors.amber.shade300
                : AppColors.surfaceBorder,
          ),
          boxShadow: AppShadow.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    effectiveCustomer,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (effectiveIsOffline) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      border: Border.all(color: Colors.amber.shade300),
                      borderRadius: BorderRadius.circular(AppRadius.chipFull),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off_rounded,
                            size: 12, color: Colors.amber.shade800),
                        const SizedBox(width: 4),
                        Text(
                          'OFFLINE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                StatusChip(status: effectiveStatus),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.tag, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    effectiveId,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (transaction?.userName != null && transaction!.userName!.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person_outline, size: 11, color: AppColors.primary),
                        const SizedBox(width: 3),
                        Text(
                          transaction!.userName!,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                const Icon(Icons.calendar_today_outlined,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  effectiveDateStr,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (effectiveAlamat.isNotEmpty) ...[
                  const Icon(Icons.location_on_outlined,
                      size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      effectiveAlamat,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ] else
                  const Spacer(),
                Text(
                  effectiveTotalStr,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            if (onEdit != null || onDelete != null) ...[
              const SizedBox(height: 8),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onEdit != null)
                    TextButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                      ),
                    ),
                  if (onDelete != null)
                    TextButton.icon(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Hapus'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Kondisi kosong (empty state) — teks + satu aksi relevan.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Skeleton loading shimmer untuk list.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _shimmerBox(width: 140, height: 16),
              const Spacer(),
              _shimmerBox(width: 70, height: 24, radius: AppRadius.chipFull),
            ],
          ),
          const SizedBox(height: 12),
          _shimmerBox(width: 200, height: 12),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _shimmerBox(width: 120, height: 12),
              _shimmerBox(width: 100, height: 20),
            ],
          ),
        ],
      ),
    );
  }

  Widget _shimmerBox(
      {required double width, required double height, double radius = 8}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceBorder.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Skeleton loading list (menampilkan beberapa SkeletonCard).
class SkeletonList extends StatelessWidget {
  final int count;
  const SkeletonList({super.key, this.count = 5});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.screenMargin),
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.cardGap),
      itemBuilder: (_, __) => const SkeletonCard(),
    );
  }
}

/// Segmented control untuk LUNAS / BON.
class PaymentSegmentedControl extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const PaymentSegmentedControl({
    super.key,
    String? selectedStatus,
    String? value,
    required this.onChanged,
  }) : value = selectedStatus ?? value ?? 'LUNAS';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        children: [
          _segment('LUNAS', Icons.check_circle_outline, AppColors.lunas),
          _segment('BON', Icons.schedule, AppColors.bon),
          _segment('QRIS', Icons.qr_code_2_rounded, const Color(0xFF1971C2)),
        ],
      ),
    );
  }

  Widget _segment(String label, IconData icon, Color activeColor) {
    final isActive = value.toUpperCase() == label.toUpperCase();
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(label),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color:
                isActive ? activeColor.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.input - 2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isActive ? activeColor : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? activeColor : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
