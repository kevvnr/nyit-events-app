import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String name;
  final String email;
  final String studentId;
  final String role;
  final bool approved;
  final String photoUrl;
  final int reminderMinutes;
  final String fcmToken;
  final DateTime createdAt;

  const UserModel({
    required this.uid,
    required this.name,
    required this.email,
    this.studentId = '',
    required this.role,
    this.approved = false,
    this.photoUrl = '',
    this.reminderMinutes = 60,
    this.fcmToken = '',
    required this.createdAt,
  });

  bool get isStudent => role == 'student';
  bool get isTeacher => role == 'teacher';
  bool get isSuperAdmin => role == 'superadmin';
  bool get canCreateEvents => isTeacher || isSuperAdmin;
  bool get isApproved => role == 'student' || approved;

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: doc.id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      studentId: data['studentId'] ?? '',
      role: data['role'] ?? 'student',
      approved: data['approved'] ?? false,
      photoUrl: data['photoUrl'] ?? '',
      reminderMinutes: data['reminderMinutes'] ?? 60,
      fcmToken: data['fcmToken'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'email': email,
      'studentId': studentId,
      'role': role,
      'approved': approved,
      'photoUrl': photoUrl,
      'reminderMinutes': reminderMinutes,
      'fcmToken': fcmToken,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  UserModel copyWith({
    String? name,
    String? studentId,
    String? role,
    bool? approved,
    String? photoUrl,
    int? reminderMinutes,
    String? fcmToken,
  }) {
    return UserModel(
      uid: uid,
      name: name ?? this.name,
      email: email,
      studentId: studentId ?? this.studentId,
      role: role ?? this.role,
      approved: approved ?? this.approved,
      photoUrl: photoUrl ?? this.photoUrl,
      reminderMinutes: reminderMinutes ?? this.reminderMinutes,
      fcmToken: fcmToken ?? this.fcmToken,
      createdAt: createdAt,
    );
  }
}