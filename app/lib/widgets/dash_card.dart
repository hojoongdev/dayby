import 'package:flutter/material.dart';

import '../format.dart';
import '../units.dart';

/// The big glanceable card on the dashboard: what a thing was, how long ago, and how
/// far through the usual gap that is. The number is the headline; the bar fills toward
/// the next one and turns warm once it is overdue.
class DashCard extends StatelessWidget {
  const DashCard({
    super.key,
    required this.icon,
    required this.accent,
    required this.detail,
    required this.sinceLabel,
    required this.at,
    this.nextAt,
    this.headlineOverride,
    this.onAdd,
  });

  final IconData icon;
  final Color accent;

  /// What the last one was, e.g. "Formula · 160 ml". Shown small, above the number.
  final String detail;

  /// e.g. "since feeding" — the label under the progress bar.
  final String sinceLabel;

  /// When the last one happened. Null means nothing of this kind is logged yet.
  final DateTime? at;

  /// When the rhythm says the next is due, for the progress bar. Null draws no bar.
  final DateTime? nextAt;

  /// Replaces the "N ago" headline — for a card about something still going, like a
  /// sleep in progress ("1h 35m" asleep, not "1h 35m ago").
  final String? headlineOverride;

  final VoidCallback? onAdd;

  static const _overdue = Color(0xFFE8833A);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final logged = at != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark
            ? const Color(0xFF121821).withValues(alpha: 0.82)
            : Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: dark ? 0.22 : 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 19, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              if (onAdd != null)
                _AddButton(accent: accent, onTap: onAdd!),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            logged ? (headlineOverride ?? formatAgo(at!)) : 'Not logged yet',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: logged
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (logged && nextAt != null) ...[
            const SizedBox(height: 12),
            _bar(context),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(sinceLabel,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const Spacer(),
                Text('~${formatMinutes(nextAt!.difference(at!).inMinutes)}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _bar(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final total = nextAt!.difference(at!).inSeconds;
    final elapsed = now.difference(at!).inSeconds;
    final overdue = now.isAfter(nextAt!);
    final fraction =
        overdue || total <= 0 ? 1.0 : (elapsed / total).clamp(0.0, 1.0);
    final color = overdue ? _overdue : accent;

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: fraction,
        minHeight: 8,
        backgroundColor: (dark ? Colors.white : Colors.black).withValues(alpha: 0.08),
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.accent, required this.onTap});

  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accent.withValues(alpha: 0.16),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(Icons.add, size: 20, color: accent),
        ),
      ),
    );
  }
}
