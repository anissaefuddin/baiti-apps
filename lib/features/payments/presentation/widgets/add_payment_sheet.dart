import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exception.dart';
import '../../../transactions/domain/transaction_model.dart';
import '../../domain/payment_model.dart';
import '../providers/payments_provider.dart';

/// Modal bottom sheet for adding a payment to a transaction.
///
/// Shows the remaining balance prominently so the user knows the max amount.
/// Method defaults to Cash; all three methods are selectable.
///
/// Call via:
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   isScrollControlled: true,
///   builder: (_) => AddPaymentSheet(transaction: t),
/// );
/// ```
class AddPaymentSheet extends ConsumerStatefulWidget {
  const AddPaymentSheet({super.key, required this.transaction});

  final TransactionModel transaction;

  @override
  ConsumerState<AddPaymentSheet> createState() => _AddPaymentSheetState();
}

class _AddPaymentSheetState extends ConsumerState<AddPaymentSheet> {
  final _amountCtrl = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  final _notesCtrl = TextEditingController();

  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amountStr = _amountCtrl.text.trim();
    if (amountStr.isEmpty) {
      setState(() => _error = 'Masukkan jumlah pembayaran');
      return;
    }
    final amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Jumlah harus berupa angka positif');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error        = null;
    });

    try {
      await ref.read(paymentsProvider(widget.transaction.id).notifier).create(
            amount: amount,
            method: _method,
            notes:  _notesCtrl.text.trim(),
          );

      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme    = Theme.of(context).colorScheme;
    final t         = widget.transaction;
    final remaining = t.remaining;

    // Listen to live transaction state so remaining balance updates if the
    // user somehow has two sessions open.
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Handle ──────────────────────────────────────────────────
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Title + remaining ─────────────────────────────────────
              Row(
                children: [
                  Text(
                    'Tambah Pembayaran',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Sisa tagihan',
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                      Text(
                        t.formattedRemaining,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: remaining > 0 ? scheme.error : const Color(0xFF2E7D32),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Error banner ──────────────────────────────────────────
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: scheme.onErrorContainer, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!,
                            style:
                                TextStyle(color: scheme.onErrorContainer)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── Amount field ──────────────────────────────────────────
              TextField(
                controller: _amountCtrl,
                decoration: InputDecoration(
                  labelText: 'Jumlah *',
                  prefixText: 'Rp ',
                  prefixIcon: const Icon(Icons.payments_outlined),
                  helperText: remaining > 0
                      ? 'Maks: ${t.formattedRemaining}'
                      : 'Transaksi sudah lunas',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                enabled: !_isSubmitting,
                autofocus: true,
              ),
              const SizedBox(height: 16),

              // ── Method selector ───────────────────────────────────────
              Text(
                'Metode Pembayaran',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<PaymentMethod>(
                segments: PaymentMethod.values
                    .map((m) => ButtonSegment(
                          value: m,
                          label: Text(m.label),
                        ))
                    .toList(),
                selected: {_method},
                onSelectionChanged: _isSubmitting
                    ? null
                    : (s) => setState(() => _method = s.first),
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(height: 16),

              // ── Notes ─────────────────────────────────────────────────
              TextField(
                controller: _notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Catatan',
                  hintText: 'Bukti transfer, nama pengirim, dll.',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
                maxLines: 2,
                maxLength: 200,
                enabled: !_isSubmitting,
              ),
              const SizedBox(height: 8),

              // ── Submit ────────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Catat Pembayaran'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
