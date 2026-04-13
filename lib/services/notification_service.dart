import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import '../config/app_config.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class NotificationService {
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;

    // Initialize timezone database and default to New York
    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('America/New_York'));
    } catch (_) {
      // Fall back to UTC if location lookup fails
    }

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await flutterLocalNotificationsPlugin.initialize(initSettings);
    _initialized = true;
  }

  // ── Instant (in-app banner) notification ──────────────────────
  static Future<void> showInstantNotification({
    required String title,
    required String body,
  }) async {
    const NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        'general',
        'General',
        channelDescription: 'General app notifications',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }

  // ── Scheduled reminder notification ───────────────────────────
  /// Schedules a local notification [reminderMinutes] before [eventStartTime].
  /// Uses the absolute event ID hash as a stable notification ID so it can
  /// be cancelled later.  Silently no-ops if the fire time is in the past.
  static Future<void> scheduleEventReminder({
    required String eventId,
    required String eventTitle,
    required DateTime eventStartTime,
    required int reminderMinutes,
  }) async {
    final fireAt = eventStartTime
        .subtract(Duration(minutes: reminderMinutes));

    if (fireAt.isBefore(DateTime.now())) return;

    final notifId = eventId.hashCode.abs() % 2147483647;

    final tzFireAt = tz.TZDateTime.from(fireAt, tz.local);

    const NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        'reminders',
        'Event Reminders',
        channelDescription: 'Reminders for upcoming events you RSVPd for',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await flutterLocalNotificationsPlugin.zonedSchedule(
      notifId,
      '📅 Upcoming event',
      '$eventTitle starts in $reminderMinutes ${reminderMinutes == 1 ? 'minute' : reminderMinutes < 60 ? 'minutes' : reminderMinutes == 60 ? 'hour' : '${reminderMinutes ~/ 60} hours'}!',
      tzFireAt,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Cancels a previously scheduled reminder for [eventId].
  static Future<void> cancelEventReminder(String eventId) async {
    final notifId = eventId.hashCode.abs() % 2147483647;
    await flutterLocalNotificationsPlugin.cancel(notifId);
  }

  static Future<void> cancelReminder(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
  }

  static Future<void> cancelAllReminders() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }

  // ── In-app (Firestore) notification ───────────────────────────
  static Future<void> writeInAppNotification({
    required String userId,
    required String type,
    required String eventId,
    required String message,
  }) async {
    await FirebaseFirestore.instance
        .collection(AppConfig.notificationsCol)
        .add({
      'userId': userId,
      'type': type,
      'eventId': eventId,
      'message': message,
      'read': false,
      'createdAt': Timestamp.now(),
    });
  }
}
