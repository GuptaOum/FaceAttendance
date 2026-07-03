import 'package:flutter/material.dart';

import '../api.dart';

class ReportScreen extends StatefulWidget {
  final int? sessionId;
  final String? sessionTitle;
  const ReportScreen({super.key, this.sessionId, this.sessionTitle});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  DateTime _day = DateTime.now();
  Map<String, dynamic>? _report;
  String? _error;
  String _group = '';
  List<String> _groups = [];
  String _query = '';

  List<dynamic> _filter(List<dynamic> rows) => _query.isEmpty
      ? rows
      : rows
          .where((s) =>
              (s['name'] as String).toLowerCase().contains(_query) ||
              (s['roll_no'] as String).contains(_query))
          .toList();

  @override
  void initState() {
    super.initState();
    _loadGroups();
    _load();
  }

  Future<void> _loadGroups() async {
    try {
      final groups = await ApiClient.instance.listGroups();
      setState(() => _groups = groups.map((g) => g['name'] as String).toList());
    } catch (_) {}
  }

  String get _dayStr =>
      '${_day.year}-${_day.month.toString().padLeft(2, '0')}-${_day.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _report = null;
      _error = null;
    });
    try {
      final report = await ApiClient.instance.attendanceReport(
          day: _dayStr, group: _group, sessionId: widget.sessionId);
      setState(() => _report = report);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2025),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _day = picked);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final present = _filter((_report?['present'] as List<dynamic>?) ?? []);
    final absent = _filter((_report?['absent'] as List<dynamic>?) ?? []);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.sessionId != null
            ? 'Report — ${widget.sessionTitle}'
            : 'Attendance — $_dayStr'),
        actions: [
          if (widget.sessionId == null)
            IconButton(icon: const Icon(Icons.calendar_month), onPressed: _pickDay),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
          : _report == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search by name or roll no',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                      ),
                    ),
                    if (_groups.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: DropdownButtonFormField<String>(
                          initialValue: _group,
                          decoration: const InputDecoration(
                              labelText: 'Group', border: OutlineInputBorder()),
                          items: [
                            const DropdownMenuItem(value: '', child: Text('All groups')),
                            ..._groups.map((g) => DropdownMenuItem(value: g, child: Text(g))),
                          ],
                          onChanged: (v) {
                            setState(() => _group = v ?? '');
                            _load();
                          },
                        ),
                      ),
                    ListTile(
                      title: Text('Present (${present.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                    ),
                    ...present.map((s) => ListTile(
                          leading: Icon(
                            widget.sessionId != null && s['exit_at'] == null
                                ? Icons.warning_amber
                                : Icons.check_circle,
                            color: widget.sessionId != null && s['exit_at'] == null
                                ? Colors.orange
                                : Colors.green,
                          ),
                          title: Text('${s['name']} (${s['roll_no']})'),
                          subtitle: Text(widget.sessionId != null
                              ? (s['exit_at'] == null
                                  ? 'IN ${(s['marked_at'] as String).substring(11)} · no exit scan ⚠'
                                  : 'IN ${(s['marked_at'] as String).substring(11)} → OUT ${(s['exit_at'] as String).substring(11)}')
                              : '${s['class_name']} · marked at ${s['marked_at']}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Remove this attendance',
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text('Remove attendance for ${s['name']}?'),
                                  content: Text('${s['name']} will be marked absent for $_dayStr.'),
                                  actions: [
                                    TextButton(
                                        onPressed: () => Navigator.pop(ctx, false),
                                        child: const Text('Cancel')),
                                    FilledButton(
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('Remove')),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                try {
                                  await ApiClient.instance
                                      .deleteAttendance(s['attendance_id']);
                                  _load();
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(e.toString())));
                                  }
                                }
                              }
                            },
                          ),
                        )),
                    const Divider(),
                    ListTile(
                      title: Text('Absent (${absent.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                    ),
                    ...absent.map((s) => ListTile(
                          leading: const Icon(Icons.cancel, color: Colors.red),
                          title: Text('${s['name']} (${s['roll_no']})'),
                          subtitle: Text(s['class_name']),
                        )),
                  ],
                ),
    );
  }
}
