import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/services/ktp_ocr_service.dart';
import '../../data/customer_repository.dart';
import '../../domain/customer_model.dart';
import '../providers/customers_provider.dart';

/// Create or edit a customer (Tamu).
///
/// In create mode, a "Scan KTP" button triggers camera capture → OCR →
/// pre-fills the form fields. The user can then review and correct before saving.
///
/// In edit mode, NIK is shown as read-only (immutable after creation).
class CustomerFormScreen extends ConsumerStatefulWidget {
  const CustomerFormScreen({super.key, this.customer});

  final CustomerModel? customer;
  bool get isEditing => customer != null;

  @override
  ConsumerState<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends ConsumerState<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nikCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _birthDateCtrl;

  bool _isSubmitting = false;
  bool _isScanning = false;
  String? _submitError;

  // Set to true after OCR fills the form — shows a banner so users know
  // the fields were pre-filled and may need correction.
  bool _ocrFilled = false;

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    _nikCtrl       = TextEditingController(text: c?.nik ?? '');
    _nameCtrl      = TextEditingController(text: c?.name ?? '');
    _phoneCtrl     = TextEditingController(text: c?.phone ?? '');
    _addressCtrl   = TextEditingController(text: c?.address ?? '');
    _birthDateCtrl = TextEditingController(text: c?.birthDate ?? '');
  }

  @override
  void dispose() {
    _nikCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _birthDateCtrl.dispose();
    super.dispose();
  }

  // ── OCR ──────────────────────────────────────────────────────────────────

  Future<void> _scanKtp() async {
    // Ask the user for image source before starting the scan.
    final source = await _pickImageSource();
    if (source == null || !mounted) return;

    setState(() {
      _isScanning  = true;
      _submitError = null;
      _ocrFilled   = false;
    });

    try {
      final picker = ImagePicker();
      final image  = await picker.pickImage(
        source:                source,
        imageQuality:          100,  // no compression — OCR needs full detail
        maxWidth:              1920,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (image == null || !mounted) return;

      final result = await KtpOcrService.processImage(image);

      if (!mounted) return;
      setState(() {
        if (result.nik.isNotEmpty)       _nikCtrl.text       = result.nik;
        if (result.name.isNotEmpty)      _nameCtrl.text      = result.name;
        if (result.address.isNotEmpty)   _addressCtrl.text   = result.address;
        if (result.birthDate.isNotEmpty) _birthDateCtrl.text = result.birthDate;
        _ocrFilled = result.hasData;
      });

      if (!result.hasData) {
        _showSnack(
            'Tidak ada teks terdeteksi. Pastikan foto KTP jelas dan tidak buram.');
      }
    } catch (e) {
      if (mounted) setState(() => _submitError = 'Gagal memindai KTP: $e');
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  /// Show a dialog to choose between camera and gallery.
  Future<ImageSource?> _pickImageSource() => showDialog<ImageSource>(
        context: context,
        builder: (_) => SimpleDialog(
          title: const Text('Scan KTP'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(ImageSource.camera),
              child: const Row(children: [
                Icon(Icons.camera_alt_outlined),
                SizedBox(width: 14),
                Text('Foto Langsung'),
              ]),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(ImageSource.gallery),
              child: const Row(children: [
                Icon(Icons.photo_library_outlined),
                SizedBox(width: 14),
                Text('Pilih dari Galeri'),
              ]),
            ),
          ],
        ),
      );

  // ── NIK uniqueness check on blur ─────────────────────────────────────────

  Future<void> _checkNikOnBlur() async {
    if (widget.isEditing) return;
    final nik = _nikCtrl.text.trim();
    if (nik.length != 16) return;

    try {
      final existing =
          await ref.read(customerRepositoryProvider).getByNik(nik);
      if (existing != null && mounted) {
        setState(() => _submitError =
            'NIK $nik sudah terdaftar atas nama "${existing.name}"');
      }
    } catch (_) {
      // Not found or network error — silently ignore on blur
    }
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      final nik       = _nikCtrl.text.trim();
      final name      = _nameCtrl.text.trim();
      final phone     = _phoneCtrl.text.trim();
      final address   = _addressCtrl.text.trim();
      final birthDate = _birthDateCtrl.text.trim();

      if (widget.isEditing) {
        await ref.read(customersProvider.notifier).edit(
              id:        widget.customer!.id,
              name:      name,
              phone:     phone,
              address:   address,
              birthDate: birthDate,
            );
      } else {
        await ref.read(customersProvider.notifier).create(
              nik:       nik,
              name:      name,
              phone:     phone,
              address:   address,
              birthDate: birthDate,
            );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isEditing
                  ? 'Data tamu berhasil diperbarui'
                  : 'Tamu berhasil ditambahkan',
            ),
            backgroundColor: const Color(0xFF2E7D32),
          ),
        );
        context.go(AppRoutes.customers);
      }
    } on ApiException catch (e) {
      setState(() => _submitError = e.message);
    } catch (e) {
      setState(() => _submitError = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Tamu' : 'Tambah Tamu'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed:
              _isSubmitting ? null : () => context.go(AppRoutes.customers),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // ── Scan KTP button (create mode only) ───────────────────────
            if (!widget.isEditing) ...[
              OutlinedButton.icon(
                onPressed: (_isSubmitting || _isScanning) ? null : _scanKtp,
                icon: _isScanning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.document_scanner_outlined),
                label: Text(_isScanning ? 'Memindai...' : 'Scan KTP'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Atau isi data secara manual di bawah.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
            ],

            // ── OCR pre-fill notice ───────────────────────────────────────
            if (_ocrFilled) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.auto_fix_high_outlined,
                        color: scheme.onPrimaryContainer, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Data diisi otomatis dari KTP. Periksa dan koreksi jika perlu.',
                        style: TextStyle(
                            color: scheme.onPrimaryContainer, fontSize: 13),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _ocrFilled = false),
                      child: Icon(Icons.close,
                          color: scheme.onPrimaryContainer.withOpacity(0.7),
                          size: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // ── Error banner ──────────────────────────────────────────────
            if (_submitError != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        color: scheme.onErrorContainer, size: 18),
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
                          color: scheme.onErrorContainer.withOpacity(0.7),
                          size: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // ── NIK ───────────────────────────────────────────────────────
            TextFormField(
              controller: _nikCtrl,
              decoration: InputDecoration(
                labelText: 'NIK *',
                hintText: '16 digit nomor KTP',
                prefixIcon: const Icon(Icons.badge_outlined),
                // Show lock icon in edit mode since NIK is immutable.
                suffixIcon: widget.isEditing
                    ? const Icon(Icons.lock_outline, size: 18)
                    : null,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(16),
              ],
              enabled: !_isSubmitting && !widget.isEditing,
              onEditingComplete: _checkNikOnBlur,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'NIK wajib diisi';
                if (v.trim().length != 16) return 'NIK harus 16 digit';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // ── Nama ──────────────────────────────────────────────────────
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nama Lengkap *',
                hintText: 'Sesuai KTP',
                prefixIcon: Icon(Icons.person_outline),
              ),
              textCapitalization: TextCapitalization.words,
              enabled: !_isSubmitting,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Nama wajib diisi';
                if (v.trim().length < 2) return 'Nama terlalu pendek';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // ── No. Telepon ───────────────────────────────────────────────
            TextFormField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(
                labelText: 'No. Telepon',
                hintText: '08xx-xxxx-xxxx',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d\-+ ]')),
              ],
              enabled: !_isSubmitting,
            ),
            const SizedBox(height: 16),

            // ── Alamat ────────────────────────────────────────────────────
            TextFormField(
              controller: _addressCtrl,
              decoration: const InputDecoration(
                labelText: 'Alamat',
                hintText: 'Sesuai KTP',
                prefixIcon: Icon(Icons.home_outlined),
                alignLabelWithHint: true,
              ),
              maxLines: 3,
              maxLength: 300,
              enabled: !_isSubmitting,
            ),

            // ── Tanggal Lahir ─────────────────────────────────────────────
            TextFormField(
              controller: _birthDateCtrl,
              decoration: const InputDecoration(
                labelText: 'Tanggal Lahir',
                hintText: 'DD-MM-YYYY',
                prefixIcon: Icon(Icons.cake_outlined),
              ),
              keyboardType: TextInputType.datetime,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d\-]')),
                LengthLimitingTextInputFormatter(10),
              ],
              enabled: !_isSubmitting,
            ),
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
                  : Text(widget.isEditing
                      ? 'Simpan Perubahan'
                      : 'Tambah Tamu'),
            ),
          ],
        ),
      ),
    );
  }
}
