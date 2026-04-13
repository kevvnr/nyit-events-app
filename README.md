# campus_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## SideStore Source Update Script

Use `scripts/update_sidestore_source.sh` to update `public/apps.json` in one command.

Example:

```bash
./scripts/update_sidestore_source.sh \
  --version 1.5.1 \
  --description "• Room scheduling fix\n• Map walking directions" \
  --download-url "https://github.com/kevvnr/nyit-events-app/releases/download/v1.5.1/NYIT.Events.ipa" \
  --ipa "build/ios/ipa/NYIT.Events.ipa"
```

Next release, only change:
- `--version`
- `--description`
- `--download-url`
- `--ipa` (or pass `--size`)

## iOS + Firebase rollout setup

1. Install new Flutter dependencies:

```bash
flutter pub get
```

2. Deploy hosting only (no Cloud Functions required):

```bash
firebase deploy --only hosting
```

3. In Firebase Remote Config, configure flags:
- `enable_live_activities`
- `enable_siri_shortcuts`
- `enable_app_clip_checkin`
- `enable_in_app_review`

4. QA matrix:
- iOS Simulator: feed experiments, campaign queueing UI, RSVP/check-in logging.
- Physical iPhone: push delivery, Live Activities/Dynamic Island, Siri donations, universal-link check-in flow.

## 100% free mode

- Campaigns are delivered as in-app notifications via Firestore writes from admin tools.
- No Firebase Functions deployment is required.
- If you want push campaigns later, that would require a server/function sender.

