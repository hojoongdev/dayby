import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth.dart';
import 'providers.dart';
import 'screens/home_screen.dart';
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C8EBF)),
        useMaterial3: true,
      ),
      home: const _Entry(),
    );
  }
}

/// Three questions, in order: does this server want a sign-in, are we signed in,
/// and do we have a family yet.
class _Entry extends ConsumerWidget {
  const _Entry();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: GlassBackground()),
          Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
