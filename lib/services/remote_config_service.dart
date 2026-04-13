import 'package:firebase_remote_config/firebase_remote_config.dart';

class RemoteConfigService {
  RemoteConfigService._();
  static final RemoteConfigService instance = RemoteConfigService._();

  final FirebaseRemoteConfig _remoteConfig = FirebaseRemoteConfig.instance;
  bool _initialized = false;

  static const _defaults = <String, dynamic>{
    'feed_header_variant': 'A',
    'smart_picks_layout_variant': 'A',
    'rsvp_cta_variant': 'A',
    'enable_live_activities': false,
    'enable_siri_shortcuts': false,
    'enable_app_clip_checkin': false,
    'enable_in_app_review': true,
  };

  Future<void> initialize() async {
    if (_initialized) return;
    await _remoteConfig.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 15),
        minimumFetchInterval: const Duration(minutes: 10),
      ),
    );
    await _remoteConfig.setDefaults(_defaults);
    await _remoteConfig.fetchAndActivate();
    _initialized = true;
  }

  String getString(String key) => _remoteConfig.getString(key);
  bool getBool(String key) => _remoteConfig.getBool(key);
}
