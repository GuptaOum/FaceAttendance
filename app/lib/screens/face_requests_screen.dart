import 'package:flutter/material.dart';

import '../api.dart';
import 'enroll_screen.dart';

class FaceRequestsScreen extends StatefulWidget {
  const FaceRequestsScreen({super.key});

  @override
  State<FaceRequestsScreen> createState() => _FaceRequestsScreenState();
}

class _FaceRequestsScreenState extends State<FaceRequestsScreen> {
  List<dynamic>? _requests;
  String? _error;
  String _filter = 'open';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _requests = null;
      _error = null;
    });
    try {
      final rows = await ApiClient.instance.listFaceRequests(statusFilter: _filter);
      if (mounted) setState(() => _requests = rows);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _resolve(Map<String, dynamic> req, String status) async {
    final notes = TextEditingController();
    final verb = status == 'resolved' ? 'Resolve' : 'Reject';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$verb request from ${req['name']}?'),
        content: TextField(
          controller: notes,
          maxLines: 2,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Note for the student (optional)',
            hintText: 'e.g. Re-enrolled your face today',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(verb)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiClient.instance.resolveFaceRequest(req['id'], status, notes.text.trim());
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Color _statusColour(String status) => switch (status) {
        'open' => Colors.orange,
        'resolved' => Colors.green,
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Requests'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filter',
            initialValue: _filter,
            onSelected: (v) {
              setState(() => _filter = v);
              _load();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'open', child: Text('Open')),
              PopupMenuItem(value: 'resolved', child: Text('Resolved')),
              PopupMenuItem(value: 'rejected', child: Text('Rejected')),
              PopupMenuItem(value: 'all', child: Text('All')),
            ],
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
          : _requests == null
              ? const Center(child: CircularProgressIndicator())
              : _requests!.isEmpty
                  ? Center(
                      child: Text(_filter == 'open'
                          ? 'No open requests'
                          : 'No $_filter requests'),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        itemCount: _requests!.length,
                        itemBuilder: (_, i) {
                          final r = _requests![i] as Map<String, dynamic>;
                          final isOpen = r['status'] == 'open';
                          final isReenroll = r['request_type'] == 'reenroll';
                          return Card(
                            margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        isReenroll ? Icons.face_retouching_natural : Icons.report_outlined,
                                        color: _statusColour(r['status']),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '${r['name']} (${r['roll_no']})',
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      Chip(
                                        label: Text(r['status'],
                                            style: const TextStyle(fontSize: 11)),
                                        backgroundColor:
                                            _statusColour(r['status']).withValues(alpha: 0.15),
                                        side: BorderSide.none,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    isReenroll ? 'Wants face re-enrolled' : 'Reported a problem',
                                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                                  ),
                                  if ((r['message'] as String).isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text('"${r['message']}"',
                                        style: const TextStyle(fontStyle: FontStyle.italic)),
                                  ],
                                  const SizedBox(height: 4),
                                  Text('Raised ${r['created_at']}',
                                      style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                                  if ((r['teacher_notes'] as String).isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text('Your note: ${r['teacher_notes']}',
                                          style: const TextStyle(fontSize: 12)),
                                    ),
                                  if (isOpen) ...[
                                    const Divider(height: 20),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton.icon(
                                          icon: const Icon(Icons.camera_alt_outlined, size: 18),
                                          label: const Text('Re-enroll'),
                                          onPressed: () async {
                                            await Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => EnrollScreen(
                                                  studentId: r['student_id'],
                                                  studentName: r['name'],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                        TextButton(
                                          onPressed: () => _resolve(r, 'rejected'),
                                          child: const Text('Reject'),
                                        ),
                                        FilledButton(
                                          onPressed: () => _resolve(r, 'resolved'),
                                          child: const Text('Resolve'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
