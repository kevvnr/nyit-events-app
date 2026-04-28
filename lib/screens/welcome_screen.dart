import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../router/app_router.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF1565C0);
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Hero image section with overlay
          Expanded(
            flex: 5,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Premium gradient hero
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF1a3a6b),
                        Color(0xFF1565C0),
                      ],
                    ),
                  ),
                ),

                // Subtle texture overlay
                Opacity(
                  opacity: 0.05,
                  child: Container(
                    decoration: const BoxDecoration(
                      image: DecorationImage(
                        image: AssetImage('assets/icon/app_icon.webp'),
                        fit: BoxFit.cover,
                        opacity: 0.1,
                      ),
                    ),
                  ),
                ),

                // Content overlay
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top bar
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            // NYIT badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black
                                        .withValues(alpha: 0.06),
                                    blurRadius: 12,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Text(
                                'NEW YORK\nTECH',
                                style: TextStyle(
                                  color: Color(0xFF1a3a6b),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  height: 1.2,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),

                            // Campus label
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color:
                                    Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: Colors.white
                                        .withValues(alpha: 0.3)),
                              ),
                              child: const Text(
                                'Old Westbury',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.1,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const Spacer(),

                        // Tagline
                        const Text(
                          'Doers. Makers.\nInnovators. Healers.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                            letterSpacing: -0.7,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'There\'s a place for you at New York Tech.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 14,
                            height: 1.5,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Refined login CTA
                        Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(
                            onTap: () =>
                                context.push(AppRoutes.login),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 30, vertical: 14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5A623),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFF5A623)
                                        .withValues(alpha: 0.35),
                                    blurRadius: 14,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: const Text(
                                'Login',
                                style: TextStyle(
                                  color: Color(0xFF1a3a6b),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom section — white with quick actions
          Expanded(
            flex: 4,
            child: Container(
              color: Colors.white,
              child: Column(
                children: [
                  // Quick action pills row
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(20, 30, 20, 0),
                    child: Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceAround,
                      children: const [
                        _QuickAction(
                          icon: Icons.event_rounded,
                          label: 'Events',
                        ),
                        _QuickAction(
                          icon: Icons.map_outlined,
                          label: 'Map',
                        ),
                        _QuickAction(
                          icon: Icons.qr_code_rounded,
                          label: 'Check-in',
                        ),
                        _QuickAction(
                          icon: Icons.notifications_outlined,
                          label: 'Alerts',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),
                  Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    color: const Color(0xFFEEF2F7),
                  ),
                  const SizedBox(height: 24),

                  // Create account button
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: primary.withValues(alpha: 0.25),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () =>
                              context.push(AppRoutes.register),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                          child: const Text('Create account'),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Sign in text button
                  TextButton(
                    onPressed: () => context.push(AppRoutes.login),
                    style: TextButton.styleFrom(
                      foregroundColor: primary,
                    ),
                    child: const Text(
                      'Already have an account? Sign in',
                      style: TextStyle(
                        color: Color(0xFF1565C0),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Footer
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Text(
                      'For NYIT students and faculty only · @nyit.edu',
                      style: TextStyle(
                        color: const Color(0xFF94A3B8),
                        fontSize: 11,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;

  const _QuickAction({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFFEEF2F7),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(
            icon,
            color: const Color(0xFF1565C0),
            size: 24,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}
