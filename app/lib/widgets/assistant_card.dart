import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tip.dart';
import '../providers.dart';
import '../tts.dart';
import 'glass.dart';

/// What the assistant says before being asked: an overdue nudge, a reminder of
/// what is coming up, a tip for the baby's age.
///
/// Every line is written server-side in the caregiver's own language, so there is
/// no copy to render here — only the lines and a button to hear them.
class AssistantCard extends ConsumerStatefulWidget {
  const AssistantCard({super.key, required this.babyId});

  final String babyId;

  @override
  ConsumerState<AssistantCard> createState() => _AssistantCardState();
}

class _AssistantCardState extends ConsumerState<AssistantCard> {
  final Tts _tts = Tts();
  bool _speaking = false;

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _speak(AssistantTips tips) async {
    if (_speaking) {
      await _tts.stop();
      if (mounted) setState(() => _speaking = false);
      return;
    }
    setState(() => _speaking = true);
    await _tts.speak(tips.tips.map((t) => t.text).join(' '), lang: tips.lang);
    if (mounted) setState(() => _speaking = false);
  }

  @override
  Widget build(BuildContext context) {
    final tips = ref.watch(tipsProvider(widget.babyId));
    return tips.when(
      loading: () => const _Shell(child: _Waiting()),
      // Tips are a bonus surface: if the model or the network is having a bad day,
      // the card just isn't there.
      error: (_, _) => const SizedBox.shrink(),
      data: (t) => t.tips.isEmpty ? const SizedBox.shrink() : _card(context, t),
    );
  }

  Widget _card(BuildContext context, AssistantTips tips) {
    return _Shell(
      trailing: IconButton(
        tooltip: _speaking ? 'Stop' : 'Read aloud',
        onPressed: () => _speak(tips),
        icon: Icon(_speaking ? Icons.stop_circle_outlined : Icons.volume_up),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final tip in tips.tips) _TipLine(tip: tip),
        ],
      ),
    );
  }
}

/// The glass card and its header, shared by the loading and loaded states so the
/// card does not jump when the tips arrive.
class _Shell extends StatelessWidget {
  const _Shell({required this.child, this.trailing});

  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Assistant',
                  style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              ?trailing,
            ],
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        height: 18,
        width: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

class _TipLine extends StatelessWidget {
  const _TipLine({required this.tip});

  final Tip tip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A nudge is about right now, so it gets the accent colour; a tip is context.
    final color =
        tip.isNudge ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              tip.isNudge
                  ? Icons.notifications_active_outlined
                  : Icons.lightbulb_outline,
              size: 18,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tip.text,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.35,
                fontWeight: tip.isNudge ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
