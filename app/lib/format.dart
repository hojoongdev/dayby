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

/// "amount_ml" -> "amount ml"
String prettifyKey(String key) => key.replaceAll('_', ' ');
