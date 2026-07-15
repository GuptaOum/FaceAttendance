import 'package:flutter/material.dart';

import '../api.dart';

/// Teacher-facing review-and-send screen for parent absence alerts.
///
/// Nothing is ever sent without the teacher seeing the list first: the server
/// requires an explicit list of student ids, and this screen is where that
/// list is built. "Select all" makes the common case one tap, but the teacher
/// stays in the loop because kiosk recognition can miss a present student.
class AbsenceAlertsScreen extends StatefulWidget {
  const AbsenceAlertsScreen({super.key});

  @override
  State<AbsenceAlertsScreen> createState() => _AbsenceAlertsScreenState();
}

class _AbsenceAlertsScreenState extends State<AbsenceAlertsScreen> {
  DateTime _date = DateTime.now();
  int? _sessionId;
  List<dynamic> _daySessions = [];

  Map<String, dynamic>? _preview;
  List<dynamic>? _log;
  bool _showLog = false;
  bool _sending = false;
  String? _error;
  final Set<int> _selected = {};

  String get _dateStr => '${_date.year.toString().padLeft(4, '0')}-'
      '${_date.month.toString().padLeft(2, '0')}-'
      '${_date.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _preview = null;
      _log = null;
      _error = null;
      _selected.clear();
    });
    try {
      final results = await Future.wait([
        ApiClient.instance.absentPreview(date: _dateStr, sessionId: _sessionId),
        ApiClient.instance.listSessions(),
        ApiClient.instance.notificationLog(date: _dateStr),
      ]);
      if (!mounted) return;
      final preview = results[0] as Map<String, dynamic>;
      final sessions = (results[1] as List<dynamic>)
          .where((s) => s['date'] == _dateStr)
          .toList();
      setState(() {
        _preview = preview;
        _daySessions = sessions;
        _log = results[2] as List<dynamic>;
        // Pre-select every notifiable student: send-all is the common case,
        // unticking the doubtful ones is the exception.
        for (final s in preview['absent'] as List<dynamic>) {
          if (s['notifiable'] == true) _selected.add(s['id'] as int);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      _date = picked;
      _sessionId = null; // sessions belong to a specific date
    });
    _load();
  }

  Future<void> _send() async {
    final preview = _preview;
    if (preview == null || _selected.isEmpty) return;
    final live = preview['will_actually_send'] == true;
    final n = _selected.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(live ? Icons.send : Icons.science_outlined,
            color: live ? Colors.green : Colors.orange),
        title: Text(live
            ? 'Send absence alert to $n parent${n == 1 ? '' : 's'}?'
            : 'Test-send to $n parent${n == 1 ? '' : 's'}?'),
        content: Text(live
            ? 'Each parent gets a WhatsApp message saying their child was absent '
                'on $_dateStr. A parent is only ever messaged once per day. '
                'This cannot be recalled.'
            : 'Test mode: the messages are rendered and logged so you can check '
                'them in History, but nothing is delivered to any parent.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(live ? 'Send' : 'Test send'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _sending = true);
    try {
      final result = await ApiClient.instance.sendAbsenceAlerts(
        _selected.toList(),
        date: _dateStr,
        sessionId: _sessionId,
      );
      if (!mounted) return;
      final counts = (result['counts'] as Map).map((k, v) => MapEntry(k.toString(), v));
      final parts = <String>[
        if (counts['sent'] != null) '${counts['sent']} sent',
        if (counts['dry_run'] != null) '${counts['dry_run']} test-logged',
        if (counts['failed'] != null) '${counts['failed']} failed',
        if (counts['skipped'] != null) '${counts['skipped']} skipped',
      ];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(parts.isEmpty ? 'Nothing to send' : parts.join(' · '))),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showMessagePreview(Map<String, dynamic> student) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Message to ${student['name']}\'s parent'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('To: ${student['parent_phone']}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(student['preview'] ?? ''),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _modeBanner() {
    final preview = _preview;
    if (preview == null) return const SizedBox.shrink();
    final live = preview['will_actually_send'] == true;
    return Container(
      width: double.infinity,
      color: live ? Colors.green.shade50 : Colors.orange.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(live ? Icons.check_circle_outline : Icons.science_outlined,
              size: 18, color: live ? Colors.green : Colors.orange.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              live
                  ? 'Live: alerts are delivered on WhatsApp (${preview['provider']})'
                  : 'Test mode: messages are logged in History, nothing is delivered',
              style: TextStyle(
                  fontSize: 12.5, color: live ? Colors.green.shade900 : Colors.orange.shade900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(
        children: [
          ActionChip(
            avatar: const Icon(Icons.calendar_today, size: 16),
            label: Text(_dateStr),
            onPressed: _pickDate,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<int?>(
              initialValue: _sessionId,
              isDense: true,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(), isDense: true, labelText: 'Scope'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Whole day')),
                ..._daySessions.map((s) => DropdownMenuItem<int?>(
                      value: s['id'] as int,
                      child: Text(s['title'], overflow: TextOverflow.ellipsis),
                    )),
              ],
              onChanged: (v) {
                setState(() => _sessionId = v);
                _load();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _absentList() {
    final absent = (_preview!['absent'] as List<dynamic>).cast<Map<String, dynamic>>();
    if (absent.isEmpty) {
      return const Expanded(
        child: Center(child: Text('Nobody is absent for this selection 🎉')),
      );
    }
    final notifiable = absent.where((s) => s['notifiable'] == true).toList();
    final allSelected = notifiable.isNotEmpty && _selected.length == notifiable.length;
    return Expanded(
      child: Column(
        children: [
          CheckboxListTile(
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: allSelected,
            tristate: _selected.isNotEmpty && !allSelected,
            onChanged: notifiable.isEmpty
                ? null
                : (_) => setState(() {
                      if (allSelected) {
                        _selected.clear();
                      } else {
                        _selected
                          ..clear()
                          ..addAll(notifiable.map((s) => s['id'] as int));
                      }
                    }),
            title: Text(
              '${absent.length} absent · ${notifiable.length} can be notified',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                itemCount: absent.length,
                itemBuilder: (_, i) {
                  final s = absent[i];
                  final ok = s['notifiable'] == true;
                  return CheckboxListTile(
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _selected.contains(s['id']),
                    onChanged: ok
                        ? (v) => setState(() {
                              if (v == true) {
                                _selected.add(s['id'] as int);
                              } else {
                                _selected.remove(s['id']);
                              }
                            })
                        : null,
                    title: Text('${s['name']} (${s['roll_no']})'),
                    subtitle: Text(
                      ok ? (s['parent_phone'] as String) : (s['blocked_reason'] as String),
                      style: TextStyle(
                          fontSize: 12,
                          color: ok ? Colors.grey.shade600 : Colors.orange.shade800),
                    ),
                    secondary: ok
                        ? IconButton(
                            icon: const Icon(Icons.visibility_outlined, size: 20),
                            tooltip: 'Preview message',
                            onPressed: () => _showMessagePreview(s),
                          )
                        : const Icon(Icons.block, size: 20, color: Colors.grey),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _logView() {
    final log = _log ?? [];
    if (log.isEmpty) {
      return const Expanded(child: Center(child: Text('No alerts for this date yet')));
    }
    return Expanded(
      child: ListView.builder(
        itemCount: log.length,
        itemBuilder: (_, i) {
          final n = log[i];
          final (color, icon, label) = switch (n['status']) {
            'sent' => (Colors.green, Icons.check_circle, 'Delivered'),
            'dry_run' => (Colors.orange, Icons.science_outlined, 'Test only'),
            _ => (Colors.red, Icons.error_outline, 'Failed'),
          };
          return ListTile(
            leading: Icon(icon, color: color),
            title: Text('${n['name']} (${n['roll_no']})'),
            subtitle: Text(
              '$label · ${n['to_phone']} · ${n['created_at']}'
              '${n['error'] != null ? '\n${n['error']}' : ''}',
              style: const TextStyle(fontSize: 12),
            ),
            isThreeLine: n['error'] != null,
            onTap: () => showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text('${n['name']} — $label'),
                content: Text(n['body'] ?? ''),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loading = _preview == null && _error == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(_showLog ? 'Alert History' : 'Absence Alerts'),
        actions: [
          IconButton(
            icon: Icon(_showLog ? Icons.checklist : Icons.history),
            tooltip: _showLog ? 'Back to review' : 'History',
            onPressed: () => setState(() => _showLog = !_showLog),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            )
          : loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    _modeBanner(),
                    _filters(),
                    if (_showLog) _logView() else _absentList(),
                  ],
                ),
      bottomNavigationBar: _showLog || _preview == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  icon: _sending
                      ? const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(_preview!['will_actually_send'] == true
                          ? Icons.send
                          : Icons.science_outlined),
                  label: Text(_selected.isEmpty
                      ? 'Select students to notify'
                      : _preview!['will_actually_send'] == true
                          ? 'Send to ${_selected.length} parent${_selected.length == 1 ? '' : 's'}'
                          : 'Test send to ${_selected.length}'),
                  onPressed: _selected.isEmpty || _sending ? null : _send,
                ),
              ),
            ),
    );
  }
}
