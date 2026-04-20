import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../config/app_config.dart';
import 'analytics_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<UserModel?> getUserModel(String uid) async {
    try {
      final doc = await _db.collection(AppConfig.usersCol).doc(uid).get();
      if (doc.exists) return UserModel.fromFirestore(doc);
      return null;
    } catch (e) {
      return null;
    }
  }

  Stream<UserModel?> userModelStream(String uid) {
    return _db
        .collection(AppConfig.usersCol)
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists ? UserModel.fromFirestore(doc) : null);
  }

  Future<bool> isStudentIdTaken(String studentId) async {
    try {
      final snap = await _db
          .collection(AppConfig.usersCol)
          .where('studentId', isEqualTo: studentId.trim())
          .limit(1)
          .get();
      return snap.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<UserModel> register({
    required String name,
    required String email,
    required String password,
    required String studentId,
    required String role,
  }) async {
    if (!AppConfig.isValidNyitEmail(email)) {
      throw FirebaseAuthException(
        code: 'invalid-email-domain',
        message: 'Only @nyit.edu email addresses are allowed.',
      );
    }

    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final uid = credential.user!.uid;
      // Students and superadmins are auto-approved; teachers need manual approval
      final bool approved =
          role == AppConfig.roleStudent || role == AppConfig.roleSuperAdmin;

      final userData = {
        'name': name.trim(),
        'email': email.trim().toLowerCase(),
        'studentId': studentId.trim(),
        'role': role,
        'approved': approved,
        'photoUrl': '',
        'reminderMinutes': 60,
        'fcmToken': '',
        'segmentRole': role,
        'segmentCampus': 'old_westbury',
        'segmentEngagementTier': 'new',
        'segmentInterestCategories': <String>[],
        'lastActiveAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      };

      await _db.collection(AppConfig.usersCol).doc(uid).set(userData);

      await credential.user!.updateDisplayName(name.trim());

      final user = UserModel(
        uid: uid,
        name: name.trim(),
        email: email.trim().toLowerCase(),
        studentId: studentId.trim(),
        role: role,
        approved: approved,
        createdAt: DateTime.now(),
      );

      return user;
    } catch (e) {
      rethrow;
    }
  }

  Future<UserModel?> login({
    required String email,
    required String password,
  }) async {
    if (!AppConfig.isValidNyitEmail(email)) {
      throw FirebaseAuthException(
        code: 'invalid-email-domain',
        message: 'Only @nyit.edu email addresses are allowed.',
      );
    }

    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final userModel = await getUserModel(credential.user!.uid);

      // Auth account exists but Firestore document was deleted —
      // sign out immediately so the email becomes usable again.
      if (userModel == null) {
        await _auth.signOut();
        throw FirebaseAuthException(
          code: 'user-not-found',
          message:
              'This account has been removed. Please register again or contact an administrator.',
        );
      }

      await _saveFcmToken(credential.user!.uid);
      await AnalyticsService.instance.setUserId(credential.user!.uid);
      await AnalyticsService.instance.setUserProperty('role', userModel.role);
      return userModel;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _saveFcmToken(String uid) async {
    try {
      // On iOS, APNs token must be available before FCM token can be fetched.
      // If it isn't ready yet (e.g. simulator, no paid dev account), skip silently.
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final apns = await FirebaseMessaging.instance.getAPNSToken();
        if (apns == null) return;
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _db.collection(AppConfig.usersCol).doc(uid).update({
          'fcmToken': token,
          'lastActiveAt': Timestamp.now(),
        });
      }
    } catch (_) {
      // FCM token unavailable — non-fatal, push notifications simply won't work.
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
  }

  Future<void> sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }
}
