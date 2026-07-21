import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format.dart';
import '../models/insights.dart';
import '../providers.dart';
import 'glass.dart';

/// Looking forward and back, under the assistant's "right now" card: the next feed and
/// diaper the baby's rhythm points to, and one or two trends across the week.
class InsightsCard extends ConsumerWidget {
  const InsightsCard({super.key, required this.babyId});

  final String babyId;

  static const _labels = {
    'feeding': 'Next feeding',
    'diaper': 'Next diaper',
    'sleep': 'Next sleep',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(insightsProvider(babyId)).value;
    // A bonus surface: nothing to say (or still loading) means no card at all.
    if (insights == null || insights.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_outlined,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Insights', style: theme.textTheme.labelLarge),
            ],
          ),
          for (final p in insights.predictions) ...[
            const SizedBox(height: 10),
            _prediction(theme, p),
          ],
          for (final observation in insights.observations)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(observation, style: theme.textTheme.bodyMedium),
            ),
        ],
      ),
    );
  }

  Widget _prediction(ThemeData theme, Prediction p) {
    final soon = !p.at.isAfter(DateTime.now());
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(_labels[p.type] ?? 'Next ${p.type}',
              style: theme.textTheme.bodyLarge),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(soon ? 'about now' : formatClock(p.at),
                style: theme.textTheme.titleMedium),
            Text(p.basis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }
}
