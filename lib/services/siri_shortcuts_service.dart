import 'dart:io';

import 'package:flutter/services.dart';

import 'remote_config_service.dart';

class SiriShortcutsService {
  SiriShortcutsService._();
  static final SiriShortcutsService instance = SiriShortcutsService._();

  static const MethodChannel _channel = MethodChannel(
    'nyit_events/siri_shortcuts',
  );

  bool get _enabled =>
      RemoteConfigService.instance.getBool('enable_siri_shortcuts');

  Future<void> donateOpenEvent({
    required String eventId,
    required String eventTitle,
  }) async {
    if (!Platform.isIOS || !_enabled) return;
    try {
      await _channel.invokeMethod('donateOpenEvent', {
        'eventId': eventId,
        'eventTitle': eventTitle,
      });
    } catch (_) {}
  }

  Future<void> donateShowQr({
    required String eventId,
    required String eventTitle,
  }) async {
    if (!Platform.isIOS || !_enabled) return;
    try {
      await _channel.invokeMethod('donateShowQr', {
        'eventId': eventId,
        'eventTitle': eventTitle,
      });
    } catch (_) {}
  }
}
