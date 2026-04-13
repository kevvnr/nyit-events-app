import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'remote_config_service.dart';

class LiveActivityService {
  LiveActivityService._();
  static final LiveActivityService instance = LiveActivityService._();

  static const MethodChannel _channel = MethodChannel(
    'nyit_events/live_activities',
  );
  static const _kActiveEventId = 'live_activity_active_event_id';

  bool get _enabled =>
      RemoteConfigService.instance.getBool('enable_live_activities');

  Future<void> startOrUpdate({
    required String eventId,
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    required String location,
  }) async {
    if (!Platform.isIOS || !_enabled) return;
    try {
      await _channel.invokeMethod('startOrUpdate', {
        'eventId': eventId,
        'title': title,
        'startTimeMs': startTime.millisecondsSinceEpoch,
        'endTimeMs': endTime.millisecondsSinceEpoch,
        'location': location,
      });
    } catch (_) {}
  }

  Future<void> end(String eventId) async {
    if (!Platform.isIOS || !_enabled) return;
    try {
      await _channel.invokeMethod('end', {'eventId': eventId});
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_kActiveEventId) == eventId) {
        await prefs.remove(_kActiveEventId);
      }
    } catch (_) {}
  }

  Future<void> syncNextUpcoming({
    required String eventId,
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    required String location,
  }) async {
    if (!Platform.isIOS || !_enabled) return;
    final prefs = await SharedPreferences.getInstance();
    final previous = prefs.getString(_kActiveEventId);
    if (previous != null && previous != eventId) {
      await end(previous);
    }
    await startOrUpdate(
      eventId: eventId,
      title: title,
      startTime: startTime,
      endTime: endTime,
      location: location,
    );
    await prefs.setString(_kActiveEventId, eventId);
  }
}
