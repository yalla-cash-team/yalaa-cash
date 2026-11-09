import 'package:flutter/material.dart';
import 'package:yalla_cash_admin/src/admin_app.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';

/// The production API every release build talks to. A build can still pin
/// another backend with `--dart-define=YALLA_CASH_API_BASE_URL=...`.
const productionApiBaseUrl = 'https://yalla-cash-api.onrender.com';

/// The API base URL for this build: the explicit define when given,
/// otherwise the production API for release builds. Debug and profile builds
/// keep the platform-aware local default ([YallaCashEnvironment]).
///
/// A release build used to throw here when the define was missing, before
/// any widget existed, which left a blank white screen on the phone.
String resolveAdminApiBaseUrl({
  required String configured,
  required bool releaseMode,
}) {
  final value = configured.trim();
  if (value.isNotEmpty) return value;
  return releaseMode ? productionApiBaseUrl : '';
}

/// Builds the shared runtime for [baseUrl] (empty = local default).
YallaCashRuntime createAdminRuntime(String baseUrl) {
  final environment = baseUrl.isEmpty
      ? YallaCashEnvironment.fromEnvironment(useRemoteBackend: true)
      : YallaCashEnvironment(
          apiBaseUrl: Uri.parse(baseUrl),
          useRemoteBackend: true,
        );
  return YallaCashRuntime.fromEnvironment(environment: environment);
}

/// Runs [initialize] and shows the admin app. If it throws, shows a clear
/// error with a retry button instead of leaving a blank screen. The error is
/// shown, never swallowed.
class AdminStartup extends StatefulWidget {
  const AdminStartup({required this.initialize, super.key});

  final Future<YallaCashRuntime> Function() initialize;

  @override
  State<AdminStartup> createState() => _AdminStartupState();
}

class _AdminStartupState extends State<AdminStartup> {
  YallaCashRuntime? _runtime;
  Object? _error;
  var _attempt = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final attempt = ++_attempt;
    setState(() {
      _runtime = null;
      _error = null;
    });
    try {
      final runtime = await widget.initialize();
      if (!mounted || attempt != _attempt) return;
      setState(() => _runtime = runtime);
    } on Object catch (error, stackTrace) {
      debugPrint('ADMIN STARTUP FAILED: $error\n$stackTrace');
      if (!mounted || attempt != _attempt) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final runtime = _runtime;
    if (runtime != null) return YallaCashAdminApp(runtime: runtime);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'لوحة تحكم يلا كاش',
      theme: buildYallaTheme(Brightness.light),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: Scaffold(
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator(key: Key('startup-loading'))
              : _StartupError(error: _error!, onRetry: _start),
        ),
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: const Key('startup-error'),
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 56, color: scheme.error),
            const SizedBox(height: 16),
            Text(
              'تعذر تشغيل لوحة التحكم',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'حدث خطأ أثناء التهيئة. تحقق من الاتصال بالإنترنت ثم حاول مرة أخرى.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            // The technical reason stays visible so it can be reported.
            SelectableText(
              '$error',
              key: const Key('startup-error-detail'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('startup-retry'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}
