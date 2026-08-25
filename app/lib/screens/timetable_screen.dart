import 'package:flutter/material.dart';

import '../api.dart';

/// Schedule a repeating weekly timetable in advance.
///
/// A block is one scan window (e.g. 10:00-13:00). Students scan once on
/// arrival and once on leaving; the periods inside the block are worked out
/// from those two scans, so nobody queues between back-to-back classes.
class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _PeriodDraft {
  String subject;
  TimeOfDay start;
  TimeOfDay end;
  _PeriodDraft(this.subject, this.start, this.end);
}

class _BlockDraft {
  String title;
  TimeOfDay start;
  TimeOfDay end;
  List<_PeriodDraft> periods;
  _BlockDraft(this.title, this.start, this.end, this.periods);
}

String _fmt(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class _TimetableScreenState extends State<TimetableScreen> {
  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  final Set<int> _weekdays = {0, 1, 2, 3, 4};
  DateTime _startDate = DateTime.now();
  int _weeks = 1;
  String _group = '';
  bool _replace = false;
  bool _busy = false;

  final List<_BlockDraft> _blocks = [
    _BlockDraft('Morning', const TimeOfDay(hour: 10, minute: 0), const TimeOfDay(hour: 13, minute: 0), [
      _PeriodDraft('Period 1', const TimeOfDay(hour: 10, minute: 0), const TimeOfDay(hour: 11, minute: 0)),
      _PeriodDraft('Period 2', const TimeOfDay(hour: 11, minute: 0), const TimeOfDay(hour: 12, minute: 0)),
      _PeriodDraft('Period 3', const TimeOfDay(hour: 12, minute: 0), const TimeOfDay(hour: 13, minute: 0)),
    ]),
    _BlockDraft('Afternoon', const TimeOfDay(hour: 14, minute: 0), const TimeOfDay(hour: 17, minute: 0), [
      _PeriodDraft('Period 4', const TimeOfDay(hour: 14, minute: 0), const TimeOfDay(hour: 15, minute: 0)),
      _PeriodDraft('Period 5', const TimeOfDay(hour: 15, minute: 0), const TimeOfDay(hour: 16, minute: 0)),
      _PeriodDraft('Period 6', const TimeOfDay(hour: 16, minute: 0), const TimeOfDay(hour: 17, minute: 0)),
    ]),
  ];

  String get _dateStr => '${_startDate.year.toString().padLeft(4, '0')}-'
      '${_startDate.month.toString().padLeft(2, '0')}-'
      '${_startDate.day.toString().padLeft(2, '0')}';

  Future<TimeOfDay?> _pickTime(TimeOfDay initial) =>
      showTimePicker(context: context, initialTime: initial);

  Future<void> _editPeriod(_BlockDraft block, _PeriodDraft p) async {
    final subject = TextEditingController(text: p.subject);
    var start = p.start;
    var end = p.end;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Period'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: subject,
                decoration: const InputDecoration(labelText: 'Subject'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final t = await showTimePicker(context: ctx, initialTime: start);
                        if (t != null) setLocal(() => start = t);
                      },
                      child: Text('From ${_fmt(start)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final t = await showTimePicker(context: ctx, initialTime: end);
                        if (t != null) setLocal(() => end = t);
                      },
                      child: Text('To ${_fmt(end)}'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                block.periods.remove(p);
                Navigator.pop(ctx, true);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved == true && block.periods.contains(p)) {
      setState(() {
        p.subject = subject.text.trim().isEmpty ? p.subject : subject.text.trim();
        p.start = start;
        p.end = end;
      });
    } else if (saved == true) {
      setState(() {});
    }
  }

  Future<void> _editBlock(_BlockDraft b) async {
    final title = TextEditingController(text: b.title);
    var start = b.start;
    var end = b.end;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Block'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(
                  labelText: 'Block name',
                  helperText: 'Students scan once at the start and once at the end',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final t = await showTimePicker(context: ctx, initialTime: start);
                        if (t != null) setLocal(() => start = t);
                      },
                      child: Text('From ${_fmt(start)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final t = await showTimePicker(context: ctx, initialTime: end);
                        if (t != null) setLocal(() => end = t);
                      },
                      child: Text('To ${_fmt(end)}'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() => _blocks.remove(b));
                Navigator.pop(ctx, false);
              },
              child: const Text('Delete block', style: TextStyle(color: Colors.red)),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved == true) {
      setState(() {
        b.title = title.text.trim().isEmpty ? b.title : title.text.trim();
        b.start = start;
        b.end = end;
      });
    }
  }

  Future<void> _save() async {
    if (_blocks.isEmpty || _weekdays.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Add a block and pick at least one day')));
      return;
    }
    setState(() => _busy = true);
    try {
      final payload = {
        'group_name': _group,
        'start_date': _dateStr,
        'weeks': _weeks,
        'weekdays': _weekdays.toList()..sort(),
        'replace_existing': _replace,
        'blocks': _blocks
            .map((b) => {
                  'title': b.title,
                  'start_time': _fmt(b.start),
                  'end_time': _fmt(b.end),
                  'periods': b.periods
                      .map((p) => {
                            'subject': p.subject,
                            'start_time': _fmt(p.start),
                            'end_time': _fmt(p.end),
                          })
                      .toList(),
                })
            .toList(),
      };
      final result = await ApiClient.instance.createTimetable(payload);
      if (!mounted) return;
      final created = result['created'] ?? 0;
      final skipped = result['skipped'] ?? 0;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.event_available, color: Colors.green),
          title: const Text('Timetable scheduled'),
          content: Text(
            '$created session${created == 1 ? '' : 's'} created'
            '${skipped > 0 ? '\n$skipped skipped (already scheduled)' : ''}',
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
    return Scaffold(
      appBar: AppBar(title: const Text('Weekly Timetable')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Students scan once when they arrive at a block and once when they leave. '
              'Periods inside the block are worked out from those two scans, so there is '
              'no scanning between back-to-back classes. Attendance is only counted once '
              'the leaving scan is done.',
              style: TextStyle(fontSize: 12.5),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text('From $_dateStr'),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _startDate,
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setState(() => _startDate = picked);
                  },
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _weeks,
                items: [1, 2, 4, 8, 12]
                    .map((w) => DropdownMenuItem(value: w, child: Text('$w week${w == 1 ? '' : 's'}')))
                    .toList(),
                onChanged: (v) => setState(() => _weeks = v ?? 1),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            children: List.generate(7, (i) {
              final on = _weekdays.contains(i);
              return FilterChip(
                label: Text(_dayNames[i]),
                selected: on,
                onSelected: (v) => setState(() => v ? _weekdays.add(i) : _weekdays.remove(i)),
              );
            }),
          ),
          const SizedBox(height: 10),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Group / class (optional)',
              hintText: 'Leave empty for all your students',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => _group = v.trim(),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Replace existing sessions', style: TextStyle(fontSize: 14)),
            subtitle: const Text('Off: days already scheduled are skipped',
                style: TextStyle(fontSize: 11)),
            value: _replace,
            onChanged: (v) => setState(() => _replace = v),
          ),
          const Divider(height: 28),
          ..._blocks.map((b) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Column(
                  children: [
                    ListTile(
                      title: Text(b.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${_fmt(b.start)} - ${_fmt(b.end)}  ·  '
                          '${b.periods.length} period${b.periods.length == 1 ? '' : 's'}  ·  2 scans'),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _editBlock(b),
                      ),
                    ),
                    ...b.periods.map((p) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.schedule, size: 18),
                          title: Text(p.subject),
                          subtitle: Text('${_fmt(p.start)} - ${_fmt(p.end)}'),
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: () => _editPeriod(b, p),
                        )),
                    TextButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add period'),
                      onPressed: () => setState(() => b.periods.add(_PeriodDraft(
                            'Period ${b.periods.length + 1}',
                            b.periods.isEmpty ? b.start : b.periods.last.end,
                            b.end,
                          ))),
                    ),
                  ],
                ),
              )),
          OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add block'),
            onPressed: () => setState(() => _blocks.add(_BlockDraft(
                  'Block ${_blocks.length + 1}',
                  const TimeOfDay(hour: 9, minute: 0),
                  const TimeOfDay(hour: 12, minute: 0),
                  [],
                ))),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.event_available),
            label: Text(_busy
                ? 'Scheduling...'
                : 'Schedule ${_blocks.length * _weekdays.length * _weeks} sessions'),
            onPressed: _busy ? null : _save,
          ),
        ),
      ),
    );
  }
}
