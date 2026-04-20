import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/event_model.dart';
import '../config/app_config.dart';
import '../config/campus_locations.dart';
import 'algolia_service.dart';
import 'analytics_service.dart';
import 'live_activity_service.dart';
import 'notification_service.dart';

class EventService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<Map<String, int>> getRoomCapacityOverrides() async {
    final doc = await _db
        .collection(AppConfig.appConfigCol)
        .doc(AppConfig.appConfigDoc)
        .get();
    final data = doc.data();
    if (data == null) return {};
    final raw = data[AppConfig.roomCapacityOverridesField];
    if (raw is! Map<String, dynamic>) return {};
    final out = <String, int>{};
    raw.forEach((key, value) {
      final v = value is int ? value : int.tryParse('$value');
      if (v != null && v > 0) out[key] = v;
    });
    return out;
  }

  Future<Map<String, int>> getEffectiveRoomCapacities() async {
    final overrides = await getRoomCapacityOverrides();
    final out = <String, int>{};
    for (final loc in CampusLocations.all) {
      out[loc.id] = overrides[loc.id] ?? loc.maxCapacity;
    }
    return out;
  }

  static bool timeRangesOverlap(
    DateTime aStart,
    DateTime aEnd,
    DateTime bStart,
    DateTime bEnd,
  ) {
    return aStart.isBefore(bEnd) && bStart.isBefore(aEnd);
  }

  /// Returns a conflicting published event at the same canonical location, if any.
  Future<EventModel?> findSchedulingConflict({
    required String locationKey,
    required DateTime start,
    required DateTime end,
    String? excludeEventId,
  }) async {
    if (locationKey.isEmpty) return null;
    final snapshot = await _db
        .collection(AppConfig.eventsCol)
        .where('status', isEqualTo: AppConfig.eventPublished)
        .get();
    for (final doc in snapshot.docs) {
      if (doc.id == excludeEventId) continue;
      final e = EventModel.fromFirestore(doc);
      final key = CampusLocations.effectiveKeyFor(
        e.locationKey.isEmpty ? null : e.locationKey,
        e.locationName,
      );
      if (key != locationKey) continue;
      if (timeRangesOverlap(start, end, e.startTime, e.endTime)) {
        return e;
      }
    }
    return null;
  }

  /// Free campus locations that fit [capacity] and have no time overlap.
  Future<List<CampusLocation>> suggestFreeLocations({
    required int capacity,
    required DateTime start,
    required DateTime end,
    String? excludeEventId,
  }) async {
    final capacities = await getEffectiveRoomCapacities();
    final fits = CampusLocations.all.where((l) {
      final maxCap = capacities[l.id] ?? l.maxCapacity;
      return maxCap >= capacity;
    }).toList();
    final out = <CampusLocation>[];
    for (final loc in fits) {
      final conflict = await findSchedulingConflict(
        locationKey: loc.id,
        start: start,
        end: end,
        excludeEventId: excludeEventId,
      );
      if (conflict == null) out.add(loc);
    }
    out.sort((a, b) => a.maxCapacity.compareTo(b.maxCapacity));
    return out;
  }

  /// Returns canonical location ids that are already occupied
  /// during the requested time window.
  Future<Set<String>> getUnavailableLocationKeys({
    required DateTime start,
    required DateTime end,
    String? excludeEventId,
  }) async {
    final blocked = <String>{};
    final snapshot = await _db
        .collection(AppConfig.eventsCol)
        .where('status', isEqualTo: AppConfig.eventPublished)
        .get();
    for (final doc in snapshot.docs) {
      if (doc.id == excludeEventId) continue;
      final e = EventModel.fromFirestore(doc);
      if (!timeRangesOverlap(start, end, e.startTime, e.endTime)) {
        continue;
      }
      final key = CampusLocations.effectiveKeyFor(
        e.locationKey.isEmpty ? null : e.locationKey,
        e.locationName,
      );
      if (key.isNotEmpty) blocked.add(key);
    }
    return blocked;
  }

  // Get all published events
  Future<List<EventModel>> getEvents({int limit = 50}) async {
    final snapshot = await _db
        .collection(AppConfig.eventsCol)
        .where('status', isEqualTo: AppConfig.eventPublished)
        .limit(limit)
        .get();
    final events = snapshot.docs
        .map((doc) => EventModel.fromFirestore(doc))
        .toList();
    // Sort client-side to avoid needing a composite Firestore index
    events.sort((a, b) => a.startTime.compareTo(b.startTime));
    return events;
  }

  // Stream single event for real-time updates
  Stream<EventModel?> eventStream(String eventId) {
    return _db
        .collection(AppConfig.eventsCol)
        .doc(eventId)
        .snapshots()
        .map((doc) => doc.exists ? EventModel.fromFirestore(doc) : null);
  }

  // Get single event by ID
  Future<EventModel?> getEventById(String eventId) async {
    try {
      final doc = await _db.collection(AppConfig.eventsCol).doc(eventId).get();
      if (doc.exists) return EventModel.fromFirestore(doc);
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<EventModel> createEvent({
    required String title,
    required String description,
    required String hostId,
    required String hostName,
    required String category,
    required DateTime startTime,
    required DateTime endTime,
    required String locationName,
    String locationKey = '',
    required double locationLat,
    required double locationLng,
    required int capacity,
    List<String> vibeTags = const [],
    String? imageUrl,
  }) async {
    final docRef = _db.collection(AppConfig.eventsCol).doc();

    final event = EventModel(
      id: docRef.id,
      title: title,
      description: description,
      hostId: hostId,
      hostName: hostName,
      category: category,
      vibeTags: vibeTags,
      startTime: startTime,
      endTime: endTime,
      locationName: locationName,
      locationKey: locationKey,
      locationLat: locationLat,
      locationLng: locationLng,
      capacity: capacity,
      createdAt: DateTime.now(),
      imageUrl: imageUrl ?? '',
      importKey: '',
    );

    await docRef.set(event.toFirestore());
    await AlgoliaService.instance.indexEvent(event);
    return event;
  }

  /// Creates or updates a published event keyed by [importKey] (e.g. campusgroups:123).
  /// Preserves RSVP counts when updating.
  Future<EventModel> upsertImportedEvent({
    required String importKey,
    required String title,
    required String description,
    required String hostId,
    required String hostName,
    required String category,
    required DateTime startTime,
    required DateTime endTime,
    required String locationName,
    String locationKey = '',
    double locationLat = 0,
    double locationLng = 0,
    required int capacity,
    List<String> vibeTags = const [],
    String imageUrl = '',
  }) async {
    final existing = await _db
        .collection(AppConfig.eventsCol)
        .where('importKey', isEqualTo: importKey)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      final doc = existing.docs.first;
      final current = EventModel.fromFirestore(doc);
      final cap = capacity > current.capacity ? capacity : current.capacity;
      await doc.reference.update({
        'title': title,
        'description': description,
        'hostName': hostName,
        'category': category,
        'startTime': Timestamp.fromDate(startTime),
        'endTime': Timestamp.fromDate(endTime),
        'locationName': locationName,
        'locationKey': locationKey,
        'locationLat': locationLat,
        'locationLng': locationLng,
        'capacity': cap,
        'vibeTags': vibeTags,
        'imageUrl': imageUrl,
        'importKey': importKey,
        'status': AppConfig.eventPublished,
      });
      final snap = await doc.reference.get();
      return EventModel.fromFirestore(snap);
    }

    final docRef = _db.collection(AppConfig.eventsCol).doc();
    final event = EventModel(
      id: docRef.id,
      title: title,
      description: description,
      hostId: hostId,
      hostName: hostName,
      category: category,
      vibeTags: vibeTags,
      startTime: startTime,
      endTime: endTime,
      locationName: locationName,
      locationKey: locationKey,
      locationLat: locationLat,
      locationLng: locationLng,
      capacity: capacity,
      createdAt: DateTime.now(),
      imageUrl: imageUrl,
      importKey: importKey,
    );
    await docRef.set(event.toFirestore());
    await AlgoliaService.instance.indexEvent(event);
    return event;
  }

  // Update event
  Future<void> updateEvent(String eventId, Map<String, dynamic> data) async {
    await _db.collection(AppConfig.eventsCol).doc(eventId).update(data);
    // Re-fetch and sync the full updated record to Algolia.
    final snap = await _db.collection(AppConfig.eventsCol).doc(eventId).get();
    if (snap.exists) {
      await AlgoliaService.instance.indexEvent(EventModel.fromFirestore(snap));
    }
  }

  // Cancel event and notify all RSVPs
  Future<void> cancelEvent(String eventId) async {
    final batch = _db.batch();

    final eventRef = _db.collection(AppConfig.eventsCol).doc(eventId);
    batch.update(eventRef, {'status': AppConfig.eventCancelled});

    final rsvps = await _db
        .collection(AppConfig.rsvpsCol)
        .where('eventId', isEqualTo: eventId)
        .where('status', isEqualTo: AppConfig.rsvpConfirmed)
        .get();

    for (final rsvp in rsvps.docs) {
      final notifRef = _db.collection(AppConfig.notificationsCol).doc();
      batch.set(notifRef, {
        'userId': rsvp['userId'],
        'type': AppConfig.notifCancel,
        'eventId': eventId,
        'message': 'An event you RSVP\'d for has been cancelled.',
        'read': false,
        'createdAt': Timestamp.now(),
      });
    }

    await batch.commit();
    await AlgoliaService.instance.deleteEvent(eventId);
  }

  /// Hard-delete an event and all dependent Firestore data (RSVPs, in-app
  /// notifications, per-user past-event history, reaction subdocs). Does not
  /// delete the Firebase Auth accounts of attendees.
  Future<void> permanentlyDeleteEvent(String eventId) async {
    final eventRef = _db.collection(AppConfig.eventsCol).doc(eventId);
    final eventSnap = await eventRef.get();
    String imageUrl = '';
    if (eventSnap.exists) {
      imageUrl = (eventSnap.data()?['imageUrl'] ?? '').toString();
    }

    await LiveActivityService.instance.end(eventId);
    await NotificationService.cancelEventReminder(eventId);

    await _deleteDocumentsFromQuery(
      _db
          .collection(AppConfig.rsvpsCol)
          .where('eventId', isEqualTo: eventId),
    );

    await _deleteDocumentsFromQuery(
      _db
          .collection(AppConfig.notificationsCol)
          .where('eventId', isEqualTo: eventId),
    );

    try {
      final pastSnap = await _db
          .collectionGroup('pastEvents')
          .where('eventId', isEqualTo: eventId)
          .get();
      await _deleteDocumentsInBatches(pastSnap.docs);
    } catch (e) {
      // non-fatal — pastEvents subcollection cleanup skipped
    }

    final reactionsSnap = await eventRef.collection('userReactions').get();
    await _deleteDocumentsInBatches(reactionsSnap.docs);

    if (imageUrl.isNotEmpty) {
      try {
        if (imageUrl.contains('firebasestorage')) {
          await FirebaseStorage.instance.refFromURL(imageUrl).delete();
        }
      } catch (e) {
        // non-fatal — storage object already deleted or unreachable
      }
    }

    await eventRef.delete();
    await AlgoliaService.instance.deleteEvent(eventId);
  }

  Future<void> _deleteDocumentsFromQuery(Query<Map<String, dynamic>> query) async {
    while (true) {
      final snap = await query.limit(400).get();
      if (snap.docs.isEmpty) break;
      await _deleteDocumentsInBatches(snap.docs);
    }
  }

  Future<void> _deleteDocumentsInBatches(
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

  // RSVP for event
  Future<String> rsvpEvent({
    required String eventId,
    required String userId,
    required String qrToken,
  }) async {
    String resultStatus = '';

    // Read before transaction
    final existingRsvp = await _db
        .collection(AppConfig.rsvpsCol)
        .where('eventId', isEqualTo: eventId)
        .where('userId', isEqualTo: userId)
        .where(
          'status',
          whereIn: [AppConfig.rsvpConfirmed, AppConfig.rsvpWaitlist],
        )
        .get();

    if (existingRsvp.docs.isNotEmpty) {
      throw Exception('Already RSVP\'d for this event');
    }

    final eventDoc = await _db
        .collection(AppConfig.eventsCol)
        .doc(eventId)
        .get();

    if (!eventDoc.exists) throw Exception('Event not found');
    final event = EventModel.fromFirestore(eventDoc);
    if (event.isCancelled) throw Exception('Event is cancelled');

    await _db.runTransaction((transaction) async {
      final freshEvent = await transaction.get(
        _db.collection(AppConfig.eventsCol).doc(eventId),
      );
      final currentRsvpCount = (freshEvent.data()?['rsvpCount'] ?? 0) as int;
      final capacity = (freshEvent.data()?['capacity'] ?? 0) as int;

      final rsvpRef = _db.collection(AppConfig.rsvpsCol).doc();
      final eventRef = _db.collection(AppConfig.eventsCol).doc(eventId);

      if (currentRsvpCount < capacity) {
        transaction.set(rsvpRef, {
          'eventId': eventId,
          'userId': userId,
          'status': AppConfig.rsvpConfirmed,
          'qrToken': qrToken,
          'checkedIn': false,
          'checkedInAt': null,
          'createdAt': Timestamp.now(),
        });
        transaction.update(eventRef, {'rsvpCount': FieldValue.increment(1)});
        resultStatus = AppConfig.rsvpConfirmed;
      } else {
        transaction.set(rsvpRef, {
          'eventId': eventId,
          'userId': userId,
          'status': AppConfig.rsvpWaitlist,
          'qrToken': qrToken,
          'checkedIn': false,
          'checkedInAt': null,
          'createdAt': Timestamp.now(),
        });
        transaction.update(eventRef, {
          'waitlistCount': FieldValue.increment(1),
        });
        resultStatus = AppConfig.rsvpWaitlist;
      }
    });

    await AnalyticsService.instance.logEvent(
      'rsvp_action',
      parameters: {'event_id': eventId, 'status': resultStatus},
    );
    await _db.collection(AppConfig.usersCol).doc(userId).set({
      'lastActiveAt': Timestamp.now(),
      'segmentEngagementTier': resultStatus == AppConfig.rsvpConfirmed
          ? 'engaged'
          : 'interested',
      'segmentInterestCategories': FieldValue.arrayUnion([event.category]),
    }, SetOptions(merge: true));
    if (resultStatus == AppConfig.rsvpConfirmed) {
      await LiveActivityService.instance.startOrUpdate(
        eventId: event.id,
        title: event.title,
        startTime: event.startTime,
        endTime: event.endTime,
        location: event.locationName,
      );
    }

    return resultStatus;
  }

  // Cancel RSVP and auto-promote waitlist
  // Reads done BEFORE transaction to avoid Firestore read-after-write issues
  Future<void> cancelRsvp({
    required String eventId,
    required String userId,
  }) async {
    // Read RSVP before transaction
    final rsvpQuery = await _db
        .collection(AppConfig.rsvpsCol)
        .where('eventId', isEqualTo: eventId)
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: AppConfig.rsvpConfirmed)
        .get();

    if (rsvpQuery.docs.isEmpty) return;

    // Read waitlist before transaction
    final waitlistQuery = await _db
        .collection(AppConfig.rsvpsCol)
        .where('eventId', isEqualTo: eventId)
        .where('status', isEqualTo: AppConfig.rsvpWaitlist)
        .orderBy('createdAt', descending: false)
        .limit(1)
        .get();

    final rsvpRef = rsvpQuery.docs.first.reference;
    final eventRef = _db.collection(AppConfig.eventsCol).doc(eventId);

    await _db.runTransaction((transaction) async {
      // Cancel the RSVP
      transaction.update(rsvpRef, {'status': AppConfig.rsvpCancelled});
      transaction.update(eventRef, {'rsvpCount': FieldValue.increment(-1)});

      // Promote waitlist if someone is waiting
      if (waitlistQuery.docs.isNotEmpty) {
        final nextInLine = waitlistQuery.docs.first;
        transaction.update(nextInLine.reference, {
          'status': AppConfig.rsvpConfirmed,
        });
        transaction.update(eventRef, {
          'rsvpCount': FieldValue.increment(1),
          'waitlistCount': FieldValue.increment(-1),
        });

        // Notify promoted student
        final notifRef = _db.collection(AppConfig.notificationsCol).doc();
        transaction.set(notifRef, {
          'userId': nextInLine['userId'],
          'type': AppConfig.notifPromoted,
          'eventId': eventId,
          'message':
              'You\'ve been moved off the waitlist! You\'re now confirmed.',
          'read': false,
          'createdAt': Timestamp.now(),
        });
      }
    });

    await AnalyticsService.instance.logEvent(
      'rsvp_cancelled',
      parameters: {'event_id': eventId},
    );
    await LiveActivityService.instance.end(eventId);
  }

  // Get user's RSVP for a specific event
  Future<Map<String, dynamic>?> getUserRsvp({
    required String eventId,
    required String userId,
  }) async {
    try {
      final snapshot = await _db
          .collection(AppConfig.rsvpsCol)
          .where('eventId', isEqualTo: eventId)
          .where('userId', isEqualTo: userId)
          .where(
            'status',
            whereIn: [AppConfig.rsvpConfirmed, AppConfig.rsvpWaitlist],
          )
          .get();

      if (snapshot.docs.isEmpty) return null;
      return {'id': snapshot.docs.first.id, ...snapshot.docs.first.data()};
    } catch (e) {
      return null;
    }
  }

  // Get all user RSVPs
  Future<List<Map<String, dynamic>>> getUserRsvps(String userId) async {
    try {
      final snapshot = await _db
          .collection(AppConfig.rsvpsCol)
          .where('userId', isEqualTo: userId)
          .where(
            'status',
            whereIn: [AppConfig.rsvpConfirmed, AppConfig.rsvpWaitlist],
          )
          .get();
      return snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
    } catch (e) {
      return [];
    }
  }

  // Toggle reaction — one per user per emoji
  Future<void> toggleReaction({
    required String eventId,
    required String userId,
    required String emoji,
  }) async {
    final reactionDoc = await _db
        .collection(AppConfig.eventsCol)
        .doc(eventId)
        .collection('userReactions')
        .doc(userId)
        .get();

    final existingReactions = Map<String, dynamic>.from(
      reactionDoc.data() ?? {},
    );
    final alreadyReacted = existingReactions[emoji] == true;

    final batch = _db.batch();

    final eventRef = _db.collection(AppConfig.eventsCol).doc(eventId);
    final reactionRef = _db
        .collection(AppConfig.eventsCol)
        .doc(eventId)
        .collection('userReactions')
        .doc(userId);

    if (alreadyReacted) {
      batch.update(eventRef, {'reactions.$emoji': FieldValue.increment(-1)});
      batch.update(reactionRef, {emoji: FieldValue.delete()});
    } else {
      batch.update(eventRef, {'reactions.$emoji': FieldValue.increment(1)});
      batch.set(reactionRef, {emoji: true}, SetOptions(merge: true));
    }

    await batch.commit();
  }

  // Get user's reactions for an event
  Future<Map<String, bool>> getUserReactions({
    required String eventId,
    required String userId,
  }) async {
    try {
      final doc = await _db
          .collection(AppConfig.eventsCol)
          .doc(eventId)
          .collection('userReactions')
          .doc(userId)
          .get();
      if (!doc.exists) return {};
      return Map<String, bool>.from(doc.data() ?? {});
    } catch (e) {
      return {};
    }
  }

  // Add reaction to event
  Future<void> addReaction({
    required String eventId,
    required String emoji,
  }) async {
    await _db.collection(AppConfig.eventsCol).doc(eventId).update({
      'reactions.$emoji': FieldValue.increment(1),
    });
  }

  // Check in student via QR
  Future<Map<String, dynamic>?> checkInStudent({
    required String qrToken,
    required String eventId,
  }) async {
    try {
      final snapshot = await _db
          .collection(AppConfig.rsvpsCol)
          .where('qrToken', isEqualTo: qrToken)
          .where('eventId', isEqualTo: eventId)
          .where('status', isEqualTo: AppConfig.rsvpConfirmed)
          .get();

      if (snapshot.docs.isEmpty) return null;

      final rsvpDoc = snapshot.docs.first;

      if (rsvpDoc['checkedIn'] == true) {
        return {'alreadyCheckedIn': true, ...rsvpDoc.data()};
      }

      await rsvpDoc.reference.update({
        'checkedIn': true,
        'checkedInAt': Timestamp.now(),
      });
      await LiveActivityService.instance.end(eventId);
      await AnalyticsService.instance.logEvent(
        'checkin_success',
        parameters: {'event_id': eventId},
      );

      final userDoc = await _db
          .collection(AppConfig.usersCol)
          .doc(rsvpDoc['userId'])
          .get();
      await userDoc.reference.set({
        'lastActiveAt': Timestamp.now(),
        'segmentEngagementTier': 'active_attendee',
      }, SetOptions(merge: true));

      return {
        'alreadyCheckedIn': false,
        ...rsvpDoc.data(),
        'userName': userDoc['name'],
        'studentId': userDoc['studentId'],
      };
    } catch (e) {
      rethrow;
    }
  }

  // Get checked in count for an event
  Future<int> getCheckedInCount(String eventId) async {
    try {
      final snapshot = await _db
          .collection(AppConfig.rsvpsCol)
          .where('eventId', isEqualTo: eventId)
          .where('status', isEqualTo: AppConfig.rsvpConfirmed)
          .where('checkedIn', isEqualTo: true)
          .get();
      return snapshot.docs.length;
    } catch (e) {
      return 0;
    }
  }

  // Admin removes student from event
  Future<void> removeStudentFromEvent({
    required String eventId,
    required String userId,
    required String rsvpId,
    required bool wasConfirmed,
  }) async {
    // Read waitlist before transaction
    final waitlistQuery = wasConfirmed
        ? await _db
              .collection(AppConfig.rsvpsCol)
              .where('eventId', isEqualTo: eventId)
              .where('status', isEqualTo: AppConfig.rsvpWaitlist)
              .orderBy('createdAt', descending: false)
              .limit(1)
              .get()
        : null;

    await _db.runTransaction((transaction) async {
      final eventRef = _db.collection(AppConfig.eventsCol).doc(eventId);
      final rsvpRef = _db.collection(AppConfig.rsvpsCol).doc(rsvpId);

      transaction.update(rsvpRef, {'status': AppConfig.rsvpCancelled});

      if (wasConfirmed) {
        transaction.update(eventRef, {'rsvpCount': FieldValue.increment(-1)});

        if (waitlistQuery != null && waitlistQuery.docs.isNotEmpty) {
          final nextInLine = waitlistQuery.docs.first;
          transaction.update(nextInLine.reference, {
            'status': AppConfig.rsvpConfirmed,
          });
          transaction.update(eventRef, {
            'rsvpCount': FieldValue.increment(1),
            'waitlistCount': FieldValue.increment(-1),
          });

          final notifRef = _db.collection(AppConfig.notificationsCol).doc();
          transaction.set(notifRef, {
            'userId': nextInLine['userId'],
            'type': AppConfig.notifPromoted,
            'eventId': eventId,
            'message':
                'You\'ve been moved off the waitlist! You\'re now confirmed for the event.',
            'read': false,
            'createdAt': Timestamp.now(),
          });
        }
      } else {
        transaction.update(eventRef, {
          'waitlistCount': FieldValue.increment(-1),
        });
      }

      // Notify removed student
      final notifRef = _db.collection(AppConfig.notificationsCol).doc();
      transaction.set(notifRef, {
        'userId': userId,
        'type': AppConfig.notifCancel,
        'eventId': eventId,
        'message': 'You have been removed from this event by an administrator.',
        'read': false,
        'createdAt': Timestamp.now(),
      });
    });
  }

  // Get user's past events
  Future<List<Map<String, dynamic>>> getPastEvents(String userId) async {
    try {
      final snapshot = await _db
          .collection(AppConfig.usersCol)
          .doc(userId)
          .collection('pastEvents')
          .orderBy('eventDate', descending: true)
          .get();
      return snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
    } catch (e) {
      return [];
    }
  }

  // Write past event to user history
  Future<void> writePastEvent({
    required String userId,
    required EventModel event,
    required bool attended,
  }) async {
    await _db
        .collection(AppConfig.usersCol)
        .doc(userId)
        .collection('pastEvents')
        .doc(event.id)
        .set({
          'eventId': event.id,
          'eventTitle': event.title,
          'category': event.category,
          'eventDate': Timestamp.fromDate(event.startTime),
          'attended': attended,
          'hostName': event.hostName,
        });
  }

  // Recalculate rsvpCount and waitlistCount for an event
  // Fixes any drift between actual RSVPs and stored counts
  Future<void> recalculateEventCounts(String eventId) async {
    try {
      final confirmed = await _db
          .collection(AppConfig.rsvpsCol)
          .where('eventId', isEqualTo: eventId)
          .where('status', isEqualTo: AppConfig.rsvpConfirmed)
          .get();

      final waitlist = await _db
          .collection(AppConfig.rsvpsCol)
          .where('eventId', isEqualTo: eventId)
          .where('status', isEqualTo: AppConfig.rsvpWaitlist)
          .get();

      await _db.collection(AppConfig.eventsCol).doc(eventId).update({
        'rsvpCount': confirmed.docs.length,
        'waitlistCount': waitlist.docs.length,
      });
    } catch (e) {
      // non-fatal — count drift remains until next recalculation
    }
  }

  // Recalculate counts for ALL events
  Future<void> recalculateAllEventCounts() async {
    try {
      final events = await _db.collection(AppConfig.eventsCol).get();
      for (final event in events.docs) {
        await recalculateEventCounts(event.id);
      }
    } catch (e) {
      // non-fatal
    }
  }

  // Archive a single past event
  Future<void> archiveEvent(String eventId) async {
    await _db.collection(AppConfig.eventsCol).doc(eventId).update({
      'status': AppConfig.eventArchived,
    });
    await AlgoliaService.instance.deleteEvent(eventId);
  }

  // Auto-archive all events that have ended
  Future<int> archiveEndedEvents() async {
    final now = Timestamp.now();
    final snap = await _db
        .collection(AppConfig.eventsCol)
        .where('status', isEqualTo: AppConfig.eventPublished)
        .get();

    int count = 0;
    for (final doc in snap.docs) {
      final endTime = doc.data()['endTime'] as Timestamp?;
      if (endTime != null && endTime.compareTo(now) < 0) {
        await doc.reference.update({'status': AppConfig.eventArchived});
        count++;
      }
    }
    return count;
  }

  // Send a reminder notification to all confirmed RSVPs for an event
  Future<int> sendEventReminder({
    required String eventId,
    required String eventTitle,
    required String message,
  }) async {
    try {
      final rsvps = await _db
          .collection(AppConfig.rsvpsCol)
          .where('eventId', isEqualTo: eventId)
          .where('status', isEqualTo: AppConfig.rsvpConfirmed)
          .get();

      final batch = _db.batch();
      int count = 0;
      for (final rsvp in rsvps.docs) {
        final notifRef = _db.collection(AppConfig.notificationsCol).doc();
        batch.set(notifRef, {
          'userId': rsvp['userId'],
          'type': 'reminder',
          'eventId': eventId,
          'message': message,
          'read': false,
          'createdAt': Timestamp.now(),
        });
        count++;
      }
      await batch.commit();
      return count;
    } catch (e) {
      return 0;
    }
  }

  // Get all archived events with attendance stats
  Future<List<Map<String, dynamic>>> getArchivedEvents() async {
    try {
      final snap = await _db
          .collection(AppConfig.eventsCol)
          .where('status', isEqualTo: AppConfig.eventArchived)
          .get();

      final events = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final data = doc.data();

        // Get confirmed RSVPs
        final rsvps = await _db
            .collection(AppConfig.rsvpsCol)
            .where('eventId', isEqualTo: doc.id)
            .where('status', isEqualTo: AppConfig.rsvpConfirmed)
            .get();

        // Get checked in count
        final checkedIn = rsvps.docs
            .where((r) => r.data()['checkedIn'] == true)
            .length;

        events.add({
          'id': doc.id,
          ...data,
          'actualRsvpCount': rsvps.docs.length,
          'actualCheckedIn': checkedIn,
          'attendanceRate': rsvps.docs.isEmpty
              ? 0.0
              : (checkedIn / rsvps.docs.length).clamp(0.0, 1.0),
        });
      }
      return events;
    } catch (e) {
      return [];
    }
  }
}
