import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  Future<void> logEvent(
    String name, {
    Map<String, Object?> parameters = const {},
  }) async {
    try {
      final sanitized = <String, Object>{};
      parameters.forEach((key, value) {
        if (value != null) sanitized[key] = value;
      });
      await _analytics.logEvent(name: name, parameters: sanitized);
    } catch (_) {}
  }

  Future<void> logScreenView(String screenName) async {
    try {
      await _analytics.logScreenView(screenName: screenName);
    } catch (_) {}
  }

  Future<void> setUserId(String uid) async {
    try {
      await _analytics.setUserId(id: uid);
    } catch (_) {}
  }

  Future<void> setUserProperty(String name, String value) async {
    try {
      await _analytics.setUserProperty(name: name, value: value);
    } catch (_) {}
  }
}
