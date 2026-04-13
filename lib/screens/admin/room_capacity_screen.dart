import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../config/campus_locations.dart';
import '../../services/event_service.dart';

class RoomCapacityScreen extends StatefulWidget {
  const RoomCapacityScreen({super.key});

  @override
  State<RoomCapacityScreen> createState() => _RoomCapacityScreenState();
}

class _RoomCapacityScreenState extends State<RoomCapacityScreen> {
  bool _loading = true;
  bool _saving = false;
  final Map<String, int> _limits = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final limits = await EventService().getEffectiveRoomCapacities();
      if (!mounted) return;
      setState(() {
        _limits
          ..clear()
          ..addAll(limits);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final overrides = <String, int>{};
      for (final loc in CampusLocations.all) {
        final v = _limits[loc.id] ?? loc.maxCapacity;
        if (v != loc.maxCapacity) overrides[loc.id] = v;
      }
      await FirebaseFirestore.instance
          .collection(AppConfig.appConfigCol)
          .doc(AppConfig.appConfigDoc)
          .set({AppConfig.roomCapacityOverridesField: overrides}, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Room capacities updated.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      appBar: AppBar(
        title: const Text('Room capacities'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: CampusLocations.all.length,
              itemBuilder: (context, index) {
                final loc = CampusLocations.all[index];
                final current = _limits[loc.id] ?? loc.maxCapacity;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              loc.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              'Default: ${loc.maxCapacity}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 92,
                        child: TextFormField(
                          initialValue: '$current',
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            contentPadding:
                                EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            isDense: true,
                          ),
                          onChanged: (v) {
                            final parsed = int.tryParse(v);
                            if (parsed != null && parsed > 0) {
                              _limits[loc.id] = parsed;
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
