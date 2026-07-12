import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../widgets/glass.dart';

/// What stands between whoever is holding the phone and a record of a child's
/// every feed, illness and photograph.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  bool _asking = false;
  bool _refused = false;

  @override
  void initState() {
    super.initState();
    // Ask straight away: nobody wants to tap a button to be allowed to tap a button.
    WidgetsBinding.instance.addPostFrameCallback((_) => _ask());
  }

  Future<void> _ask() async {
    if (_asking) return;
    setState(() {
      _asking = true;
      _refused = false;
    });

    final ok = await ref.read(appLockProvider).unlock();
    if (!mounted) return;

    if (ok) {
      ref.read(unlockedProvider.notifier).unlock();
    } else {
      setState(() {
        _asking = false;
        _refused = true;
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
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline,
                      size: 40, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text('Dayby is locked', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 20),
                  if (_asking)
                    const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _ask,
                      icon: const Icon(Icons.fingerprint),
                      label: Text(_refused ? 'Try again' : 'Unlock'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
