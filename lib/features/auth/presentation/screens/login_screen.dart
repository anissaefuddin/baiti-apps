import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(authProvider);
    final isLoading = authAsync.isLoading;
    final error = authAsync.valueOrNull?.error;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),

              // ── Brand ──────────────────────────────────────────────────
              _AppBrand(),

              const Spacer(flex: 2),

              // ── Error banner ───────────────────────────────────────────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: error != null
                    ? _ErrorBanner(
                        key: ValueKey(error.message),
                        error: error,
                        onDismiss: () =>
                            ref.read(authProvider.notifier).clearError(),
                      )
                    : const SizedBox.shrink(),
              ),

              if (error != null) const SizedBox(height: 16),

              // ── Google Sign-In button ──────────────────────────────────
              _GoogleSignInButton(
                isLoading: isLoading,
                onPressed: () => ref.read(authProvider.notifier).signIn(),
              ),

              const SizedBox(height: 16),

              // ── Setup link ─────────────────────────────────────────────
              Center(
                child: TextButton(
                  onPressed: isLoading ? null : () => context.go(AppRoutes.setup),
                  child: Text(
                    'Ubah konfigurasi server',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),

              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Brand widget ──────────────────────────────────────────────────────────────

class _AppBrand extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Icon(
            Icons.hotel_rounded,
            size: 52,
            color: scheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Baiti App',
          style: textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Masuk untuk mengelola penginapan Anda',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ── Google Sign-In button ─────────────────────────────────────────────────────
//
// Follows Google Sign-In branding guidelines:
//   https://developers.google.com/identity/branding-guidelines

class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({
    required this.isLoading,
    required this.onPressed,
  });

  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF3C4043),
          disabledBackgroundColor: Colors.white.withOpacity(0.6),
          side: BorderSide(
            color: isLoading
                ? const Color(0xFFDADCE0).withOpacity(0.5)
                : const Color(0xFFDADCE0),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 0,
        ),
        child: isLoading
            ? const _LoadingRow()
            : const _ButtonContentRow(),
      ),
    );
  }
}

class _ButtonContentRow extends StatelessWidget {
  const _ButtonContentRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _GoogleLogo(),
        SizedBox(width: 12),
        Text(
          'Masuk dengan Google',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Color(0xFF3C4043),
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF4285F4),
          ),
        ),
        SizedBox(width: 12),
        Text(
          'Sedang masuk...',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Color(0xFF9AA0A6),
          ),
        ),
      ],
    );
  }
}

/// Draws the Google "G" logo using the four brand colors.
class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const strokeWidth = 3.5;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Blue arc (top-right, ~200° sweep)
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
      -0.35, // start angle (radians)
      4.4,   // sweep angle
      false,
      paint,
    );

    // Red arc (top-left, small)
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
      -0.35 + 4.4,
      0.9,
      false,
      paint,
    );

    // Horizontal bar of the "G" (blue)
    paint
      ..style = PaintingStyle.stroke
      ..color = const Color(0xFF4285F4);
    canvas.drawLine(
      Offset(center.dx, center.dy),
      Offset(size.width - strokeWidth / 2, center.dy),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Error banner ──────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    super.key,
    required this.error,
    required this.onDismiss,
  });

  final AuthError error;
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _iconForError(error.type),
            color: scheme.onErrorContainer,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  error.title,
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (error.message.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    error.message,
                    style: TextStyle(
                      color: scheme.onErrorContainer.withOpacity(0.85),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: Icon(
              Icons.close,
              color: scheme.onErrorContainer.withOpacity(0.7),
              size: 16,
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForError(AuthErrorType type) {
    return switch (type) {
      AuthErrorType.network => Icons.wifi_off_rounded,
      AuthErrorType.cancelled => Icons.cancel_outlined,
      AuthErrorType.unauthorized => Icons.lock_outline_rounded,
      AuthErrorType.notConfigured => Icons.settings_outlined,
      AuthErrorType.unknown => Icons.error_outline_rounded,
    };
  }
}
