import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../router/app_router.dart';
import '../feed/feed_screen.dart';
import '../events/create_event_screen.dart';
import '../profile/profile_screen.dart';
import '../notifications/notifications_screen.dart';
import '../map/map_screen.dart';
import '../admin/admin_screen.dart';
import '../study/study_group_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() =>
      _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  void _selectTab(int index) {
    if (index == _currentIndex) return;
    HapticFeedback.selectionClick();
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(userModelProvider);
    final unreadCount = ref.watch(unreadCountProvider);

    return userAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(child: Text('Error: $e')),
      ),
      data: (user) {
        if (user == null) {
          // No Firestore document — sign out and block access.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(authServiceProvider).logout();
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Teacher pending approval
        if (user.isTeacher && !user.approved) {
          return Scaffold(
            backgroundColor: const Color(0xFF1a3a6b),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisAlignment:
                      MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        color: Colors.white
                            .withOpacity(0.15),
                        borderRadius:
                            BorderRadius.circular(45),
                      ),
                      child: const Icon(
                        Icons.hourglass_empty_rounded,
                        size: 44,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'Pending Approval',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Hi ${user.name.split(' ').first}! Your faculty account is awaiting approval from a Super Admin.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white
                            .withOpacity(0.8),
                        fontSize: 15,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () async {
                          await ref
                              .read(authNotifierProvider
                                  .notifier)
                              .logout();
                          if (context.mounted) {
                            context
                                .go(AppRoutes.welcome);
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(
                              color: Colors.white,
                              width: 1.5),
                          padding: const EdgeInsets
                              .symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Sign out',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight:
                                    FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final isAdmin = user.canCreateEvents;

        // Students: Feed, Study, Map, Profile
        // Admins: Feed, Map, Manage, Profile (no study)
        final screens = isAdmin
            ? [
                const FeedScreen(),
                const MapScreen(),
                const AdminScreen(),
                const ProfileScreen(),
              ]
            : [
                const FeedScreen(),
                const StudyGroupScreen(),
                const MapScreen(),
                const ProfileScreen(),
              ];

        final showAppBar =
            _currentIndex == 0 ||
            (!isAdmin && _currentIndex == 1);

        final appBarTitle = _currentIndex == 0
            ? 'Campus Events'
            : (!isAdmin && _currentIndex == 1)
                ? 'Study Groups'
                : '';

        final screenWidth = MediaQuery.of(context).size.width;
        final isTablet = screenWidth >= 600;

        // ── Tablet / iPad: side rail layout ──────────────────────
        if (isTablet) {
          final navItems = isAdmin
              ? [
                  const NavigationRailDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: Text('Feed'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.explore_outlined),
                    selectedIcon: Icon(Icons.explore_rounded),
                    label: Text('Map'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.dashboard_outlined),
                    selectedIcon: Icon(Icons.dashboard_rounded),
                    label: Text('Manage'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.person_outline_rounded),
                    selectedIcon: Icon(Icons.person_rounded),
                    label: Text('Profile'),
                  ),
                ]
              : [
                  const NavigationRailDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: Text('Feed'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.groups_outlined),
                    selectedIcon: Icon(Icons.groups_rounded),
                    label: Text('Study'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.explore_outlined),
                    selectedIcon: Icon(Icons.explore_rounded),
                    label: Text('Map'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.person_outline_rounded),
                    selectedIcon: Icon(Icons.person_rounded),
                    label: Text('Profile'),
                  ),
                ];

          return Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            appBar: showAppBar
                ? AppBar(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    elevation: 0,
                    surfaceTintColor: Colors.transparent,
                    automaticallyImplyLeading: false,
                    titleSpacing: 20,
                    title: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1a3a6b),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'NY\nTECH',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              height: 1.2,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          appBarTitle,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1a3a6b),
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const NotificationsScreen(),
                          ),
                        ),
                        child: Container(
                          margin: const EdgeInsets.only(right: 16),
                          child: Stack(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Icon(
                                  Icons.notifications_outlined,
                                  color: Color(0xFF1a3a6b),
                                  size: 22,
                                ),
                              ),
                              if (unreadCount > 0)
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: Container(
                                    width: 18,
                                    height: 18,
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        unreadCount > 9 ? '9+' : '$unreadCount',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
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
                    bottom: PreferredSize(
                      preferredSize: const Size.fromHeight(1),
                      child: Container(
                          height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                  )
                : null,
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _currentIndex,
                  onDestinationSelected: (i) =>
                      setState(() => _currentIndex = i),
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  selectedIconTheme: const IconThemeData(
                      color: Color(0xFF1565C0)),
                  unselectedIconTheme: const IconThemeData(
                      color: Color(0xFF94A3B8)),
                  selectedLabelTextStyle: const TextStyle(
                    color: Color(0xFF1565C0),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                  unselectedLabelTextStyle: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
                  leading: isAdmin && _currentIndex == 0
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: FloatingActionButton.small(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const CreateEventScreen()),
                            ),
                            backgroundColor:
                                const Color(0xFF1565C0),
                            child: const Icon(Icons.add_rounded,
                                color: Colors.white),
                          ),
                        )
                      : null,
                  destinations: navItems,
                ),
                VerticalDivider(
                    thickness: 1, width: 1, color: Theme.of(context).colorScheme.outlineVariant),
                Expanded(child: screens[_currentIndex]),
              ],
            ),
          );
        }

        // ── Phone: original bottom-nav layout ─────────────────────
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: showAppBar
              ? AppBar(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  elevation: 0,
                  automaticallyImplyLeading: false,
                  surfaceTintColor:
                      Colors.transparent,
                  titleSpacing: 20,
                  title: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets
                            .symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF1a3a6b),
                          borderRadius:
                              BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'NY\nTECH',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            height: 1.2,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        appBarTitle,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1a3a6b),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const NotificationsScreen(),
                        ),
                      ),
                      child: Container(
                        margin: const EdgeInsets.only(
                            right: 16),
                        child: Stack(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(
                                    0xFFF1F5F9),
                                borderRadius:
                                    BorderRadius.circular(
                                        20),
                              ),
                              child: const Icon(
                                Icons
                                    .notifications_outlined,
                                color:
                                    Color(0xFF1a3a6b),
                                size: 22,
                              ),
                            ),
                            if (unreadCount > 0)
                              Positioned(
                                right: 0,
                                top: 0,
                                child: Container(
                                  width: 18,
                                  height: 18,
                                  decoration:
                                      const BoxDecoration(
                                    color: Colors.red,
                                    shape:
                                        BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      unreadCount > 9
                                          ? '9+'
                                          : '$unreadCount',
                                      style:
                                          const TextStyle(
                                        color:
                                            Colors.white,
                                        fontSize: 10,
                                        fontWeight:
                                            FontWeight
                                                .w700,
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
                  bottom: PreferredSize(
                    preferredSize:
                        const Size.fromHeight(1),
                    child: Container(
                      height: 1,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                )
              : null,
          body: screens[_currentIndex],
          floatingActionButton:
              isAdmin && _currentIndex == 0
                  ? FloatingActionButton.extended(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const CreateEventScreen(),
                        ),
                      ),
                      backgroundColor:
                          const Color(0xFF1565C0),
                      elevation: 2,
                      icon: const Icon(
                          Icons.add_rounded,
                          color: Colors.white),
                      label: const Text(
                        'New Event',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    )
                  : null,
          bottomNavigationBar: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.96),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: SafeArea(
              child: SizedBox(
                height: 64,
                child: Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceAround,
                  children: isAdmin
                      ? [
                          // Admin nav: Feed, Map, Manage, Profile
                          _NavItem(
                            icon: Icons.home_outlined,
                            activeIcon:
                                Icons.home_rounded,
                            label: 'Feed',
                            index: 0,
                            currentIndex: _currentIndex,
                            onTap: () => _selectTab(0),
                          ),
                          _NavItem(
                            icon: Icons.explore_outlined,
                            activeIcon:
                                Icons.explore_rounded,
                            label: 'Map',
                            index: 1,
                            currentIndex: _currentIndex,
                            onTap: () => _selectTab(1),
                          ),
                          _NavItem(
                            icon:
                                Icons.dashboard_outlined,
                            activeIcon:
                                Icons.dashboard_rounded,
                            label: 'Manage',
                            index: 2,
                            currentIndex: _currentIndex,
                            onTap: () => _selectTab(2),
                          ),
                          _NavItem(
                            icon: Icons
                                .person_outline_rounded,
                            activeIcon:
                                Icons.person_rounded,
                            label: 'Profile',
                            index: 3,
                            currentIndex: _currentIndex,
                            onTap: () => _selectTab(3),
                          ),
                        ]
                      : [
                          // Student nav: Feed, Study, Map, Profile
                          _NavItem(
                            icon: Icons.home_outlined,
                            activeIcon:
                                Icons.home_rounded,
                            label: 'Feed',
                            index: 0,
                            currentIndex: _currentIndex,
                            onTap: () => _selectTab(0),
                          ),
                          _NavItem(
                            icon: Icons.groups_outlined,
                            activeIcon:
                                Icons.groups_rounded,
                            label: 'Study',
                            index: 1,
                            currentIndex: _currentIndex,
                            onTap: () => _selectTab(1),
                          ),
                          _NavItem(
                            icon: Icons.explore_outlined,
                            activeIcon:
                                Icons.explore_rounded,
                            label: 'Map',
                            index: 2,
                            currentIndex: _currentIndex,
                            onTap: () => _selectTab(2),
                          ),
                          _NavItem(
                            icon: Icons
                                .person_outline_rounded,
                            activeIcon:
                                Icons.person_rounded,
                            label: 'Profile',
                            index: 3,
                            currentIndex: _currentIndex,
                            onTap: () => _selectTab(3),
                          ),
                        ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int index;
  final int currentIndex;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.index,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = index == currentIndex;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration:
                  const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFF1565C0)
                        .withOpacity(0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                isActive ? activeIcon : icon,
                color: isActive
                    ? const Color(0xFF1565C0)
                    : const Color(0xFF94A3B8),
                size: 24,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive
                    ? FontWeight.w700
                    : FontWeight.w400,
                color: isActive
                    ? const Color(0xFF1565C0)
                    : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}