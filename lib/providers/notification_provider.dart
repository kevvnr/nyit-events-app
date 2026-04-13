import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/app_config.dart';
import '../providers/auth_provider.dart';

// Stream of all notifications for current user
final notificationsProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  final user = ref.watch(userModelProvider).asData?.value;
  if (user == null) return Stream.value([]);

  return FirebaseFirestore.instance
      .collection(AppConfig.notificationsCol)
      .where('userId', isEqualTo: user.uid)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList());
});

// Count of unread notifications
final unreadCountProvider = Provider<int>((ref) {
  final notifications = ref.watch(notificationsProvider).asData?.value ?? [];
  return notifications.where((n) => n['read'] == false).length;
});

// Mark notification as read
Future<void> markAsRead(String notificationId) async {
  await FirebaseFirestore.instance
      .collection(AppConfig.notificationsCol)
      .doc(notificationId)
      .update({'read': true});
}

// Mark all as read
Future<void> markAllAsRead(String userId) async {
  final batch = FirebaseFirestore.instance.batch();
  final snapshot = await FirebaseFirestore.instance
      .collection(AppConfig.notificationsCol)
      .where('userId', isEqualTo: userId)
      .where('read', isEqualTo: false)
      .get();

  for (final doc in snapshot.docs) {
    batch.update(doc.reference, {'read': true});
  }
  await batch.commit();
}

// Delete notification
Future<void> deleteNotification(String notificationId) async {
  await FirebaseFirestore.instance
      .collection(AppConfig.notificationsCol)
      .doc(notificationId)
      .delete();
}