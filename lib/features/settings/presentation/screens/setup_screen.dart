import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/services/backend_status_service.dart';
import '../../../../core/storage/local_storage.dart';

/// App-level constants — used in the About section and for display elsewhere.
abstract class AppInfo {
  static const appName   = 'Baiti App';
  static const version   = '1.1.0';
  static const buildCode = '2';
  static const developer = 'maloka.app';
  static const copyright = '© 2026 maloka.app. All rights reserved.';
  static const packageId = 'app.maloka.catat';
  static const tagline   = 'Manajemen penginapan sederhana & cepat';
}

/// Configuration + About screen.
///
/// Used in two contexts:
///  - First-time setup (via splash — no back stack, saves → /login)
///  - Settings from dashboard (pushed → back button appears, saves → pop)
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _formKey            = GlobalKey<FormState>();
  final _urlController      = TextEditingController();
  final _calendarController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final storage            = ref.read(localStorageProvider);
    _urlController.text      = storage.scriptUrl ?? '';
    _calendarController.text = storage.calendarId ?? '';
  }

  @override
  void dispose() {
    _urlController.dispose();
    _calendarController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final storage = ref.read(localStorageProvider);
    await storage.saveScriptUrl(_urlController.text.trim());
    await storage.saveCalendarId(_calendarController.text.trim());

    if (!mounted) return;
    setState(() => _saving = false);

    // Pushed from dashboard → go back. First-time setup → proceed to login.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        // automaticallyImplyLeading shows the back arrow when this screen
        // was pushed onto the navigation stack (e.g. from dashboard).
        title: const Text('Pengaturan'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [

            // ── Konfigurasi Server ───────────────────────────────────────
            const _SectionLabel('Konfigurasi Server'),
            const SizedBox(height: 12),
            Text(
              'Masukkan URL Google Apps Script Web App Anda. '
              'Data tersimpan di perangkat dan tidak dikirim ke pihak ketiga.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 20),

            TextFormField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Apps Script Web App URL *',
                hintText: 'https://script.google.com/macros/s/...',
                prefixIcon: Icon(Icons.link),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              onChanged: (_) => ref.read(backendStatusProvider.notifier).reset(),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'URL wajib diisi';
                final uri = Uri.tryParse(v.trim());
                if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
                  return 'URL tidak valid';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            _BackendStatusCard(urlController: _urlController),
            const SizedBox(height: 12),

            TextFormField(
              controller: _calendarController,
              decoration: const InputDecoration(
                labelText: 'Google Calendar ID (opsional)',
                hintText: 'xxx@group.calendar.google.com',
                prefixIcon: Icon(Icons.calendar_today),
              ),
              autocorrect: false,
            ),
            const SizedBox(height: 8),
            Text(
              'Gunakan "primary" untuk kalender utama akun Google Anda.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 28),

            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Simpan'),
            ),

            const SizedBox(height: 40),
            const Divider(),
            const SizedBox(height: 8),

            // ── Tentang Aplikasi ─────────────────────────────────────────
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.info_outline, color: scheme.onSurfaceVariant),
              title: const Text('Tentang Aplikasi'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(AppRoutes.about),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'v${AppInfo.version} (${AppInfo.buildCode})',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant.withOpacity(0.6),
                    ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ── Backend status card ───────────────────────────────────────────────────────

class _BackendStatusCard extends ConsumerWidget {
  const _BackendStatusCard({required this.urlController});
  final TextEditingController urlController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(backendStatusProvider);
    final scheme = Theme.of(context).colorScheme;
    final isChecking = status.status == BackendStatusCode.checking;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          _StatusDot(status.status),
          const SizedBox(width: 12),
          Expanded(
            child: _StatusText(status),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: isChecking
                ? null
                : () {
                    final url = urlController.text.trim();
                    if (url.isEmpty) return;
                    ref.read(backendStatusProvider.notifier).check(url);
                  },
            child: isChecking
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Cek', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot(this.code);
  final BackendStatusCode code;

  @override
  Widget build(BuildContext context) {
    final color = switch (code) {
      BackendStatusCode.active   => Colors.green,
      BackendStatusCode.inactive => Colors.red,
      BackendStatusCode.checking => Colors.orange,
      BackendStatusCode.idle     => Colors.grey,
    };
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText(this.status);
  final BackendStatus status;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return switch (status.status) {
      BackendStatusCode.idle => Text(
          'Tekan "Cek" untuk verifikasi koneksi',
          style: textTheme.bodySmall?.copyWith(color: muted),
        ),
      BackendStatusCode.checking => Text(
          'Memeriksa koneksi…',
          style: textTheme.bodySmall?.copyWith(color: muted),
        ),
      BackendStatusCode.active => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Server aktif',
              style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              'HTTP ${status.httpCode} · ${status.responseTime} ms',
              style: textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      BackendStatusCode.inactive => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Server tidak dapat dijangkau',
              style: textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.red,
              ),
            ),
            if (status.error != null)
              Text(
                status.error!,
                style: textTheme.bodySmall?.copyWith(color: muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            else
              Text(
                'HTTP ${status.httpCode}',
                style: textTheme.bodySmall?.copyWith(color: muted),
              ),
          ],
        ),
    };
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      );
}

