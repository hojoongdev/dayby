import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// A nudge left with the operating system, to be delivered at a given moment
/// whether or not Dayby is running.
///
/// That is the whole point: a caregiver who has forgotten to log a feed is, by
/// definition, not looking at the app. The server decides when and writes what — in
/// the caregiver's own language — and this hands both to the phone.
abstract class Reminders {
  /// Replaces whatever was pending. A null time or text simply clears it, which is
  /// what should happen the moment the thing gets logged after all.
  Future<void> schedule({DateTime? at, String? text});
}

class LocalReminders implements Reminders {
  LocalReminders([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  // One pending nudge at a time: a newer one is always about the same thing, only
  // better informed, so it replaces rather than joins.
  static const _id = 1;

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  Future<bool> _prepare() async {
    if (_ready) return true;
    // There is no notification tray in a browser tab worth reaching for here.
    if (kIsWeb) return false;

    try {
      await _plugin.initialize(const InitializationSettings(
        iOS: DarwinInitializationSettings(),
        macOS: DarwinInitializationSettings(),
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ));
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);

      // Scheduling is done in the caregiver's own zone: "in four hours" has to mean
      // four hours on their clock, not on UTC's.
      tz_data.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation(await FlutterTimezone.getLocalTimezone()));
      _ready = true;
    } catch (_) {
      // No notifications on this platform, or permission refused. The assistant card
      // still says the same thing when they next open the app.
      return false;
    }
    return _ready;
  }

  @override
  Future<void> schedule({DateTime? at, String? text}) async {
    if (!await _prepare()) return;

    await _plugin.cancel(_id);
    if (at == null || text == null || text.isEmpty) return;
    if (!at.isAfter(DateTime.now())) return;

    await _plugin.zonedSchedule(
      _id,
      'Dayby',
      text,
      tz.TZDateTime.from(at.toLocal(), tz.local),
      const NotificationDetails(
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
        android: AndroidNotificationDetails(
          'nudges',
          'Reminders',
          channelDescription: 'A nudge when something has not been logged in a while',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      // The moment is "four hours after the last feed", which is an instant, not a
      // time on a clock face — it does not move if they fly somewhere.
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}
