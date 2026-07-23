import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../models/family.dart';
import '../providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _familyName = TextEditingController();
  final _babyName = TextEditingController();
  final _server = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill with whatever the build baked in; the caregiver can point it at their
    // own server (local, AWS, anywhere) before anything is created.
    _server.text = ref.read(serverUrlProvider);
  }

  @override
  void dispose() {
    _familyName.dispose();
    _babyName.dispose();
    _server.dispose();
    super.dispose();
  }

  /// Save the server address so every client rebuilds against it before the first call.
  Future<void> _useServer() =>
      ref.read(serverUrlProvider.notifier).set(_server.text);

  Future<void> _submit() async {
    final familyName = _familyName.text.trim();
    final babyName = _babyName.text.trim();
    if (familyName.isEmpty || babyName.isEmpty) return;

    setState(() => _saving = true);
    try {
      await _useServer();
      final api = ref.read(apiClientProvider);
      final family = await api.createFamily(familyName);
      api.setFamilyId(family.id);
      final baby = await api.addBaby(name: babyName);
      await _remember(family);
      await ref.read(selectedBabyIdProvider.notifier).set(baby.id);
      await ref.read(familyIdProvider.notifier).set(family.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create your family: $e')),
      );
    }
  }

  Future<void> _remember(Family family) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setString(familyNameKey, family.name);
    await prefs.setString(inviteCodeKey, family.inviteCode);
    ref.read(sessionProvider.notifier).joinedFamily(family.id);
  }

  /// The other half of the invite code: the second parent joins the family that is
  /// already there, rather than starting a second one.
  Future<void> _join() async {
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => _InviteCodeDialog(),
    );
    if (code == null || code.isEmpty || !mounted) return;

    setState(() => _saving = true);
    try {
      await _useServer();
      final api = ref.read(apiClientProvider);
      final family = await api.joinFamily(code);
      api.setFamilyId(family.id);
      await _remember(family);
      await ref.read(familyIdProvider.notifier).set(family.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Welcome to Dayby',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create your family to start logging.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _server,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Server address',
                      hintText: 'http://192.168.0.10:8000',
                      helperText: 'Your Dayby server — run it yourself, anywhere.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _familyName,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Family name',
                      hintText: 'The Kim family',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _babyName,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(labelText: "Baby's name"),
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _saving ? null : _submit,
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Get started'),
                  ),
                  if (ref.watch(sessionProvider).value != null)
                    TextButton(
                      onPressed: _saving ? null : _join,
                      child: const Text('Join with an invite code'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InviteCodeDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final code = TextEditingController();
    return AlertDialog(
      title: const Text('Join a family'),
      content: TextField(
        controller: code,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Invite code'),
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, code.text.trim()),
          child: const Text('Join'),
        ),
      ],
    );
  }
}
