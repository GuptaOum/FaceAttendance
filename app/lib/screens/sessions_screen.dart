import 'package:flutter/material.dart';

import '../api.dart';
import 'kiosk_screen.dart';
import 'report_screen.dart';

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  List<dynamic>? _sessions;
  List<String> _groups = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _today {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _load() async {
    setState(() {
      _sessions = null;
      _error = null;
    });
    try {
      final sessions = await ApiClient.instance.listSessions();
      final groups = await ApiClient.instance.listGroups();
      setState(() {
        _sessions = sessions;
        _groups = groups.map((g) => g['name'] as String).toList();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _addSessionDialog() async {
    final title = TextEditingController();
    String group = '';
    DateTime date = DateTime.now();
    TimeOfDay start = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay end = const TimeOfDay(hour: 10, minute: 0);
    TimeOfDay? entryUntil;
    TimeOfDay? exitFrom;
    TimeOfDay? exitUntil;

    String two(int n) => n.toString().padLeft(2, '0');
    String dateStr(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
    String timeStr(TimeOfDay t) => '${two(t.hour)}:${two(t.minute)}';
    TimeOfDay shift(TimeOfDay t, int minutes) {
      final total = (t.hour * 60 + t.minute + minutes).clamp(0, 23 * 60 + 59);
      return TimeOfDay(hour: total ~/ 60, minute: total % 60);
    }

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('New session'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration:
                    const InputDecoration(labelText: 'Title', hintText: 'e.g. Math period'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: group,
                decoration: const InputDecoration(labelText: 'Group'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('All my students')),
                  ..._groups.map((g) => DropdownMenuItem(value: g, child: Text(g))),
                ],
                onChanged: (v) => setLocal(() => group = v ?? ''),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_month),
                title: Text(dateStr(date)),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) setLocal(() => date = picked);
                },
              ),
              Row(
                children: [
                  Expanded(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule),
                      title: Text(timeStr(start)),
                      onTap: () async {
                        final picked = await showTimePicker(context: ctx, initialTime: start);
                        if (picked != null) setLocal(() => start = picked);
                      },
                    ),
                  ),
                  const Text('to'),
                  Expanded(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule),
                      title: Text(timeStr(end)),
                      onTap: () async {
                        final picked = await showTimePicker(context: ctx, initialTime: end);
                        if (picked != null) setLocal(() => end = picked);
                      },
                    ),
                  ),
                ],
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.login, color: Colors.green),
                title: Text('Entry allowed until ${timeStr(entryUntil ?? shift(start, 15))}'),
                subtitle: const Text('Students scan IN before this time'),
                onTap: () async {
                  final picked = await showTimePicker(
                      context: ctx, initialTime: entryUntil ?? shift(start, 15));
                  if (picked != null) setLocal(() => entryUntil = picked);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.logout, color: Colors.orange),
                title: Text(
                    'Exit scan ${timeStr(exitFrom ?? shift(end, -10))} to ${timeStr(exitUntil ?? shift(end, 15))}'),
                subtitle: const Text('Students scan OUT in this window'),
                onTap: () async {
                  final from = await showTimePicker(
                      context: ctx,
                      initialTime: exitFrom ?? shift(end, -10),
                      helpText: 'Exit window opens');
                  if (from == null || !ctx.mounted) return;
                  final until = await showTimePicker(
                      context: ctx,
                      initialTime: exitUntil ?? shift(end, 15),
                      helpText: 'Exit window closes');
                  if (until == null) return;
                  setLocal(() {
                    exitFrom = from;
                    exitUntil = until;
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
          ],
        ),
      ),
    );
    if (created != true || title.text.trim().isEmpty) return;
    try {
      await ApiClient.instance.createSession(
        title.text.trim(),
        group,
        dateStr(date),
        timeStr(start),
        timeStr(end),
        timeStr(entryUntil ?? shift(start, 15)),
        timeStr(exitFrom ?? shift(end, -10)),
        timeStr(exitUntil ?? shift(end, 15)),
      );
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Widget _sessionTile(Map<String, dynamic> s) {
    final isToday = s['date'] == _today;
    final isPast = (s['date'] as String).compareTo(_today) < 0;
    final group = (s['group_name'] as String).isEmpty ? 'All students' : s['group_name'];
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: isToday ? Colors.indigo.shade50 : null,
      child: ListTile(
        leading: Icon(
          isToday ? Icons.today : (isPast ? Icons.history : Icons.event),
          color: isToday ? Colors.indigo : (isPast ? Colors.grey : null),
        ),
        title: Text(s['title']),
        subtitle: Text(
            '$group · ${s['date']} · ${s['start_time']}–${s['end_time']}\nIN until ${s['entry_until']} · OUT ${s['exit_from']}–${s['exit_until']}'),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isToday)
              FilledButton.icon(
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Start'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => KioskScreen(
                      sessionId: s['id'],
                      sessionTitle: s['title'],
                      group: (s['group_name'] as String).isEmpty ? null : s['group_name'],
                    ),
                  ),
                ),
              ),
            if (isPast || isToday)
              IconButton(
                icon: const Icon(Icons.assessment_outlined),
                tooltip: 'Session report',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          ReportScreen(sessionId: s['id'], sessionTitle: s['title'])),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await ApiClient.instance.deleteSession(s['id']);
                _load();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions ?? [];
    final today = sessions.where((s) => s['date'] == _today).toList();
    final upcoming = sessions.where((s) => (s['date'] as String).compareTo(_today) > 0).toList()
      ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
    final past = sessions.where((s) => (s['date'] as String).compareTo(_today) < 0).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Sessions'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
          : _sessions == null
              ? const Center(child: CircularProgressIndicator())
              : sessions.isEmpty
                  ? const Center(
                      child: Text('No sessions yet.\nTap + to schedule your first period.',
                          textAlign: TextAlign.center))
                  : ListView(
                      children: [
                        if (today.isNotEmpty) ...[
                          const ListTile(
                              title: Text('Today',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold, color: Colors.indigo))),
                          ...today.map((s) => _sessionTile(s)),
                        ],
                        if (upcoming.isNotEmpty) ...[
                          const ListTile(
                              title: Text('Upcoming',
                                  style: TextStyle(fontWeight: FontWeight.bold))),
                          ...upcoming.map((s) => _sessionTile(s)),
                        ],
                        if (past.isNotEmpty) ...[
                          const ListTile(
                              title: Text('Past',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold, color: Colors.grey))),
                          ...past.take(10).map((s) => _sessionTile(s)),
                        ],
                      ],
                    ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add Session'),
        onPressed: _addSessionDialog,
      ),
    );
  }
}
