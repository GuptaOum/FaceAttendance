import 'package:flutter/material.dart';

import '../api.dart';
import 'login_screen.dart';

class StudentHome extends StatefulWidget {
  const StudentHome({super.key});

  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<StudentHome> {
  List<dynamic>? _records;
  List<dynamic> _requests = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _records = null;
      _error = null;
    });
    try {
      final records = await ApiClient.instance.myAttendance();
      // A missing/failing request list must not hide the attendance history,
      // which is the main reason a student opens this screen.
      List<dynamic> requests = [];
      try {
        requests = await ApiClient.instance.myFaceRequests();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _records = records;
        _requests = requests;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Map<String, dynamic>? get _openRequest {
    for (final r in _requests) {
      if (r['status'] == 'open') return r as Map<String, dynamic>;
    }
    return null;
  }

  Future<void> _raiseRequest() async {
    var type = 'reenroll';
    final message = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Ask your teacher'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'reenroll',
                    icon: Icon(Icons.face_retouching_natural, size: 18),
                    label: Text('Re-enroll'),
                  ),
                  ButtonSegment(
                    value: 'issue',
                    icon: Icon(Icons.report_outlined, size: 18),
                    label: Text('Problem'),
                  ),
                ],
                selected: {type},
                onSelectionChanged: (v) => setLocal(() => type = v.first),
              ),
              const SizedBox(height: 6),
              Text(
                type == 'reenroll'
                    ? 'My look changed (glasses, beard, etc.) and I need my face enrolled again.'
                    : 'The kiosk does not recognise me.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: message,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Details (optional)',
                  hintText: 'e.g. I started wearing glasses last week',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await ApiClient.instance.createFaceRequest(type, message.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sent to your teacher')),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _logout() async {
    await ApiClient.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Widget _requestBanner() {
    final open = _openRequest;
    if (open != null) {
      return Container(
        width: double.infinity,
        color: Colors.orange.shade50,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.hourglass_top, color: Colors.orange),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                open['request_type'] == 'reenroll'
                    ? 'Re-enrollment requested. Waiting for your teacher.'
                    : 'Problem reported. Waiting for your teacher.',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }
    // Show the most recent resolution once, so the student learns the outcome.
    for (final r in _requests) {
      if (r['status'] == 'resolved' || r['status'] == 'rejected') {
        final resolved = r['status'] == 'resolved';
        final notes = r['teacher_notes'] as String;
        return Container(
          width: double.infinity,
          color: resolved ? Colors.green.shade50 : Colors.grey.shade200,
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(resolved ? Icons.check_circle_outline : Icons.info_outline,
                  color: resolved ? Colors.green : Colors.grey.shade700),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  notes.isNotEmpty
                      ? 'Teacher: $notes'
                      : (resolved
                          ? 'Your last request was resolved.'
                          : 'Your last request was declined.'),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        );
      }
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Attendance'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
          : _records == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    _requestBanner(),
                    Expanded(
                      child: _records!.isEmpty
                          ? const Center(child: Text('No attendance records yet'))
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.builder(
                                itemCount: _records!.length,
                                itemBuilder: (_, i) {
                                  final r = _records![i];
                                  return ListTile(
                                    leading: const Icon(Icons.check_circle, color: Colors.green),
                                    title: Text(r['date']),
                                    subtitle: Text('Marked at ${r['marked_at']}'),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
      floatingActionButton: _records == null || _openRequest != null
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.face_retouching_natural),
              label: const Text('Face problem?'),
              onPressed: _raiseRequest,
            ),
    );
  }
}
