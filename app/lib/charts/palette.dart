import 'package:flutter/material.dart';

/// The chart palette, and why these hexes and not others.
///
/// Every value here was run through a colour-blindness and contrast validator against the
/// surface it actually renders on — the frosted card, not white — and only the sets that
/// passed are in this file. That matters more than usual: a parent reads these at 3am on a
/// phone at arm's length, and roughly one man in twelve cannot tell red from green.
///
/// Colour follows the *thing*, never the chart. Sleep is the same blue on the sleep chart
/// and on the 24-hour view; feeding is the same green in both places. Within one chart, the
/// kinds of a thing (a nap against a night, a wet nappy against a dirty one) are steps of
/// that thing's own hue, so the eye never has to learn a second alphabet.
///
/// Two of these sit below a 3:1 contrast ratio on the pale surface, which the validator
/// allows only on the condition that the numbers are also written down. That is why every
/// chart on the stats screen carries its figure in text as well as in paint.
class ChartInk {
  const ChartInk._({
    required this.sleep,
    required this.nap,
    required this.feeding,
    required this.diaper,
    required this.diaperWet,
    required this.diaperMixed,
    required this.diaperDirty,
    required this.growth,
    required this.grid,
  });

  factory ChartInk.of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _dark : _light;

  final Color sleep;
  final Color nap;
  final Color feeding;
  final Color diaper;
  final Color diaperWet;
  final Color diaperMixed;
  final Color diaperDirty;
  final Color growth;
  final Color grid;

  Color diaperKind(String kind) => switch (kind) {
        'wet' => diaperWet,
        'dirty' => diaperDirty,
        'mixed' => diaperMixed,
        _ => diaper,
      };

  static const _light = ChartInk._(
    sleep: Color(0xFF2A78D6),
    nap: Color(0xFF86B6EF),
    feeding: Color(0xFF1BAF7A),
    diaper: Color(0xFFD99400),
    diaperWet: Color(0xFFD99400),
    diaperMixed: Color(0xFFA86F00),
    diaperDirty: Color(0xFF6B4800),
    growth: Color(0xFF008300),
    grid: Color(0x1A000000),
  );

  static const _dark = ChartInk._(
    sleep: Color(0xFF3987E5),
    nap: Color(0xFF9EC5F4),
    feeding: Color(0xFF199E70),
    diaper: Color(0xFFC98500),
    diaperWet: Color(0xFFF0C264),
    diaperMixed: Color(0xFFE0A52E),
    diaperDirty: Color(0xFFC98500),
    growth: Color(0xFF46B06A),
    grid: Color(0x1AFFFFFF),
  );
}
