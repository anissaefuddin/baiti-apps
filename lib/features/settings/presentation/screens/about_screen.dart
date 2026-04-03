import 'package:flutter/material.dart';

import 'setup_screen.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Tentang Aplikasi')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // ── Identity block ──────────────────────────────────────────────
          Center(
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.home_work_rounded,
                    color: scheme.onPrimary,
                    size: 42,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  AppInfo.appName,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  AppInfo.tagline,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'v${AppInfo.version} (build ${AppInfo.buildCode})',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
          Divider(color: scheme.outlineVariant),
          const SizedBox(height: 8),

          // ── Info rows ───────────────────────────────────────────────────
          const _InfoRow(
            icon: Icons.business_outlined,
            label: 'Pengembang',
            value: AppInfo.developer,
          ),
          Divider(height: 1, indent: 56, color: scheme.outlineVariant),
          const _InfoRow(
            icon: Icons.inventory_2_outlined,
            label: 'Package ID',
            value: AppInfo.packageId,
          ),
          Divider(height: 1, indent: 56, color: scheme.outlineVariant),
          const _InfoRow(
            icon: Icons.copyright_outlined,
            label: 'Hak Cipta',
            value: AppInfo.copyright,
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 20),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
