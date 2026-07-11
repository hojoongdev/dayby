import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../format.dart';
import '../models/event.dart';
import '../models/family.dart';
import '../providers.dart';
import '../widgets/confirm_card.dart';
import '../widgets/glass.dart';

/// One line in the conversation: the app's confirmation or acknowledgement.
/// The caregiver's own words are intentionally not echoed back.
class _Msg {
  const _Msg({required this.title, this.subtitle, this.saved = false});

  final String title;
  final String? subtitle;
  final bool saved;
}

class LogScreen extends ConsumerStatefulWidget {
  const LogScreen({super.key});

  @override
  ConsumerState<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends ConsumerState<LogScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final SpeechToText _speech = SpeechToText();
  bool _speechAvailable = false;
  bool _listening = false;

  final List<_Msg> _history = [];
  StructuredResult? _pending;
  String _lastText = '';
  bool _thinking = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  @override
  void dispose() {
    if (_listening) _speech.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    try {
      final available = await _speech.initialize(
        onStatus: (s) {
          if (mounted && s != 'listening') setState(() => _listening = false);
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
      if (mounted) setState(() => _speechAvailable = available);
    } catch (_) {
      if (mounted) setState(() => _speechAvailable = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
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
      _pending = null;
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
    if (text.isEmpty || _thinking) return;
    final messenger = ScaffoldMessenger.of(context);
    final api = ref.read(apiClientProvider);
    final lang = ref.read(voiceLangProvider);
    _lastText = text;
    _input.clear();
    setState(() {
      _thinking = true;
      _pending = null;
    });
    _scrollToBottom();
    try {
      final result = await api.ingestText(text, lang: lang);
      if (!mounted) return;
      setState(() {
        _pending = result;
        _thinking = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _thinking = false);
      messenger.showSnackBar(SnackBar(content: Text('Could not process: $e')));
    }
  }

  Future<void> _saveEvent(StructuredEvent e, Baby baby) async {
    final messenger = ScaffoldMessenger.of(context);
    final api = ref.read(apiClientProvider);
    setState(() => _saving = true);
    try {
      final saved = await api.createEvent(
        babyId: baby.id,
        type: e.type,
        subtype: e.subtype,
        fields: e.fields,
        time: e.time?.toUtc(),
        note: e.note,
        rawText: _lastText,
      );
      _afterSave(saved);
    } catch (err) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $err')));
    }
  }

  void _afterSave(Event saved) {
    ref.invalidate(eventsProvider(saved.babyId));
    setState(() {
      _saving = false;
      _pending = null;
      _history.add(_Msg(
        title: eventSummary(saved.type, saved.subtype, saved.fields),
        subtitle: 'Saved to the timeline',
        saved: true,
      ));
    });
    _scrollToBottom();
  }

  void _edit(StructuredEvent e, List<Baby> babies, Baby active) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: ConfirmCard(
            event: e,
            babies: babies,
            babyId: active.id,
            rawText: _lastText,
            onSaved: (saved) {
              Navigator.pop(ctx);
              _afterSave(saved);
            },
            onDiscard: () => Navigator.pop(ctx),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final babies = ref.watch(babiesProvider).value ?? const <Baby>[];
    final active = ref.watch(activeBabyProvider);
    final voiceLang = ref.watch(voiceLangProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Dayby'),
        backgroundColor: Colors.transparent,
        actions: [
          if (_speechAvailable)
            TextButton(
              onPressed: () => ref
                  .read(voiceLangProvider.notifier)
                  .set(voiceLang == 'ko' ? 'en' : 'ko'),
              child: Text(voiceLang == 'ko' ? 'KO' : 'EN'),
            ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: GlassBackground()),
          SafeArea(
            child: Column(
              children: [
                Expanded(child: _conversation(active, babies)),
                _composeBar(active),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _conversation(Baby? active, List<Baby> babies) {
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      children: [
        _bubble(
          active == null
              ? 'Add a baby in Settings to start logging.'
              : 'Tap the mic and tell me what happened.',
        ),
        for (final m in _history)
          _bubble(m.title, subtitle: m.subtitle, saved: m.saved),
        if (_thinking) _bubble('…'),
        if (_pending != null && active != null)
          _confirm(_pending!, active, babies),
      ],
    );
  }

  Widget _bubble(String title, {String? subtitle, bool saved = false}) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: const BoxConstraints(maxWidth: 420),
        child: GlassCard(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (saved) ...[
                Icon(Icons.check_circle, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.bodyLarge),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _confirm(StructuredResult r, Baby active, List<Baby> babies) {
    if (r.needsClarification != null) return _bubble(r.needsClarification!);
    if (r.action == 'query') {
      return _bubble('Asking about your logs is coming soon.',
          subtitle: r.events.isEmpty ? null : null);
    }
    if (r.events.isEmpty) {
      return _bubble("I couldn't catch that — try again.");
    }
    final e = r.events.first;
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: const BoxConstraints(maxWidth: 420),
        child: GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(eventSummary(e.type, e.subtype, e.fields),
                  style: theme.textTheme.titleMedium),
              if (e.note != null && e.note!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(e.note!, style: theme.textTheme.bodyMedium),
                ),
              const SizedBox(height: 4),
              Text(formatTime(e.time ?? DateTime.now()),
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => _edit(e, babies, active),
                    child: const Text('Edit'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _saving ? null : () => _saveEvent(e, active),
                    child: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _composeBar(Baby? active) {
    final theme = Theme.of(context);
    final canType = active != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: GlassCard(
        radius: 28,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          children: [
            IconButton(
              onPressed: _speechAvailable && canType ? _toggleMic : null,
              tooltip: _listening ? 'Stop' : 'Speak',
              color: _listening ? theme.colorScheme.error : theme.colorScheme.primary,
              icon: Icon(_listening ? Icons.stop_circle : Icons.mic),
            ),
            Expanded(
              child: TextField(
                controller: _input,
                enabled: canType,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration.collapsed(
                  hintText: _listening ? 'Listening…' : 'Say or type…',
                ),
              ),
            ),
            IconButton(
              onPressed: (_thinking || !canType) ? null : _submit,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
