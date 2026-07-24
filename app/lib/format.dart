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

/// "just now" / "45m ago" / "2h 10m ago" / "4h ago" / "3d ago"
String formatAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) {
    final minutes = d.inMinutes % 60;
    return minutes == 0 ? '${d.inHours}h ago' : '${d.inHours}h ${minutes}m ago';
  }
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

/// "1,031" — the numbers in a keepsake are big enough to need the commas.
String formatCount(num n) {
  final digits = n.round().toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// A lifetime of feeding is litres, not millilitres.
String formatTotalVolume(double ml, UnitPrefs units) {
  if (units.volume == 'oz') return '${formatCount(ml / 29.5735)} oz';
  if (ml >= 1000) return '${(ml / 1000).toStringAsFixed(1)} L';
  return '${formatCount(ml)} ml';
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// A one-line human summary, e.g. "Feeding · formula · 120 ml", with fields
/// converted to the caregiver's preferred units.
/// Plumbing or too-verbose fields that a one-line summary leaves out. The document
/// still holds them (queries and the wrapped story read them); the tile just does not
/// shout them.
const _summarySkip = {'photo_id', 'made_at_home', 'ingredients', 'texture'};

String eventSummary(String type, String? subtype, Map<String, dynamic> fields,
    {UnitPrefs units = const UnitPrefs()}) {
  final parts = <String>[_capitalize(type)];
  if (subtype != null && subtype.isNotEmpty) parts.add(subtype.replaceAll('_', ' '));
  fields.forEach((key, value) {
    // Money reads as one thing ("$42"), not "amount 42 · USD".
    if (_summarySkip.contains(key) || key == 'currency') return;
    final part = key == 'amount'
        ? formatMoney(value, fields['currency'] as String?)
        : formatField(key, value, units);
    if (part.isNotEmpty) parts.add(part);
  });
  return parts.join(' · ');
}

/// A price with its currency symbol in front where there is one.
String formatMoney(dynamic amount, String? currency) {
  switch (currency) {
    case 'USD':
      return '\$$amount';
    case 'KRW':
      return '₩$amount';
    case null:
    case '':
      return '$amount';
    default:
      return '$amount $currency';
  }
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
