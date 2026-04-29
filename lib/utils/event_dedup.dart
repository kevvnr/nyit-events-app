import '../models/event_model.dart';

/// Single source of truth for "what counts as the same event" across the app.
///
/// Returns events deduplicated in this priority order:
///   1. Firestore document id (always unique by definition).
///   2. Non-empty importKey (e.g. `campusgroups:123`) — collapses the same
///      external event re-imported under a fresh Firestore id.
///   3. Content signature: lowercased title + startTime millis + lowercased
///      location key (or location name if no key). Catches duplicates where
///      the same event was created twice manually or via different imports.
///
/// Within a duplicate group we keep the document with the highest RSVP count
/// (then the oldest createdAt as a tiebreaker) so counts/displays land on the
/// "real" copy that students have actually engaged with.
List<EventModel> dedupeEvents(Iterable<EventModel> events) {
  // Bucket inputs by their strongest available identity.
  final byId = <String, EventModel>{};
  for (final e in events) {
    if (e.id.isEmpty) continue;
    final existing = byId[e.id];
    if (existing == null || _isBetter(e, existing)) {
      byId[e.id] = e;
    }
  }

  final byImport = <String, EventModel>{};
  final keptIds = <String>{};
  for (final e in byId.values) {
    final key = e.importKey.trim();
    if (key.isEmpty) {
      keptIds.add(e.id);
      continue;
    }
    final existing = byImport[key];
    if (existing == null || _isBetter(e, existing)) {
      byImport[key] = e;
    }
  }
  final afterImport = <EventModel>[
    ...byImport.values,
    for (final e in byId.values)
      if (keptIds.contains(e.id)) e,
  ];

  final bySignature = <String, EventModel>{};
  for (final e in afterImport) {
    final sig = _signature(e);
    final existing = bySignature[sig];
    if (existing == null || _isBetter(e, existing)) {
      bySignature[sig] = e;
    }
  }

  return bySignature.values.toList();
}

String _signature(EventModel e) {
  final loc = e.locationKey.trim().isNotEmpty
      ? e.locationKey.trim().toLowerCase()
      : e.locationName.trim().toLowerCase();
  return '${e.title.trim().toLowerCase()}|'
      '${e.startTime.millisecondsSinceEpoch}|'
      '$loc';
}

bool _isBetter(EventModel candidate, EventModel current) {
  if (candidate.rsvpCount != current.rsvpCount) {
    return candidate.rsvpCount > current.rsvpCount;
  }
  // Lower millis = older = preferred (stable canonical pick).
  return candidate.createdAt.millisecondsSinceEpoch <
      current.createdAt.millisecondsSinceEpoch;
}
