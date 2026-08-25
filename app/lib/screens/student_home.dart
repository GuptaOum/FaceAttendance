import 'package:flutter/material.dart';

import '../api.dart';
import 'login_screen.dart';

/// Read-only attendance view for a student.
///
/// Students have exactly one endpoint available to them (`/attendance/me`),
/// so there is deliberately nothing on this screen that mutates state.
class StudentHome extends StatefulWidget {
  const StudentHome({super.key});

  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<StudentHome> {
  List<dynamic>? _records;
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
      if (mounted) setState(() => _records = records);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
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

  /// Days present in the last 30 calendar days, as a simple attendance rate.
  Widget _summary() {
    final records = _records!;
    if (records.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: 30));
    final recent = records.where((r) {
      final d = DateTime.tryParse(r['date'] ?? '');
      return d != null && d.isAfter(cutoff);
    }).length;
    final name = records.first['name'] ?? '';
    final roll = records.first['roll_no'] ?? '';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (name.isNotEmpty)
            Text('$name  ·  $roll',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$recent',
                        style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade800)),
                    const Text('days present (last 30)', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${records.length}',
                        style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade800)),
                    const Text('total records', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Attendance'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _load),
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Logout', onPressed: _logout),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            )
          : _records == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _records!.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 120),
                            Icon(Icons.event_busy, size: 48, color: Colors.grey),
                            SizedBox(height: 12),
                            Center(child: Text('No attendance records yet')),
                            SizedBox(height: 6),
                            Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 40),
                                child: Text(
                                  'Your attendance appears here once you are scanned at the kiosk.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          itemCount: _records!.length + 1,
                          itemBuilder: (_, i) {
                            if (i == 0) return _summary();
                            final r = _records![i - 1];
                            final exit = r['exit_at'];
                            return ListTile(
                              leading: const Icon(Icons.check_circle, color: Colors.green),
                              title: Text(r['date'] ?? ''),
                              subtitle: Text(exit == null
                                  ? 'In at ${r['marked_at']}'
                                  : 'In at ${r['marked_at']}  ·  Out at $exit'),
                            );
                          },
                        ),
                ),
    );
  }
}
