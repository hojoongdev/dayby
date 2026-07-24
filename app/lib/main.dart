import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth.dart';
import 'providers.dart';
import 'screens/home_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/signin_screen.dart';
import 'widgets/glass.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Phone, portrait only. The dashboard is laid out for one column held upright.
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const DaybyApp(),
    ),
  );
}

class DaybyApp extends ConsumerWidget {
  const DaybyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Dayby',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      home: const _Entry(),
    );
  }
}

/// The background, the glass and the charts each carry their own dark values already.
/// This is only the Material half: the colours everything else is drawn from.
///
/// Dark is true black, for OLED: the background paints #000 and the scaffold matches,
/// so unlit pixels stay off. The glass panels are the only thing that lifts.
ThemeData _theme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF6C8EBF),
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? Colors.black : const Color(0xFFF4F6FA),
    useMaterial3: true,
    // Bars sit on the glass, not on a Material tint. Keep them clear so nothing
    // opaque shows through the frost.
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
  );
}

/// Four questions, in order: is the phone allowed to show this at all, does this
/// server want a sign-in, are we signed in, and do we have a family yet.
class _Entry extends ConsumerStatefulWidget {
  const _Entry();

  @override
  ConsumerState<_Entry> createState() => _EntryState();
}

class _EntryState extends ConsumerState<_Entry> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Locked again the moment it leaves the screen. An app lock that survives the
    // app switcher is not a lock.
    if (state != AppLifecycleState.resumed) {
      ref.read(unlockedProvider.notifier).lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(appLockEnabledProvider) && !ref.watch(unlockedProvider)) {
      return const LockScreen();
    }

    final config = ref.watch(authConfigProvider);
    final session = ref.watch(sessionProvider);

    // The server did not answer -- a wrong address, or off the same network. Offer to fix
    // the address instead of spinning on the splash forever.
    if (config.hasError) return const _ServerUnreachable();

    // Deciding before the server has answered would flash the wrong screen.
    if (config.isLoading || session.isLoading) return const _Splash();

    final auth = config.value ?? const AuthConfig();
    if (auth.enabled && session.value == null) {
      return SignInScreen(provider: auth.provider);
    }
    return ref.watch(familyIdProvider) == null
        ? const OnboardingScreen()
        : const HomeScreen();
  }
}

/// The same gradient and the same wordmark as the iOS launch screen, in the same place.
/// Flutter takes over without anything moving: the spinner simply arrives underneath.
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: GlassBackground()),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Dayby',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w300,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 40),
                // Fade the spinner in so it does not pop over the native launch screen,
                // which shows the wordmark alone. Muted, to sit quietly on the gradient.
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 500),
                  builder: (context, t, child) => Opacity(opacity: t, child: child),
                  child: SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when the server does not answer -- almost always a stale address after the
/// laptop's IP moved, or the phone dropping off the network. Lets them fix the address
/// in place, without resetting the app and losing the family.
class _ServerUnreachable extends ConsumerStatefulWidget {
  const _ServerUnreachable();

  @override
  ConsumerState<_ServerUnreachable> createState() => _ServerUnreachableState();
}

class _ServerUnreachableState extends ConsumerState<_ServerUnreachable> {
  late final TextEditingController _server =
      TextEditingController(text: ref.read(serverUrlProvider));
  bool _retrying = false;

  @override
  void dispose() {
    _server.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    setState(() => _retrying = true);
    await ref.read(serverUrlProvider.notifier).set(_server.text.trim());
    // The api client watches the URL, so this refetches against the new address.
    ref.invalidate(authConfigProvider);
    ref.invalidate(sessionProvider);
    if (mounted) setState(() => _retrying = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: GlassBackground()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.cloud_off_outlined,
                          size: 44, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(height: 16),
                      Text("Can't reach your server",
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text(
                        'Check the address below, and that this device is on the same '
                        'network as the server.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _server,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Server address',
                          hintText: '192.168.0.10',
                          helperText: 'Just the IP is enough — port 8000 is assumed.',
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _retrying ? null : _retry,
                        child: _retrying
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Save and retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
