import 'package:flutter/material.dart';
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

/// The gradient, the glass and the charts each carry their own dark values already.
/// This is only the Material half: the colours everything else is drawn from.
ThemeData _theme(Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6C8EBF),
        brightness: brightness,
      ),
      useMaterial3: true,
    );

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
                const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
