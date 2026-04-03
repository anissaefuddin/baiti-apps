import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/storage/local_storage.dart';
import '../providers/auth_provider.dart';

/// Entry screen shown briefly on every cold start while the session is resolved.
///
/// Navigation outcomes:
///   /setup      → Apps Script URL has never been configured
///   /login      → no valid cached session
///   /dashboard  → cached session found (auto-login)
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();

    _fadeAnim = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );

    _resolve();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _resolve() async {
    // Minimum splash display time — lets the animation play at least once.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    // Check setup before auth — unconfigured app should never reach login.
    final storage = ref.read(localStorageProvider);
    if (!storage.isConfigured) {
      context.go('/setup');
      return;
    }

    // `authProvider.future` properly awaits the AsyncNotifier's build() method.
    // Using ref.read(authProvider) would race against loading state and do nothing.
    try {
      final authState = await ref.read(authProvider.future);
      if (!mounted) return;

      if (authState.isAuthenticated) {
        context.go('/dashboard');
      } else {
        context.go('/login');
      }
    } catch (_) {
      // build() threw — treat as unauthenticated.
      if (mounted) context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: scheme.primary,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App icon
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: scheme.onPrimary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  Icons.hotel_rounded,
                  size: 56,
                  color: scheme.onPrimary,
                ),
              ),
              const SizedBox(height: 24),

              // App name
              Text(
                'Catat App',
                style: textTheme.headlineMedium?.copyWith(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Manajemen Penginapan',
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onPrimary.withOpacity(0.75),
                ),
              ),

              const SizedBox(height: 64),

              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: scheme.onPrimary.withOpacity(0.7),
                  strokeWidth: 2.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
