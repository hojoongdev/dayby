import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../providers.dart';
import '../widgets/glass.dart';

/// Sign in. Which provider is behind this is the server's business — the app only
/// gets a token from it and hands it over, and the server is the one that checks it.
///
/// With AUTH_PROVIDER=mock the token is simply the email you claim to be, so the
/// whole session flow runs with no keys and no Google project.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key, required this.provider});

  final String provider;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  // Password provider only: whether the button makes an account or signs in to one.
  bool _createMode = false;
  String? _error;

  bool get _google => widget.provider == 'google';
  bool get _isPassword => widget.provider == 'password';

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn(Future<String?> Function() token) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final providerToken = await token();
      // Backed out of the Google sheet, or an empty box: not an error, just not
      // signed in.
      if (providerToken == null || providerToken.isEmpty) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      await ref.read(sessionProvider.notifier).signIn(providerToken);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyError(e);
      });
    }
  }

  /// Password provider: make an account or sign in to one, depending on the mode.
  Future<void> _submitPassword() async {
    if (_busy) return;
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = ref.read(sessionProvider.notifier);
      if (_createMode) {
        await session.signUp(email, password);
      } else {
        await session.signInWithPassword(email, password);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: GlassBackground()),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: GlassCard(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Dayby', style: theme.textTheme.headlineMedium),
                      const SizedBox(height: 4),
                      Text(
                        _createMode
                            ? 'Create an account to keep your logs across devices.'
                            : 'Sign in to keep your logs across devices.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 24),
                      if (_google)
                        ..._googleSection(theme)
                      else if (_isPassword)
                        ..._passwordSection(theme)
                      else
                        ..._emailSection(theme),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(_error!,
                              style: TextStyle(color: theme.colorScheme.error)),
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

  List<Widget> _googleSection(ThemeData theme) {
    final google = ref.read(googleIdentityProvider);
    if (!google.isAvailable) {
      return [
        Text(
          'This server signs in with Google, but this build was not given a client '
          'id. Rebuild with --dart-define=GOOGLE_CLIENT_ID=… (the same client the '
          'server verifies against), on iOS or Android.',
          style: theme.textTheme.bodyMedium,
        ),
      ];
    }
    return [
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _busy ? null : () => _signIn(google.idToken),
          icon: _busy ? _spinner() : const Icon(Icons.g_mobiledata, size: 28),
          label: const Text('Continue with Google'),
        ),
      ),
    ];
  }

  List<Widget> _passwordSection(ThemeData theme) {
    return [
      TextField(
        controller: _email,
        enabled: !_busy,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Email',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _password,
        enabled: !_busy,
        obscureText: true,
        autofillHints: const [AutofillHints.password],
        onSubmitted: (_) => _submitPassword(),
        decoration: InputDecoration(
          labelText: 'Password',
          helperText: _createMode ? 'At least 8 characters' : null,
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _busy ? null : _submitPassword,
          child: _busy
              ? _spinner()
              : Text(_createMode ? 'Create account' : 'Sign in'),
        ),
      ),
      TextButton(
        onPressed: _busy
            ? null
            : () => setState(() {
                  _createMode = !_createMode;
                  _error = null;
                }),
        child: Text(_createMode
            ? 'Already have an account? Sign in'
            : "New here? Create an account"),
      ),
    ];
  }

  List<Widget> _emailSection(ThemeData theme) {
    return [
      TextField(
        controller: _email,
        enabled: !_busy,
        keyboardType: TextInputType.emailAddress,
        autofocus: true,
        onSubmitted: (_) => _signIn(() async => _email.text.trim()),
        decoration: const InputDecoration(
          labelText: 'Email',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _busy ? null : () => _signIn(() async => _email.text.trim()),
          child: _busy ? _spinner() : const Text('Continue'),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          'Development sign-in: any email works, and signing in with the same one '
          'twice is the same account.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    ];
  }

  Widget _spinner() => const SizedBox(
        height: 18,
        width: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
}
