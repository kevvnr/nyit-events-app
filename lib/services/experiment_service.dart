import 'analytics_service.dart';
import 'remote_config_service.dart';

class ExperimentService {
  ExperimentService._();
  static final ExperimentService instance = ExperimentService._();

  Future<void> initialize() async {
    await RemoteConfigService.instance.initialize();
  }

  String get feedHeaderVariant =>
      RemoteConfigService.instance.getString('feed_header_variant');
  String get smartPicksVariant =>
      RemoteConfigService.instance.getString('smart_picks_layout_variant');
  String get rsvpCtaVariant =>
      RemoteConfigService.instance.getString('rsvp_cta_variant');

  Future<void> logExposure({
    required String experimentId,
    required String variant,
    String placement = '',
  }) async {
    await AnalyticsService.instance.logEvent(
      'experiment_exposure',
      parameters: {
        'experiment_id': experimentId,
        'variant': variant,
        'placement': placement,
      },
    );
  }
}
