import 'package:flutter/material.dart';

import '../charts/palette.dart';
import '../models/stats.dart';

/// The 24-hour view: one row a day, midnight to midnight, laid one above another.
///
/// No chart library draws this, and none should — it is not a plot of a number, it is a
/// picture of a day. Sleep is the long blocks, feeds and nappies are the marks between
/// them, and what a parent is looking for is not any single value but the shape settling
/// down: the night block growing, the marks thinning out of the small hours.
class RhythmChart extends StatelessWidget {
  const RhythmChart(this.blocks, {super.key, this.days = 7});

  final List<RhythmBlock> blocks;

  /// A week fits on a phone and is long enough to see the shape move.
  final int days;

  static const _minutesADay = 24 * 60;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = ChartInk.of(context);

    final dates = blocks.map((b) => b.date).toSet().toList()..sort();
    final recent = dates.length <= days ? dates : dates.sublist(dates.length - days);
    final byDate = {
      for (final date in recent)
        date: blocks.where((b) => b.date == date).toList(),
    };

    return Column(
      children: [
        Expanded(
          child: Column(
            children: [
              for (final date in recent)
                Expanded(
                  child: Row(
                    children: [
                      SizedBox(
                        width: 34,
                        child: Text(
                          date.substring(5).replaceAll('-', '/'),
                          style: theme.textTheme.bodySmall?.copyWith(fontSize: 9),
                        ),
                      ),
                      Expanded(
                        child: CustomPaint(
                          painter: _DayPainter(byDate[date]!, ink),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Midnight, noon, midnight -- enough of a clock to read the blocks against.
        Padding(
          padding: const EdgeInsets.only(left: 34),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final hour in ['12am', '6am', '12pm', '6pm', '12am'])
                Text(hour, style: theme.textTheme.bodySmall?.copyWith(fontSize: 9)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          children: [
            for (final e in {
              'sleep': ink.sleep,
              'feed': ink.feeding,
              'nappy': ink.diaper,
            }.entries)
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
                  Text(e.key, style: theme.textTheme.bodySmall),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _DayPainter extends CustomPainter {
  const _DayPainter(this.blocks, this.ink);

  final List<RhythmBlock> blocks;
  final ChartInk ink;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / RhythmChart._minutesADay;
    final track = Paint()..color = ink.grid;
    final rows = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 2, size.width, size.height - 6),
      const Radius.circular(3),
    );
    canvas.drawRRect(rows, track);

    // Sleep first, so a feed in the middle of the night stays visible on top of it.
    for (final block in blocks.where((b) => b.type == 'sleep')) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            block.startMin * scale,
            2,
            (block.minutes * scale).clamp(2.0, size.width),
            size.height - 6,
          ),
          const Radius.circular(3),
        ),
        Paint()..color = ink.sleep,
      );
    }

    for (final block in blocks.where((b) => b.type != 'sleep')) {
      final colour = block.type == 'feeding' ? ink.feeding : ink.diaper;
      final x = block.startMin * scale;
      // A mark, not a block: a feed takes no time worth drawing, but you have to be able
      // to see where in the night it happened.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 1.5, 0, 3, size.height - 2),
          const Radius.circular(2),
        ),
        Paint()..color = colour,
      );
    }
  }

  @override
  bool shouldRepaint(_DayPainter old) => old.blocks != blocks || old.ink != ink;
}
