import 'dart:convert';

import 'package:campus_app/services/campus_groups_import_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CampusGroupsImportService.extractEventObjects', () {
    test('raw mobile_events_list array converts rows', () {
      final raw = '''
[{"fields":"eventId,eventName,eventDates,eventCategory,eventLocation,ariaEventDetails","p0":"1","p1":"My Event","p2":"<p style='margin:0;'>Thu, Apr 9, 2026</p><p style='margin:0;'>6 PM &ndash;7 PM</p>","p3":"Talk","p4":"Room A","p5":"Title. Thursday, 9 April 2026 At 6:00 PM, EDT."}]
''';
      final maps =
          CampusGroupsImportService.extractEventObjects(json.decode(raw));
      expect(maps, hasLength(1));
      expect(maps.first['title'], 'My Event');
      expect(maps.first['start_time'], isNotNull);
      expect(maps.first['end_time'], isNotNull);
    });

    test('wrapped in data uses mobile parser', () {
      final inner = {
        'fields': 'eventId,eventName,eventDates',
        'p0': '42',
        'p1': 'Wrapped',
        'p2': '<p>Thu, Apr 9, 2026</p><p>12 PM - 1 PM</p>',
      };
      final wrapped = json.encode({'data': [inner]});
      final maps =
          CampusGroupsImportService.extractEventObjects(json.decode(wrapped));
      expect(maps, hasLength(1));
      expect(maps.first['title'], 'Wrapped');
    });

    test('aria fallback when eventDates empty', () {
      final row = {
        'fields': 'eventId,eventName,eventDates,ariaEventDetails',
        'p0': '99',
        'p1': 'Aria only',
        'p2': '',
        'p3': 'Event. Monday, 13 April 2026 At 12:00 PM, PDT.',
      };
      final maps = CampusGroupsImportService.extractEventObjects([row]);
      expect(maps, hasLength(1));
      expect(maps.first['title'], 'Aria only');
    });

    test('aria accepts hour without minutes', () {
      final row = {
        'fields': 'eventId,eventName,eventDates,ariaEventDetails',
        'p0': '100',
        'p1': 'No minutes',
        'p2': '',
        'p3': 'Tuesday, 14 April 2026 At 6 PM, EDT.',
      };
      final maps = CampusGroupsImportService.extractEventObjects([row]);
      expect(maps, hasLength(1));
      expect(maps.first['title'], 'No minutes');
    });
  });
}
