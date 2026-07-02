import 'package:flutter/material.dart';

import '../api.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  DateTime _day = DateTime.now();
  Map<String, dynamic>? _report;
  String? _error;
  String _group = '';
  List<String> _groups = [];

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
      final report = await ApiClient.instance.attendanceReport(day: _dayStr, group: _group);
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
    final present = (_report?['present'] as List<dynamic>?) ?? [];
    final absent = (_report?['absent'] as List<dynamic>?) ?? [];
    return Scaffold(
      appBar: AppBar(
        title: Text('Attendance — $_dayStr'),
        actions: [
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
                          leading: const Icon(Icons.check_circle, color: Colors.green),
                          title: Text('${s['name']} (${s['roll_no']})'),
                          subtitle: Text('${s['class_name']} · marked at ${s['marked_at']}'),
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
