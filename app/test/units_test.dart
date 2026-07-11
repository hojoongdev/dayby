import 'package:dayby/format.dart';
import 'package:dayby/units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('event summary converts to the preferred units', () {
    expect(
      eventSummary('feeding', 'formula', {'amount_ml': 120}),
      'Feeding · formula · 120 ml',
    );
    expect(
      eventSummary('feeding', 'formula', {'amount_ml': 120},
          units: const UnitPrefs(volume: 'oz')),
      contains('oz'), // 120 ml ~= 4.1 oz
    );
    expect(
      eventSummary('temperature', null, {'celsius': 37},
          units: const UnitPrefs(temp: 'f')),
      contains('98.6°F'),
    );
    expect(
      eventSummary('growth', null, {'weight_kg': 6, 'height_cm': 60},
          units: const UnitPrefs(weight: 'lb', length: 'in')),
      allOf(contains('lb'), contains('in')),
    );
  });
}
