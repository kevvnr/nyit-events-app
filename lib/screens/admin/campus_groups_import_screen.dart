import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_config.dart';
import '../../providers/auth_provider.dart';
import '../../providers/event_provider.dart';
import '../../services/campus_groups_import_service.dart';

class CampusGroupsImportScreen extends ConsumerStatefulWidget {
  const CampusGroupsImportScreen({super.key});

  @override
  ConsumerState<CampusGroupsImportScreen> createState() =>
      _CampusGroupsImportScreenState();
}

class _CampusGroupsImportScreenState
    extends ConsumerState<CampusGroupsImportScreen> {
  final _jsonController = TextEditingController();
  final _tokenController = TextEditingController();
  final _urlController = TextEditingController(
    text: '${AppConfig.campusGroupsEventsApiUrl}?page=1&per_page=100',
  );
  bool _onlyUpcoming = true;
  bool _busy = false;
  /// When true, token is masked (can block paste on some iOS builds).
  bool _obscureToken = false;

  @override
  void dispose() {
    _jsonController.dispose();
    _tokenController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _runImport(String jsonText) async {
    final user = ref.read(userModelProvider).asData?.value;
    if (user == null || !user.isSuperAdmin) return;

    setState(() => _busy = true);
    try {
      final svc = ref.read(eventServiceProvider);
      final importer = CampusGroupsImportService(svc);
      final result = await importer.importFromJsonString(
        jsonText: jsonText,
        hostId: user.uid,
        hostName: '${user.name} · CampusGroups',
        onlyUpcoming: _onlyUpcoming,
      );
      await ref.read(eventsNotifierProvider.notifier).loadEvents();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Import finished'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Saved ${result.saved} event(s). Skipped ${result.skipped}.',
                ),
                if (result.issues.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Notes:',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...result.issues.take(12).map(
                        (s) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(s, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                        ),
                      ),
                  if (result.issues.length > 12)
                    Text(
                      '… and ${result.issues.length - 12} more',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pasteTokenFromClipboard() async {
    final clip = await Clipboard.getData('text/plain');
    final raw = clip?.text?.trim();
    if (raw == null || raw.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Clipboard is empty. Open Mail or Notes on this phone, copy the token there first, then tap Paste token again.',
            ),
          ),
        );
      }
      return;
    }
    var token = raw;
    if (token.toLowerCase().startsWith('bearer ')) {
      token = token.substring(7).trim();
    }
    setState(() => _tokenController.text = token);
  }

  Future<void> _fetchAndImport() async {
    final token = _tokenController.text.replaceAll(RegExp(r'\s+'), '').trim();
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paste a Bearer token first.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final body = await CampusGroupsImportService.fetchEventsWithBearer(
        bearerToken: token,
        requestUrl: _urlController.text.trim().isEmpty
            ? null
            : _urlController.text.trim(),
      );
      _tokenController.clear();
      await _runImport(body);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userModelProvider).asData?.value;
    if (user == null || !user.isSuperAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('CampusGroups import')),
        body: const Center(child: Text('Super Admin only.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('CampusGroups import'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0F4FA8), Color(0xFF1565C0)],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Copy events into the app (Firestore). Re-import updates the same event when the CampusGroups id matches.',
                style: TextStyle(fontSize: 14, height: 1.45, color: Colors.grey.shade800),
              ),
              const SizedBox(height: 16),
              Text(
                'How to get JSON',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '1) On a computer, log in to campusgroups.nyit.edu.\n'
                '2) Open DevTools → Network → Fetch/XHR.\n'
                '3) Reload the events list, click mobile_events_list, open Response, copy the full body.\n'
                '   Raw array [{…}] or wrapped like {"data":[…]} both work. Rows use "fields" plus p0, p1, …\n'
                '4) Paste below and tap Import JSON.\n\n'
                'Or use a Bearer token from an /api/… request’s headers → Fetch & import. The token is not stored.',
                style: TextStyle(fontSize: 13, height: 1.45, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Only upcoming (skip ended)'),
                value: _onlyUpcoming,
                onChanged: _busy ? null : (v) => setState(() => _onlyUpcoming = v),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _jsonController,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Event JSON',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.multiline,
                enabled: !_busy,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              final clip = await Clipboard.getData('text/plain');
                              final t = clip?.text;
                              if (t != null && t.isNotEmpty) {
                                setState(() => _jsonController.text = t);
                              }
                            },
                      icon: const Icon(Icons.paste_rounded, size: 18),
                      label: const Text('Paste'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _runImport(_jsonController.text),
                      icon: const Icon(Icons.upload_rounded, size: 20),
                      label: const Text('Import JSON'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              const Divider(),
              const SizedBox(height: 12),
              Text(
                'Fetch with token',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Mac → iPhone clipboard usually fails. Reliable path: email the JWT to yourself → open Mail on the iPhone → copy the line → Paste token below. Or paste into Notes on the phone, copy, then Paste token.',
                style: TextStyle(fontSize: 12, height: 1.35, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _tokenController,
                minLines: 3,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: 'Bearer token (JWT)',
                  hintText: 'Paste the full eyJ… token here',
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _obscureToken ? 'Show token' : 'Hide token',
                    icon: Icon(
                      _obscureToken ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                    ),
                    onPressed: _busy
                        ? null
                        : () => setState(() => _obscureToken = !_obscureToken),
                  ),
                ),
                obscureText: _obscureToken,
                autocorrect: false,
                enableSuggestions: false,
                smartDashesType: SmartDashesType.disabled,
                smartQuotesType: SmartQuotesType.disabled,
                keyboardType: TextInputType.multiline,
                enabled: !_busy,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pasteTokenFromClipboard,
                icon: const Icon(Icons.paste_rounded, size: 18),
                label: const Text('Paste token from clipboard'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'Request URL (optional)',
                  border: OutlineInputBorder(),
                ),
                enabled: !_busy,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: _busy ? null : _fetchAndImport,
                  icon: const Icon(Icons.cloud_download_rounded),
                  label: const Text('Fetch & import'),
                ),
              ),
            ],
          ),
          if (_busy)
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}
