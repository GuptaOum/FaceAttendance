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
    // Periods only count once the leaving scan is done, so this figure never
    // includes a block the student walked out of without scanning.
    var periodsAttended = 0;
    var periodsTotal = 0;
    var awaiting = 0;
    for (final r in records) {
      final s = r['period_summary'] as Map<String, dynamic>?;
      if (s == null) continue;
      periodsAttended += (s['attended'] as int? ?? 0);
      periodsTotal += (s['total'] as int? ?? 0);
      if (s['awaiting_exit'] == true) awaiting++;
    }
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
                    Text(periodsTotal > 0 ? '$periodsAttended/$periodsTotal' : '${records.length}',
                        style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade800)),
                    Text(periodsTotal > 0 ? 'periods attended' : 'total records',
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          if (awaiting > 0) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.hourglass_top, size: 16, color: Colors.orange.shade800),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$awaiting block${awaiting == 1 ? '' : 's'} not counted - '
                    'you did not scan out when leaving',
                    style: TextStyle(fontSize: 11.5, color: Colors.orange.shade900),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// One attendance record. A block-based record expands to show which
  /// periods it actually earned; a plain kiosk record is a single line.
  Widget _recordTile(Map<String, dynamic> r) {
    final exit = r['exit_at'];
    final summary = r['period_summary'] as Map<String, dynamic>?;
    final title = (r['session_title'] as String?) ?? 'Kiosk attendance';
    final times = exit == null
        ? 'In ${r['marked_at']}  ·  no leaving scan yet'
        : 'In ${r['marked_at']}  ·  Out $exit';

    if (summary == null) {
      return ListTile(
        leading: Icon(exit == null ? Icons.hourglass_top : Icons.check_circle,
            color: exit == null ? Colors.orange : Colors.green),
        title: Text('${r['date']}  ·  $title'),
        subtitle: Text(times, style: const TextStyle(fontSize: 12)),
      );
    }

    final awaiting = summary['awaiting_exit'] == true;
    final periods = (summary['periods'] as List).cast<Map<String, dynamic>>();
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: ExpansionTile(
        leading: Icon(awaiting ? Icons.hourglass_top : Icons.check_circle,
            color: awaiting ? Colors.orange : Colors.green),
        title: Text('${r['date']}  ·  $title'),
        subtitle: Text(
          awaiting
              ? 'Not counted yet - you have not scanned out'
              : '${summary['label']}  ·  $times',
          style: TextStyle(
              fontSize: 12, color: awaiting ? Colors.orange.shade800 : Colors.grey.shade700),
        ),
        children: periods.map((p) {
          final (icon, colour, label) = switch (p['status']) {
            'present' => (Icons.check_circle, Colors.green, 'Present'),
            'pending_exit' => (Icons.hourglass_empty, Colors.orange, 'Awaiting leaving scan'),
            _ => (Icons.cancel, Colors.red.shade300, 'Absent'),
          };
          return ListTile(
            dense: true,
            leading: Icon(icon, size: 18, color: colour),
            title: Text(p['subject'] ?? ''),
            subtitle: Text('${p['start_time']} - ${p['end_time']}',
                style: const TextStyle(fontSize: 11)),
            trailing: Text(label, style: TextStyle(fontSize: 11, color: colour)),
          );
        }).toList(),
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
                            return _recordTile(_records![i - 1] as Map<String, dynamic>);
                          },
                        ),
                ),
    );
  }
}
