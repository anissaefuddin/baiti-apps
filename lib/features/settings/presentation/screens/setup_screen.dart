import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/storage/local_storage.dart';

/// App-level constants — used in the About section and for display elsewhere.
abstract class AppInfo {
  static const appName   = 'Baiti App';
  static const version   = '1.0.0';
  static const buildCode = '1';
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
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'URL wajib diisi';
                final uri = Uri.tryParse(v.trim());
                if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
                  return 'URL tidak valid';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

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
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
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

