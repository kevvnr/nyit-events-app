import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../providers/auth_provider.dart';
import '../screens/splash_screen.dart';
import '../screens/welcome_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/home/home_screen.dart';

class AppRoutes {
  static const splash = '/';
  static const welcome = '/welcome';
  static const login = '/login';
  static const register = '/register';
  static const home = '/home';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final authAsync = ref.watch(authStateProvider);
  final userModelAsync = ref.watch(userModelProvider);
  return GoRouter(
    initialLocation: AppRoutes.splash,
    redirect: (context, state) {
      // Wait for Firebase Auth to initialise
      if (authAsync.isLoading) return AppRoutes.splash;

      final firebaseUser = authAsync.asData?.value;
      final isLoggedIn = firebaseUser != null;

      // Wait for Firestore user document to finish loading
      if (isLoggedIn && userModelAsync.isLoading) return AppRoutes.splash;

      final userModel = userModelAsync.asData?.value;

      // Firebase Auth says logged in but no Firestore document.
      // Two cases: (1) registration in progress — the auth account was
      // just created but the Firestore write hasn't finished yet.
      // (2) account was deleted by admin. Use creation time to tell apart.
      if (isLoggedIn && userModel == null) {
        final creationTime = firebaseUser.metadata.creationTime;
        final isNewUser = creationTime != null &&
            DateTime.now().difference(creationTime).inSeconds < 60;

        if (isNewUser) {
          // Registration in progress — stay on splash and wait for the doc.
          return AppRoutes.splash;
        }

        // Old account with deleted Firestore doc — sign out and block access.
        FirebaseAuth.instance.signOut();
        return AppRoutes.welcome;
      }

      final isOnAuthScreen =
          state.matchedLocation == AppRoutes.login ||
          state.matchedLocation == AppRoutes.register ||
          state.matchedLocation == AppRoutes.welcome;

      // Not logged in → always show welcome
      if (!isLoggedIn && !isOnAuthScreen) {
        return AppRoutes.welcome;
      }

      // Logged in with valid account → never stay on auth/splash screens
      if (isLoggedIn && userModel != null && isOnAuthScreen) {
        return AppRoutes.home;
      }

      // Splash → home if logged in with valid account, welcome if not
      if (state.matchedLocation == AppRoutes.splash) {
        return (isLoggedIn && userModel != null) ? AppRoutes.home : AppRoutes.welcome;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        pageBuilder: (context, state) => _fadePage(
          key: state.pageKey,
          child: const SplashScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.welcome,
        pageBuilder: (context, state) => _fadePage(
          key: state.pageKey,
          child: const WelcomeScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.login,
        pageBuilder: (context, state) => _fadePage(
          key: state.pageKey,
          child: const LoginScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.register,
        pageBuilder: (context, state) => _fadePage(
          key: state.pageKey,
          child: const RegisterScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.home,
        pageBuilder: (context, state) => _fadePage(
          key: state.pageKey,
          child: const HomeScreen(),
        ),
      ),
    ],
  );
});

CustomTransitionPage<void> _fadePage({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 360),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      final offset = Tween<Offset>(
        begin: const Offset(0.0, 0.02),
        end: Offset.zero,
      ).animate(curve);
      return FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: offset,
          child: child,
        ),
      );
    },
  );
}