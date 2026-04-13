import 'package:cloud_firestore/cloud_firestore.dart';

class EventModel {
  final String id;
  final String title;
  final String description;
  final String hostId;
  final String hostName;
  final String category;
  final List<String> vibeTags;
  final DateTime startTime;
  final DateTime endTime;
  final String locationName;
  /// Canonical campus location id for room scheduling (empty if custom/legacy).
  final String locationKey;
  final double locationLat;
  final double locationLng;
  final int capacity;
  final int rsvpCount;
  final int waitlistCount;
  final String status;
  final Map<String, int> reactions;
  final DateTime createdAt;
  final bool isPinned;
  final String postEventSummary;
  final String imageUrl;
  /// When set (e.g. `campusgroups:12345`), re-imports update the same Firestore doc.
  final String importKey;

  const EventModel({
    required this.id,
    required this.title,
    required this.description,
    required this.hostId,
    required this.hostName,
    required this.category,
    this.vibeTags = const [],
    required this.startTime,
    required this.endTime,
    required this.locationName,
    this.locationKey = '',
    this.locationLat = 0.0,
    this.locationLng = 0.0,
    required this.capacity,
    this.rsvpCount = 0,
    this.waitlistCount = 0,
    this.status = 'published',
    this.reactions = const {},
    required this.createdAt,
    this.isPinned = false,
    this.postEventSummary = '',
    this.imageUrl = '',
    this.importKey = '',
  });

  bool get isFull => rsvpCount >= capacity;
  bool get isCancelled => status == 'cancelled';
  int get spotsLeft => capacity - rsvpCount;
  bool get isHappeningNow =>
      DateTime.now().isAfter(startTime) &&
      DateTime.now().isBefore(endTime);
  bool get isUpcoming => DateTime.now().isBefore(startTime);
  bool get isPast => DateTime.now().isAfter(endTime);
  double get fillPercent =>
      capacity > 0
          ? (rsvpCount / capacity).clamp(0.0, 1.0)
          : 0.0;

  factory EventModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return EventModel(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      hostId: data['hostId'] ?? '',
      hostName: data['hostName'] ?? '',
      category: data['category'] ?? 'Other',
      vibeTags: List<String>.from(data['vibeTags'] ?? []),
      startTime:
          (data['startTime'] as Timestamp).toDate(),
      endTime: (data['endTime'] as Timestamp).toDate(),
      locationName: data['locationName'] ?? '',
      locationKey: data['locationKey']?.toString() ?? '',
      locationLat:
          (data['locationLat'] ?? 0.0).toDouble(),
      locationLng:
          (data['locationLng'] ?? 0.0).toDouble(),
      capacity: data['capacity'] ?? 0,
      rsvpCount: data['rsvpCount'] ?? 0,
      waitlistCount: data['waitlistCount'] ?? 0,
      status: data['status'] ?? 'published',
      reactions:
          Map<String, int>.from(data['reactions'] ?? {}),
      createdAt: (data['createdAt'] as Timestamp?)
              ?.toDate() ??
          DateTime.now(),
      isPinned: data['isPinned'] ?? false,
      postEventSummary: data['postEventSummary'] ?? '',
      imageUrl: data['imageUrl'] ?? '',
      importKey: data['importKey']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'description': description,
      'hostId': hostId,
      'hostName': hostName,
      'category': category,
      'vibeTags': vibeTags,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'locationName': locationName,
      'locationKey': locationKey,
      'locationLat': locationLat,
      'locationLng': locationLng,
      'capacity': capacity,
      'rsvpCount': rsvpCount,
      'waitlistCount': waitlistCount,
      'status': status,
      'reactions': reactions,
      'createdAt': Timestamp.fromDate(createdAt),
      'isPinned': isPinned,
      'postEventSummary': postEventSummary,
      'imageUrl': imageUrl,
      'importKey': importKey,
    };
  }

  EventModel copyWith({
    String? title,
    String? description,
    String? category,
    List<String>? vibeTags,
    DateTime? startTime,
    DateTime? endTime,
    String? locationName,
    String? locationKey,
    double? locationLat,
    double? locationLng,
    int? capacity,
    int? rsvpCount,
    int? waitlistCount,
    String? status,
    Map<String, int>? reactions,
    bool? isPinned,
    String? postEventSummary,
    String? imageUrl,
    String? importKey,
  }) {
    return EventModel(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      hostId: hostId,
      hostName: hostName,
      category: category ?? this.category,
      vibeTags: vibeTags ?? this.vibeTags,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      locationName: locationName ?? this.locationName,
      locationKey: locationKey ?? this.locationKey,
      locationLat: locationLat ?? this.locationLat,
      locationLng: locationLng ?? this.locationLng,
      capacity: capacity ?? this.capacity,
      rsvpCount: rsvpCount ?? this.rsvpCount,
      waitlistCount: waitlistCount ?? this.waitlistCount,
      status: status ?? this.status,
      reactions: reactions ?? this.reactions,
      createdAt: createdAt,
      isPinned: isPinned ?? this.isPinned,
      postEventSummary:
          postEventSummary ?? this.postEventSummary,
      imageUrl: imageUrl ?? this.imageUrl,
      importKey: importKey ?? this.importKey,
    );
  }
}