import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../config/app_config.dart';
import '../../providers/auth_provider.dart';

// ─── Model ─────────────────────────────────────────────
class StudyGroup {
  final String id;
  final String title;
  final String course;
  final String description;
  final String hostId;
  final String hostName;
  final String location;
  final DateTime meetTime;
  final DateTime endTime;
  final int maxMembers;
  final List<String> memberIds;
  final List<String> memberNames;
  final DateTime createdAt;

  const StudyGroup({
    required this.id,
    required this.title,
    required this.course,
    required this.description,
    required this.hostId,
    required this.hostName,
    required this.location,
    required this.meetTime,
    required this.endTime,
    required this.maxMembers,
    required this.memberIds,
    required this.memberNames,
    required this.createdAt,
  });

  bool get isFull => memberIds.length >= maxMembers;
  int get spotsLeft => maxMembers - memberIds.length;
  bool get isHappeningNow =>
      DateTime.now().isAfter(meetTime) &&
      DateTime.now().isBefore(endTime);
  bool get isOver => DateTime.now().isAfter(endTime);

  factory StudyGroup.fromFirestore(
      DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return StudyGroup(
      id: doc.id,
      title: data['title'] ?? '',
      course: data['course'] ?? '',
      description: data['description'] ?? '',
      hostId: data['hostId'] ?? '',
      hostName: data['hostName'] ?? '',
      location: data['location'] ?? '',
      meetTime:
          (data['meetTime'] as Timestamp).toDate(),
      endTime: (data['endTime'] as Timestamp).toDate(),
      maxMembers: data['maxMembers'] ?? 5,
      memberIds:
          List<String>.from(data['memberIds'] ?? []),
      memberNames:
          List<String>.from(data['memberNames'] ?? []),
      createdAt: (data['createdAt'] as Timestamp?)
              ?.toDate() ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'title': title,
        'course': course,
        'description': description,
        'hostId': hostId,
        'hostName': hostName,
        'location': location,
        'meetTime': Timestamp.fromDate(meetTime),
        'endTime': Timestamp.fromDate(endTime),
        'maxMembers': maxMembers,
        'memberIds': memberIds,
        'memberNames': memberNames,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}

// ─── Main Screen ───────────────────────────────────────
class StudyGroupScreen extends ConsumerStatefulWidget {
  const StudyGroupScreen({super.key});

  @override
  ConsumerState<StudyGroupScreen> createState() =>
      _StudyGroupScreenState();
}

class _StudyGroupScreenState
    extends ConsumerState<StudyGroupScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user =
        ref.watch(userModelProvider).asData?.value;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          // Header
          Container(
            color: Colors.white,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Study Groups',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1a3a6b),
                          ),
                        ),
                        const Spacer(),
                        if (user?.isStudent == true)
                          GestureDetector(
                            onTap: () =>
                                Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const CreateStudyGroupScreen(),
                              ),
                            ),
                            child: Container(
                              padding: const EdgeInsets
                                  .symmetric(
                                  horizontal: 14,
                                  vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(
                                    0xFF1565C0),
                                borderRadius:
                                    BorderRadius.circular(
                                        20),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.add_rounded,
                                      color: Colors.white,
                                      size: 16),
                                  SizedBox(width: 4),
                                  Text(
                                    'Create',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight:
                                          FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(
                          () => _searchQuery = val),
                      decoration: InputDecoration(
                        hintText:
                            'Search by course or subject...',
                        prefixIcon: const Icon(
                            Icons.search_rounded,
                            size: 20),
                        suffixIcon:
                            _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(
                                        Icons.clear_rounded,
                                        size: 18),
                                    onPressed: () {
                                      _searchController
                                          .clear();
                                      setState(() =>
                                          _searchQuery =
                                              '');
                                    },
                                  )
                                : null,
                        filled: true,
                        fillColor:
                            const Color(0xFFF1F5F9),
                        contentPadding:
                            const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('studyGroups')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                      child:
                          CircularProgressIndicator());
                }

                final now = DateTime.now();
                var groups = (snapshot.data?.docs ?? [])
                    .map((doc) =>
                        StudyGroup.fromFirestore(doc))
                    .where((g) =>
                        g.endTime.isAfter(now) &&
                        (_searchQuery.isEmpty ||
                            g.title
                                .toLowerCase()
                                .contains(_searchQuery
                                    .toLowerCase()) ||
                            g.course
                                .toLowerCase()
                                .contains(_searchQuery
                                    .toLowerCase())))
                    .toList()
                  ..sort((a, b) => a.meetTime.compareTo(b.meetTime));

                if (groups.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        Icon(Icons.groups_rounded,
                            size: 64,
                            color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(
                          'No study groups yet',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Be the first to create one!',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                      16, 12, 16, 100),
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(
                          bottom: 14),
                      child: _StudyGroupCard(
                        group: groups[index],
                        currentUser: user,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Study Group Card ──────────────────────────────────
class _StudyGroupCard extends ConsumerWidget {
  final StudyGroup group;
  final dynamic currentUser;

  const _StudyGroupCard({
    required this.group,
    required this.currentUser,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMember =
        currentUser != null &&
        group.memberIds.contains(currentUser.uid);
    final isHost = currentUser?.uid == group.hostId;
    final pct = group.maxMembers > 0
        ? (group.memberIds.length / group.maxMembers)
            .clamp(0.0, 1.0)
        : 0.0;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              StudyGroupDetailScreen(group: group),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Color header
            Container(
              height: 5,
              decoration: BoxDecoration(
                color: group.isHappeningNow
                    ? Colors.green.shade600
                    : const Color(0xFF1565C0),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16)),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  // Top row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius:
                              BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                                Icons.menu_book_rounded,
                                size: 12,
                                color: Color(0xFF1565C0)),
                            const SizedBox(width: 4),
                            Text(
                              'Study Group',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1565C0),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (group.isHappeningNow)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius:
                                BorderRadius.circular(8),
                            border: Border.all(
                                color:
                                    Colors.green.shade200),
                          ),
                          child: Text(
                            'Happening now',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ),
                      if (isMember && !isHost)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade50,
                            borderRadius:
                                BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Joined',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.purple.shade700,
                            ),
                          ),
                        ),
                      if (isHost)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius:
                                BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Your group',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.amber.shade800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Course tag
                  if (group.course.isNotEmpty)
                    Container(
                      margin:
                          const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1565C0)
                            .withOpacity(0.08),
                        borderRadius:
                            BorderRadius.circular(20),
                      ),
                      child: Text(
                        group.course,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1565C0),
                        ),
                      ),
                    ),

                  // Title
                  Text(
                    group.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),

                  // Meta row
                  Row(
                    children: [
                      Icon(Icons.access_time_rounded,
                          size: 13,
                          color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Text(
                        _formatTime(group.meetTime),
                        style: TextStyle(
                          fontSize: 12,
                          color: group.isHappeningNow
                              ? Colors.green.shade700
                              : Colors.grey.shade600,
                          fontWeight:
                              group.isHappeningNow
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.location_on_outlined,
                          size: 13,
                          color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          group.location,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Members
                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        group.isFull
                            ? 'Group full'
                            : '${group.spotsLeft} spots left',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: group.isFull
                              ? Colors.orange.shade700
                              : Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        '${group.memberIds.length}/${group.maxMembers} members',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor:
                          Colors.grey.shade200,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(
                        pct >= 1.0
                            ? Colors.orange
                            : const Color(0xFF1565C0),
                      ),
                      minHeight: 5,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Join button
                  if (currentUser?.isStudent == true &&
                      !isHost)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: group.isFull &&
                                !isMember
                            ? null
                            : () => _toggleJoin(
                                context,
                                ref,
                                isMember),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isMember
                              ? Colors.red.shade50
                              : const Color(0xFF1565C0),
                          foregroundColor: isMember
                              ? Colors.red.shade700
                              : Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets
                              .symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(10),
                            side: isMember
                                ? BorderSide(
                                    color:
                                        Colors.red.shade200)
                                : BorderSide.none,
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        child: Text(isMember
                            ? 'Leave group'
                            : group.isFull
                                ? 'Group full'
                                : 'Join group'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = time.difference(now);
    if (diff.inDays == 0) {
      return 'Today, ${DateFormat('h:mm a').format(time)}';
    } else if (diff.inDays == 1) {
      return 'Tomorrow, ${DateFormat('h:mm a').format(time)}';
    }
    return DateFormat('MMM d, h:mm a').format(time);
  }

  Future<void> _toggleJoin(BuildContext context,
      WidgetRef ref, bool isMember) async {
    final user =
        ref.read(userModelProvider).asData?.value;
    if (user == null) return;

    try {
      final docRef = FirebaseFirestore.instance
          .collection('studyGroups')
          .doc(group.id);

      if (isMember) {
        await docRef.update({
          'memberIds':
              FieldValue.arrayRemove([user.uid]),
          'memberNames':
              FieldValue.arrayRemove([user.name]),
        });
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Left study group'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        await docRef.update({
          'memberIds': FieldValue.arrayUnion([user.uid]),
          'memberNames':
              FieldValue.arrayUnion([user.name]),
        });
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Joined ${group.title}!'),
              backgroundColor: Colors.green.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}

// ─── Detail Screen ─────────────────────────────────────
class StudyGroupDetailScreen extends ConsumerWidget {
  final StudyGroup group;
  const StudyGroupDetailScreen({super.key, required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user =
        ref.watch(userModelProvider).asData?.value;
    final isMember = user != null &&
        group.memberIds.contains(user.uid);
    final isHost = user?.uid == group.hostId;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Study Group',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF1a3a6b),
          ),
        ),
        actions: [
          if (isHost)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Colors.red),
              onPressed: () =>
                  _deleteGroup(context, ref),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF1a3a6b),
                    const Color(0xFF1565C0),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  if (group.course.isNotEmpty)
                    Container(
                      margin:
                          const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color:
                            Colors.white.withOpacity(0.2),
                        borderRadius:
                            BorderRadius.circular(20),
                      ),
                      child: Text(
                        group.course,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  Text(
                    group.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Hosted by ${group.hostName}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Info card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                children: [
                  _DetailRow(
                    icon: Icons.access_time_rounded,
                    label: 'Meet time',
                    value: DateFormat(
                            'EEEE, MMM d · h:mm a')
                        .format(group.meetTime),
                  ),
                  const Divider(
                      height: 20,
                      color: Color(0xFFE2E8F0)),
                  _DetailRow(
                    icon: Icons.timer_off_rounded,
                    label: 'End time',
                    value: DateFormat(
                            'EEEE, MMM d · h:mm a')
                        .format(group.endTime),
                  ),
                  const Divider(
                      height: 20,
                      color: Color(0xFFE2E8F0)),
                  _DetailRow(
                    icon: Icons.location_on_rounded,
                    label: 'Location',
                    value: group.location,
                  ),
                  const Divider(
                      height: 20,
                      color: Color(0xFFE2E8F0)),
                  _DetailRow(
                    icon: Icons.people_rounded,
                    label: 'Group size',
                    value:
                        '${group.memberIds.length} / ${group.maxMembers} members',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Description
            if (group.description.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color:
                          Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'About',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      group.description,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF475569),
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),

            // Members list
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    'Members (${group.memberIds.length})',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (group.memberNames.isEmpty)
                    Text(
                      'No members yet',
                      style: TextStyle(
                          color: Colors.grey.shade500),
                    )
                  else
                    ...group.memberNames
                        .asMap()
                        .entries
                        .map((entry) {
                      final name = entry.value;
                      final isThisHost = group.memberIds.isNotEmpty &&
    entry.key < group.memberIds.length &&
    group.memberIds[entry.key] == group.hostId;
                      final initials = name
                          .split(' ')
                          .map((w) => w.isNotEmpty
                              ? w[0].toUpperCase()
                              : '')
                          .take(2)
                          .join();

                      return Container(
                        margin: const EdgeInsets.only(
                            bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius:
                              BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: const Color(
                                        0xFF1565C0)
                                    .withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  initials,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight:
                                        FontWeight.w700,
                                    color:
                                        Color(0xFF1565C0),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight:
                                      FontWeight.w600,
                                ),
                              ),
                            ),
                           if (isThisHost)
                              Container(
                                padding: const EdgeInsets
                                    .symmetric(
                                    horizontal: 8,
                                    vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors
                                      .amber.shade50,
                                  borderRadius:
                                      BorderRadius.circular(
                                          6),
                                ),
                                child: Text(
                                  'Host',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight:
                                        FontWeight.w700,
                                    color: Colors
                                        .amber.shade800,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Join/Leave button
            if (user != null &&
                user.isStudent &&
                !isHost)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: group.isFull && !isMember
                      ? null
                      : () =>
                          _toggleJoin(context, ref, isMember, user),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isMember
                        ? Colors.red.shade600
                        : const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(12),
                    ),
                    elevation: 0,
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(isMember
                      ? 'Leave Group'
                      : group.isFull
                          ? 'Group Full'
                          : 'Join Group'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleJoin(BuildContext context,
      WidgetRef ref, bool isMember, dynamic user) async {
    try {
      final docRef = FirebaseFirestore.instance
          .collection('studyGroups')
          .doc(group.id);

      if (isMember) {
        await docRef.update({
          'memberIds': FieldValue.arrayRemove([user.uid]),
          'memberNames':
              FieldValue.arrayRemove([user.name]),
        });
        if (context.mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Left study group')),
          );
        }
      } else {
        await docRef.update({
          'memberIds': FieldValue.arrayUnion([user.uid]),
          'memberNames':
              FieldValue.arrayUnion([user.name]),
        });
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Joined ${group.title}!'),
              backgroundColor: Colors.green.shade700,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _deleteGroup(
      BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete study group?'),
        content: const Text(
            'This will permanently delete the study group.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete',
                style: TextStyle(
                    color: Colors.red.shade700)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await FirebaseFirestore.instance
        .collection('studyGroups')
        .doc(group.id)
        .delete();

    if (context.mounted) Navigator.pop(context);
  }
}

// ─── Create Screen ─────────────────────────────────────
class CreateStudyGroupScreen extends ConsumerStatefulWidget {
  const CreateStudyGroupScreen({super.key});

  @override
  ConsumerState<CreateStudyGroupScreen> createState() =>
      _CreateStudyGroupScreenState();
}

class _CreateStudyGroupScreenState
    extends ConsumerState<CreateStudyGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _courseController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  int _maxMembers = 5;
  DateTime _meetTime =
      DateTime.now().add(const Duration(hours: 1));
  DateTime _endTime =
      DateTime.now().add(const Duration(hours: 3));
  bool _isLoading = false;

  static const List<String> _commonLocations = [
    'Library - Study Room 1',
    'Library - Study Room 2',
    'Library - Open Area',
    'Schure Hall',
    'Anna Rubin Hall',
    'Theobald Science Center',
    'Student Activity Center',
    'Online (Zoom/Discord)',
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _courseController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime(
      {required bool isStart}) async {
    final date = await showDatePicker(
      context: context,
      initialDate: isStart ? _meetTime : _endTime,
      firstDate: DateTime.now(),
      lastDate:
          DateTime.now().add(const Duration(days: 30)),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
          isStart ? _meetTime : _endTime),
    );
    if (time == null) return;

    final dt = DateTime(date.year, date.month, date.day,
        time.hour, time.minute);
    setState(() {
      if (isStart) {
        _meetTime = dt;
        if (_endTime.isBefore(_meetTime)) {
          _endTime =
              _meetTime.add(const Duration(hours: 2));
        }
      } else {
        _endTime = dt;
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user =
        ref.read(userModelProvider).asData?.value;
    if (user == null) return;

    setState(() => _isLoading = true);
    try {
      final group = StudyGroup(
        id: '',
        title: _titleController.text.trim(),
        course: _courseController.text.trim(),
        description: _descriptionController.text.trim(),
        hostId: user.uid,
        hostName: user.name,
        location: _locationController.text.trim(),
        meetTime: _meetTime,
        endTime: _endTime,
        maxMembers: _maxMembers,
        memberIds: [user.uid],
        memberNames: [user.name],
        createdAt: DateTime.now(),
      );

      await FirebaseFirestore.instance
          .collection('studyGroups')
          .add(group.toFirestore());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Study group created!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Create Study Group',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: Color(0xFF1a3a6b),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _submit,
            child: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2),
                  )
                : const Text(
                    'Post',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Course field
            _buildCard(
              child: TextFormField(
                controller: _courseController,
                decoration: const InputDecoration(
                  labelText: 'Course / Subject',
                  hintText: 'e.g. CSCI 380, Calculus II',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  prefixIcon: Icon(
                      Icons.menu_book_rounded,
                      color: Color(0xFF1565C0)),
                ),
                validator: (val) =>
                    val == null || val.trim().isEmpty
                        ? 'Course is required'
                        : null,
              ),
            ),
            const SizedBox(height: 12),

            // Title
            _buildCard(
              child: TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Group name',
                  hintText: 'e.g. Final Exam Prep',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  prefixIcon: Icon(Icons.group_rounded,
                      color: Color(0xFF1565C0)),
                ),
                validator: (val) =>
                    val == null || val.trim().isEmpty
                        ? 'Name is required'
                        : null,
              ),
            ),
            const SizedBox(height: 12),

            // Description
            _buildCard(
              child: TextFormField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'What will you study?',
                  hintText:
                      'Topics, chapters, problems...',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(bottom: 48),
                    child: Icon(
                        Icons.description_rounded,
                        color: Color(0xFF1565C0)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Date/Time
            _buildCard(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 4),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                        Icons.calendar_today_rounded,
                        color: Color(0xFF1565C0)),
                    title: const Text('Meet time',
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey)),
                    subtitle: Text(
                      DateFormat('EEE, MMM d · h:mm a')
                          .format(_meetTime),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    onTap: () =>
                        _pickDateTime(isStart: true),
                  ),
                  Divider(
                      height: 0,
                      color: Colors.grey.shade200),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                        Icons.timer_off_rounded,
                        color: Color(0xFF1565C0)),
                    title: const Text('End time',
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey)),
                    subtitle: Text(
                      DateFormat('EEE, MMM d · h:mm a')
                          .format(_endTime),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    onTap: () =>
                        _pickDateTime(isStart: false),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Location
            _buildCard(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _locationController,
                    decoration: const InputDecoration(
                      labelText: 'Location',
                      hintText:
                          'Where will you meet?',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      prefixIcon: Icon(
                          Icons.location_on_rounded,
                          color: Color(0xFF1565C0)),
                    ),
                    validator: (val) =>
                        val == null || val.trim().isEmpty
                            ? 'Location is required'
                            : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        16, 0, 16, 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: _commonLocations
                          .map((loc) {
                        final selected =
                            _locationController.text ==
                                loc;
                        return GestureDetector(
                          onTap: () => setState(() =>
                              _locationController.text =
                                  loc),
                          child: Container(
                            padding: const EdgeInsets
                                .symmetric(
                                horizontal: 10,
                                vertical: 6),
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFF1565C0)
                                  : const Color(
                                      0xFFF1F5F9),
                              borderRadius:
                                  BorderRadius.circular(
                                      20),
                            ),
                            child: Text(
                              loc,
                              style: TextStyle(
                                fontSize: 11,
                                color: selected
                                    ? Colors.white
                                    : const Color(
                                        0xFF475569),
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: 12),

            // Max members
            _buildCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.people_rounded,
                          color: Color(0xFF1565C0),
                          size: 20),
                      const SizedBox(width: 10),
                      const Text(
                        'Max members',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '$_maxMembers people',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1565C0),
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _maxMembers.toDouble(),
                    min: 2,
                    max: 10,
                    divisions: 8,
                    activeColor: const Color(0xFF1565C0),
                    onChanged: (val) => setState(
                        () => _maxMembers = val.toInt()),
                  ),
                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.spaceBetween,
                    children: [
                      Text('2',
                          style: TextStyle(
                              fontSize: 11,
                              color:
                                  Colors.grey.shade500)),
                      Text('10',
                          style: TextStyle(
                              fontSize: 11,
                              color:
                                  Colors.grey.shade500)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(12),
                  ),
                  elevation: 0,
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Create Study Group'),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({
    required Widget child,
    EdgeInsets padding =
        const EdgeInsets.symmetric(horizontal: 4),
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

// ─── Shared widgets ────────────────────────────────────
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF1565C0).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon,
              size: 18, color: const Color(0xFF1565C0)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}