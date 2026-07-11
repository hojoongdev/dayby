import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _familyName = TextEditingController();
  final _babyName = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _familyName.dispose();
    _babyName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final familyName = _familyName.text.trim();
    final babyName = _babyName.text.trim();
    if (familyName.isEmpty || babyName.isEmpty) return;

    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      final family = await api.createFamily(familyName);
      api.setFamilyId(family.id);
      await api.addBaby(name: babyName);
      await ref.read(familyIdProvider.notifier).set(family.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create your family: $e')),
      );
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
