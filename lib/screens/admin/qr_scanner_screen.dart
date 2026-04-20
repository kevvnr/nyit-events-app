import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../config/app_config.dart';
import '../../models/event_model.dart';
import '../../providers/event_provider.dart';
import '../../services/review_prompt_service.dart';

class QrScannerScreen extends ConsumerStatefulWidget {
  final EventModel event;
  const QrScannerScreen({super.key, required this.event});

  @override
  ConsumerState<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends ConsumerState<QrScannerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late MobileScannerController _cameraController;
  bool _isProcessing = false;
  Map<String, dynamic>? _lastResult;
  int _checkedInCount = 0;
  final _tokenController = TextEditingController();
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _rsvps = [];
  List<Map<String, dynamic>> _filteredRsvps = [];
  bool _loadingRsvps = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _cameraController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
    );
    _loadCheckedInCount();
    _loadRsvps();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _cameraController.dispose();
    _tokenController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCheckedInCount() async {
    try {
      final count = await ref
          .read(eventServiceProvider)
          .getCheckedInCount(widget.event.id);
      if (mounted) setState(() => _checkedInCount = count);
    } catch (e) {
      // non-fatal — count stays at 0 until next successful load
    }
  }

  Future<void> _loadRsvps() async {
    setState(() => _loadingRsvps = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(AppConfig.rsvpsCol)
          .where('eventId', isEqualTo: widget.event.id)
          .where('status', isEqualTo: AppConfig.rsvpConfirmed)
          .get();

      final rsvps = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection(AppConfig.usersCol)
              .doc(data['userId'])
              .get();
          rsvps.add({
            'rsvpId': doc.id,
            ...data,
            'userName': userDoc['name'] ?? 'Unknown',
            'studentId': userDoc['studentId'] ?? '',
            'email': userDoc['email'] ?? '',
          });
        } catch (e) {
          rsvps.add({'rsvpId': doc.id, ...data, 'userName': 'Unknown'});
        }
      }

      if (mounted) {
        setState(() {
          _rsvps = rsvps;
          _filteredRsvps = rsvps;
          _loadingRsvps = false;
        });
      }
    } catch (e) {
      print('loadRsvps error: $e');
      if (mounted) setState(() => _loadingRsvps = false);
    }
  }

  void _filterRsvps(String query) {
    setState(() {
      _filteredRsvps = _rsvps.where((r) {
        final name = (r['userName'] ?? '').toLowerCase();
        final id = (r['studentId'] ?? '').toLowerCase();
        final email = (r['email'] ?? '').toLowerCase();
        final q = query.toLowerCase();
        return name.contains(q) || id.contains(q) || email.contains(q);
      }).toList();
    });
  }

  Future<void> _processQrToken(String raw) async {
    if (_isProcessing || raw.isEmpty) return;

    // QR codes encode a full URL — extract just the token param
    String token = raw.trim();
    try {
      final uri = Uri.parse(raw.trim());
      if (uri.queryParameters.containsKey('token')) {
        token = uri.queryParameters['token']!;
      }
    } catch (_) {}

    if (token.isEmpty) return;
    setState(() => _isProcessing = true);

    try {
      final result = await ref
          .read(eventServiceProvider)
          .checkInStudent(qrToken: token, eventId: widget.event.id);

      if (mounted) {
        setState(() {
          _lastResult = result ?? {'error': 'QR code not found for this event'};
          if (result != null && result['alreadyCheckedIn'] != true) {
            _checkedInCount++;
          }
        });
        if (result != null && result['alreadyCheckedIn'] != true) {
          await ReviewPromptService.instance.registerPositiveSignal();
        }
        await _loadRsvps();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _lastResult = {'error': e.toString()});
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _manualCheckIn(Map<String, dynamic> rsvp) async {
    if (_isProcessing) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Manual check-in'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Check in ${rsvp['userName']}?',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'ID: ${rsvp['studentId']}',
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            Text(
              rsvp['email'] ?? '',
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Check in'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isProcessing = true);
    try {
      await FirebaseFirestore.instance
          .collection(AppConfig.rsvpsCol)
          .doc(rsvp['rsvpId'])
          .update({
            'checkedIn': true,
            'checkedInAt': Timestamp.now(),
            'manualCheckIn': true,
          });

      setState(() => _checkedInCount++);
      await _loadRsvps();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${rsvp['userName']} checked in manually!'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _undoCheckIn(Map<String, dynamic> rsvp) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Undo check-in?'),
        content: Text('Remove check-in for ${rsvp['userName']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Undo', style: TextStyle(color: Colors.red.shade700)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection(AppConfig.rsvpsCol)
          .doc(rsvp['rsvpId'])
          .update({
            'checkedIn': false,
            'checkedInAt': null,
            'manualCheckIn': false,
          });

      setState(() => _checkedInCount = (_checkedInCount - 1).clamp(0, 9999));
      await _loadRsvps();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Check-in undone.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _removeStudent(Map<String, dynamic> rsvp) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove student?'),
        content: Text(
          'Remove ${rsvp['userName']} from this event? The next person on the waitlist will be promoted and the student will be notified.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Remove', style: TextStyle(color: Colors.red.shade700)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isProcessing = true);
    try {
      await ref
          .read(eventServiceProvider)
          .removeStudentFromEvent(
            eventId: widget.event.id,
            userId: rsvp['userId'],
            rsvpId: rsvp['rsvpId'],
            wasConfirmed: rsvp['status'] == AppConfig.rsvpConfirmed,
          );
      if (rsvp['checkedIn'] == true) {
        setState(() => _checkedInCount = (_checkedInCount - 1).clamp(0, 9999));
      }
      await _loadRsvps();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${rsvp['userName']} removed and waitlist updated.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Check-in'),
            Text(
              widget.event.title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(
              icon: Icon(Icons.qr_code_rounded, size: 18),
              text: 'QR Scanner',
            ),
            Tab(icon: Icon(Icons.people_rounded, size: 18), text: 'Manual'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Check-in counter banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            color: AppConfig.primaryColor,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Checked in',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '$_checkedInCount / ${widget.event.rsvpCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1 — Live Camera Scanner
                _CameraTab(
                  cameraController: _cameraController,
                  isProcessing: _isProcessing,
                  lastResult: _lastResult,
                  onDetect: (token) async {
                    if (_isProcessing || token.isEmpty) return;
                    await _processQrToken(token);
                  },
                  onReset: () {
                    setState(() => _lastResult = null);
                    _cameraController.start();
                  },
                ),

                // Tab 2 — Manual
                _ManualCheckInTab(
                  searchController: _searchController,
                  rsvps: _filteredRsvps,
                  isLoading: _loadingRsvps,
                  isProcessing: _isProcessing,
                  onSearch: _filterRsvps,
                  onCheckIn: _manualCheckIn,
                  onUndo: _undoCheckIn,
                  onRemove: _removeStudent,
                  onRefresh: _loadRsvps,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tab 1: Live Camera Scanner ────────────────────────────────
class _CameraTab extends StatelessWidget {
  final MobileScannerController cameraController;
  final bool isProcessing;
  final Map<String, dynamic>? lastResult;
  final ValueChanged<String> onDetect;
  final VoidCallback onReset;

  const _CameraTab({
    required this.cameraController,
    required this.isProcessing,
    required this.lastResult,
    required this.onDetect,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    // Once we have a result, show it full-screen instead of the camera
    if (lastResult != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 16),
            _ResultCard(result: lastResult!, onReset: onReset),
          ],
        ),
      );
    }

    return Stack(
      children: [
        // Full-view camera feed
        MobileScanner(
          controller: cameraController,
          onDetect: (capture) {
            final raw = capture.barcodes.firstOrNull?.rawValue ?? '';
            if (raw.isNotEmpty) {
              cameraController.stop();
              onDetect(raw.trim());
            }
          },
        ),

        // Scanning frame overlay
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),

        // Instruction label
        Positioned(
          bottom: 32,
          left: 24,
          right: 24,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.qr_code_scanner_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                SizedBox(width: 8),
                Text(
                  'Point camera at student\'s check-in QR',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Processing overlay
        if (isProcessing)
          Container(
            color: Colors.black.withOpacity(0.55),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Checking in…',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Tab 2: Manual Check-in ────────────────────────────────────
class _ManualCheckInTab extends StatelessWidget {
  final TextEditingController searchController;
  final List<Map<String, dynamic>> rsvps;
  final bool isLoading;
  final bool isProcessing;
  final ValueChanged<String> onSearch;
  final Future<void> Function(Map<String, dynamic>) onCheckIn;
  final Future<void> Function(Map<String, dynamic>) onUndo;
  final Future<void> Function(Map<String, dynamic>) onRemove;
  final Future<void> Function() onRefresh;

  const _ManualCheckInTab({
    required this.searchController,
    required this.rsvps,
    required this.isLoading,
    required this.isProcessing,
    required this.onSearch,
    required this.onCheckIn,
    required this.onUndo,
    required this.onRemove,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: searchController,
            onChanged: onSearch,
            decoration: InputDecoration(
              hintText: 'Search by name, ID or email...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 20),
                      onPressed: () {
                        searchController.clear();
                        onSearch('');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : rsvps.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.people_outline_rounded,
                        size: 64,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 16),
                      const Text('No students found'),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: onRefresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                    itemCount: rsvps.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final rsvp = rsvps[index];
                      final checkedIn = rsvp['checkedIn'] == true;
                      final isManual = rsvp['manualCheckIn'] == true;

                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: checkedIn
                              ? Colors.green.shade50
                              : Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: checkedIn
                                ? Colors.green.shade200
                                : const Color(0xFFE2E8F0),
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: checkedIn
                                    ? Colors.green.withOpacity(0.15)
                                    : AppConfig.primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: Icon(
                                checkedIn
                                    ? Icons.check_circle_rounded
                                    : Icons.person_rounded,
                                color: checkedIn
                                    ? Colors.green.shade700
                                    : AppConfig.primaryColor,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    rsvp['userName'] ?? 'Unknown',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'ID: ${rsvp['studentId'] ?? 'N/A'}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                  if (checkedIn)
                                    Text(
                                      isManual
                                          ? 'Manually checked in'
                                          : 'QR checked in',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.green.shade600,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // Action buttons
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                checkedIn
                                    ? TextButton(
                                        onPressed: isProcessing
                                            ? null
                                            : () => onUndo(rsvp),
                                        style: TextButton.styleFrom(
                                          foregroundColor:
                                              Colors.orange.shade600,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                          minimumSize: const Size(0, 0),
                                        ),
                                        child: const Text(
                                          'Undo',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      )
                                    : ElevatedButton(
                                        onPressed: isProcessing
                                            ? null
                                            : () => onCheckIn(rsvp),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              Colors.green.shade600,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          minimumSize: const Size(0, 0),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: const Text(
                                          'Check in',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ),
                                const SizedBox(height: 4),
                                GestureDetector(
                                  onTap: isProcessing
                                      ? null
                                      : () => onRemove(rsvp),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: Colors.red.shade200,
                                      ),
                                    ),
                                    child: Text(
                                      'Remove',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.red.shade700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

// ─── Result Card with animation ────────────────────────────────
class _ResultCard extends StatefulWidget {
  final Map<String, dynamic> result;
  final VoidCallback onReset;

  const _ResultCard({required this.result, required this.onReset});

  @override
  State<_ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends State<_ResultCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.result['error'] != null;
    final alreadyCheckedIn = widget.result['alreadyCheckedIn'] == true;
    final success = !hasError && !alreadyCheckedIn;

    final color = hasError
        ? Colors.red
        : alreadyCheckedIn
        ? Colors.orange
        : Colors.green;

    final icon = hasError
        ? Icons.error_rounded
        : alreadyCheckedIn
        ? Icons.warning_rounded
        : Icons.check_circle_rounded;

    final title = hasError
        ? 'Invalid QR token'
        : alreadyCheckedIn
        ? 'Already checked in'
        : 'Successfully checked in!';

    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: color.withOpacity(0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.4), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.15),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            children: [
              // Animated icon
              ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 48),
                ),
              ),
              const SizedBox(height: 14),

              Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
                textAlign: TextAlign.center,
              ),

              // Student info
              if (success || alreadyCheckedIn) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Icon(
                          Icons.person_rounded,
                          color: color,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.result['userName'] ?? 'Student',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'ID: ${widget.result['studentId'] ?? 'N/A'}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            if (success)
                              Row(
                                children: [
                                  Icon(
                                    Icons.check_circle_rounded,
                                    size: 12,
                                    color: Colors.green.shade600,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Checked in just now',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.green.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Error message
              if (hasError) ...[
                const SizedBox(height: 8),
                Text(
                  widget.result['error'].toString(),
                  style: TextStyle(fontSize: 13, color: Colors.red.shade700),
                  textAlign: TextAlign.center,
                ),
              ],

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: widget.onReset,
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                  label: const Text('Scan next student'),
                  style: ElevatedButton.styleFrom(backgroundColor: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
