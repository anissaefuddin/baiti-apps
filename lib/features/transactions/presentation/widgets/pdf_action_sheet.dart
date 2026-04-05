import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import '../../../../core/services/pdf_service.dart';
import '../../../customers/presentation/providers/customers_provider.dart';
import '../../../payments/presentation/providers/payments_provider.dart';
import '../../../rooms/presentation/providers/rooms_provider.dart';
import '../../domain/transaction_model.dart';

// ── Action enum ───────────────────────────────────────────────────────────────

enum _DocType { invoice, receipt }
enum _PdfAction { share, download }

// ── Sheet ─────────────────────────────────────────────────────────────────────

/// Bottom sheet that lets the user generate, share, or download an Invoice
/// or Kwitansi PDF for [transaction].
class PdfActionSheet extends ConsumerStatefulWidget {
  const PdfActionSheet({super.key, required this.transaction});

  final TransactionModel transaction;

  @override
  ConsumerState<PdfActionSheet> createState() => _PdfActionSheetState();
}

class _PdfActionSheetState extends ConsumerState<PdfActionSheet> {
  // null = idle; non-null = which button is currently loading
  _DocType? _loadingType;
  _PdfAction? _loadingAction;

  bool _isLoading(_DocType type, _PdfAction action) =>
      _loadingType == type && _loadingAction == action;

  bool get _anyLoading => _loadingType != null;

  // ── Core generate + act ───────────────────────────────────────────────────

  Future<void> _go(_DocType docType, _PdfAction action) async {
    if (_anyLoading) return;
    setState(() {
      _loadingType   = docType;
      _loadingAction = action;
    });

    try {
      final bytes    = await _generate(docType);
      final filename = _filename(docType);

      if (!mounted) return;

      switch (action) {
        case _PdfAction.share:
          // Opens native share / print sheet
          await Printing.sharePdf(bytes: bytes, filename: filename);

        case _PdfAction.download:
          final dir  = await getApplicationDocumentsDirectory();
          final file = File('${dir.path}/$filename');
          await file.writeAsBytes(bytes);

          if (!mounted) return;
          // Close sheet first, then show snackbar on the host screen
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Tersimpan: $filename'),
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'Bagikan',
                onPressed: () async {
                  await Printing.sharePdf(bytes: bytes, filename: filename);
                },
              ),
            ),
          );
          return; // sheet already closed above
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal membuat PDF: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingType   = null;
          _loadingAction = null;
        });
      }
    }
  }

  Future<Uint8List> _generate(_DocType docType) async {
    final t = widget.transaction;

    final customer = ref.read(customersProvider).valueOrNull
        ?.where((c) => c.id == t.customerId)
        .firstOrNull;
    final rooms = ref.read(roomsProvider).valueOrNull
            ?.where((r) => t.roomIds.contains(r.id))
            .toList() ??
        [];
    final payments =
        ref.read(paymentsProvider(t.id)).valueOrNull ?? [];

    return switch (docType) {
      _DocType.invoice => PdfService.generateInvoice(
          transaction: t,
          customer: customer,
          rooms: rooms,
          payments: payments,
        ),
      _DocType.receipt => PdfService.generateReceipt(
          transaction: t,
          customer: customer,
          rooms: rooms,
          payments: payments,
        ),
    };
  }

  String _filename(_DocType docType) {
    final code = widget.transaction.bookingCode;
    return switch (docType) {
      _DocType.invoice => 'Invoice_$code.pdf',
      _DocType.receipt => 'Kwitansi_$code.pdf',
    };
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Dokumen PDF',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              widget.transaction.bookingCode,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color:
                        Theme.of(context).colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Document cards ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              children: [
                _DocCard(
                  icon: Icons.receipt_long_outlined,
                  label: 'Invoice',
                  description: 'Tagihan & rincian pembayaran',
                  docType: _DocType.invoice,
                  isLoadingShare:
                      _isLoading(_DocType.invoice, _PdfAction.share),
                  isLoadingDownload:
                      _isLoading(_DocType.invoice, _PdfAction.download),
                  disabled: _anyLoading,
                  onShare:    () => _go(_DocType.invoice, _PdfAction.share),
                  onDownload: () => _go(_DocType.invoice, _PdfAction.download),
                ),
                const SizedBox(height: 12),
                _DocCard(
                  icon: Icons.handshake_outlined,
                  label: 'Kwitansi',
                  description: 'Bukti penerimaan pembayaran',
                  docType: _DocType.receipt,
                  isLoadingShare:
                      _isLoading(_DocType.receipt, _PdfAction.share),
                  isLoadingDownload:
                      _isLoading(_DocType.receipt, _PdfAction.download),
                  disabled: _anyLoading,
                  onShare:    () => _go(_DocType.receipt, _PdfAction.share),
                  onDownload: () => _go(_DocType.receipt, _PdfAction.download),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Document card ──────────────────────────────────────────────────────────────

class _DocCard extends StatelessWidget {
  const _DocCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.docType,
    required this.isLoadingShare,
    required this.isLoadingDownload,
    required this.disabled,
    required this.onShare,
    required this.onDownload,
  });

  final IconData icon;
  final String label;
  final String description;
  final _DocType docType;
  final bool isLoadingShare;
  final bool isLoadingDownload;
  final bool disabled;
  final VoidCallback onShare;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  color: scheme.onPrimaryContainer, size: 22),
            ),
            const SizedBox(width: 14),

            // Label + description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Action buttons
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionButton(
                  icon: Icons.share_outlined,
                  tooltip: 'Bagikan',
                  isLoading: isLoadingShare,
                  disabled: disabled,
                  onTap: onShare,
                ),
                const SizedBox(width: 4),
                _ActionButton(
                  icon: Icons.download_outlined,
                  tooltip: 'Unduh',
                  isLoading: isLoadingDownload,
                  disabled: disabled,
                  onTap: onDownload,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Action button (share / download) ──────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.isLoading,
    required this.disabled,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool isLoading;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
          ),
          child: isLoading
              ? Padding(
                  padding: const EdgeInsets.all(10),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.primary,
                  ),
                )
              : Icon(
                  icon,
                  size: 20,
                  color: disabled
                      ? scheme.onSurface.withValues(alpha: 0.3)
                      : scheme.onSurface,
                ),
        ),
      ),
    );
  }
}
