import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'config/app_theme.dart';
import 'router/app_router.dart';
import 'services/analytics_service.dart';
import 'services/experiment_service.dart';
import 'services/notification_service.dart';

/// Background FCM handler — must be a top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.initialize();
  await ExperimentService.instance.initialize();
  await NotificationService.showInstantNotification(
    title: message.notification?.title ?? 'NYIT Events',
    body: message.notification?.body ?? '',
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  await NotificationService.initialize();

  // Request iOS notification permissions and set up FCM
  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Show foreground FCM messages as local notifications
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    AnalyticsService.instance.logEvent(
      'fcm_foreground_received',
      parameters: {'message_id': message.messageId ?? ''},
    );
    NotificationService.showInstantNotification(
      title: message.notification?.title ?? 'NYIT Events',
      body: message.notification?.body ?? '',
    );
  });

  // Always sign out on app start — require fresh login every time
  await FirebaseAuth.instance.signOut();

  runApp(const ProviderScope(child: NYITCampusEventsApp()));
}

class NYITCampusEventsApp extends ConsumerWidget {
  const NYITCampusEventsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AnalyticsService.instance.logScreenView('app_root');
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'NYIT Campus Events',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
