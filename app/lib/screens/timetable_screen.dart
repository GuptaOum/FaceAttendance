import 'package:flutter/material.dart';

import '../api.dart';

/// Schedule a repeating weekly timetable in advance.
///
/// Each weekday carries its own blocks, because real timetables differ by day:
/// a Saturday half day may run one period in the afternoon where a Monday runs
/// three. A block is one scan window (e.g. 10:00-13:00); students scan once on
/// arrival and once on leaving, and the periods inside are worked out from
/// those two scans.
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
  _PeriodDraft copy() => _PeriodDraft(subject, start, end);
}

class _BlockDraft {
  String title;
  TimeOfDay start;
  TimeOfDay end;
  List<_PeriodDraft> periods;
  bool spotCheck;
  _BlockDraft(this.title, this.start, this.end, this.periods, {this.spotCheck = false});
  _BlockDraft copy() => _BlockDraft(
      title, start, end, periods.map((p) => p.copy()).toList(), spotCheck: spotCheck);
}

String _fmt(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

TimeOfDay _plus(TimeOfDay t, int minutes) {
  final total = (t.hour * 60 + t.minute + minutes).clamp(0, 23 * 60 + 59);
  return TimeOfDay(hour: total ~/ 60, minute: total % 60);
}

class _TimetableScreenState extends State<TimetableScreen> {
  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// Blocks per weekday. A weekday absent from this map has no classes.
  final Map<int, List<_BlockDraft>> _byDay = {};
  int _editing = 0;
  DateTime _startDate = DateTime.now();
  int _weeks = 1;
  String _group = '';
  bool _replace = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // A sensible Mon-Fri starting point; the teacher edits each day from here.
    for (final d in [0, 1, 2, 3, 4]) {
      _byDay[d] = _defaultDay();
    }
  }

  List<_BlockDraft> _defaultDay() => [
        _BlockDraft('Morning', const TimeOfDay(hour: 10, minute: 0),
            const TimeOfDay(hour: 13, minute: 0), [
          _PeriodDraft('Period 1', const TimeOfDay(hour: 10, minute: 0),
              const TimeOfDay(hour: 11, minute: 0)),
          _PeriodDraft('Period 2', const TimeOfDay(hour: 11, minute: 0),
              const TimeOfDay(hour: 12, minute: 0)),
          _PeriodDraft('Period 3', const TimeOfDay(hour: 12, minute: 0),
              const TimeOfDay(hour: 13, minute: 0)),
        ]),
        _BlockDraft('Afternoon', const TimeOfDay(hour: 14, minute: 0),
            const TimeOfDay(hour: 17, minute: 0), [
          _PeriodDraft('Period 4', const TimeOfDay(hour: 14, minute: 0),
              const TimeOfDay(hour: 15, minute: 0)),
          _PeriodDraft('Period 5', const TimeOfDay(hour: 15, minute: 0),
              const TimeOfDay(hour: 16, minute: 0)),
          _PeriodDraft('Period 6', const TimeOfDay(hour: 16, minute: 0),
              const TimeOfDay(hour: 17, minute: 0)),
        ]),
      ];

  List<_BlockDraft> get _blocks => _byDay[_editing] ?? [];

  String get _dateStr => '${_startDate.year.toString().padLeft(4, '0')}-'
      '${_startDate.month.toString().padLeft(2, '0')}-'
      '${_startDate.day.toString().padLeft(2, '0')}';

  int get _totalSessions =>
      _byDay.values.fold(0, (sum, blocks) => sum + blocks.length) * _weeks;

  /// Most weekdays repeat, so copying one day onto others saves rebuilding it.
  Future<void> _copyDayTo() async {
    final targets = <int>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Copy ${_dayNames[_editing]} to'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(7, (i) {
              if (i == _editing) return const SizedBox.shrink();
              return CheckboxListTile(
                dense: true,
                value: targets.contains(i),
                title: Text(_dayNames[i]),
                subtitle: Text(_byDay.containsKey(i)
                    ? '${_byDay[i]!.length} block(s) - will be replaced'
                    : 'no classes yet'),
                onChanged: (v) =>
                    setLocal(() => v == true ? targets.add(i) : targets.remove(i)),
              );
            }),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Copy')),
          ],
        ),
      ),
    );
    if (ok != true || targets.isEmpty) return;
    setState(() {
      for (final t in targets) {
        _byDay[t] = _blocks.map((b) => b.copy()).toList();
      }
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Copied to ${targets.map((t) => _dayNames[t]).join(', ')}')));
    }
  }

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
                  decoration: const InputDecoration(labelText: 'Subject')),
              const SizedBox(height: 12),
              Row(children: [
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
              ]),
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
    if (saved != true) return;
    setState(() {
      if (block.periods.contains(p)) {
        p.subject = subject.text.trim().isEmpty ? p.subject : subject.text.trim();
        p.start = start;
        p.end = end;
      }
    });
  }

  Future<void> _editBlock(_BlockDraft b) async {
    final title = TextEditingController(text: b.title);
    var start = b.start;
    var end = b.end;
    var spot = b.spotCheck;
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
              Row(children: [
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
              ]),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Roll call', style: TextStyle(fontSize: 14)),
                subtitle: const Text('Let me tick absentees mid-block',
                    style: TextStyle(fontSize: 11)),
                value: spot,
                onChanged: (v) => setLocal(() => spot = v),
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
    if (saved != true) return;
    setState(() {
      b.title = title.text.trim().isEmpty ? b.title : title.text.trim();
      b.start = start;
      b.end = end;
      b.spotCheck = spot;
    });
  }

  Future<void> _save() async {
    if (_byDay.values.every((b) => b.isEmpty)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Add a block to at least one day')));
      return;
    }
    setState(() => _busy = true);
    try {
      final days = _byDay.entries
          .where((e) => e.value.isNotEmpty)
          .map((e) => {
                'weekday': e.key,
                'blocks': e.value
                    .map((b) => {
                          'title': b.title,
                          'start_time': _fmt(b.start),
                          'end_time': _fmt(b.end),
                          'spot_check_enabled': b.spotCheck,
                          'periods': b.periods
                              .map((p) => {
                                    'subject': p.subject,
                                    'start_time': _fmt(p.start),
                                    'end_time': _fmt(p.end),
                                  })
                              .toList(),
                        })
                    .toList(),
              })
          .toList();

      final result = await ApiClient.instance.createTimetable({
        'group_name': _group,
        'start_date': _dateStr,
        'weeks': _weeks,
        'replace_existing': _replace,
        'days': days,
      });
      if (!mounted) return;
      final created = result['created'] ?? 0;
      final skipped = result['skipped'] ?? 0;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.event_available, color: Colors.green),
          title: const Text('Timetable scheduled'),
          content: Text('$created session${created == 1 ? '' : 's'} created'
              '${skipped > 0 ? '\n$skipped skipped (already scheduled)' : ''}'),
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
    final blocks = _blocks;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly Timetable'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all),
            tooltip: 'Copy this day to other days',
            onPressed: blocks.isEmpty ? null : _copyDayTo,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
        children: [
          Row(children: [
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
                  .map((w) =>
                      DropdownMenuItem(value: w, child: Text('$w week${w == 1 ? '' : 's'}')))
                  .toList(),
              onChanged: (v) => setState(() => _weeks = v ?? 1),
            ),
          ]),
          const SizedBox(height: 10),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Group / class (optional)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => _group = v.trim(),
          ),
          const SizedBox(height: 12),
          // Each weekday is edited separately: Saturday can be a half day.
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 7,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final count = _byDay[i]?.length ?? 0;
                return ChoiceChip(
                  selected: _editing == i,
                  onSelected: (_) => setState(() => _editing = i),
                  avatar: count == 0
                      ? const Icon(Icons.remove, size: 14)
                      : CircleAvatar(
                          radius: 9,
                          child: Text('$count', style: const TextStyle(fontSize: 10))),
                  label: Text(_dayNames[i]),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(
            blocks.isEmpty
                ? 'No classes on ${_dayNames[_editing]}'
                : '${_dayNames[_editing]}: ${blocks.length} block(s), '
                    '${blocks.fold(0, (s, b) => s + b.periods.length)} periods',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const Divider(height: 20),
          ...blocks.map((b) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Column(children: [
                  ListTile(
                    title: Text(b.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${_fmt(b.start)} - ${_fmt(b.end)}  ·  '
                        '${b.periods.length} period${b.periods.length == 1 ? '' : 's'}'
                        '${b.spotCheck ? '  ·  roll call on' : ''}'),
                    trailing: IconButton(
                        icon: const Icon(Icons.edit_outlined), onPressed: () => _editBlock(b)),
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
                    onPressed: () => setState(() {
                      final from = b.periods.isEmpty ? b.start : b.periods.last.end;
                      b.periods.add(_PeriodDraft(
                          'Period ${b.periods.length + 1}', from, _plus(from, 60)));
                    }),
                  ),
                ]),
              )),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add block'),
                onPressed: () => setState(() {
                  _byDay.putIfAbsent(_editing, () => []);
                  _byDay[_editing]!.add(_BlockDraft(
                      'Block ${_byDay[_editing]!.length + 1}',
                      const TimeOfDay(hour: 9, minute: 0),
                      const TimeOfDay(hour: 12, minute: 0), []));
                }),
              ),
            ),
            if (blocks.isNotEmpty) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_busy, size: 18),
                label: const Text('No classes'),
                onPressed: () => setState(() => _byDay.remove(_editing)),
              ),
            ],
          ]),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            icon: _busy
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.event_available),
            label: Text(_busy ? 'Scheduling...' : 'Schedule $_totalSessions sessions'),
            onPressed: _busy ? null : _save,
          ),
        ),
      ),
    );
  }
}
