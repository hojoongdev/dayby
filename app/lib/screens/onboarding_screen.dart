import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../format.dart';
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
  final _yourName = TextEditingController();
  final _server = TextEditingController();
  final _inviteCode = TextEditingController();
  // null = the caregiver has not chosen yet; then "create" or "join".
  String? _mode;
  String? _relation;
  DateTime? _birthdate;
  String? _sex;
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
    _yourName.dispose();
    _server.dispose();
    _inviteCode.dispose();
    super.dispose();
  }

  Future<void> _useServer() =>
      ref.read(serverUrlProvider.notifier).set(_server.text);

  /// With no login, register this device's caregiver so its records are stamped with a
  /// name/relation. When signed in, the account is already the author, so skip it.
  Future<void> _registerCaregiver(ApiClient api) async {
    if (ref.read(sessionProvider).value != null) return;
    final name = _yourName.text.trim();
    final display = name.isEmpty ? (_relation ?? 'Me') : name;
    final me = await api.addCaregiver(display, relation: _relation);
    api.setCaregiverId(me.id);
    await ref.read(sharedPrefsProvider).setString(caregiverIdKey, me.id);
  }

  String? _missing() {
    final missing = [
      if (_familyName.text.trim().isEmpty) 'a family name',
      if (_relation == null) 'whether you are Dad or Mum',
      if (_babyName.text.trim().isEmpty) "your baby's name",
      if (_birthdate == null) "your baby's birthday",
      if (_sex == null) "your baby's sex",
    ];
    return missing.isEmpty ? null : 'Please add ${missing.join(', ')}.';
  }

  Future<void> _submit() async {
    final missing = _missing();
    if (missing != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(missing)));
      return;
    }
    setState(() => _saving = true);
    try {
      await _useServer();
      final api = ref.read(apiClientProvider);
      final family = await api.createFamily(_familyName.text.trim());
      api.setFamilyId(family.id);
      await _registerCaregiver(api);
      final baby = await api.addBaby(
        name: _babyName.text.trim(),
        birthdate: _birthdate,
        sex: _sex,
      );
      await _remember(family);
      await ref.read(selectedBabyIdProvider.notifier).set(baby.id);
      await ref.read(familyIdProvider.notifier).set(family.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create your family: ${friendlyError(e)}')),
      );
    }
  }

  Future<void> _remember(Family family) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setString(familyNameKey, family.name);
    await prefs.setString(inviteCodeKey, family.inviteCode);
    ref.read(sessionProvider.notifier).joinedFamily(family.id);
  }

  /// The second caregiver joins the family that is already there rather than starting
  /// another one. They still register themselves (Dad/Mum) so their logs are stamped.
  Future<void> _join() async {
    if (_relation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('First pick whether you are Dad or Mum.')),
      );
      return;
    }
    final code = _inviteCode.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the invite code your family shared.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _useServer();
      final api = ref.read(apiClientProvider);
      final family = await api.joinFamily(code);
      api.setFamilyId(family.id);
      await _registerCaregiver(api);
      await _remember(family);
      await ref.read(familyIdProvider.notifier).set(family.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _pickBirthdate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthdate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      helpText: "Baby's birthday",
    );
    if (picked != null) setState(() => _birthdate = picked);
  }

  Widget get _spinner => const SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );

  Widget _back() => TextButton(
        onPressed: _saving ? null : () => setState(() => _mode = null),
        child: const Text('Back'),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // "You" is asked either way, so both a new family and a join can stamp who logs what.
    // Joining only needs Dad/Mum; starting a new family also takes a display name.
    final relationBlock = <Widget>[
      _Label('You', theme),
      const SizedBox(height: 8),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'Dad', label: Text('Dad')),
          ButtonSegment(value: 'Mum', label: Text('Mum')),
          ButtonSegment(value: 'Other', label: Text('Other')),
        ],
        emptySelectionAllowed: true,
        selected: {?_relation},
        onSelectionChanged: (s) =>
            setState(() => _relation = s.isEmpty ? null : s.first),
      ),
    ];
    final youBlock = <Widget>[
      ...relationBlock,
      const SizedBox(height: 12),
      TextField(
        controller: _yourName,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'Your name (optional)',
          hintText: 'Shown on what you log',
        ),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Welcome to Dayby', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    switch (_mode) {
                      'create' => 'Set up your family to start logging.',
                      'join' => 'Join a family with the code they shared.',
                      _ => 'Start a new family, or join one you were invited to.',
                    },
                    style: theme.textTheme.bodyMedium,
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
                  const SizedBox(height: 20),
                  if (_mode == null) ...[
                    FilledButton.icon(
                      onPressed: () => setState(() => _mode = 'create'),
                      icon: const Icon(Icons.add_home_outlined),
                      label: const Text('Start a new family'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _mode = 'join'),
                      icon: const Icon(Icons.group_add_outlined),
                      label: const Text('Join with an invite code'),
                    ),
                  ],
                  if (_mode == 'create') ...[
                    TextField(
                      controller: _familyName,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Family name',
                        hintText: 'The Kim family',
                      ),
                    ),
                    const SizedBox(height: 20),
                    ...youBlock,
                    const SizedBox(height: 20),
                    _Label('Baby', theme),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _babyName,
                      decoration: const InputDecoration(labelText: "Baby's name"),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _pickBirthdate,
                      icon: const Icon(Icons.cake_outlined),
                      label: Text(
                          _birthdate == null ? 'Birthday' : formatDate(_birthdate!)),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'female', label: Text('Girl')),
                        ButtonSegment(value: 'male', label: Text('Boy')),
                      ],
                      emptySelectionAllowed: true,
                      selected: {?_sex},
                      onSelectionChanged: (s) =>
                          setState(() => _sex = s.isEmpty ? null : s.first),
                    ),
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: _saving ? null : _submit,
                      child: _saving ? _spinner : const Text('Get started'),
                    ),
                    _back(),
                  ],
                  if (_mode == 'join') ...[
                    ...relationBlock,
                    const SizedBox(height: 16),
                    TextField(
                      controller: _inviteCode,
                      autocorrect: false,
                      textCapitalization: TextCapitalization.none,
                      decoration: const InputDecoration(
                        labelText: 'Invite code',
                        hintText: 'The 6-character code they shared',
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _saving ? null : _join,
                      child: _saving ? _spinner : const Text('Join family'),
                    ),
                    _back(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, this.theme);

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Text(text,
            style: theme.textTheme.labelLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      );
}

