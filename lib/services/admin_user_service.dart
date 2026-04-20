import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/app_config.dart';
import 'event_service.dart';

/// Super-admin cleanup of a user's app data in Firestore (Spark-safe).
///
/// Note: deleting another user's Firebase Auth account requires Admin SDK,
/// which is not available on Firebase Spark without Cloud Functions deploy.
/// After this cleanup, remove the Auth user in Firebase Console when needed.
class AdminUserService {
  AdminUserService({FirebaseFirestore? db, EventService? eventService})
      : _db = db ?? FirebaseFirestore.instance,
        _events = eventService ?? EventService();

  final FirebaseFirestore _db;
  final EventService _events;
  static const String _studyGroupsCol = 'studyGroups';

  Future<void> permanentlyDeleteUserFirestoreData(String targetUid) async {
    // Phase 1: Delete hosted events sequentially — each has its own deep cleanup.
    final hostedEvents = await _db
        .collection(AppConfig.eventsCol)
        .where('hostId', isEqualTo: targetUid)
        .get();
    for (final doc in hostedEvents.docs) {
      await _events.permanentlyDeleteEvent(doc.id);
    }

    // Phase 2: Fetch all remaining user data in parallel.
    // Using explicit type parameter avoids runtime cast failures.
    final fetches = await Future.wait<QuerySnapshot<Map<String, dynamic>>>([
      _db.collection(_studyGroupsCol).where('hostId', isEqualTo: targetUid).get(),
      _db.collection(_studyGroupsCol).where('memberIds', arrayContains: targetUid).get(),
      _db.collection(AppConfig.rsvpsCol).where('userId', isEqualTo: targetUid).get(),
      _db.collection(AppConfig.notificationsCol).where('userId', isEqualTo: targetUid).get(),
      _db.collection(AppConfig.usersCol).doc(targetUid).collection('pastEvents').get(),
    ]);

    final hostedGroupsSnap = fetches[0];
    final memberGroupsSnap = fetches[1];
    final rsvpSnap = fetches[2];
    final notifSnap = fetches[3];
    final pastSnap = fetches[4];

    // Build member-group update futures (remove targetUid from each group).
    final memberGroupUpdates = <Future<void>>[];
    for (final doc in memberGroupsSnap.docs) {
      final data = doc.data();
      final ids = List<String>.from(data['memberIds'] ?? []);
      final names = List<String>.from(data['memberNames'] ?? []);
      final idx = ids.indexOf(targetUid);
      if (idx < 0) continue;
      ids.removeAt(idx);
      if (idx < names.length) names.removeAt(idx);
      memberGroupUpdates.add(
        doc.reference.update({'memberIds': ids, 'memberNames': names}),
      );
    }

    // Collect which event counts need recalculating after RSVP deletion.
    final touchedEvents = <String>{};
    for (final doc in rsvpSnap.docs) {
      final eid = doc.data()['eventId']?.toString();
      if (eid != null && eid.isNotEmpty) touchedEvents.add(eid);
    }

    // Phase 3: Delete / update everything in parallel.
    await Future.wait([
      _deleteDocs(hostedGroupsSnap.docs),
      _deleteDocs(rsvpSnap.docs),
      _deleteDocs(notifSnap.docs),
      _deleteDocs(pastSnap.docs),
      ...memberGroupUpdates,
    ]);

    // Phase 4: Recalculate counts for events that lost RSVPs.
    for (final eid in touchedEvents) {
      await _events.recalculateEventCounts(eid);
    }

    // Phase 5: Delete the user document last.
    await _db.collection(AppConfig.usersCol).doc(targetUid).delete();
  }

  Future<void> _deleteDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    const chunk = 400;
    for (var i = 0; i < docs.length; i += chunk) {
      final batch = _db.batch();
      final end = (i + chunk > docs.length) ? docs.length : i + chunk;
      for (var j = i; j < end; j++) {
        batch.delete(docs[j].reference);
      }
      await batch.commit();
    }
  }
}
