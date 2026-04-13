import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'remote_config_service.dart';

class ReviewPromptService {
  ReviewPromptService._();
  static final ReviewPromptService instance = ReviewPromptService._();

  static const _kLastPromptAt = 'review_last_prompt_at';
  static const _kPromptCount = 'review_prompt_count';
  static const _kSuccessCount = 'review_success_count';

  Future<void> registerPositiveSignal() async {
    if (!RemoteConfigService.instance.getBool('enable_in_app_review')) return;
    final prefs = await SharedPreferences.getInstance();
    final successCount = (prefs.getInt(_kSuccessCount) ?? 0) + 1;
    await prefs.setInt(_kSuccessCount, successCount);
    if (successCount < 2) return;

    final promptCount = prefs.getInt(_kPromptCount) ?? 0;
    if (promptCount >= 3) return;

    final lastPromptMs = prefs.getInt(_kLastPromptAt) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (lastPromptMs > 0 &&
        now - lastPromptMs < const Duration(days: 45).inMilliseconds) {
      return;
    }

    final review = InAppReview.instance;
    if (await review.isAvailable()) {
      await review.requestReview();
      await prefs.setInt(_kPromptCount, promptCount + 1);
      await prefs.setInt(_kLastPromptAt, now);
    }
  }
}
