import 'package:cloud_firestore/cloud_firestore.dart';

class AnnouncementService {
  static final _db = FirebaseFirestore.instance;
  static const String _col = 'announcements';

  // Stream all active announcements
  static Stream<List<Map<String, dynamic>>> announcementsStream() {
    return _db
        .collection(_col)
        .orderBy('createdAt', descending: true)
        .limit(10)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList());
  }

  // Post new announcement
  static Future<void> postAnnouncement({
    required String message,
    required String postedBy,
    String priority = 'normal', // normal, urgent
  }) async {
    await _db.collection(_col).add({
      'message': message,
      'postedBy': postedBy,
      'priority': priority,
      'createdAt': Timestamp.now(),
      'active': true,
    });
  }

  // Delete announcement
  static Future<void> deleteAnnouncement(String id) async {
    await _db.collection(_col).doc(id).delete();
  }
}