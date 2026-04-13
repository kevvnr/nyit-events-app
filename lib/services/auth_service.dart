import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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
      print('Getting user model for uid: $uid');
      final doc = await _db.collection(AppConfig.usersCol).doc(uid).get();
      if (doc.exists) {
        print('User doc found!');
        return UserModel.fromFirestore(doc);
      }
      print('User doc not found');
      return null;
    } catch (e) {
      print('getUserModel error: $e');
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
      print('Step 1: Creating Firebase Auth account for ${email.trim()}');
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      print('Step 2: Auth account created — uid: ${credential.user!.uid}');

      final uid = credential.user!.uid;
      // Students and superadmins are auto-approved; teachers need manual approval
      final bool approved =
          role == AppConfig.roleStudent || role == AppConfig.roleSuperAdmin;

      print('Step 3: Saving user to Firestore...');
      print('Collection: ${AppConfig.usersCol}');
      print('Document ID: $uid');

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

      print('Data to save: $userData');

      await _db.collection(AppConfig.usersCol).doc(uid).set(userData);

      print('Step 4: Firestore save complete!');

      await credential.user!.updateDisplayName(name.trim());
      print('Step 5: Registration complete!');

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
      print('Registration error: $e');
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
      print('Logging in: ${email.trim()}');
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      print('Login success: ${credential.user!.uid}');

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
      print('Login error: $e');
      rethrow;
    }
  }

  Future<void> _saveFcmToken(String uid) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        final now = Timestamp.now();
        await _db.collection(AppConfig.usersCol).doc(uid).update({
          'fcmToken': token,
          'lastActiveAt': now,
          'segmentRole': _auth.currentUser != null ? 'authenticated' : 'guest',
        });
      }
    } catch (e) {
      print('saveFcmToken error: $e');
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
  }

  Future<void> sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }
}
