import 'package:flutter/material.dart';

import '../api.dart';
import 'kiosk_screen.dart';

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

    String two(int n) => n.toString().padLeft(2, '0');
    String dateStr(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
    String timeStr(TimeOfDay t) => '${two(t.hour)}:${two(t.minute)}';

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
      await ApiClient.instance
          .createSession(title.text.trim(), group, dateStr(date), timeStr(start), timeStr(end));
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
        subtitle: Text('$group · ${s['date']} · ${s['start_time']}–${s['end_time']}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isPast)
              FilledButton.icon(
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text(isToday ? 'Start' : 'Kiosk'),
                style: FilledButton.styleFrom(
                    backgroundColor: isToday ? Colors.indigo : Colors.grey),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => KioskScreen(
                        group: (s['group_name'] as String).isEmpty ? null : s['group_name']),
                  ),
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
