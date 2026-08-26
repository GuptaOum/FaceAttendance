import 'package:flutter/material.dart';

import '../api.dart';
import 'login_screen.dart';

/// Read-only attendance view for a student, laid out as a month calendar.
///
/// Students have exactly one endpoint available to them (`/attendance/me`), so
/// there is deliberately nothing here that changes anything. The calendar shows
/// each day at a glance; tapping one breaks it down period by period.
class StudentHome extends StatefulWidget {
  const StudentHome({super.key});

  @override
  State<StudentHome> createState() => _StudentHomeState();
}

/// Everything recorded for one calendar day, across all blocks.
class _DayRecord {
  final List<Map<String, dynamic>> blocks = [];
  int attended = 0;
  int total = 0;
  bool awaitingExit = false;

  /// Days with no periods (plain kiosk marking) still count as attended.
  bool get isPlainMarking => total == 0 && blocks.isNotEmpty;
  double get ratio => total == 0 ? 1 : attended / total;
}

class _StudentHomeState extends State<StudentHome> {
  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  List<dynamic>? _records;
  String? _error;
  final Map<String, _DayRecord> _byDate = {};
  late DateTime _month;
  String? _selected;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _load();
  }

  String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _records = null;
      _error = null;
    });
    try {
      final records = await ApiClient.instance.myAttendance();
      if (!mounted) return;
      _byDate.clear();
      for (final r in records) {
        final rec = r as Map<String, dynamic>;
        final day = _byDate.putIfAbsent(rec['date'] as String, () => _DayRecord());
        day.blocks.add(rec);
        final s = rec['period_summary'] as Map<String, dynamic>?;
        if (s != null) {
          day.attended += (s['attended'] as int? ?? 0);
          day.total += (s['total'] as int? ?? 0);
          if (s['awaiting_exit'] == true) day.awaitingExit = true;
        } else if (rec['exit_at'] == null && rec['session_id'] != null) {
          day.awaitingExit = true;
        }
      }
      setState(() => _records = records);
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

  /// Green when every period was earned, amber when only some, red when none,
  /// and a hollow outline while a block is still waiting on a leaving scan.
  Color _dayColour(_DayRecord d) {
    if (d.awaitingExit) return Colors.orange.shade400;
    if (d.isPlainMarking) return Colors.green.shade600;
    if (d.attended == 0) return Colors.red.shade300;
    if (d.attended == d.total) return Colors.green.shade600;
    return Colors.amber.shade700;
  }

  Widget _monthHeader() {
    final now = DateTime.now();
    final canGoForward = _month.isBefore(DateTime(now.year, now.month));
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => setState(() {
            _month = DateTime(_month.year, _month.month - 1);
            _selected = null;
          }),
        ),
        Text('${_monthNames[_month.month - 1]} ${_month.year}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: canGoForward
              ? () => setState(() {
                    _month = DateTime(_month.year, _month.month + 1);
                    _selected = null;
                  })
              : null,
        ),
      ],
    );
  }

  Widget _calendar() {
    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    // Monday-first grid, so the leading blanks are however far into the week
    // the 1st falls.
    final lead = first.weekday - 1;
    final cells = <Widget>[];

    for (var i = 0; i < lead; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_month.year, _month.month, day);
      final key = _key(date);
      final rec = _byDate[key];
      final isToday = _key(DateTime.now()) == key;
      final isSelected = _selected == key;

      cells.add(GestureDetector(
        onTap: rec == null ? null : () => setState(() => _selected = isSelected ? null : key),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: rec == null ? null : _dayColour(rec).withValues(alpha: 0.18),
            border: Border.all(
              color: isSelected
                  ? Colors.indigo
                  : isToday
                      ? Colors.indigo.shade200
                      : Colors.transparent,
              width: isSelected ? 2 : 1.5,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$day',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                    color: rec == null ? Colors.grey.shade500 : Colors.black87,
                  )),
              const SizedBox(height: 2),
              if (rec != null)
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: _dayColour(rec), shape: BoxShape.circle),
                )
              else
                const SizedBox(height: 6),
            ],
          ),
        ),
      ));
    }

    return Column(
      children: [
        Row(
          children: _dayLabels
              .map((d) => Expanded(
                    child: Center(
                      child: Text(d,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade600)),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.95,
          children: cells,
        ),
      ],
    );
  }

  Widget _legend() {
    Widget dot(Color c, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 10.5)),
          ],
        );
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: [
        dot(Colors.green.shade600, 'All periods'),
        dot(Colors.amber.shade700, 'Some periods'),
        dot(Colors.red.shade300, 'None'),
        dot(Colors.orange.shade400, 'No leaving scan'),
      ],
    );
  }

  Widget _monthSummary() {
    var attended = 0, total = 0, daysPresent = 0, pending = 0;
    for (final entry in _byDate.entries) {
      final d = DateTime.parse(entry.key);
      if (d.year != _month.year || d.month != _month.month) continue;
      daysPresent++;
      attended += entry.value.attended;
      total += entry.value.total;
      if (entry.value.awaitingExit) pending++;
    }
    final pct = total == 0 ? null : (attended / total * 100).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pct == null ? '$daysPresent' : '$pct%',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo.shade700)),
                Text(pct == null ? 'days marked' : 'this month',
                    style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(total == 0 ? '-' : '$attended/$total',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo.shade700)),
                const Text('periods', style: TextStyle(fontSize: 11)),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$daysPresent',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo.shade700)),
                const Text('days attended', style: TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The selected day, broken down block by block and period by period.
  Widget _dayDetail() {
    final key = _selected;
    if (key == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text('Tap a highlighted day to see your periods',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
      );
    }
    final rec = _byDate[key];
    if (rec == null) return const SizedBox.shrink();
    final d = DateTime.parse(key);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Text(
            '${d.day} ${_monthNames[d.month - 1]}  ·  '
            '${rec.total == 0 ? "marked present" : "${rec.attended} of ${rec.total} periods"}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
        ...rec.blocks.map((b) {
          final summary = b['period_summary'] as Map<String, dynamic>?;
          final title = (b['session_title'] as String?) ?? 'Kiosk attendance';
          final exit = b['exit_at'];
          final inAt = (b['marked_at'] as String?) ?? '';
          final times = exit == null
              ? 'In ${inAt.length > 11 ? inAt.substring(11, 16) : inAt}  ·  no leaving scan'
              : 'In ${inAt.length > 11 ? inAt.substring(11, 16) : inAt}  ·  '
                  'Out ${(exit as String).length > 11 ? exit.substring(11, 16) : exit}';

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  dense: true,
                  leading: Icon(
                    summary?['awaiting_exit'] == true ? Icons.hourglass_top : Icons.event_available,
                    color: summary?['awaiting_exit'] == true ? Colors.orange : Colors.green,
                  ),
                  title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(times, style: const TextStyle(fontSize: 11.5)),
                  trailing: summary == null
                      ? null
                      : Text(summary['label'] as String,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                if (summary != null)
                  ...(summary['periods'] as List).cast<Map<String, dynamic>>().map((p) {
                    final (icon, colour, label) = switch (p['status']) {
                      'present' => (Icons.check_circle, Colors.green, 'Attended'),
                      'pending_exit' => (Icons.hourglass_empty, Colors.orange, 'Not counted yet'),
                      _ => (Icons.cancel_outlined, Colors.red.shade300, 'Missed'),
                    };
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      child: Row(
                        children: [
                          Icon(icon, size: 16, color: colour),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(p['subject'] ?? '',
                                style: const TextStyle(fontSize: 13)),
                          ),
                          Text('${p['start_time']}-${p['end_time']}',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 86,
                            child: Text(label,
                                textAlign: TextAlign.right,
                                style: TextStyle(fontSize: 10.5, color: colour)),
                          ),
                        ],
                      ),
                    );
                  }),
                if (summary?['cut_by_spot_check'] == true)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Text(
                      'Marked missing at a roll call at ${summary!['spot_check_at']}',
                      style: TextStyle(fontSize: 11, color: Colors.red.shade400),
                    ),
                  ),
                if (summary?['awaiting_exit'] == true)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Text(
                      'These periods will not count until the leaving scan is recorded. '
                      'Ask your teacher if you attended.',
                      style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _records != null && _records!.isNotEmpty
        ? (_records!.first['name'] as String? ?? '')
        : '';
    return Scaffold(
      appBar: AppBar(
        title: Text(name.isEmpty ? 'My Attendance' : name),
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
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    children: [
                      _monthSummary(),
                      const SizedBox(height: 8),
                      _monthHeader(),
                      _calendar(),
                      const SizedBox(height: 8),
                      _legend(),
                      const Divider(height: 24),
                      _dayDetail(),
                    ],
                  ),
                ),
    );
  }
}
