import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format.dart';
import '../models/family.dart';
import '../models/wrapped.dart';
import '../providers.dart';
import '../tts.dart';
import '../units.dart';
import '../widgets/glass.dart';

/// The keepsake. Everything ever logged for one baby, counted by MongoDB and told
/// back by the model — the story first, because that is what anyone comes here for.
class WrappedScreen extends ConsumerStatefulWidget {
  const WrappedScreen({super.key, required this.baby});

  final Baby baby;

  @override
  ConsumerState<WrappedScreen> createState() => _WrappedScreenState();
}

class _WrappedScreenState extends ConsumerState<WrappedScreen> {
  final Tts _tts = Tts();
  bool _speaking = false;

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _speak(Wrapped wrapped) async {
    if (_speaking) {
      await _tts.stop();
      if (mounted) setState(() => _speaking = false);
      return;
    }
    setState(() => _speaking = true);
    await _tts.speak(wrapped.story, lang: wrapped.lang);
    if (mounted) setState(() => _speaking = false);
  }

  @override
  Widget build(BuildContext context) {
    final wrapped = ref.watch(wrappedProvider(widget.baby.id));
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(widget.baby.name),
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: GlassBackground()),
          SafeArea(
            child: wrapped.when(
              loading: () => _MemoriesLoading(name: widget.baby.name),
              error: (e, _) => Center(child: Text('Could not load: $e')),
              data: (w) => w.stats.isEmpty
                  ? const Center(child: Text('Log a few days first.'))
                  : _content(w),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(Wrapped wrapped) {
    final theme = Theme.of(context);
    final units = ref.watch(unitPrefsProvider);
    final s = wrapped.stats;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (wrapped.story.isNotEmpty)
          GlassCard(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  wrapped.story,
                  style: theme.textTheme.titleMedium?.copyWith(height: 1.6),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: _speaking ? 'Stop' : 'Read aloud',
                    onPressed: () => _speak(wrapped),
                    icon: Icon(_speaking
                        ? Icons.stop_circle_outlined
                        : Icons.volume_up),
                  ),
                ),
              ],
            ),
          ),
        Row(
          children: [
            _Big(value: formatCount(s.daysTracked), label: 'days tracked'),
            const SizedBox(width: 12),
            _Big(value: formatCount(s.diapers), label: 'diapers changed'),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _Big(
              value: formatCount(s.feedings),
              label: 'feedings',
              footnote: s.totalFeedMl > 0
                  ? formatTotalVolume(s.totalFeedMl, units)
                  : null,
            ),
            const SizedBox(width: 12),
            _Big(
              value: formatCount(s.nightFeeds),
              label: 'night feeds',
              footnote: 'before 5am',
            ),
          ],
        ),
        if (s.hasGrowth) ...[
          const SizedBox(height: 12),
          _Card(
            title: 'How much bigger',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (s.firstWeightKg != null && s.lastWeightKg != null)
                  _Journey(
                    icon: Icons.monitor_weight_outlined,
                    from: formatField('weight_kg', s.firstWeightKg, units),
                    to: formatField('weight_kg', s.lastWeightKg, units),
                  ),
                if (s.firstHeightCm != null && s.lastHeightCm != null)
                  _Journey(
                    icon: Icons.height_outlined,
                    from: formatField('height_cm', s.firstHeightCm, units),
                    to: formatField('height_cm', s.lastHeightCm, units),
                  ),
              ],
            ),
          ),
        ],
        if (s.busiestDay != null) ...[
          const SizedBox(height: 12),
          _Card(
            title: 'The longest day',
            child: Text(
              '${formatDate(DateTime.parse(s.busiestDay!))}'
              ' · ${formatCount(s.busiestDayEvents)} logs',
              style: theme.textTheme.titleMedium,
            ),
          ),
        ],
        if (s.milestones.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Card(
            title: 'Firsts',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final m in s.milestones)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(child: Text(m.text ?? 'milestone')),
                        Text(
                          formatDate(m.time),
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (s.spend.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Card(
            title: 'What it cost',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final spend in s.spend)
                  Text(
                    '${formatMoney(formatCount(spend.total), spend.currency)}'
                    ' · ${formatCount(spend.count)} purchases',
                    style: theme.textTheme.titleMedium,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Big extends StatelessWidget {
  const _Big({required this.value, required this.label, this.footnote});

  final String value;
  final String label;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: theme.textTheme.displaySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: theme.textTheme.bodyMedium),
            if (footnote != null)
              Text(
                footnote!,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _Journey extends StatelessWidget {
  const _Journey({required this.icon, required this.from, required this.to});

  final IconData icon;
  final String from;
  final String to;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Text(from, style: theme.textTheme.titleMedium),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.arrow_forward,
                size: 16, color: theme.colorScheme.onSurfaceVariant),
          ),
          Text(
            to,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// The story is one aggregation plus a model write, a few seconds either way. A bare
/// spinner reads as a stall; this frames the wait as what it is -- looking back.
class _MemoriesLoading extends StatelessWidget {
  const _MemoriesLoading({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 34,
              width: 34,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: theme.colorScheme.primary.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Looking back through your days with $name…',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Gathering every feed, nap and little first.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
