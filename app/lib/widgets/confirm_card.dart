import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format.dart';
import '../models/event.dart';
import '../models/family.dart';
import '../providers.dart';

const _eventTypes = [
  'feeding', 'sleep', 'diaper', 'bath', 'medicine', 'temperature',
  'pumping', 'growth', 'milestone', 'memo', 'other',
];

/// Editable review of one structured event. The user tweaks anything the model
/// got wrong, then saves it to the timeline.
class ConfirmCard extends ConsumerStatefulWidget {
  const ConfirmCard({
    super.key,
    required this.event,
    required this.babies,
    required this.babyId,
    required this.rawText,
    required this.onSaved,
    required this.onDiscard,
  });

  final StructuredEvent event;
  final List<Baby> babies;
  final String babyId;
  final String rawText;
  final void Function(Event saved) onSaved;
  final VoidCallback onDiscard;

  @override
  ConsumerState<ConfirmCard> createState() => _ConfirmCardState();
}

class _ConfirmCardState extends ConsumerState<ConfirmCard> {
  late String _babyId = widget.babyId;
  late String _type = widget.event.type;
  late DateTime _time = (widget.event.time ?? DateTime.now()).toLocal();
  late final _subtype = TextEditingController(text: widget.event.subtype ?? '');
  late final _note = TextEditingController(text: widget.event.note ?? '');
  late final Map<String, TextEditingController> _fields = {
    for (final e in widget.event.fields.entries)
      e.key: TextEditingController(text: '${e.value}'),
  };
  bool _saving = false;

  @override
  void dispose() {
    _subtype.dispose();
    _note.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<DropdownMenuItem<String>> get _typeItems {
    final types = _eventTypes.contains(_type)
        ? _eventTypes
        : [_type, ..._eventTypes];
    return [
      for (final t in types) DropdownMenuItem(value: t, child: Text(t)),
    ];
  }

  Future<void> _pickTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _time,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final clock = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_time),
    );
    if (!mounted) return;
    setState(() {
      _time = DateTime(date.year, date.month, date.day,
          clock?.hour ?? _time.hour, clock?.minute ?? _time.minute);
    });
  }

  Map<String, dynamic> _collectFields() {
    final out = <String, dynamic>{};
    for (final entry in _fields.entries) {
      final raw = entry.value.text.trim();
      if (raw.isEmpty) continue;
      final n = num.tryParse(raw);
      out[entry.key] = n == null ? raw : (n % 1 == 0 ? n.toInt() : n);
    }
    return out;
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final api = ref.read(apiClientProvider);
    setState(() => _saving = true);
    try {
      final saved = await api.createEvent(
        babyId: _babyId,
        type: _type,
        subtype: _subtype.text.trim().isEmpty ? null : _subtype.text.trim(),
        fields: _collectFields(),
        time: _time.toUtc(),
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        rawText: widget.rawText,
      );
      widget.onSaved(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Confirm', style: theme.textTheme.titleMedium),
                const Spacer(),
                _ConfidenceChip(widget.event.confidence),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.babies.length > 1) ...[
              DropdownButtonFormField<String>(
                initialValue: _babyId,
                decoration: const InputDecoration(labelText: 'Baby'),
                items: [
                  for (final b in widget.babies)
                    DropdownMenuItem(value: b.id, child: Text(b.name)),
                ],
                onChanged: (v) => setState(() => _babyId = v ?? _babyId),
              ),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: _typeItems,
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _subtype,
              decoration: const InputDecoration(labelText: 'Subtype (optional)'),
            ),
            for (final entry in _fields.entries) ...[
              const SizedBox(height: 12),
              TextField(
                controller: entry.value,
                decoration: InputDecoration(labelText: prettifyKey(entry.key)),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickTime,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Time',
                  suffixIcon: Icon(Icons.edit_calendar_outlined),
                ),
                child: Text(formatTime(_time)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: _saving ? null : widget.onDiscard,
                  child: const Text('Discard'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip(this.confidence);

  final String confidence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (Color bg, Color fg) = switch (confidence) {
      'high' => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      'low' => (scheme.errorContainer, scheme.onErrorContainer),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(confidence, style: theme.textTheme.labelSmall?.copyWith(color: fg)),
    );
  }
}
