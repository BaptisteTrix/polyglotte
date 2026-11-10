import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Rappel quotidien par notification locale.
class Reminders {
  Reminders._();
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _init = false;

  static const _messages = [
    'Ta série t\'attend ! 🔥 10 minutes de russe ou de mandarin ?',
    'Привет ! 你好 ! C\'est l\'heure de ta session du jour.',
    'Quelques cartes à réviser avant que ta mémoire ne les oublie 🧠',
  ];

  static Future<void> init() async {
    if (_init || kIsWeb) return;
    try {
      tzdata.initializeTimeZones();
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      debugPrint('Timezone error: $e');
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _init = true;
  }

  /// Programme (ou annule) le rappel quotidien. Renvoie false si la
  /// permission a été refusée.
  static Future<bool> schedule(
      {required bool enabled, required int hour, required int minute}) async {
    if (kIsWeb) return false;
    await init();
    await _plugin.cancelAll();
    if (!enabled) return true;

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission() ?? true;
    if (!granted) return false;

    final now = tz.TZDateTime.now(tz.local);
    var when =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));

    await _plugin.zonedSchedule(
      id: 1,
      title: 'Polyglotte',
      body: _messages[now.day % _messages.length],
      scheduledDate: when,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_reminder',
          'Rappel quotidien',
          channelDescription: 'Rappel pour ta session d\'apprentissage',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
    return true;
  }
}
