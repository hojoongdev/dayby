import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/event.dart';
import '../models/family.dart';
import '../providers.dart';
import '../widgets/confirm_card.dart';

class LogScreen extends ConsumerStatefulWidget {
  const LogScreen({super.key});

  @override
  ConsumerState<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends ConsumerState<LogScreen> {
  final _input = TextEditingController();
  StructuredResult? _result;
  int _resultSeq = 0;
  bool _loading = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _input.text.trim();
    if (text.isEmpty || _loading) return;
    final messenger = ScaffoldMessenger.of(context);
    final api = ref.read(apiClientProvider);
    setState(() {
      _loading = true;
      _result = null;
    });
    try {
      final result = await api.ingestText(text);
      if (!mounted) return;
      setState(() {
        _result = result;
        _resultSeq++;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      messenger.showSnackBar(SnackBar(content: Text('Could not process: $e')));
    }
  }

  void _onSaved(Event saved) {
    final messenger = ScaffoldMessenger.of(context);
    _input.clear();
    setState(() => _result = null);
    ref.invalidate(eventsProvider(saved.babyId));
    messenger.showSnackBar(
      const SnackBar(content: Text('Saved to the timeline')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final babies = ref.watch(babiesProvider).value ?? const <Baby>[];
    final active = ref.watch(activeBabyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Log')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (active != null)
                Text(
                  'Logging for ${active.name}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: 'e.g. fed 120 ml, wet diaper, went to sleep',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _loading ? null : _submit,
                  ),
                ),
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(),
                ),
              if (active == null && !_loading)
                const _Hint('Add a baby in Settings to start logging.')
              else if (_result != null)
                _buildResult(_result!, active!, babies),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResult(StructuredResult result, Baby active, List<Baby> babies) {
    if (result.needsClarification != null) {
      return _Hint(result.needsClarification!);
    }
    if (result.action == 'query') {
      return const _Hint(
        'That looks like a question. Asking about your logs is coming soon — '
        'for now, try stating what happened.',
      );
    }
    if (result.events.isEmpty) {
      return const _Hint("I couldn't find anything to log. Try rephrasing.");
    }
    return Column(
      key: ValueKey(_resultSeq),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final event in result.events)
          ConfirmCard(
            event: event,
            babies: babies,
            babyId: active.id,
            rawText: _input.text.trim(),
            onSaved: _onSaved,
            onDiscard: () => setState(() => _result = null),
          ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(color: scheme.onSurfaceVariant)),
    );
  }
}
