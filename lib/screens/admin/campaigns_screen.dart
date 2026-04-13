import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../config/app_config.dart';

class CampaignsScreen extends StatefulWidget {
  const CampaignsScreen({super.key});

  @override
  State<CampaignsScreen> createState() => _CampaignsScreenState();
}

class _CampaignsScreenState extends State<CampaignsScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _roleController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _roleController.dispose();
    super.dispose();
  }

  Future<void> _sendCampaign() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.isEmpty || body.isEmpty) return;

    setState(() => _sending = true);
    try {
      final db = FirebaseFirestore.instance;
      final role = _roleController.text.trim();
      Query<Map<String, dynamic>> q = db.collection(AppConfig.usersCol);
      if (role.isNotEmpty) {
        q = q.where('role', isEqualTo: role);
      }
      final users = await q.get();
      if (users.docs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No users matched this segment.')),
        );
        return;
      }

      final batch = db.batch();
      for (final u in users.docs) {
        final notifRef = db.collection(AppConfig.notificationsCol).doc();
        batch.set(notifRef, {
          'userId': u.id,
          'type': AppConfig.notifUpdate,
          'eventId': '',
          'message': '$title\n$body',
          'read': false,
          'createdAt': Timestamp.now(),
          'campaign': true,
        });
      }
      await batch.commit();

      await db.collection(AppConfig.campaignsCol).add({
        'title': title,
        'body': body,
        'segmentRole': role.isEmpty ? 'all' : role,
        'status': 'sent_in_app_only',
        'sentCount': users.docs.length,
        'createdAt': Timestamp.now(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Campaign sent in-app to ${users.docs.length} users.'),
        ),
      );
      _titleController.clear();
      _bodyController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Send failed: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Campaigns')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _bodyController,
              decoration: const InputDecoration(labelText: 'Body'),
              maxLines: 3,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _roleController,
              decoration: const InputDecoration(
                labelText: 'Role segment (optional)',
                hintText: 'student / teacher / superadmin',
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _sending ? null : _sendCampaign,
                icon: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(_sending ? 'Sending...' : 'Send in-app campaign'),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Free mode: campaigns are delivered as in-app notifications only (no Cloud Functions required).',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection(AppConfig.campaignsCol)
                    .orderBy('createdAt', descending: true)
                    .limit(30)
                    .snapshots(),
                builder: (context, snap) {
                  final docs = snap.data?.docs ?? const [];
                  if (docs.isEmpty) {
                    return const Center(child: Text('No campaigns yet'));
                  }
                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (_, i) {
                      final d = docs[i].data();
                      return ListTile(
                        title: Text((d['title'] ?? '').toString()),
                        subtitle: Text((d['body'] ?? '').toString()),
                        trailing: Text((d['status'] ?? '').toString()),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
