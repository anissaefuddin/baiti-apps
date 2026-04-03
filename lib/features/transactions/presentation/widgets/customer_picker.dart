import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/services/ktp_ocr_service.dart';
import '../../../customers/domain/customer_model.dart';
import '../../../customers/presentation/providers/customers_provider.dart';

/// Tappable field for selecting a customer.
///
/// Opens a bottom sheet with:
///  - Text search filtering the existing customer list by name, phone, or NIK.
///  - A "Tambah Baru" button that switches to a quick-create form.
///
/// The quick-create form (NIK + name + phone) calls [CustomersNotifier.create]
/// and automatically selects the newly created customer.
class CustomerPicker extends ConsumerWidget {
  const CustomerPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final CustomerModel? value;
  final ValueChanged<CustomerModel?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme   = Theme.of(context).colorScheme;
    final hasValue = value != null;

    return InkWell(
      onTap: enabled ? () => _openSheet(context) : null,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.person_outline),
          suffixIcon: hasValue
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Hapus pilihan',
                  onPressed: enabled ? () => onChanged(null) : null,
                )
              : const Icon(Icons.search),
          hintText: hasValue ? null : 'Cari atau tambah tamu…',
        ),
        isEmpty: !hasValue,
        child: hasValue
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value!.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    value!.maskedNik,
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  Future<void> _openSheet(BuildContext context) async {
    final selected = await showModalBottomSheet<CustomerModel>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CustomerPickerSheet(currentCustomer: value),
    );
    if (selected != null) onChanged(selected);
  }
}

// ── Bottom sheet ──────────────────────────────────────────────────────────────

enum _SheetView { search, addNew }

class _CustomerPickerSheet extends ConsumerStatefulWidget {
  const _CustomerPickerSheet({this.currentCustomer});

  final CustomerModel? currentCustomer;

  @override
  ConsumerState<_CustomerPickerSheet> createState() =>
      _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends ConsumerState<_CustomerPickerSheet> {
  _SheetView _view = _SheetView.search;

  // Search
  final _searchCtrl = TextEditingController();
  String _query = '';

  // Quick-add
  final _nikCtrl       = TextEditingController();
  final _nameCtrl      = TextEditingController();
  final _phoneCtrl     = TextEditingController();
  final _birthDateCtrl = TextEditingController();
  final _addressCtrl   = TextEditingController();
  String? _addError;
  bool    _isCreating = false;

  // KTP scan
  bool    _isScanning   = false;
  bool    _scanSuccess  = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _nikCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _birthDateCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  List<CustomerModel> _applyFilter(List<CustomerModel> all) {
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all.where((c) {
      return c.name.toLowerCase().contains(q) ||
          c.phone.contains(q) ||
          c.nik.contains(q);
    }).toList();
  }

  void _switchToAddNew({String prefillName = ''}) {
    _nameCtrl.text = prefillName;
    setState(() => _view = _SheetView.addNew);
  }

  Future<void> _scanKtp(ImageSource source) async {
    setState(() {
      _isScanning  = true;
      _scanSuccess = false;
      _addError    = null;
    });

    try {
      final picker = ImagePicker();
      final image  = await picker.pickImage(
        source:                source,
        imageQuality:          100,
        maxWidth:              1920,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (image == null || !mounted) return;

      final result = await KtpOcrService.processImage(image);

      if (!mounted) return;

      if (!result.hasData) {
        setState(() => _addError =
            'Teks tidak terdeteksi. Pastikan foto KTP jelas, '
            'tidak buram, dan pencahayaan cukup.');
        return;
      }

      if (result.nik.isNotEmpty)       _nikCtrl.text       = result.nik;
      if (result.name.isNotEmpty)      _nameCtrl.text      = result.name;
      if (result.birthDate.isNotEmpty) _birthDateCtrl.text = result.birthDate;
      if (result.address.isNotEmpty)   _addressCtrl.text   = result.address;
      setState(() => _scanSuccess = true);
    } on Exception catch (e) {
      if (mounted) setState(() => _addError = 'Gagal memindai: $e');
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  void _showScanSourcePicker() {
    showDialog<ImageSource>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Scan KTP'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(ImageSource.camera),
            child: const Row(
              children: [
                Icon(Icons.camera_alt_outlined),
                SizedBox(width: 14),
                Text('Foto Langsung'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(ImageSource.gallery),
            child: const Row(
              children: [
                Icon(Icons.photo_library_outlined),
                SizedBox(width: 14),
                Text('Pilih dari Galeri'),
              ],
            ),
          ),
        ],
      ),
    ).then((source) {
      if (source != null) _scanKtp(source);
    });
  }

  Future<void> _createAndSelect() async {
    final nik  = _nikCtrl.text.trim();
    final name = _nameCtrl.text.trim();

    if (!RegExp(r'^\d{16}$').hasMatch(nik)) {
      setState(() => _addError = 'NIK harus 16 digit angka');
      return;
    }
    if (name.isEmpty) {
      setState(() => _addError = 'Nama tidak boleh kosong');
      return;
    }

    setState(() {
      _isCreating = true;
      _addError   = null;
    });

    try {
      final customer = await ref.read(customersProvider.notifier).create(
            nik:       nik,
            name:      name,
            phone:     _phoneCtrl.text.trim(),
            birthDate: _birthDateCtrl.text.trim(),
            address:   _addressCtrl.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(customer);
    } on Exception catch (e) {
      if (mounted) setState(() => _addError = e.toString());
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          const SizedBox(height: 12),
          // Drag handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          // Header
          _view == _SheetView.search
              ? _buildSearchHeader()
              : _buildAddNewHeader(),
          const Divider(height: 1),
          Expanded(
            child: _view == _SheetView.search
                ? _buildSearchBody(scrollCtrl)
                : _buildAddNewBody(scrollCtrl),
          ),
        ],
      ),
    );
  }

  // ── Search view ─────────────────────────────────────────────────────────────

  Widget _buildSearchHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 20),
                hintText: 'Nama, telepon, atau NIK…',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          TextButton.icon(
            onPressed: () => _switchToAddNew(),
            icon: const Icon(Icons.person_add_outlined, size: 18),
            label: const Text('Baru'),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBody(ScrollController scrollCtrl) {
    final customersAsync = ref.watch(customersProvider);

    return customersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _SearchError(
        error: e,
        onRetry: () => ref.invalidate(customersProvider),
        onAddNew: () => _switchToAddNew(),
      ),
      data: (customers) {
        final filtered = _applyFilter(customers);
        if (filtered.isEmpty) {
          return _EmptySearch(
            query: _query,
            onAddNew: () => _switchToAddNew(prefillName: _query),
          );
        }
        return ListView.builder(
          controller: scrollCtrl,
          itemCount: filtered.length,
          itemBuilder: (_, i) {
            final c          = filtered[i];
            final isSelected = widget.currentCustomer?.id == c.id;
            return ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(c.name),
              subtitle: Text(
                [if (c.phone.isNotEmpty) c.phone, c.maskedNik].join(' · '),
                style: const TextStyle(fontSize: 12),
              ),
              trailing: isSelected
                  ? Icon(Icons.check,
                      color: Theme.of(context).colorScheme.primary)
                  : null,
              onTap: () => Navigator.of(context).pop(c),
            );
          },
        );
      },
    );
  }

  // ── Add new view ────────────────────────────────────────────────────────────

  Widget _buildAddNewHeader() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _view = _SheetView.search),
        ),
        const Text(
          'Tambah Tamu Baru',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildAddNewBody(ScrollController scrollCtrl) {
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      controller: scrollCtrl,
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Scan KTP card ───────────────────────────────────────────────
          _ScanKtpCard(
            isScanning: _isScanning,
            scanSuccess: _scanSuccess,
            onScan: _isScanning ? null : _showScanSourcePicker,
          ),
          const SizedBox(height: 16),

          // ── Status messages ─────────────────────────────────────────────
          if (_scanSuccess && _addError == null) ...[
            _StatusBanner(
              color: const Color(0xFF1B5E20),
              bgColor: const Color(0xFFE8F5E9),
              icon: Icons.check_circle_outline,
              text: 'Data KTP berhasil dibaca. Periksa dan lengkapi jika perlu.',
            ),
            const SizedBox(height: 12),
          ],
          if (_addError != null) ...[
            _StatusBanner(
              color: scheme.onErrorContainer,
              bgColor: scheme.errorContainer,
              icon: Icons.error_outline,
              text: _addError!,
            ),
            const SizedBox(height: 12),
          ],

          // ── Manual fields ───────────────────────────────────────────────
          TextField(
            controller: _nikCtrl,
            decoration: const InputDecoration(
              labelText: 'NIK *',
              hintText: '16 digit nomor KTP',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
            keyboardType: TextInputType.number,
            maxLength: 16,
            onChanged: (_) {
              if (_scanSuccess) setState(() => _scanSuccess = false);
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Nama Lengkap *',
              prefixIcon: Icon(Icons.person_outline),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _birthDateCtrl,
            decoration: const InputDecoration(
              labelText: 'Tanggal Lahir',
              hintText: 'DD-MM-YYYY',
              prefixIcon: Icon(Icons.cake_outlined),
            ),
            keyboardType: TextInputType.datetime,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _addressCtrl,
            decoration: const InputDecoration(
              labelText: 'Alamat',
              hintText: 'Sesuai KTP',
              prefixIcon: Icon(Icons.home_outlined),
              alignLabelWithHint: true,
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phoneCtrl,
            decoration: const InputDecoration(
              labelText: 'No. Telepon',
              hintText: 'Opsional',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: (_isCreating || _isScanning) ? null : _createAndSelect,
            icon: _isCreating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('Simpan & Pilih'),
          ),
        ],
      ),
    );
  }
}

// ── Empty / error states ──────────────────────────────────────────────────────

class _SearchError extends StatelessWidget {
  const _SearchError({
    required this.error,
    required this.onRetry,
    required this.onAddNew,
  });

  final Object error;
  final VoidCallback onRetry;
  final VoidCallback onAddNew;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            const Text(
              'Gagal memuat daftar tamu',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              error.toString(),
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Coba Lagi'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: onAddNew,
                  icon: const Icon(Icons.person_add_outlined, size: 16),
                  label: const Text('Tambah Baru'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySearch extends StatelessWidget {
  const _EmptySearch({required this.query, required this.onAddNew});

  final String query;
  final VoidCallback onAddNew;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 48),
            const SizedBox(height: 12),
            Text(
              query.isEmpty
                  ? 'Belum ada data tamu'
                  : 'Tidak ditemukan: "$query"',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAddNew,
              icon: const Icon(Icons.person_add_outlined, size: 16),
              label: const Text('Tambah Tamu Baru'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Scan KTP card ─────────────────────────────────────────────────────────────

class _ScanKtpCard extends StatelessWidget {
  const _ScanKtpCard({
    required this.isScanning,
    required this.scanSuccess,
    required this.onScan,
  });

  final bool isScanning;
  final bool scanSuccess;
  final VoidCallback? onScan;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scanSuccess
            ? const Color(0xFFE8F5E9)
            : scheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scanSuccess
              ? const Color(0xFF4CAF50)
              : scheme.outlineVariant,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(
            scanSuccess ? Icons.document_scanner : Icons.document_scanner_outlined,
            size: 36,
            color: scanSuccess
                ? const Color(0xFF388E3C)
                : scheme.onSecondaryContainer,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Scan KTP',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: scanSuccess
                        ? const Color(0xFF1B5E20)
                        : scheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  scanSuccess
                      ? 'Data terdeteksi — periksa kolom di bawah'
                      : 'Isi NIK & nama otomatis dari foto KTP',
                  style: TextStyle(
                    fontSize: 12,
                    color: scanSuccess
                        ? const Color(0xFF2E7D32)
                        : scheme.onSecondaryContainer.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isScanning)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            FilledButton.tonal(
              onPressed: onScan,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(scanSuccess ? 'Scan Ulang' : 'Scan'),
            ),
        ],
      ),
    );
  }
}

// ── Generic status banner ─────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.color,
    required this.bgColor,
    required this.icon,
    required this.text,
  });

  final Color color;
  final Color bgColor;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
