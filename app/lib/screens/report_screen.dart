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

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _dayStr =>
      '${_day.year}-${_day.month.toString().padLeft(2, '0')}-${_day.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _report = null;
      _error = null;
    });
    try {
      final report = await ApiClient.instance.attendanceReport(day: _dayStr);
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
