import 'units.dart';

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

/// "just now" / "45m ago" / "2h 10m ago" / "3d ago"
String formatAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ${d.inMinutes % 60}m ago';
  return '${d.inDays}d ago';
}

/// "12 days old" / "3 months old" / "2 years old"
String formatAge(DateTime birth) {
  final now = DateTime.now();
  var months = (now.year - birth.year) * 12 + (now.month - birth.month);
  if (now.day < birth.day) months -= 1;
  if (months < 1) return '${now.difference(birth).inDays} days old';
  if (months < 24) return '$months months old';
  return '${months ~/ 12} years old';
}

/// True if the instant falls on today in the device's local time.
bool isToday(DateTime t) {
  final l = t.toLocal();
  final now = DateTime.now();
  return l.year == now.year && l.month == now.month && l.day == now.day;
}

/// "amount_ml" -> "amount ml"
String prettifyKey(String key) => key.replaceAll('_', ' ');

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// A one-line human summary, e.g. "Feeding · formula · 120 ml", with fields
/// converted to the caregiver's preferred units.
String eventSummary(String type, String? subtype, Map<String, dynamic> fields,
    {UnitPrefs units = const UnitPrefs()}) {
  final parts = <String>[_capitalize(type)];
  if (subtype != null && subtype.isNotEmpty) parts.add(subtype);
  fields.forEach((key, value) => parts.add(formatField(key, value, units)));
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
