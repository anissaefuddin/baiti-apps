import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../core/router/app_router.dart';
import '../../../customers/domain/customer_model.dart';
import '../../../rooms/domain/room_model.dart';
import '../../../rooms/presentation/providers/rooms_provider.dart';
import '../providers/transactions_provider.dart';
import '../widgets/customer_picker.dart';

/// Booking creation form.
///
/// Flow:
///   1. Pick check-in / check-out dates → nights & total auto-computed.
///   2. Select customer from loaded list.
///   3. Select room from loaded list.
///   4. When all three are set, availability is checked automatically.
///   5. User reviews summary and submits.
///
/// The server re-validates availability under a lock on submit — the client-side
/// check is for UX only and should not be relied upon for correctness.
class BookingFormScreen extends ConsumerStatefulWidget {
  const BookingFormScreen({super.key});

  @override
  ConsumerState<BookingFormScreen> createState() => _BookingFormScreenState();
}

class _BookingFormScreenState extends ConsumerState<BookingFormScreen> {
  DateTime? _checkIn;
  DateTime? _checkOut;
  CustomerModel? _customer;
  RoomModel? _room;
  final _notesCtrl = TextEditingController();

  bool _isSubmitting = false;
  String? _submitError;

  // Availability check state
  bool _isCheckingAvail = false;
  bool? _isAvailable; // null = not yet checked
  String? _conflictCode;

  static final _dateFmt = DateFormat('d MMM yyyy', 'id_ID');
  static final _idrFmt  = NumberFormat.currency(
    locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0,
  );

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  // ── Computed helpers ────────────────────────────────────────────────────

  int get _nights {
    if (_checkIn == null || _checkOut == null) return 0;
    return _checkOut!.difference(_checkIn!).inDays;
  }

  double get _totalPrice {
    if (_room == null) return 0;
    return _nights * _room!.pricePerNight;
  }

  bool get _canCheckAvail =>
      _room != null && _checkIn != null && _checkOut != null;

  bool get _canSubmit =>
      _canCheckAvail && _customer != null && _isAvailable == true;

  // ── Availability check ──────────────────────────────────────────────────

  Future<void> _checkAvailability() async {
    if (!_canCheckAvail) return;
    setState(() {
      _isCheckingAvail = true;
      _isAvailable = null;
      _conflictCode = null;
    });

    try {
      final result = await ref.read(transactionsProvider.notifier).checkAvailability(
            roomId:   _room!.id,
            checkIn:  _checkIn!,
            checkOut: _checkOut!,
          );
      if (mounted) {
        setState(() {
          _isAvailable  = result.available;
          _conflictCode = result.conflictCode;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _submitError = e.message);
    } catch (e) {
      if (mounted) setState(() => _submitError = e.toString());
    } finally {
      if (mounted) setState(() => _isCheckingAvail = false);
    }
  }

  // ── Date pickers ────────────────────────────────────────────────────────

  Future<void> _pickCheckIn() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _checkIn ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked == null || !mounted) return;

    setState(() {
      _checkIn = picked;
      // If check-out is before or equal to new check-in, reset it.
      if (_checkOut != null && !_checkOut!.isAfter(picked)) {
        _checkOut = picked.add(const Duration(days: 1));
      }
      _isAvailable = null;
    });
    _checkAvailability();
  }

  Future<void> _pickCheckOut() async {
    if (_checkIn == null) {
      await _pickCheckIn();
      return;
    }
    final minDate = _checkIn!.add(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: _checkOut ?? minDate,
      firstDate: minDate,
      lastDate: _checkIn!.add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;

    setState(() {
      _checkOut    = picked;
      _isAvailable = null;
    });
    _checkAvailability();
  }

  void _onRoomChanged(RoomModel? room) {
    setState(() {
      _room        = room;
      _isAvailable = null;
    });
    _checkAvailability();
  }

  // ── Submit ──────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _isSubmitting = true;
      _submitError  = null;
    });

    try {
      await ref.read(transactionsProvider.notifier).create(
            customerId: _customer!.id,
            roomId:     _room!.id,
            checkIn:    _checkIn!,
            checkOut:   _checkOut!,
            notes:      _notesCtrl.text.trim(),
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pemesanan berhasil dibuat'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
        context.go(AppRoutes.transactions);
      }
    } on ApiException catch (e) {
      setState(() {
        _submitError = e.message;
        // If server rejects due to conflict, invalidate our cached check result.
        if (e.isConflict) _isAvailable = false;
      });
    } catch (e) {
      setState(() => _submitError = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme     = Theme.of(context).colorScheme;
    final roomsAsync = ref.watch(roomsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Buat Pemesanan'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed:
              _isSubmitting ? null : () => context.go(AppRoutes.transactions),
        ),
      ),
      body: Form(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // ── Error banner ────────────────────────────────────────────
            if (_submitError != null) ...[
              _ErrorBanner(
                message: _submitError!,
                onDismiss: () => setState(() => _submitError = null),
              ),
              const SizedBox(height: 20),
            ],

            // ── Dates ───────────────────────────────────────────────────
            Text('Tanggal Menginap',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _DateTile(
                    label: 'Check-in',
                    date: _checkIn,
                    onTap: _isSubmitting ? null : _pickCheckIn,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward,
                      size: 18, color: scheme.onSurfaceVariant),
                ),
                Expanded(
                  child: _DateTile(
                    label: 'Check-out',
                    date: _checkOut,
                    onTap: _isSubmitting ? null : _pickCheckOut,
                  ),
                ),
              ],
            ),
            if (_nights > 0) ...[
              const SizedBox(height: 8),
              Text(
                '$_nights malam',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
            const SizedBox(height: 24),

            // ── Customer ─────────────────────────────────────────────────
            Text('Tamu',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            CustomerPicker(
              value: _customer,
              enabled: !_isSubmitting,
              onChanged: (c) => setState(() => _customer = c),
            ),
            const SizedBox(height: 24),

            // ── Room ─────────────────────────────────────────────────────
            Text('Kamar',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            roomsAsync.when(
              loading: () => const _DropdownShimmer(),
              error: (e, _) => Text('Gagal memuat kamar: $e',
                  style: TextStyle(color: scheme.error)),
              data: (rooms) => DropdownButtonFormField<RoomModel>(
                value: _room,
                hint: const Text('Pilih kamar'),
                isExpanded: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.meeting_room_outlined),
                ),
                items: rooms
                    .map((r) => DropdownMenuItem(
                          value: r,
                          child: Text(
                            '${r.name}  ·  ${r.formattedPrice}/malam',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: _isSubmitting ? null : _onRoomChanged,
                validator: (_) =>
                    _room == null ? 'Pilih kamar terlebih dahulu' : null,
              ),
            ),
            const SizedBox(height: 16),

            // ── Availability indicator ────────────────────────────────────
            if (_canCheckAvail) _AvailabilityTile(
              isChecking: _isCheckingAvail,
              isAvailable: _isAvailable,
              conflictCode: _conflictCode,
              onRecheck: _checkAvailability,
            ),

            // ── Summary ───────────────────────────────────────────────────
            if (_room != null && _nights > 0) ...[
              const SizedBox(height: 16),
              _SummaryCard(
                nights:     _nights,
                room:       _room!,
                totalPrice: _totalPrice,
              ),
            ],
            const SizedBox(height: 24),

            // ── Notes ─────────────────────────────────────────────────────
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Catatan',
                hintText: 'Permintaan khusus, nomor kendaraan, dll.',
                prefixIcon: Icon(Icons.notes_outlined),
                alignLabelWithHint: true,
              ),
              maxLines: 3,
              maxLength: 300,
              enabled: !_isSubmitting,
            ),
            const SizedBox(height: 32),

            // ── Submit ────────────────────────────────────────────────────
            FilledButton(
              onPressed: (_isSubmitting || !_canSubmit) ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Buat Pemesanan'),
            ),
            if (!_canSubmit && _customer != null && _room != null &&
                _checkIn != null && _checkOut != null && _isAvailable != true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _isAvailable == false
                      ? 'Kamar tidak tersedia untuk tanggal ini.'
                      : _isCheckingAvail
                          ? 'Memeriksa ketersediaan...'
                          : 'Periksa ketersediaan kamar sebelum memesan.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: _isAvailable == false
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Date tile ─────────────────────────────────────────────────────────────────

class _DateTile extends StatelessWidget {
  const _DateTile({required this.label, required this.date, this.onTap});

  final String label;
  final DateTime? date;
  final VoidCallback? onTap;

  static final _fmt = DateFormat('d MMM yyyy', 'id_ID');

  @override
  Widget build(BuildContext context) {
    final scheme  = Theme.of(context).colorScheme;
    final isEmpty = date == null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isEmpty
                ? scheme.outline.withValues(alpha: 0.5)
                : scheme.primary,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isEmpty ? scheme.onSurfaceVariant : scheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              date != null ? _fmt.format(date!) : '—',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isEmpty
                    ? scheme.onSurfaceVariant
                    : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Availability indicator ────────────────────────────────────────────────────

class _AvailabilityTile extends StatelessWidget {
  const _AvailabilityTile({
    required this.isChecking,
    required this.isAvailable,
    required this.conflictCode,
    required this.onRecheck,
  });

  final bool isChecking;
  final bool? isAvailable;
  final String? conflictCode;
  final VoidCallback onRecheck;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (isChecking) {
      return Row(
        children: [
          const SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text('Memeriksa ketersediaan...',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
        ],
      );
    }

    if (isAvailable == null) {
      return TextButton.icon(
        onPressed: onRecheck,
        icon: const Icon(Icons.search, size: 16),
        label: const Text('Periksa Ketersediaan'),
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    if (isAvailable!) {
      return Row(
        children: [
          const Icon(Icons.check_circle_outline,
              size: 18, color: Color(0xFF2E7D32)),
          const SizedBox(width: 8),
          const Text('Kamar tersedia',
              style: TextStyle(color: Color(0xFF2E7D32), fontSize: 13)),
          const Spacer(),
          TextButton(
            onPressed: onRecheck,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Refresh', style: TextStyle(fontSize: 12)),
          ),
        ],
      );
    }

    // Not available
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.block_outlined, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              conflictCode != null
                  ? 'Kamar sudah dipesan (${conflictCode!})'
                  : 'Kamar tidak tersedia untuk tanggal ini',
              style: TextStyle(color: scheme.onErrorContainer, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: onRecheck,
            style: TextButton.styleFrom(
              foregroundColor: scheme.onErrorContainer,
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Cek ulang', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ── Summary card ──────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.nights,
    required this.room,
    required this.totalPrice,
  });

  final int nights;
  final RoomModel room;
  final double totalPrice;

  static final _idr = NumberFormat.currency(
    locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0,
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                '$nights malam × ${room.formattedPrice}',
                style: TextStyle(
                    color: scheme.onPrimaryContainer, fontSize: 13),
              ),
              const Spacer(),
              Text(
                _idr.format(totalPrice),
                style: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: TextStyle(color: scheme.onErrorContainer)),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: Icon(Icons.close,
                color: scheme.onErrorContainer.withValues(alpha: 0.7),
                size: 16),
          ),
        ],
      ),
    );
  }
}

class _DropdownShimmer extends StatelessWidget {
  const _DropdownShimmer();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        border: Border.all(
            color: Theme.of(context)
                .colorScheme
                .outline
                .withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
      ),
      child: const Center(
        child: SizedBox(
          width: 20, height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
