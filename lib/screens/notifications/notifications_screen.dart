import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../config/app_config.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/event_provider.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userModelProvider).asData?.value;
    if (user == null) return const Scaffold();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () => _markAllRead(user.uid),
            child: const Text(
              'Mark all read',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection(AppConfig.notificationsCol)
            .where('userId', isEqualTo: user.uid)
            .orderBy('createdAt', descending: true)
            .limit(50)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_none_rounded,
                    size: 64,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No notifications yet',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You\'ll be notified about your events here',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final isRead = data['read'] == true;
              final createdAt =
                  (data['createdAt'] as Timestamp?)?.toDate();
              final type = data['type'] ?? '';

              return Dismissible(
                key: Key(doc.id),
                direction: DismissDirection.endToStart,
                onDismissed: (_) => _deleteNotification(doc.id),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(
                    color: Colors.red.shade400,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.white,
                  ),
                ),
                child: GestureDetector(
                  onTap: () => _markRead(doc.id, isRead),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isRead
                          ? Theme.of(context)
                              .colorScheme
                              .surface
                          : AppConfig.primaryColor
                              .withOpacity(0.06),
                      borderRadius:
                          BorderRadius.circular(12),
                      border: Border.all(
                        color: isRead
                            ? const Color(0xFFE2E8F0)
                            : AppConfig.primaryColor
                                .withOpacity(0.2),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        // Icon
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _iconColor(type)
                                .withOpacity(0.1),
                            borderRadius:
                                BorderRadius.circular(20),
                          ),
                          child: Icon(
                            _iconData(type),
                            color: _iconColor(type),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Content
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                data['message'] ?? '',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isRead
                                      ? FontWeight.w400
                                      : FontWeight.w600,
                                  height: 1.4,
                                ),
                              ),
                              if (createdAt != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  _formatTime(createdAt),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color:
                                        Colors.grey.shade400,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        // X dismiss button + unread dot
                        Column(
                          children: [
                            // X button
                            GestureDetector(
                              onTap: () =>
                                  _deleteNotification(doc.id),
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color:
                                      Colors.grey.shade100,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 14,
                                  color:
                                      Colors.grey.shade500,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            // Unread dot
                            if (!isRead)
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color:
                                      AppConfig.primaryColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _markRead(String id, bool isRead) async {
    if (isRead) return;
    await FirebaseFirestore.instance
        .collection(AppConfig.notificationsCol)
        .doc(id)
        .update({'read': true});
  }

  Future<void> _markAllRead(String userId) async {
    final snap = await FirebaseFirestore.instance
        .collection(AppConfig.notificationsCol)
        .where('userId', isEqualTo: userId)
        .where('read', isEqualTo: false)
        .get();

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }

  Future<void> _deleteNotification(String id) async {
    await FirebaseFirestore.instance
        .collection(AppConfig.notificationsCol)
        .doc(id)
        .delete();
  }

  IconData _iconData(String type) {
    switch (type) {
      case 'promoted':
        return Icons.arrow_upward_rounded;
      case 'cancel':
      case 'cancelled':
        return Icons.cancel_outlined;
      case 'update':
        return Icons.edit_outlined;
      case 'reminder':
        return Icons.notifications_active_rounded;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _iconColor(String type) {
    switch (type) {
      case 'promoted':
        return Colors.green;
      case 'cancel':
      case 'cancelled':
        return Colors.red;
      case 'update':
        return Colors.orange;
      case 'reminder':
        return Colors.amber.shade700;
      default:
        return AppConfig.primaryColor;
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(time);
  }
}