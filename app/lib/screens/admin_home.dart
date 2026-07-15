import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import 'enroll_screen.dart';
import 'face_requests_screen.dart';
import 'kiosk_screen.dart';
import 'login_screen.dart';
import 'report_screen.dart';
import 'sessions_screen.dart';

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
    final parentPhone = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Student'),
        content: SingleChildScrollView(
          child: Column(
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
                decoration:
                    const InputDecoration(labelText: 'Name', hintText: 'English letters only'),
              ),
              TextField(
                controller: className,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9 -]'))],
                decoration: const InputDecoration(
                    labelText: 'Group / Class', hintText: 'e.g. Class A'),
              ),
              TextField(
                controller: parentPhone,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))],
                decoration: const InputDecoration(
                  labelText: 'Parent phone (optional)',
                  hintText: '+919876543210',
                  helperText: 'Country code required',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (created != true || rollNo.text.trim().isEmpty || name.text.trim().isEmpty) return;
    try {
      await ApiClient.instance.createStudent(
        rollNo.text.trim(),
        name.text.trim(),
        className.text.trim(),
        parentPhone: parentPhone.text.trim(),
      );
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _editPhoneDialog(Map<String, dynamic> s) async {
    final phone = TextEditingController(text: s['parent_phone'] ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Parent phone for ${s['name']}'),
        content: TextField(
          controller: phone,
          keyboardType: TextInputType.phone,
          autofocus: true,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))],
          decoration: const InputDecoration(
            labelText: 'Parent phone',
            hintText: '+919876543210',
            helperText: 'Country code required. Leave empty to remove.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved != true) return;
    try {
      await ApiClient.instance.updateParentPhone(s['id'], phone.text.trim());
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
            icon: const Icon(Icons.face_retouching_natural),
            tooltip: 'Face requests',
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const FaceRequestsScreen()));
              _refresh();
            },
          ),
          IconButton(
            icon: const Icon(Icons.event_note),
            tooltip: 'Sessions',
            onPressed: () =>
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SessionsScreen())),
          ),
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
                      final phone = (s['parent_phone'] ?? '') as String;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: enrolled ? Colors.green.shade100 : Colors.orange.shade100,
                          child: Icon(enrolled ? Icons.verified_user : Icons.person_outline,
                              color: enrolled ? Colors.green : Colors.orange),
                        ),
                        title: Text('${s['name']} (${s['roll_no']})'),
                        subtitle: Text([
                          s['class_name'],
                          enrolled ? '${s['enrolled_images']} face images' : 'Not enrolled yet',
                          phone.isEmpty ? 'No parent phone' : phone,
                        ].where((p) => (p as String).isNotEmpty).join(' · ')),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                phone.isEmpty ? Icons.phone_disabled_outlined : Icons.phone_outlined,
                                color: phone.isEmpty ? Colors.grey : Colors.green,
                              ),
                              tooltip: phone.isEmpty ? 'Add parent phone' : 'Edit parent phone',
                              onPressed: () => _editPhoneDialog(s as Map<String, dynamic>),
                            ),
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
