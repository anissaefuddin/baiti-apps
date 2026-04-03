import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../core/router/app_router.dart';
import '../../domain/room_model.dart';
import '../providers/rooms_provider.dart';


/// Create or edit a room.
///
/// Pass [room] to enter edit mode; omit it (or pass null) for create mode.
/// GoRouter passes the [RoomModel] via `state.extra` so no extra network
/// call is needed to populate the form.
class RoomFormScreen extends ConsumerStatefulWidget {
  const RoomFormScreen({super.key, this.room});

  /// Non-null when editing an existing room.
  final RoomModel? room;

  bool get isEditing => room != null;

  @override
  ConsumerState<RoomFormScreen> createState() => _RoomFormScreenState();
}

class _RoomFormScreenState extends ConsumerState<RoomFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _capacityCtrl;
  late final TextEditingController _descCtrl;
  late RoomStatus _status;

  bool _isSubmitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    final r = widget.room;
    _nameCtrl = TextEditingController(text: r?.name ?? '');
    _priceCtrl = TextEditingController(
      text: r != null ? r.pricePerNight.toInt().toString() : '',
    );
    _capacityCtrl = TextEditingController(
      text: r != null ? r.capacity.toString() : '',
    );
    _descCtrl = TextEditingController(text: r?.description ?? '');
    _status = r?.status ?? RoomStatus.available;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _capacityCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  // ── Submit ──────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      final name = _nameCtrl.text.trim();
      final price = double.parse(_priceCtrl.text.trim());
      final capacity = int.parse(_capacityCtrl.text.trim());
      final desc = _descCtrl.text.trim();

      if (widget.isEditing) {
        await ref.read(roomsProvider.notifier).edit(
              id: widget.room!.id,
              name: name,
              pricePerNight: price,
              capacity: capacity,
              description: desc,
              status: _status,
            );
      } else {
        await ref.read(roomsProvider.notifier).create(
              name: name,
              pricePerNight: price,
              capacity: capacity,
              description: desc,
            );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isEditing ? 'Kamar berhasil diperbarui' : 'Kamar berhasil ditambahkan',
            ),
            backgroundColor: const Color(0xFF2E7D32),
          ),
        );
        context.go(AppRoutes.rooms);
      }
    } on ApiException catch (e) {
      setState(() => _submitError = e.message);
    } catch (e) {
      setState(() => _submitError = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Kamar' : 'Tambah Kamar'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _isSubmitting ? null : () => context.go(AppRoutes.rooms),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // ── Error banner ─────────────────────────────────────────────
            if (_submitError != null) ...[
              Container(
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
                        _submitError!,
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _submitError = null),
                      child: Icon(Icons.close,
                          color: scheme.onErrorContainer.withOpacity(0.7), size: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // ── Nama Kamar ───────────────────────────────────────────────
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nama Kamar *',
                hintText: 'Contoh: Kamar 1, Suite Deluxe',
                prefixIcon: Icon(Icons.meeting_room_outlined),
              ),
              textCapitalization: TextCapitalization.words,
              enabled: !_isSubmitting,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Nama kamar wajib diisi';
                if (v.trim().length < 2) return 'Nama terlalu pendek';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // ── Harga & Kapasitas ─────────────────────────────────────────
            Row(
              children: [
                // Price
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _priceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Harga / Malam *',
                      prefixText: 'Rp ',
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    enabled: !_isSubmitting,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Wajib diisi';
                      final n = int.tryParse(v.trim());
                      if (n == null || n <= 0) return 'Harus > 0';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                // Capacity
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _capacityCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Kapasitas *',
                      suffixText: 'tamu',
                      prefixIcon: Icon(Icons.people_outline),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    enabled: !_isSubmitting,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Wajib diisi';
                      final n = int.tryParse(v.trim());
                      if (n == null || n < 1) return 'Min. 1';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Deskripsi ─────────────────────────────────────────────────
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Deskripsi',
                hintText: 'AC, TV, kamar mandi dalam, ...',
                prefixIcon: Icon(Icons.notes_outlined),
                alignLabelWithHint: true,
              ),
              maxLines: 3,
              maxLength: 300,
              enabled: !_isSubmitting,
            ),

            // ── Status (edit mode only) ──────────────────────────────────
            if (widget.isEditing) ...[
              const SizedBox(height: 8),
              _StatusToggle(
                value: _status,
                enabled: !_isSubmitting,
                onChanged: (s) => setState(() => _status = s),
              ),
            ],

            const SizedBox(height: 32),

            // ── Submit ────────────────────────────────────────────────────
            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(widget.isEditing ? 'Simpan Perubahan' : 'Tambah Kamar'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status toggle ─────────────────────────────────────────────────────────────

class _StatusToggle extends StatelessWidget {
  const _StatusToggle({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final RoomStatus value;
  final bool enabled;
  final ValueChanged<RoomStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isAvailable = value == RoomStatus.available;

    return InkWell(
      onTap: enabled
          ? () => onChanged(
                isAvailable ? RoomStatus.unavailable : RoomStatus.available,
              )
          : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outline.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(12),
          color: scheme.surfaceContainerLowest,
        ),
        child: Row(
          children: [
            Icon(
              isAvailable ? Icons.check_circle_outline : Icons.do_not_disturb_on_outlined,
              color: isAvailable ? const Color(0xFF2E7D32) : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Status Kamar',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  Text(
                    value.label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ],
              ),
            ),
            Switch(
              value: isAvailable,
              onChanged: enabled
                  ? (v) => onChanged(
                        v ? RoomStatus.available : RoomStatus.unavailable,
                      )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
