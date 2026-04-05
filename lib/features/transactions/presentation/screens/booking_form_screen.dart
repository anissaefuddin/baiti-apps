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

/// Booking creation form. Supports selecting multiple rooms for the same date range.
class BookingFormScreen extends ConsumerStatefulWidget {
  const BookingFormScreen({super.key});

  @override
  ConsumerState<BookingFormScreen> createState() => _BookingFormScreenState();
}

class _BookingFormScreenState extends ConsumerState<BookingFormScreen> {
  DateTime? _checkIn;
  DateTime? _checkOut;
  CustomerModel? _customer;
  List<RoomModel> _rooms = [];

  final _notesCtrl = TextEditingController();

  bool _isSubmitting    = false;
  String? _submitError;
  bool _isCheckingAvail = false;
  bool? _isAvailable;
  String?       _conflictCode;
  List<String>? _conflictRoomNames;
  DateTime?     _conflictCheckIn;
  DateTime?     _conflictCheckOut;


  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  // ── Computed ────────────────────────────────────────────────────────────

  int get _nights {
    if (_checkIn == null || _checkOut == null) return 0;
    return _checkOut!.difference(_checkIn!).inDays;
  }

  double get _totalPrice =>
      _rooms.fold(0.0, (sum, r) => sum + r.pricePerNight) * _nights;

  bool get _canCheckAvail =>
      _rooms.isNotEmpty && _checkIn != null && _checkOut != null;

  bool get _canSubmit =>
      _canCheckAvail && _customer != null && _isAvailable == true;

  // ── Availability ────────────────────────────────────────────────────────

  Future<void> _checkAvailability() async {
    if (!_canCheckAvail) return;
    setState(() {
      _isCheckingAvail    = true;
      _isAvailable        = null;
      _conflictCode       = null;
      _conflictRoomNames  = null;
      _conflictCheckIn    = null;
      _conflictCheckOut   = null;
    });
    try {
      final result = await ref
          .read(transactionsProvider.notifier)
          .checkAvailability(
            roomIds:  _rooms.map((r) => r.id).toList(),
            checkIn:  _checkIn!,
            checkOut: _checkOut!,
          );
      if (mounted) {
        setState(() {
          _isAvailable        = result.available;
          _conflictCode       = result.conflictCode;
          _conflictRoomNames  = result.conflictRoomNames;
          _conflictCheckIn    = result.conflictCheckIn;
          _conflictCheckOut   = result.conflictCheckOut;
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
    final now    = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _checkIn ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _checkIn     = picked;
      if (_checkOut != null && !_checkOut!.isAfter(picked)) {
        _checkOut = picked.add(const Duration(days: 1));
      }
      _isAvailable = null;
    });
    _checkAvailability();
  }

  Future<void> _pickCheckOut() async {
    if (_checkIn == null) { await _pickCheckIn(); return; }
    final minDate = _checkIn!.add(const Duration(days: 1));
    final picked  = await showDatePicker(
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

  // ── Room picker ─────────────────────────────────────────────────────────

  Future<void> _openRoomPicker(List<RoomModel> allRooms) async {
    // Issue 4: require dates before picking rooms
    if (_checkIn == null || _checkOut == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih tanggal check-in & check-out terlebih dahulu')),
      );
      return;
    }

    final selected = await Navigator.of(context, rootNavigator: true)
        .push<List<RoomModel>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _RoomPickerScreen(
          allRooms: allRooms,
          selected: List.of(_rooms),
          checkIn: _checkIn!,
          checkOut: _checkOut!,
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _rooms       = selected;
      _isAvailable = null;
    });
    _checkAvailability();
  }

  // ── Submit ──────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() { _isSubmitting = true; _submitError = null; });
    try {
      final txn = await ref.read(transactionsProvider.notifier).create(
            customerId: _customer!.id,
            roomIds:    _rooms.map((r) => r.id).toList(),
            checkIn:    _checkIn!,
            checkOut:   _checkOut!,
            notes:      _notesCtrl.text.trim(),
          );
      if (mounted) {
        if (txn.calendarError != null) {
          // Booking saved but calendar event failed — show warning then navigate.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Pemesanan dibuat, tapi event kalender gagal: ${txn.calendarError}',
              ),
              backgroundColor: Colors.orange.shade700,
              duration: const Duration(seconds: 6),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Pemesanan berhasil dibuat'),
              backgroundColor: Color(0xFF2E7D32),
            ),
          );
        }
        context.go(AppRoutes.transactions);
      }
    } on ApiException catch (e) {
      setState(() {
        _submitError = e.message;
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
          onPressed: _isSubmitting ? null : () => context.go(AppRoutes.transactions),
        ),
      ),
      body: Form(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [

            if (_submitError != null) ...[
              _ErrorBanner(
                message: _submitError!,
                onDismiss: () => setState(() => _submitError = null),
              ),
              const SizedBox(height: 20),
            ],

            // ── Dates ────────────────────────────────────────────────
            Text(
              'Tanggal Menginap',
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
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
                  child: Icon(Icons.arrow_forward, size: 18, color: scheme.onSurfaceVariant),
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

            // ── Customer ─────────────────────────────────────────────
            Text(
              'Tamu',
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            CustomerPicker(
              value: _customer,
              enabled: !_isSubmitting,
              onChanged: (c) => setState(() => _customer = c),
            ),
            const SizedBox(height: 24),

            // ── Rooms ─────────────────────────────────────────────────
            Text(
              'Kamar',
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            roomsAsync.when(
              loading: () => const _DropdownShimmer(),
              error: (e, _) => Text(
                'Gagal memuat kamar: $e',
                style: TextStyle(color: scheme.error),
              ),
              data: (allRooms) => _RoomSelector(
                rooms: _rooms,
                enabled: !_isSubmitting,
                onTap: () => _openRoomPicker(allRooms),
              ),
            ),
            const SizedBox(height: 16),

            // ── Availability ──────────────────────────────────────────
            if (_canCheckAvail)
              _AvailabilityTile(
                isChecking:         _isCheckingAvail,
                isAvailable:        _isAvailable,
                conflictCode:       _conflictCode,
                conflictRoomNames:  _conflictRoomNames,
                conflictCheckIn:    _conflictCheckIn,
                conflictCheckOut:   _conflictCheckOut,
                onRecheck:          _checkAvailability,
              ),

            // ── Summary ───────────────────────────────────────────────
            if (_rooms.isNotEmpty && _nights > 0) ...[
              const SizedBox(height: 16),
              _SummaryCard(
                nights:     _nights,
                rooms:      _rooms,
                totalPrice: _totalPrice,
              ),
            ],
            const SizedBox(height: 24),

            // ── Notes ─────────────────────────────────────────────────
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

            // ── Submit ────────────────────────────────────────────────
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
            if (!_canSubmit &&
                _customer != null &&
                _rooms.isNotEmpty &&
                _checkIn != null &&
                _checkOut != null &&
                _isAvailable != true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _isAvailable == false
                      ? 'Salah satu kamar tidak tersedia untuk tanggal ini.'
                      : _isCheckingAvail
                          ? 'Memeriksa ketersediaan...'
                          : 'Periksa ketersediaan kamar sebelum memesan.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: _isAvailable == false
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Room selector ─────────────────────────────────────────────────────────────

class _RoomSelector extends StatelessWidget {
  const _RoomSelector({
    required this.rooms,
    required this.enabled,
    required this.onTap,
  });
  final List<RoomModel> rooms;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(
            color: rooms.isEmpty
                ? scheme.outline.withValues(alpha: 0.5)
                : scheme.primary,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: rooms.isEmpty
            ? Row(
                children: [
                  Icon(Icons.meeting_room_outlined, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Text(
                    'Pilih kamar (bisa lebih dari satu)',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Icon(Icons.arrow_drop_down, color: scheme.onSurfaceVariant),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.meeting_room_outlined, color: scheme.primary, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        '${rooms.length} kamar dipilih',
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      Icon(Icons.edit_outlined, color: scheme.primary, size: 16),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: rooms
                        .map(
                          (r) => Chip(
                            label: Text(r.name, style: const TextStyle(fontSize: 12)),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Room picker screen ────────────────────────────────────────────────────────

class _RoomPickerScreen extends StatefulWidget {
  const _RoomPickerScreen({
    required this.allRooms,
    required this.selected,
    required this.checkIn,
    required this.checkOut,
  });
  final List<RoomModel> allRooms;
  final List<RoomModel> selected;
  final DateTime checkIn;
  final DateTime checkOut;

  @override
  State<_RoomPickerScreen> createState() => _RoomPickerScreenState();
}

class _RoomPickerScreenState extends State<_RoomPickerScreen> {
  late List<RoomModel> _selected;
  static final _idr  = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  static final _dfmt = DateFormat('d MMM yyyy', 'id_ID');

  @override
  void initState() {
    super.initState();
    _selected = List.of(widget.selected);
  }

  void _confirm() =>
      Navigator.of(context, rootNavigator: true).pop(_selected);

  void _cancel() =>
      Navigator.of(context, rootNavigator: true).pop();

  void _toggle(RoomModel room) {
    setState(() {
      if (_selected.any((r) => r.id == room.id)) {
        _selected.removeWhere((r) => r.id == room.id);
      } else {
        _selected.add(room);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nights = widget.checkOut.difference(widget.checkIn).inDays;

    return Scaffold(
      appBar: AppBar(
        // Explicit back button using rootNavigator so GoRouter doesn't intercept
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _cancel,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pilih Kamar', style: TextStyle(fontSize: 16)),
            Text(
              '${_dfmt.format(widget.checkIn)} – ${_dfmt.format(widget.checkOut)} · $nights malam',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      // Always-visible confirm button at the bottom
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _selected.isEmpty ? null : _confirm,
            child: Text(
              _selected.isEmpty
                  ? 'Pilih kamar'
                  : 'Konfirmasi ${_selected.length} kamar',
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Date summary banner
          Container(
            width: double.infinity,
            color: scheme.primaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              'Menampilkan kamar untuk ${_dfmt.format(widget.checkIn)} – ${_dfmt.format(widget.checkOut)}',
              style: TextStyle(
                fontSize: 13,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: widget.allRooms.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: scheme.outlineVariant),
              itemBuilder: (_, i) {
                final room       = widget.allRooms[i];
                final isSelected = _selected.any((r) => r.id == room.id);
                return CheckboxListTile(
                  value: isSelected,
                  onChanged: (_) => _toggle(room),
                  title: Text(room.name,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    '${_idr.format(room.pricePerNight)}/malam · ${room.capacity} tamu',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  secondary: isSelected
                      ? Icon(Icons.check_circle,
                          color: scheme.primary, size: 22)
                      : Icon(Icons.radio_button_unchecked,
                          color: scheme.outlineVariant, size: 22),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                );
              },
            ),
          ),
        ],
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
                color: isEmpty ? scheme.onSurfaceVariant : scheme.onSurface,
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
    this.conflictRoomNames,
    this.conflictCheckIn,
    this.conflictCheckOut,
  });
  final bool isChecking;
  final bool? isAvailable;
  final String? conflictCode;
  final List<String>? conflictRoomNames;
  final DateTime? conflictCheckIn;
  final DateTime? conflictCheckOut;
  final VoidCallback onRecheck;

  static final _fmt = DateFormat('d MMM yyyy', 'id_ID');

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
          Text(
            'Memeriksa ketersediaan...',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
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
          const Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF2E7D32)),
          const SizedBox(width: 8),
          const Text('Semua kamar tersedia',
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

    // Build rich conflict message
    final roomLine = (conflictRoomNames != null && conflictRoomNames!.isNotEmpty)
        ? conflictRoomNames!.join(', ')
        : null;
    final dateLine = (conflictCheckIn != null && conflictCheckOut != null)
        ? '${_fmt.format(conflictCheckIn!)} – ${_fmt.format(conflictCheckOut!)}'
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.block_outlined, size: 18, color: scheme.onErrorContainer),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kamar sudah dipesan',
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (roomLine != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    roomLine,
                    style: TextStyle(color: scheme.onErrorContainer, fontSize: 12),
                  ),
                ],
                if (dateLine != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    dateLine,
                    style: TextStyle(color: scheme.onErrorContainer, fontSize: 12),
                  ),
                ],
                if (conflictCode != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Booking: $conflictCode',
                    style: TextStyle(
                      color: scheme.onErrorContainer.withValues(alpha: 0.7),
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
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
    required this.rooms,
    required this.totalPrice,
  });
  final int nights;
  final List<RoomModel> rooms;
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
          ...rooms.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Text(
                    r.name,
                    style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 13),
                  ),
                  const Spacer(),
                  Text(
                    '${_idr.format(r.pricePerNight)}/malam',
                    style: TextStyle(
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (rooms.length > 1)
            Divider(color: scheme.onPrimaryContainer.withValues(alpha: 0.3)),
          Row(
            children: [
              Text(
                '$nights malam${rooms.length > 1 ? ' × ${rooms.length} kamar' : ''}',
                style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 13),
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
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: Icon(
              Icons.close,
              color: scheme.onErrorContainer.withValues(alpha: 0.7),
              size: 16,
            ),
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
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
        ),
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
