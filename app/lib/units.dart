/// The caregiver's preferred display units. Data is stored canonical (ml, °C,
/// kg, cm); values are converted to these only for display.
class UnitPrefs {
  const UnitPrefs({
    this.temp = 'c', // c | f
    this.weight = 'kg', // kg | g | lb
    this.length = 'cm', // cm | m | in
    this.volume = 'ml', // ml | oz
  });

  final String temp;
  final String weight;
  final String length;
  final String volume;

  UnitPrefs copyWith({String? temp, String? weight, String? length, String? volume}) =>
      UnitPrefs(
        temp: temp ?? this.temp,
        weight: weight ?? this.weight,
        length: length ?? this.length,
        volume: volume ?? this.volume,
      );
}

String _n(num x) =>
    x == x.roundToDouble() ? x.toInt().toString() : x.toStringAsFixed(1);

/// Format one open field for display, converting known measures to [u].
/// Unknown fields fall back to "key value". Handles either stored unit
/// (e.g. amount_ml or amount_oz) so mixed data still shows consistently.
String formatField(String key, dynamic value, UnitPrefs u) {
  final n = value is num ? value : num.tryParse('$value');
  switch (key) {
    case 'amount_ml':
      if (n != null && u.volume == 'oz') return '${_n(n / 29.5735)} oz';
      return '$value ml';
    case 'amount_oz':
      if (n != null && u.volume == 'ml') return '${_n(n * 29.5735)} ml';
      return '$value oz';
    case 'celsius':
      if (n != null && u.temp == 'f') return '${_n(n * 9 / 5 + 32)}°F';
      return '$value°C';
    case 'weight_kg':
      if (n != null && u.weight == 'lb') return '${_n(n * 2.20462)} lb';
      if (n != null && u.weight == 'g') return '${_n(n * 1000)} g';
      return '$value kg';
    case 'height_cm':
      if (n != null && u.length == 'in') return '${_n(n / 2.54)} in';
      if (n != null && u.length == 'm') return '${_n(n / 100)} m';
      return '$value cm';
    case 'duration_min':
      return '$value min';
    case 'item':
    case 'title':
      return '$value';
    default:
      return '${key.replaceAll('_', ' ')} $value';
  }
}
