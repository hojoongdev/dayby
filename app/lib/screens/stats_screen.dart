import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../charts/palette.dart';
import '../models/stats.dart';
import '../providers.dart';
import '../units.dart';
import '../widgets/glass.dart';
import '../widgets/rhythm.dart';

/// The charts, and the numbers they are drawn from.
///
/// Two rules run through all of it. Never two scales on one chart: millilitres and a count
/// of feeds are different things, and drawing them against each other invents a
/// relationship that is not there. And every figure is written as well as painted — some of
/// these hues sit below the contrast a chart is meant to clear on a surface this pale, and
/// the price of using them is that the number has to be legible without them.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baby = ref.watch(activeBabyProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Stats'),
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: GlassBackground()),
          SafeArea(
            child: baby == null
                ? const _Nothing('Add a baby to see how the days are going.')
                : ref.watch(statsProvider(baby.id)).when(
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (e, _) => _Nothing('Could not load the charts.\n$e'),
                      data: (stats) => stats.isEmpty
                          ? const _Nothing(
                              'Nothing logged yet. Charts need a few days to say anything.')
                          : _Charts(stats),
                    ),
          ),
        ],
      ),
    );
  }
}

class _Charts extends ConsumerWidget {
  const _Charts(this.stats);

  final Stats stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(unitPrefsProvider);
    final days = stats.days;
    final today = days.isEmpty ? null : days.last;

    return RefreshIndicator(
      onRefresh: () async {
        final baby = ref.read(activeBabyProvider);
        if (baby != null) ref.invalidate(statsProvider(baby.id));
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          if (stats.rhythm.isNotEmpty)
            _Card(
              title: 'The shape of a day',
              caption: 'One row a day. Sleep is the long blocks; feeds and nappies are '
                  'the marks. What changes is the shape.',
              child: RhythmChart(stats.rhythm),
            ),
          _Card(
            title: 'Feeding',
            hero: today == null
                ? null
                : formatField('amount_ml', today.feedMl.round(), units),
            heroLabel: 'today',
            child: _FeedVolume(days, units: units),
          ),
          _Card(
            title: 'Time between feeds',
            hero: _lastGap(days),
            heroLabel: 'today, average',
            caption: 'The gap is the thing that grows, not the amount.',
            child: _FeedGap(days),
          ),
          _Card(
            title: 'Sleep',
            hero: today == null ? null : _hours(today.sleepMin),
            heroLabel: 'today',
            child: _Sleep(days),
          ),
          _Card(
            title: 'Nappies',
            hero: today == null ? null : '${today.diaperCount}',
            heroLabel: 'today',
            child: _Diapers(days),
          ),
          if (stats.growth.any((p) => p.weightKg != null))
            _Card(
              title: 'Weight',
              hero: formatField(
                'weight_kg',
                stats.growth.lastWhere((p) => p.weightKg != null).weightKg!,
                units,
              ),
              heroLabel: 'latest',
              child: _Growth(
                points: [
                  for (final p in stats.growth)
                    if (p.weightKg != null) (p.time, p.weightKg!),
                ],
              ),
            ),
          // A separate chart, not a second line on the one above: kilograms and
          // centimetres share no scale, and drawing them together would make one look
          // like it was chasing the other.
          if (stats.growth.any((p) => p.heightCm != null))
            _Card(
              title: 'Height',
              hero: formatField(
                'height_cm',
                stats.growth.lastWhere((p) => p.heightCm != null).heightCm!,
                units,
              ),
              heroLabel: 'latest',
              child: _Growth(
                points: [
                  for (final p in stats.growth)
                    if (p.heightCm != null) (p.time, p.heightCm!),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String? _lastGap(List<DayStat> days) {
    for (final day in days.reversed) {
      if (day.avgFeedGapMin != null) return _hours(day.avgFeedGapMin!);
    }
    return null;
  }
}

// formatMinutes already turns 135 into '2h 15m'; nobody reads a nap in minutes.
String _hours(int minutes) => formatMinutes(minutes);

String _dayLabel(String date) => date.substring(5).replaceAll('-', '/');

/// Two pixels of the 110px or so a plot actually gets, expressed as a fraction of the
/// scale so the gap is the same on screen whatever the numbers happen to be.
const _gapFraction = 2 / 110;

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.child,
    this.hero,
    this.heroLabel,
    this.caption,
  });

  final String title;
  final Widget child;

  /// The figure, in words. Some of these hues are below the contrast a chart should
  /// clear on a surface this pale; writing the number down is the price of using them.
  final String? hero;
  final String? heroLabel;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              if (hero != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(hero!, style: theme.textTheme.headlineSmall),
                    if (heroLabel != null)
                      Text(
                        heroLabel!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
            ],
          ),
          if (caption != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                caption!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 16),
          SizedBox(height: 150, child: child),
        ],
      ),
    );
  }
}

/// Two or more things in one chart are never told apart by colour alone.
class _Legend extends StatelessWidget {
  const _Legend(this.entries);

  final Map<String, Color> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 14,
      children: [
        for (final e in entries.entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: e.value,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 5),
              // Text wears text colours, never the series colour: the swatch beside it
              // is what carries the identity.
              Text(e.key, style: theme.textTheme.bodySmall),
            ],
          ),
      ],
    );
  }
}

FlTitlesData _titles(List<DayStat> days, {required String Function(double) left}) {
  return FlTitlesData(
    topTitles: const AxisTitles(),
    rightTitles: const AxisTitles(),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 40,
        getTitlesWidget: (value, meta) => Text(
          value == meta.min ? '' : left(value),
          style: const TextStyle(fontSize: 10),
        ),
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 22,
        interval: 1,
        getTitlesWidget: (value, meta) {
          final i = value.toInt();
          // Every label would be a smear on a phone. The ends and the middle say enough.
          final show = i == 0 || i == days.length - 1 || i == days.length ~/ 2;
          if (!show || i < 0 || i >= days.length) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_dayLabel(days[i].date), style: const TextStyle(fontSize: 10)),
          );
        },
      ),
    ),
  );
}

FlGridData _grid(Color color) => FlGridData(
      drawVerticalLine: false,
      getDrawingHorizontalLine: (_) => FlLine(color: color, strokeWidth: 1),
    );

class _FeedVolume extends StatelessWidget {
  const _FeedVolume(this.days, {required this.units});

  final List<DayStat> days;
  final UnitPrefs units;

  @override
  Widget build(BuildContext context) {
    final ink = ChartInk.of(context);
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        borderData: FlBorderData(show: false),
        gridData: _grid(ink.grid),
        titlesData: _titles(days, left: (v) => v.toInt().toString()),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (_, _, rod, index) => BarTooltipItem(
              '${formatField('amount_ml', days[index].feedMl.round(), units)}\n'
              '${days[index].feeds} feeds',
              Theme.of(context).textTheme.bodySmall!,
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < days.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: days[i].feedMl,
                color: ink.feeding,
                width: 8,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ]),
        ],
      ),
    );
  }
}

class _FeedGap extends StatelessWidget {
  const _FeedGap(this.days);

  final List<DayStat> days;

  @override
  Widget build(BuildContext context) {
    final ink = ChartInk.of(context);
    final spots = [
      for (var i = 0; i < days.length; i++)
        if (days[i].avgFeedGapMin != null)
          FlSpot(i.toDouble(), days[i].avgFeedGapMin! / 60),
    ];
    if (spots.length < 2) {
      return const Center(child: Text('Not enough feeds yet to see a gap.'));
    }

    return LineChart(
      LineChartData(
        borderData: FlBorderData(show: false),
        gridData: _grid(ink.grid),
        titlesData: _titles(days, left: (v) => '${v.toStringAsFixed(1)}h'),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  _hours(days[s.x.toInt()].avgFeedGapMin!),
                  Theme.of(context).textTheme.bodySmall!,
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            color: ink.feeding,
            barWidth: 2,
            isCurved: true,
            curveSmoothness: 0.2,
            dotData: FlDotData(
              getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                radius: 4,
                color: ink.feeding,
                strokeWidth: 2,
                strokeColor: Theme.of(context).colorScheme.surface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Sleep extends StatelessWidget {
  const _Sleep(this.days);

  final List<DayStat> days;

  @override
  Widget build(BuildContext context) {
    final ink = ChartInk.of(context);
    final maxY = days.fold(0.0, (m, d) => d.sleepMin / 60 > m ? d.sleepMin / 60 : m);
    // Two pixels of surface between the segments, in the chart's own units. Without it a
    // reader who cannot see the hue difference sees one bar, not two.
    final gap = maxY * _gapFraction;
    return Column(
      children: [
        Expanded(
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              borderData: FlBorderData(show: false),
              gridData: _grid(ink.grid),
              titlesData: _titles(days, left: (v) => '${v.toInt()}h'),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (_, _, _, index) => BarTooltipItem(
                    'night ${_hours(days[index].nightSleepMin)}\n'
                    'naps ${_hours(days[index].napMin)}',
                    Theme.of(context).textTheme.bodySmall!,
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < days.length; i++)
                  BarChartGroupData(x: i, barRods: [
                    BarChartRodData(
                      toY: days[i].sleepMin / 60 + (days[i].napMin > 0 ? gap : 0),
                      width: 8,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      // A 2px gap of surface between the two, so they never smudge into
                      // one another for someone who cannot see the hue difference.
                      rodStackItems: [
                        BarChartRodStackItem(0, days[i].nightSleepMin / 60, ink.sleep),
                        if (days[i].napMin > 0)
                          BarChartRodStackItem(
                            days[i].nightSleepMin / 60 + gap,
                            days[i].sleepMin / 60 + gap,
                            ink.nap,
                          ),
                      ],
                      color: Colors.transparent,
                    ),
                  ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _Legend({'night': ink.sleep, 'naps': ink.nap}),
      ],
    );
  }
}

class _Diapers extends StatelessWidget {
  const _Diapers(this.days);

  final List<DayStat> days;

  @override
  Widget build(BuildContext context) {
    final ink = ChartInk.of(context);
    const kinds = ['wet', 'mixed', 'dirty'];
    final maxY = days.fold(0, (m, d) => d.diaperCount > m ? d.diaperCount : m).toDouble();
    final gap = maxY * _gapFraction;

    return Column(
      children: [
        Expanded(
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              borderData: FlBorderData(show: false),
              gridData: _grid(ink.grid),
              titlesData: _titles(days, left: (v) => v.toInt().toString()),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (_, _, _, index) => BarTooltipItem(
                    [
                      for (final kind in kinds)
                        if ((days[index].diapers[kind] ?? 0) > 0)
                          '$kind ${days[index].diapers[kind]}',
                    ].join('\n'),
                    Theme.of(context).textTheme.bodySmall!,
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < days.length; i++)
                  BarChartGroupData(x: i, barRods: [
                    BarChartRodData(
                      toY: days[i].diaperCount + _stack(days[i], kinds, ink, gap).length * gap,
                      width: 8,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      color: Colors.transparent,
                      rodStackItems: _stack(days[i], kinds, ink, gap),
                    ),
                  ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _Legend({for (final k in kinds) k: ink.diaperKind(k)}),
      ],
    );
  }

  List<BarChartRodStackItem> _stack(
    DayStat day,
    List<String> kinds,
    ChartInk ink,
    double gap,
  ) {
    final items = <BarChartRodStackItem>[];
    var from = 0.0;
    for (final kind in kinds) {
      final count = (day.diapers[kind] ?? 0).toDouble();
      if (count == 0) continue;
      items.add(BarChartRodStackItem(from, from + count, ink.diaperKind(kind)));
      from += count + gap;
    }
    return items;
  }
}

class _Growth extends StatelessWidget {
  const _Growth({required this.points});

  final List<(DateTime, double)> points;

  @override
  Widget build(BuildContext context) {
    final ink = ChartInk.of(context);
    if (points.length < 2) {
      return const Center(child: Text('Log it twice and a curve appears.'));
    }

    return LineChart(
      LineChartData(
        borderData: FlBorderData(show: false),
        gridData: _grid(ink.grid),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          bottomTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, meta) => Text(
                v == meta.min ? '' : v.toStringAsFixed(1),
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < points.length; i++)
                FlSpot(i.toDouble(), points[i].$2),
            ],
            color: ink.growth,
            barWidth: 2,
            isCurved: true,
            curveSmoothness: 0.2,
            dotData: FlDotData(
              getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                radius: 4,
                color: ink.growth,
                strokeWidth: 2,
                strokeColor: Theme.of(context).colorScheme.surface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Nothing extends StatelessWidget {
  const _Nothing(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}
