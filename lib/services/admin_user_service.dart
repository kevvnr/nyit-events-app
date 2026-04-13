import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/app_config.dart';
import 'event_service.dart';

/// Super-admin (and similar) cleanup of a user’s Firestore footprint.
///
/// Deleting another user’s **Firebase Auth** record still requires the Admin SDK
/// (Cloud Function or Firebase Console). This removes app data so the account
/// cannot use the app until re-registration, matching the router’s “deleted
/// Firestore doc” behavior for stale Auth sessions.
class AdminUserService {
  AdminUserService({FirebaseFirestore? db, EventService? eventService})
      : _db = db ?? FirebaseFirestore.instance,
        _events = eventService ?? EventService();

  final FirebaseFirestore _db;
  final EventService _events;

  static const String _studyGroupsCol = 'studyGroups';

  Future<void> permanentlyDeleteUserFirestoreData(String targetUid) async {
    final hostedEvents = await _db
        .collection(AppConfig.eventsCol)
        .where('hostId', isEqualTo: targetUid)
        .get();
    for (final doc in hostedEvents.docs) {
      await _events.permanentlyDeleteEvent(doc.id);
    }

    final hostedGroups =
        await _db.collection(_studyGroupsCol).where('hostId', isEqualTo: targetUid).get();
    for (final doc in hostedGroups.docs) {
      await doc.reference.delete();
    }

    final memberGroups = await _db
        .collection(_studyGroupsCol)
        .where('memberIds', arrayContains: targetUid)
        .get();
    for (final doc in memberGroups.docs) {
      final data = doc.data();
      final ids = List<String>.from(data['memberIds'] ?? []);
      final names = List<String>.from(data['memberNames'] ?? []);
      final idx = ids.indexOf(targetUid);
      if (idx < 0) continue;
      ids.removeAt(idx);
      if (idx < names.length) {
        names.removeAt(idx);
      }
      await doc.reference.update({
        'memberIds': ids,
        'memberNames': names,
      });
    }

    final rsvpSnap = await _db
        .collection(AppConfig.rsvpsCol)
        .where('userId', isEqualTo: targetUid)
        .get();
    final touchedEvents = <String>{};
    for (final doc in rsvpSnap.docs) {
      final eid = doc.data()['eventId']?.toString();
      if (eid != null && eid.isNotEmpty) {
        touchedEvents.add(eid);
      }
    }
    await _deleteDocs(rsvpSnap.docs);
    for (final eid in touchedEvents) {
      await _events.recalculateEventCounts(eid);
    }

    final notifSnap = await _db
        .collection(AppConfig.notificationsCol)
        .where('userId', isEqualTo: targetUid)
        .get();
    await _deleteDocs(notifSnap.docs);

    final pastSnap = await _db
        .collection(AppConfig.usersCol)
        .doc(targetUid)
        .collection('pastEvents')
        .get();
    await _deleteDocs(pastSnap.docs);

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
