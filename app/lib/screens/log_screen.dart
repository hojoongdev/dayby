import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

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
  final SpeechToText _speech = SpeechToText();
  bool _speechAvailable = false;
  bool _listening = false;

  StructuredResult? _result;
  int _resultSeq = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  @override
  void dispose() {
    if (_listening) _speech.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    try {
      final available = await _speech.initialize(
        onStatus: _onSpeechStatus,
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
      if (mounted) setState(() => _speechAvailable = available);
    } catch (_) {
      // Speech isn't available here (unsupported browser, denied, or tests):
      // typing still works.
      if (mounted) setState(() => _speechAvailable = false);
    }
  }

  void _onSpeechStatus(String status) {
    if (mounted && status != 'listening') setState(() => _listening = false);
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final lang = ref.read(voiceLangProvider);
    setState(() {
      _listening = true;
      _result = null;
    });
    await _speech.listen(
      onResult: (result) {
        setState(() {
          _input.text = result.recognizedWords;
          _input.selection =
              TextSelection.collapsed(offset: _input.text.length);
        });
        if (result.finalResult && _input.text.trim().isNotEmpty) {
          setState(() => _listening = false);
          _submit();
        }
      },
      listenOptions: SpeechListenOptions(
        partialResults: true,
        localeId: lang == 'ko' ? 'ko-KR' : 'en-US',
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _submit() async {
    final text = _input.text.trim();
    if (text.isEmpty || _loading) return;
    final messenger = ScaffoldMessenger.of(context);
    final api = ref.read(apiClientProvider);
    final lang = ref.read(voiceLangProvider);
    setState(() {
      _loading = true;
      _result = null;
    });
    try {
      final result = await api.ingestText(text, lang: lang);
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
    final voiceLang = ref.watch(voiceLangProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Log')),
      floatingActionButton: _speechAvailable
          ? FloatingActionButton(
              onPressed: _toggleMic,
              tooltip: _listening ? 'Stop' : 'Speak',
              backgroundColor:
                  _listening ? Theme.of(context).colorScheme.error : null,
              child: Icon(_listening ? Icons.stop : Icons.mic),
            )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _listening
                        ? Row(
                            children: [
                              Icon(Icons.mic,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.error),
                              const SizedBox(width: 6),
                              Text('Listening…',
                                  style: Theme.of(context).textTheme.bodySmall),
                            ],
                          )
                        : active != null
                            ? Text('Logging for ${active.name}',
                                style: Theme.of(context).textTheme.bodySmall)
                            : const SizedBox.shrink(),
                  ),
                  if (_speechAvailable)
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'ko', label: Text('Korean')),
                        ButtonSegment(value: 'en', label: Text('English')),
                      ],
                      selected: {voiceLang},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) =>
                          ref.read(voiceLangProvider.notifier).set(s.first),
                    ),
                ],
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
