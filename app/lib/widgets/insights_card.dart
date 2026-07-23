import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'glass.dart';

/// The week's trends, written by the model from the day tally ("night feeds are down to
/// about one"). The next-up predictions moved onto the cards above, so this card is just
/// the "this week" observations. Nothing to say means no card.
class InsightsCard extends ConsumerWidget {
  const InsightsCard({super.key, required this.babyId});

  final String babyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final observations =
        ref.watch(insightsProvider(babyId)).value?.observations ?? const <String>[];
    if (observations.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_outlined, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('This week', style: theme.textTheme.labelLarge),
            ],
          ),
          for (final observation in observations)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(observation, style: theme.textTheme.bodyMedium),
            ),
        ],
      ),
    );
  }
}
