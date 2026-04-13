import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../config/app_config.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/event_provider.dart';
import '../../router/app_router.dart';
import '../calendar/events_calendar_screen.dart';
import 'my_events_screen.dart';
import 'qr_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  Future<Map<String, int>> _loadProfileStats(String uid) async {
    final rsvpSnap = await FirebaseFirestore.instance
        .collection(AppConfig.rsvpsCol)
        .where('userId', isEqualTo: uid)
        .where('status', isEqualTo: AppConfig.rsvpConfirmed)
        .get();
    final eventIds = rsvpSnap.docs
        .map((d) => d.data()['eventId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final activeEventIds = <String>{};
    for (var i = 0; i < eventIds.length; i += 10) {
      final chunk = eventIds.sublist(
        i,
        (i + 10 > eventIds.length) ? eventIds.length : i + 10,
      );
      final snap = await FirebaseFirestore.instance
          .collection(AppConfig.eventsCol)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        final status = (doc.data()['status'] ?? '').toString();
        if (status != AppConfig.eventCancelled) {
          activeEventIds.add(doc.id);
        }
      }
    }

    var attended = 0;
    int checkedIn = 0;
    for (final doc in rsvpSnap.docs) {
      final eventId = doc.data()['eventId']?.toString() ?? '';
      if (!activeEventIds.contains(eventId)) continue;
      if (doc.data()['checkedIn'] == true) {
        checkedIn++;
      }
      attended++;
    }
    return {
      'rsvps': attended,
      'checkedIn': checkedIn,
      'attendance': attended == 0 ? 0 : ((checkedIn / attended) * 100).round(),
    };
  }

  Future<void> _deleteAccount(UserModel user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'This will permanently delete your account and all associated data. '
          'Your email will become available for a new registration immediately.\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final db = FirebaseFirestore.instance;
      final touchedEvents = <String>{};
      final batch = db.batch();

      final rsvpSnap = await db
          .collection(AppConfig.rsvpsCol)
          .where('userId', isEqualTo: user.uid)
          .get();
      for (final doc in rsvpSnap.docs) {
        final eventId = doc.data()['eventId']?.toString();
        if (eventId != null && eventId.isNotEmpty) {
          touchedEvents.add(eventId);
        }
        batch.delete(doc.reference);
      }

      final notifSnap = await db
          .collection(AppConfig.notificationsCol)
          .where('userId', isEqualTo: user.uid)
          .get();
      for (final doc in notifSnap.docs) {
        batch.delete(doc.reference);
      }

      batch.delete(db.collection(AppConfig.usersCol).doc(user.uid));
      await batch.commit();

      for (final eventId in touchedEvents) {
        await ref.read(eventServiceProvider).recalculateEventCounts(eventId);
      }

      // Delete Firebase Auth account — frees the email immediately
      await FirebaseAuth.instance.currentUser?.delete();

      if (mounted) {
        GoRouter.of(context).go(AppRoutes.welcome);
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'For security, please sign out and sign back in, then try deleting again.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: ${e.message}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userModelProvider).asData?.value;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header banner
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1a3a6b), Color(0xFF1565C0)],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  child: Column(
                    children: [
                      // Top row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Profile',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          GestureDetector(
                            onTap: () async {
                              await ref
                                  .read(authNotifierProvider.notifier)
                                  .logout();
                              if (context.mounted) {
                                GoRouter.of(context).go(AppRoutes.welcome);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.3),
                                ),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.logout_rounded,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Sign out',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Avatar (initials; optional legacy photo URL from Firestore)
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.4),
                            width: 2,
                          ),
                        ),
                        child:
                            (user?.photoUrl != null &&
                                user!.photoUrl.isNotEmpty)
                            ? ClipOval(
                                child: Image.network(
                                  user.photoUrl,
                                  width: 84,
                                  height: 84,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _buildInitials(user.name),
                                ),
                              )
                            : Center(child: _buildInitials(user?.name ?? '')),
                      ),
                      const SizedBox(height: 12),

                      // Name
                      Text(
                        user?.name ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Email
                      Text(
                        user?.email ?? '',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Role badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _roleColor(user?.role ?? '').withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _roleColor(
                              user?.role ?? '',
                            ).withOpacity(0.5),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _roleIcon(user?.role ?? ''),
                              color: Colors.white,
                              size: 12,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _roleLabel(user?.role ?? ''),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (user != null)
                        FutureBuilder<Map<String, int>>(
                          future: _loadProfileStats(user.uid),
                          builder: (context, snapshot) {
                            final data =
                                snapshot.data ??
                                {'rsvps': 0, 'checkedIn': 0, 'attendance': 0};
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.25),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  _HeaderStat(
                                    label: 'RSVPs',
                                    value: '${data['rsvps']}',
                                  ),
                                  _HeaderStat(
                                    label: 'Checked in',
                                    value: '${data['checkedIn']}',
                                  ),
                                  _HeaderStat(
                                    label: 'Attendance',
                                    value: '${data['attendance']}%',
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Info card
                  _SectionCard(
                    child: Column(
                      children: [
                        _InfoRow(
                          icon: Icons.badge_outlined,
                          label: 'Student / Employee ID',
                          value: user?.studentId ?? '',
                          color: const Color(0xFF1565C0),
                        ),
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),
                        _InfoRow(
                          icon: Icons.school_outlined,
                          label: 'School',
                          value: AppConfig.schoolName,
                          color: const Color(0xFF1565C0),
                        ),
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),
                        _InfoRow(
                          icon: Icons.email_outlined,
                          label: 'Email',
                          value: user?.email ?? '',
                          color: const Color(0xFF1565C0),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Section label
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'QUICK ACTIONS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade500,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // QR Code (students only)
                  if (user?.isStudent == true) ...[
                    _ActionTile(
                      icon: Icons.qr_code_2_rounded,
                      title: 'My QR Code',
                      subtitle: 'Show at event check-in',
                      color: const Color(0xFF1565C0),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const QrScreen()),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // My events
                  _ActionTile(
                    icon: Icons.event_note_rounded,
                    title: 'My Events',
                    subtitle: 'View RSVPs and attendance history',
                    color: const Color(0xFF7B1FA2),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const MyEventsScreen()),
                    ),
                  ),
                  const SizedBox(height: 10),

                  _ActionTile(
                    icon: Icons.calendar_month_rounded,
                    title: 'Event calendar',
                    subtitle: 'Week or month view of your upcoming events',
                    color: const Color(0xFF1565C0),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const EventsCalendarScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Reminders
                  _ActionTile(
                    icon: Icons.notifications_active_rounded,
                    title: 'Event Reminders',
                    subtitle: 'Set how early you get notified',
                    color: const Color(0xFFE65100),
                    onTap: () => _showReminderDialog(
                      context,
                      ref,
                      user?.reminderMinutes ?? 60,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Delete account
                  if (user != null)
                    _ActionTile(
                      icon: Icons.delete_forever_rounded,
                      title: 'Delete Account',
                      subtitle: 'Permanently remove your account',
                      color: Colors.red.shade700,
                      onTap: () => _deleteAccount(user),
                    ),

                  const SizedBox(height: 32),

                  // Footer
                  Text(
                    'NYIT Campus Events · v1.6.0',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'For NYIT students and faculty only',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitials(String name) {
    final initials = name
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .take(2)
        .join();
    return Text(
      initials.isEmpty ? '?' : initials,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 28,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Color _roleColor(String role) {
    switch (role) {
      case AppConfig.roleSuperAdmin:
        return Colors.amber;
      case AppConfig.roleTeacher:
        return Colors.green;
      default:
        return Colors.blue;
    }
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case AppConfig.roleSuperAdmin:
        return Icons.admin_panel_settings_rounded;
      case AppConfig.roleTeacher:
        return Icons.school_rounded;
      default:
        return Icons.person_rounded;
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case AppConfig.roleSuperAdmin:
        return 'SUPER ADMIN';
      case AppConfig.roleTeacher:
        return 'FACULTY';
      default:
        return 'STUDENT';
    }
  }

  void _showReminderDialog(BuildContext context, WidgetRef ref, int current) {
    final options = [15, 30, 60, 120, 1440];
    final labels = ['15 min', '30 min', '1 hour', '2 hours', '1 day'];
    int selected = current;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Reminder time'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(options.length, (i) {
              return RadioListTile<int>(
                title: Text(labels[i]),
                value: options[i],
                groupValue: selected,
                onChanged: (val) => setState(() => selected = val!),
                activeColor: AppConfig.primaryColor,
              );
            }),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final user = ref.read(userModelProvider).asData?.value;
                if (user != null) {
                  await FirebaseFirestore.instance
                      .collection(AppConfig.usersCol)
                      .doc(user.uid)
                      .update({'reminderMinutes': selected});
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Reminder set to ${labels[options.indexOf(selected)]} before events',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.chevron_right_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  final String label;
  final String value;
  const _HeaderStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
