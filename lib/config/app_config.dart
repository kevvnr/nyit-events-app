import 'package:flutter/material.dart';

class AppConfig {
  // Branding
  static const String appName = 'NYIT Campus Events';
  static const String schoolName = 'New York Institute of Technology';
  static const String campusGroupsBaseUrl = 'https://campusgroups.nyit.edu';
  /// Default API path for listing events (requires Bearer token).
  static const String campusGroupsEventsApiUrl =
      'https://campusgroups.nyit.edu/api/v1/events';
  static const String campusGroupsImportSource = 'campusgroups';
  static const String allowedEmailDomain = 'nyit.edu';
  static const Color primaryColor = Color(0xFF1565C0);
  static const Color accentColor = Color(0xFF42A5F5);

  // Firestore collections
  static const String usersCol = 'users';
  static const String eventsCol = 'events';
  static const String rsvpsCol = 'rsvps';
  static const String notificationsCol = 'notifications';
  static const String appConfigCol = 'appConfig';
  static const String appConfigDoc = 'main';
  static const String roomCapacityOverridesField = 'roomCapacityOverrides';
  static const String campaignsCol = 'campaigns';

  // User roles
  static const String roleStudent = 'student';
  static const String roleTeacher = 'teacher';
  static const String roleSuperAdmin = 'superadmin';

  // RSVP statuses
  static const String rsvpConfirmed = 'confirmed';
  static const String rsvpWaitlist = 'waitlist';
  static const String rsvpCancelled = 'cancelled';
  static const String rsvpAttended = 'attended';
  static const String rsvpRsvpOnly = 'rsvp_only';

  // Event statuses
  static const String eventPublished = 'published';
  static const String eventCancelled = 'cancelled';
  static const String eventArchived = 'archived';

  // Notification types
  static const String notifReminder = 'reminder';
  static const String notifUpdate = 'update';
  static const String notifCancel = 'cancel';
  static const String notifPromoted = 'promoted';

  // Default categories
  static const List<String> defaultCategories = [
    'Academic',
    'Social',
    'Sports',
    'Career / Networking',
    'Arts & Culture',
    'Health & Wellness',
    'Club / Org',
    'Food & Dining',
    'Other',
  ];

  // Validation
  static bool isValidNyitEmail(String email) {
    return email.trim().toLowerCase().endsWith('@$allowedEmailDomain');
  }
}
