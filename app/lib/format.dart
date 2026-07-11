/// Small display helpers. The server stores times in UTC; everything here
/// renders in the device's local time zone.
String _two(int n) => n.toString().padLeft(2, '0');

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Jul 11, 14:30"
String formatTime(DateTime t) {
  final l = t.toLocal();
  return '${_months[l.month - 1]} ${l.day}, ${_two(l.hour)}:${_two(l.minute)}';
}

/// "14:30"
String formatClock(DateTime t) {
  final l = t.toLocal();
  return '${_two(l.hour)}:${_two(l.minute)}';
}

/// "Jul 11, 2026"
String formatDate(DateTime t) {
  final l = t.toLocal();
  return '${_months[l.month - 1]} ${l.day}, ${l.year}';
}

/// "amount_ml" -> "amount ml"
String prettifyKey(String key) => key.replaceAll('_', ' ');

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// A one-line human summary, e.g. "Feeding · formula · 120 ml".
String eventSummary(String type, String? subtype, Map<String, dynamic> fields) {
  final parts = <String>[_capitalize(type)];
  if (subtype != null && subtype.isNotEmpty) parts.add(subtype);
  fields.forEach((key, value) {
    parts.add(switch (key) {
      'amount_ml' => '$value ml',
      'amount_oz' => '$value oz',
      'celsius' => '$value°C',
      'duration_min' => '$value min',
      'weight_kg' => '$value kg',
      'height_cm' => '$value cm',
      'item' || 'title' => '$value',
      _ => '${prettifyKey(key)} $value',
    });
  });
  return parts.join(' · ');
}

/// "Today" / "Yesterday" / "Jul 10" (adds the year only when it differs).
String formatDayHeader(DateTime t, DateTime now) {
  final l = t.toLocal();
  final day = DateTime(l.year, l.month, l.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  final year = day.year == now.year ? '' : ', ${day.year}';
  return '${_months[day.month - 1]} ${day.day}$year';
}
