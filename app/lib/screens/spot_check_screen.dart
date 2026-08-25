import 'package:flutter/material.dart';

import '../api.dart';

/// Optional mid-block roll call.
///
/// The teacher glances at the room and ticks anyone they cannot see. No student
/// goes near the kiosk, so it costs seconds instead of interrupting the lesson.
/// Anyone who had not arrived yet, or had already scanned out, is exempted by
/// the server even if ticked by mistake.
class SpotCheckScreen extends StatefulWidget {
  final int sessionId;
  final String sessionTitle;

  const SpotCheckScreen({super.key, required this.sessionId, required this.sessionTitle});

  @override
  State<SpotCheckScreen> createState() => _SpotCheckScreenState();
}

class _SpotCheckScreenState extends State<SpotCheckScreen> {
  List<dynamic>? _present;
  final Set<int> _missing = {};
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _present = null;
      _error = null;
      _missing.clear();
    });
    try {
      final data = await ApiClient.instance.whoIsPresent(widget.sessionId);
      if (mounted) setState(() => _present = data['present'] as List<dynamic>);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _submit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.how_to_reg, color: Colors.orange),
        title: Text('Mark ${_missing.length} student${_missing.length == 1 ? '' : 's'} missing?'),
        content: const Text(
          'They will forfeit the rest of this block. Students who had not arrived '
          'yet, or had already scanned out, are left untouched.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final result =
          await ApiClient.instance.runSpotCheck(widget.sessionId, _missing.toList());
      if (!mounted) return;
      final exempt = (result['exempt'] as List<dynamic>? ?? []);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green),
          title: Text('Roll call recorded at ${result['checked_at']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${result['marked_absent']} marked missing.'),
              if (exempt.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('Left untouched:', style: TextStyle(fontWeight: FontWeight.bold)),
                ...exempt.map((e) => Text('  • ${e['reason']}',
                    style: const TextStyle(fontSize: 12))),
              ],
            ],
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final present = _present;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Roll Call'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            )
          : present == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Container(
                      width: double.infinity,
                      color: Colors.blue.shade50,
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        '${widget.sessionTitle}: tick anyone you cannot see in the room. '
                        'Leave everyone unticked if all are present.',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    Expanded(
                      child: present.isEmpty
                          ? const Center(child: Text('Nobody has scanned in for this block yet'))
                          : ListView.builder(
                              itemCount: present.length,
                              itemBuilder: (_, i) {
                                final s = present[i];
                                final gone = s['exit_at'] != null;
                                return CheckboxListTile(
                                  value: _missing.contains(s['id']),
                                  onChanged: gone
                                      ? null
                                      : (v) => setState(() {
                                            if (v == true) {
                                              _missing.add(s['id'] as int);
                                            } else {
                                              _missing.remove(s['id']);
                                            }
                                          }),
                                  title: Text('${s['name']} (${s['roll_no']})'),
                                  subtitle: Text(
                                    gone
                                        ? 'Already scanned out at ${s['exit_at']}'
                                        : 'In at ${s['marked_at']}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  secondary: Icon(
                                    gone ? Icons.logout : Icons.person,
                                    color: gone ? Colors.grey : Colors.green,
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
      bottomNavigationBar: present == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  icon: _busy
                      ? const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.how_to_reg),
                  label: Text(_missing.isEmpty
                      ? 'Everyone is present'
                      : 'Mark ${_missing.length} missing'),
                  onPressed: _busy || _missing.isEmpty ? null : _submit,
                ),
              ),
            ),
    );
  }
}
