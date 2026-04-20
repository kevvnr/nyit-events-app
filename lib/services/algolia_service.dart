import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/algolia_config.dart';
import '../models/event_model.dart';

/// Thin wrapper around Algolia's REST API.
/// Uses the existing `http` package — no new dependency needed.
class AlgoliaService {
  AlgoliaService._();
  static final AlgoliaService instance = AlgoliaService._();

  static final _searchBase =
      'https://${AlgoliaConfig.appId}-dsn.algolia.net';
  static final _writeBase =
      'https://${AlgoliaConfig.appId}.algolia.net';

  Map<String, String> get _searchHeaders => {
        'X-Algolia-Application-Id': AlgoliaConfig.appId,
        'X-Algolia-API-Key': AlgoliaConfig.searchKey,
        'Content-Type': 'application/json',
      };

  Map<String, String> get _writeHeaders => {
        'X-Algolia-Application-Id': AlgoliaConfig.appId,
        'X-Algolia-API-Key': AlgoliaConfig.writeKey,
        'Content-Type': 'application/json',
      };

  // ─── Write ──────────────────────────────────────────────

  /// Create or update a single event record in the index.
  Future<void> indexEvent(EventModel event) async {
    try {
      final url = Uri.parse(
        '$_writeBase/1/indexes/${AlgoliaConfig.indexName}/${event.id}',
      );
      await http.put(
        url,
        headers: _writeHeaders,
        body: jsonEncode({
          'objectID': event.id,
          'title': event.title,
          'description': event.description,
          'category': event.category,
          'locationName': event.locationName,
          'locationKey': event.locationKey,
          'hostName': event.hostName,
          'vibeTags': event.vibeTags,
          'startTime': event.startTime.millisecondsSinceEpoch ~/ 1000,
          'endTime': event.endTime.millisecondsSinceEpoch ~/ 1000,
          'rsvpCount': event.rsvpCount,
          'capacity': event.capacity,
          'status': 'published',
        }),
      );
    } catch (_) {
      // Non-fatal — Algolia sync failures never block the main flow.
    }
  }

  /// Remove a single event record from the index.
  Future<void> deleteEvent(String eventId) async {
    try {
      final url = Uri.parse(
        '$_writeBase/1/indexes/${AlgoliaConfig.indexName}/$eventId',
      );
      await http.delete(url, headers: _writeHeaders);
    } catch (_) {}
  }

  /// Bulk-index a list of events (used for the initial sync from Firestore).
  /// Algolia batch API sends up to 1000 objects per request.
  Future<void> indexAllEvents(List<EventModel> events) async {
    if (events.isEmpty) return;
    try {
      const chunkSize = 1000;
      for (var i = 0; i < events.length; i += chunkSize) {
        final chunk = events.sublist(
          i,
          (i + chunkSize).clamp(0, events.length),
        );
        final url = Uri.parse(
          '$_writeBase/1/indexes/${AlgoliaConfig.indexName}/batch',
        );
        final requests = chunk.map((e) => {
              'action': 'updateObject',
              'body': {
                'objectID': e.id,
                'title': e.title,
                'description': e.description,
                'category': e.category,
                'locationName': e.locationName,
                'locationKey': e.locationKey,
                'hostName': e.hostName,
                'vibeTags': e.vibeTags,
                'startTime': e.startTime.millisecondsSinceEpoch ~/ 1000,
                'endTime': e.endTime.millisecondsSinceEpoch ~/ 1000,
                'rsvpCount': e.rsvpCount,
                'capacity': e.capacity,
                'status': 'published',
              },
            }).toList();
        await http.post(
          url,
          headers: _writeHeaders,
          body: jsonEncode({'requests': requests}),
        );
      }
    } catch (_) {}
  }

  // ─── Search ─────────────────────────────────────────────

  /// Returns matching event IDs in Algolia relevance order.
  /// Pass [category] to filter results to a single category.
  Future<List<String>> searchEventIds(
    String query, {
    String? category,
  }) async {
    try {
      final url = Uri.parse(
        '$_searchBase/1/indexes/${AlgoliaConfig.indexName}/query',
      );
      final filters = <String>['status:published'];
      if (category != null && category != 'All') {
        filters.add('category:"$category"');
      }
      final response = await http.post(
        url,
        headers: _searchHeaders,
        body: jsonEncode({
          'query': query,
          'filters': filters.join(' AND '),
          'hitsPerPage': 50,
          'attributesToRetrieve': ['objectID'],
        }),
      );
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final hits = data['hits'] as List<dynamic>? ?? [];
      return hits.map((h) => h['objectID'] as String).toList();
    } catch (_) {
      return [];
    }
  }
}
