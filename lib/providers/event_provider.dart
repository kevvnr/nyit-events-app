import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/event_service.dart';
import '../models/event_model.dart';
import '../config/app_config.dart';

final eventServiceProvider = Provider<EventService>((ref) => EventService());

final eventStreamProvider = StreamProvider.family<EventModel?, String>((ref, eventId) {
  return ref.watch(eventServiceProvider).eventStream(eventId);
});

final eventsStreamProvider = StreamProvider<List<EventModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(AppConfig.eventsCol)
      .where('status', whereIn: [
        AppConfig.eventPublished,
        AppConfig.eventArchived,
      ])
      .snapshots()
      .map((snap) {
        final events = snap.docs.map((doc) => EventModel.fromFirestore(doc)).toList();
        // Sort client-side to avoid needing a composite Firestore index
        events.sort((a, b) => a.startTime.compareTo(b.startTime));
        return events;
      });
});

/// Emits true when the latest Firestore snapshot was served from local cache
/// (i.e. the device is offline or data hasn't synced yet).
final eventsFromCacheProvider = StreamProvider<bool>((ref) {
  return FirebaseFirestore.instance
      .collection(AppConfig.eventsCol)
      .where('status', whereIn: [
        AppConfig.eventPublished,
        AppConfig.eventArchived,
      ])
      .snapshots(includeMetadataChanges: true)
      .map((snap) => snap.metadata.isFromCache);
});

typedef RsvpArgs = ({String eventId, String userId});

final userRsvpProvider = FutureProvider.family<Map<String, dynamic>?, RsvpArgs>((ref, args) async {
  return ref.watch(eventServiceProvider).getUserRsvp(
    eventId: args.eventId,
    userId: args.userId,
  );
});

final userRsvpsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, userId) async {
  return ref.watch(eventServiceProvider).getUserRsvps(userId);
});

class EventsNotifier extends Notifier<AsyncValue<List<EventModel>>> {
  @override
  AsyncValue<List<EventModel>> build() => const AsyncValue.data([]);

  Future<void> loadEvents() async {
    state = const AsyncValue.loading();
    try {
      final events = await ref.read(eventServiceProvider).getEvents();
      state = AsyncValue.data(events);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<EventModel?> createEvent({
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
  try {
    final event =
        await ref.read(eventServiceProvider).createEvent(
              title: title,
              description: description,
              hostId: hostId,
              hostName: hostName,
              category: category,
              startTime: startTime,
              endTime: endTime,
              locationName: locationName,
              locationKey: locationKey,
              locationLat: locationLat,
              locationLng: locationLng,
              capacity: capacity,
              vibeTags: vibeTags,
              imageUrl: imageUrl,
            );
    final current = state.asData?.value ?? [];
    state = AsyncValue.data([...current, event]);
    return event;
  } catch (e) {
    return null;
  }
}
  Future<void> cancelEvent(String eventId) async {
    try {
      await ref.read(eventServiceProvider).cancelEvent(eventId);
      await loadEvents();
    } catch (e) {
      rethrow;
    }
  }
}

final eventsNotifierProvider = NotifierProvider<EventsNotifier, AsyncValue<List<EventModel>>>(() {
  return EventsNotifier();
});
