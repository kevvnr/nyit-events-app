import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../router/app_router.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

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
                // Dark navy background (simulating campus hero image)
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF1a3a6b),
                        Color(0xFF0d2144),
                      ],
                    ),
                  ),
                ),

                // Grid pattern overlay for texture
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
                    padding: const EdgeInsets.all(28),
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
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius:
                                    BorderRadius.circular(6),
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
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius:
                                    BorderRadius.circular(20),
                                border: Border.all(
                                    color: Colors.white
                                        .withOpacity(0.3)),
                              ),
                              child: const Text(
                                'Old Westbury',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
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
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'There\'s a Place for you at New York Tech.',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Gold login button — like real NYIT app
                        Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(
                            onTap: () =>
                                context.push(AppRoutes.login),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 28, vertical: 14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5A623),
                                borderRadius:
                                    BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Login',
                                style: TextStyle(
                                  color: Color(0xFF1a3a6b),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
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
                  // Quick action icons row — like real NYIT app
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        20, 28, 20, 0),
                    child: Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceAround,
                      children: [
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
                  const Divider(height: 0),
                  const SizedBox(height: 28),

                  // Create account button
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () =>
                            context.push(AppRoutes.register),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              const Color(0xFF1565C0),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(8),
                          ),
                          elevation: 0,
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: const Text('Create account'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Sign in text button
                  TextButton(
                    onPressed: () =>
                        context.push(AppRoutes.login),
                    child: const Text(
                      'Already have an account? Sign in',
                      style: TextStyle(
                        color: Color(0xFF1565C0),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
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
                        color: Colors.grey.shade400,
                        fontSize: 11,
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
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF1565C0),
              width: 1.5,
            ),
          ),
          child: Icon(
            icon,
            color: const Color(0xFF1565C0),
            size: 24,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF1a3a6b),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}