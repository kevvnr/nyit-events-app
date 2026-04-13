import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../config/app_config.dart';
import 'event_service.dart';

class CampusGroupsImportResult {
  final int saved;
  final int skipped;
  final List<String> issues;

  const CampusGroupsImportResult({
    required this.saved,
    required this.skipped,
    required this.issues,
  });
}

/// Parses CampusGroups / Engage-style JSON and upserts [EventModel] docs.
class CampusGroupsImportService {
  CampusGroupsImportService(this._events);

  final EventService _events;

  static Future<String> fetchEventsWithBearer({
    required String bearerToken,
    String? requestUrl,
  }) async {
    final raw = bearerToken.trim();
    final auth = raw.toLowerCase().startsWith('bearer ')
        ? raw
        : 'Bearer $raw';
    final uri = Uri.parse(
      (requestUrl != null && requestUrl.trim().isNotEmpty)
          ? requestUrl.trim()
          : '${AppConfig.campusGroupsEventsApiUrl}?page=1&per_page=100',
    );
    final res = await http.get(
      uri,
      headers: {
        'Authorization': auth,
        'Accept': 'application/json',
      },
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final snippet = res.body.length > 280 ? '${res.body.substring(0, 280)}…' : res.body;
      throw Exception('Request failed (${res.statusCode}): $snippet');
    }
    return res.body;
  }

  static List<Map<String, dynamic>> _mapsFromMobileEventsList(List<dynamic> list) {
    final out = <Map<String, dynamic>>[];
    for (final e in list) {
      if (e is! Map) continue;
      final row = _mobileRowToEventMap(Map<String, dynamic>.from(e));
      if (row != null) out.add(row);
    }
    return out;
  }

  static List<Map<String, dynamic>> _mapsFromGenericList(List<dynamic> list) {
    return list
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  static List<Map<String, dynamic>> extractEventObjects(dynamic decoded) {
    if (decoded is List) {
      if (_looksLikeMobileEventsList(decoded)) {
        return _mapsFromMobileEventsList(decoded);
      }
      return _mapsFromGenericList(decoded);
    }
    if (decoded is Map) {
      final m = Map<String, dynamic>.from(decoded);
      const listKeys = [
        'events',
        'data',
        'results',
        'items',
        'records',
        'rows',
        'response',
        'list',
        'mobile_events_list',
      ];
      for (final key in listKeys) {
        final v = m[key];
        if (v is! List) continue;
        if (_looksLikeMobileEventsList(v)) {
          return _mapsFromMobileEventsList(v);
        }
        final generic = _mapsFromGenericList(v);
        if (generic.isNotEmpty) return generic;
      }
      for (final v in m.values) {
        if (v is! List) continue;
        if (_looksLikeMobileEventsList(v)) {
          return _mapsFromMobileEventsList(v);
        }
      }
      if (_looksLikeEventPayload(m)) {
        return [m];
      }
    }
    return [];
  }

  static bool _looksLikeEventPayload(Map<String, dynamic> m) {
    return m.containsKey('title') ||
        m.containsKey('name') ||
        m.containsKey('event_title');
  }

  /// CampusGroups web `mobile_events_list` XHR: rows use [fields] + p0, p1, …
  static bool _looksLikeMobileEventsList(List<dynamic> list) {
    for (final e in list) {
      if (e is Map && e['fields'] is String) {
        final f = e['fields'] as String;
        if (f.contains('eventId') && f.contains('eventName')) return true;
      }
    }
    return false;
  }

  static Map<String, dynamic>? _mobileRowToEventMap(Map<String, dynamic> m) {
    final fieldsRaw = m['fields'];
    if (fieldsRaw is! String) return null;
    final labels = fieldsRaw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (!labels.contains('eventId')) return null;

    final labeled = <String, dynamic>{};
    for (var i = 0; i < labels.length; i++) {
      final pk = 'p$i';
      if (!m.containsKey(pk)) continue;
      labeled[labels[i]] = m[pk];
    }

    final eventId = labeled['eventId']?.toString().trim();
    final title = labeled['eventName']?.toString().trim();
    if (eventId == null || eventId.isEmpty || title == null || title.isEmpty) {
      return null;
    }

    final htmlDates = labeled['eventDates']?.toString() ?? '';
    final aria = labeled['ariaEventDetails']?.toString() ?? '';
    final range = _parseMobileEventDateRange(htmlDates, aria);
    if (range == null) return null;

    final loc = labeled['eventLocation']?.toString().trim() ?? '';
    final cat = labeled['eventCategory']?.toString().trim() ?? '';
    final pic = labeled['eventPicture']?.toString().trim() ?? '';
    final desc = labeled['ariaEventDetailsWithLocation']?.toString().trim() ??
        aria;

    return {
      'id': eventId,
      'eventId': eventId,
      'title': title,
      'name': title,
      'start_time': range.$1.toIso8601String(),
      'end_time': range.$2.toIso8601String(),
      'location_name': loc,
      'locationName': loc,
      'category': cat,
      'event_type': cat,
      'image_url': pic,
      'imageUrl': pic,
      'description': desc,
    };
  }

  /// Parses [eventDates] HTML (two &lt;p&gt; cells) or [aria] fallback.
  static (DateTime, DateTime)? _parseMobileEventDateRange(
    String htmlDates,
    String aria,
  ) {
    var chunks = _eventDatesHtmlChunks(htmlDates);
    if (chunks.length < 2) {
      chunks = RegExp(r'>([^<]*)<')
          .allMatches(htmlDates)
          .map((x) => x.group(1)?.trim() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    }

    if (chunks.length >= 2) {
      final dateLine = chunks[0];
      final timeLine = _normalizeMobileTimeLine(chunks[1]);
      final day = _tryParseUsShortDate(dateLine);
      final times = _parseMobileTimeRange(timeLine);
      if (day != null && times != null) {
        final start = DateTime(day.year, day.month, day.day, times.$1, times.$2);
        var end = DateTime(day.year, day.month, day.day, times.$3, times.$4);
        if (!end.isAfter(start)) {
          end = end.add(const Duration(days: 1));
        }
        return (start, end);
      }
    }

    return _parseAriaEventRange(aria);
  }

  static List<String> _eventDatesHtmlChunks(String html) {
    if (html.trim().isEmpty) return const [];
    final re = RegExp(r'<p\b[^>]*>(.*?)</p>', caseSensitive: false, dotAll: true);
    return re
        .allMatches(html)
        .map((m) {
          final inner = m.group(1) ?? '';
          return inner.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
        })
        .where((s) => s.isNotEmpty)
        .toList();
  }

  static String _normalizeMobileTimeLine(String s) {
    return s
        .replaceAll('&ndash;', '-')
        .replaceAll('&mdash;', '-')
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('−', '-')
        .replaceAll('‑', '-')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static DateTime? _tryParseUsShortDate(String line) {
    try {
      return DateFormat('EEE, MMM d, yyyy', 'en_US').parse(line.trim());
    } catch (_) {
      return null;
    }
  }

  /// Returns (startH, startM, endH, endM) in 24h local wall time for one day.
  static (int, int, int, int)? _parseMobileTimeRange(String line) {
    final re = RegExp(
      r'(\d{1,2})(?::(\d{2}))?\s*(AM|PM)\s*[-–—−‑]\s*(\d{1,2})(?::(\d{2}))?\s*(AM|PM)',
      caseSensitive: false,
    );
    final m = re.firstMatch(line.trim());
    if (m == null) return null;
    final sh = int.parse(m.group(1)!);
    final sm = int.tryParse(m.group(2) ?? '0') ?? 0;
    final sap = m.group(3)!;
    final eh = int.parse(m.group(4)!);
    final em = int.tryParse(m.group(5) ?? '0') ?? 0;
    final eap = m.group(6)!;
    return (
      _to24h(sh, sap),
      sm,
      _to24h(eh, eap),
      em,
    );
  }

  static int _to24h(int h12, String ampm) {
    final up = ampm.toUpperCase();
    if (up == 'AM') return h12 == 12 ? 0 : h12;
    return h12 == 12 ? 12 : h12 + 12;
  }

  static final _monthNames = <String, int>{
    'january': 1,
    'jan': 1,
    'february': 2,
    'feb': 2,
    'march': 3,
    'mar': 3,
    'april': 4,
    'apr': 4,
    'may': 5,
    'june': 6,
    'jun': 6,
    'july': 7,
    'jul': 7,
    'august': 8,
    'aug': 8,
    'september': 9,
    'sept': 9,
    'sep': 9,
    'october': 10,
    'oct': 10,
    'november': 11,
    'nov': 11,
    'december': 12,
    'dec': 12,
  };

  /// e.g. `Title. Thursday, 09 April 2026 At 6:00 PM, EDT (GMT-4).`
  static (DateTime, DateTime)? _parseAriaEventRange(String aria) {
    if (aria.trim().isEmpty) return null;
    final re = RegExp(
      r'[A-Za-z]+,\s*(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})\s+At\s+(\d{1,2})(?::(\d{2}))?\s*(AM|PM)',
      caseSensitive: false,
    );
    final m = re.firstMatch(aria);
    if (m == null) return null;
    final day = int.parse(m.group(1)!);
    final mon = _monthNames[m.group(2)!.toLowerCase()];
    if (mon == null) return null;
    final year = int.parse(m.group(3)!);
    final h12 = int.parse(m.group(4)!);
    final minute = int.tryParse(m.group(5) ?? '0') ?? 0;
    final ap = m.group(6)!;
    final h24 = _to24h(h12, ap);
    final start = DateTime(year, mon, day, h24, minute);
    return (start, start.add(const Duration(hours: 2)));
  }

  Future<CampusGroupsImportResult> importFromJsonString({
    required String jsonText,
    required String hostId,
    required String hostName,
    bool onlyUpcoming = true,
  }) async {
    final issues = <String>[];
    dynamic decoded;
    try {
      var t = jsonText.trim();
      if (t.startsWith('\uFEFF')) {
        t = t.substring(1);
      }
      decoded = json.decode(t);
    } catch (e) {
      return CampusGroupsImportResult(
        saved: 0,
        skipped: 0,
        issues: ['Invalid JSON: $e'],
      );
    }

    final maps = extractEventObjects(decoded);
    if (maps.isEmpty) {
      return CampusGroupsImportResult(
        saved: 0,
        skipped: 0,
        issues: [
          'No event objects found. Paste the raw JSON array from mobile_events_list, or an object whose list is under keys like data, events, or response.',
        ],
      );
    }

    var saved = 0;
    var skipped = 0;
    final now = DateTime.now();

    for (var i = 0; i < maps.length; i++) {
      final flat = _flattenEventMap(maps[i]);
      final draft = _parseDraft(flat);
      if (draft == null) {
        skipped++;
        issues.add('Row ${i + 1}: missing title or start time');
        continue;
      }
      if (onlyUpcoming && draft.endTime.isBefore(now)) {
        skipped++;
        continue;
      }
      try {
        await _events.upsertImportedEvent(
          importKey: draft.importKey,
          title: draft.title,
          description: draft.description,
          hostId: hostId,
          hostName: hostName,
          category: draft.category,
          startTime: draft.startTime,
          endTime: draft.endTime,
          locationName: draft.locationName,
          locationKey: '',
          locationLat: 0,
          locationLng: 0,
          capacity: draft.capacity,
          vibeTags: const [],
          imageUrl: draft.imageUrl,
        );
        saved++;
      } catch (e) {
        skipped++;
        issues.add('Row ${i + 1} (${draft.title}): $e');
      }
    }

    if (saved == 0 && onlyUpcoming && issues.isEmpty && skipped > 0) {
      issues.add(
        'Nothing was saved with “only upcoming” enabled — every row was skipped as already ended. Turn that off to import past events.',
      );
    }

    return CampusGroupsImportResult(
      saved: saved,
      skipped: skipped,
      issues: issues,
    );
  }

  static Map<String, dynamic> _flattenEventMap(Map<String, dynamic> m) {
    var out = Map<String, dynamic>.from(m);
    final attrs = m['attributes'];
    if (attrs is Map) {
      final inner = Map<String, dynamic>.from(attrs);
      inner['id'] ??= m['id'];
      out = {...out, ...inner};
    }
    final event = m['event'];
    if (event is Map) {
      out = {...out, ...Map<String, dynamic>.from(event)};
    }
    return out;
  }

  static _Draft? _parseDraft(Map<String, dynamic> m) {
    final id =
        _stringFrom(m, const ['id', 'event_id', 'eventId', 'uuid', 'slug', 'numeric_id']) ??
            (m['id'] is int ? '${m['id']}' : null);
    final title = _stringFrom(
      m,
      const ['title', 'name', 'event_title', 'eventTitle', 'event_name'],
    );
    if (title == null || title.isEmpty) return null;

    final start = _parseDate(
      m,
      const [
        'starts_at',
        'starts_on',
        'start_time',
        'startTime',
        'start',
        'begin_time',
        'beginTime',
        'from',
        'start_date',
        'startsAt',
      ],
    );
    if (start == null) return null;

    var end = _parseDate(
      m,
      const [
        'ends_at',
        'ends_on',
        'end_time',
        'endTime',
        'end',
        'finish_time',
        'to',
        'end_date',
        'endsAt',
      ],
    );
    end ??= start.add(const Duration(hours: 2));

    final description = _stringFrom(
          m,
          const [
            'description',
            'details',
            'summary',
            'short_description',
            'shortDescription',
            'long_description',
          ],
        ) ??
        '';

    final loc = _resolveLocation(m);
    final imageRaw = _stringFrom(
      m,
      const [
        'image',
        'image_url',
        'imageUrl',
        'cover_image',
        'coverImage',
        'cover_photo',
        'banner',
        'photo',
        'picture',
        'thumbnail',
        'thumbnail_url',
        'image_path',
      ],
    );
    final imageUrl = _resolveImageUrl(imageRaw);

    final categoryRaw = _stringFrom(
      m,
      const ['category', 'event_type', 'eventType', 'type', 'topic'],
    );
    final community = _stringFrom(m, const ['community_name', 'communityName', 'group_name']);
    final category = _mapCategory(categoryRaw ?? community);

    final cap = _readCapacity(m);

    final stableId = (id != null && id.isNotEmpty)
        ? id
        : '${title}_${start.toIso8601String()}'.hashCode.abs().toString();
    final importKey = '${AppConfig.campusGroupsImportSource}:$stableId';

    return _Draft(
      importKey: importKey,
      title: title.trim(),
      description: description.trim(),
      category: category,
      startTime: start,
      endTime: end,
      locationName: loc,
      capacity: cap,
      imageUrl: imageUrl,
    );
  }

  static int _readCapacity(Map<String, dynamic> m) {
    final keys = ['capacity', 'max_capacity', 'maxCapacity', 'attendance_limit', 'limit'];
    for (final k in keys) {
      final v = m[k];
      if (v is int && v > 0) return v;
      if (v is num) {
        final i = v.toInt();
        if (i > 0) return i;
      }
    }
    return 500;
  }

  static String _resolveLocation(Map<String, dynamic> m) {
    final direct = _stringFrom(
      m,
      const [
        'location',
        'venue',
        'place',
        'address',
        'location_name',
        'locationName',
        'room',
        'building',
      ],
    );
    if (direct != null && direct.isNotEmpty) return direct.trim();

    for (final key in ['location', 'venue', 'place']) {
      final v = m[key];
      if (v is Map) {
        final inner = Map<String, dynamic>.from(v);
        final name = _stringFrom(inner, const ['name', 'title', 'label']);
        if (name != null && name.isNotEmpty) return name.trim();
      }
    }
    return 'See CampusGroups';
  }

  static String _resolveImageUrl(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    var s = raw.trim();
    if (s.startsWith('//')) {
      s = 'https:$s';
    } else if (s.startsWith('/')) {
      s = '${AppConfig.campusGroupsBaseUrl}$s';
    }
    return s;
  }

  static String _mapCategory(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'Other';
    final lower = raw.toLowerCase().trim();
    for (final c in AppConfig.defaultCategories) {
      if (c.toLowerCase() == lower) return c;
    }
    for (final c in AppConfig.defaultCategories) {
      if (lower.contains(c.toLowerCase())) return c;
    }
    return 'Other';
  }

  static String? _stringFrom(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  static DateTime? _parseDate(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      if (v is int) {
        if (v > 2000000000) {
          return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true).toLocal();
        }
        return DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true).toLocal();
      }
      if (v is num) {
        final iv = v.toInt();
        if (iv > 2000000000) {
          return DateTime.fromMillisecondsSinceEpoch(iv, isUtc: true).toLocal();
        }
        return DateTime.fromMillisecondsSinceEpoch(iv * 1000, isUtc: true).toLocal();
      }
      if (v is String) {
        try {
          return DateTime.parse(v).toLocal();
        } catch (_) {}
      }
    }
    return null;
  }
}

class _Draft {
  final String importKey;
  final String title;
  final String description;
  final String category;
  final DateTime startTime;
  final DateTime endTime;
  final String locationName;
  final int capacity;
  final String imageUrl;

  _Draft({
    required this.importKey,
    required this.title,
    required this.description,
    required this.category,
    required this.startTime,
    required this.endTime,
    required this.locationName,
    required this.capacity,
    required this.imageUrl,
  });
}
