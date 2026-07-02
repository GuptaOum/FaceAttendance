import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import 'enroll_screen.dart';
import 'kiosk_screen.dart';
import 'login_screen.dart';
import 'report_screen.dart';

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  List<dynamic> _students = [];
  bool _loading = true;
  String? _error;
  String _query = '';

  List<dynamic> get _filtered => _query.isEmpty
      ? _students
      : _students
          .where((s) =>
              (s['name'] as String).toLowerCase().contains(_query) ||
              (s['roll_no'] as String).contains(_query) ||
              (s['class_name'] as String).toLowerCase().contains(_query))
          .toList();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final students = await ApiClient.instance.listStudents();
      setState(() => _students = students);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addStudentDialog() async {
    final rollNo = TextEditingController();
    final name = TextEditingController();
    final className = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Student'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: rollNo,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Roll No', hintText: 'Numbers only'),
            ),
            TextField(
              controller: name,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z .]'))],
              decoration: const InputDecoration(labelText: 'Name', hintText: 'English letters only'),
            ),
            TextField(
              controller: className,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9 -]'))],
              decoration: const InputDecoration(
                  labelText: 'Group / Class', hintText: 'e.g. Class A'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (created != true || rollNo.text.trim().isEmpty || name.text.trim().isEmpty) return;
    try {
      await ApiClient.instance.createStudent(rollNo.text.trim(), name.text.trim(), className.text.trim());
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _openKiosk() async {
    List<dynamic> groups = [];
    try {
      groups = await ApiClient.instance.listGroups();
    } catch (_) {}
    if (!mounted) return;
    String? group;
    if (groups.isNotEmpty) {
      group = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Kiosk for which group?'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('All my students'),
            ),
            ...groups.map((g) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, g['name'] as String),
                  child: Text('${g['name']} (${g['students']} students)'),
                )),
          ],
        ),
      );
      if (group == null) return;
    }
    if (!mounted) return;
    final selected = group;
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) =>
              KioskScreen(group: selected == null || selected.isEmpty ? null : selected)),
    );
  }

  Future<void> _logout() async {
    await ApiClient.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Attendance'),
        actions: [
          IconButton(
            icon: const Icon(Icons.assessment_outlined),
            tooltip: 'Attendance report',
            onPressed: () =>
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportScreen())),
          ),
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Logout', onPressed: _logout),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search by name, roll no or group',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView.builder(
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) {
                            final s = _filtered[i];
                      final enrolled = (s['enrolled_images'] as int) > 0;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: enrolled ? Colors.green.shade100 : Colors.orange.shade100,
                          child: Icon(enrolled ? Icons.verified_user : Icons.person_outline,
                              color: enrolled ? Colors.green : Colors.orange),
                        ),
                        title: Text('${s['name']} (${s['roll_no']})'),
                        subtitle: Text(enrolled
                            ? '${s['class_name']} · ${s['enrolled_images']} face images enrolled'
                            : '${s['class_name']} · Not enrolled yet'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.camera_alt_outlined),
                              tooltip: 'Enroll face',
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => EnrollScreen(
                                        studentId: s['id'], studentName: s['name']),
                                  ),
                                );
                                _refresh();
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Delete',
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text('Delete ${s['name']}?'),
                                    actions: [
                                      TextButton(
                                          onPressed: () => Navigator.pop(ctx, false),
                                          child: const Text('Cancel')),
                                      FilledButton(
                                          onPressed: () => Navigator.pop(ctx, true),
                                          child: const Text('Delete')),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await ApiClient.instance.deleteStudent(s['id']);
                                  _refresh();
                                }
                              },
                            ),
                          ],
                        ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'kiosk',
            icon: const Icon(Icons.co_present),
            label: const Text('Kiosk Mode'),
            onPressed: _openKiosk,
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'add',
            icon: const Icon(Icons.person_add),
            label: const Text('Add Student'),
            onPressed: _addStudentDialog,
          ),
        ],
      ),
    );
  }
}
