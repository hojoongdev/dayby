import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../api/api_client.dart';
import '../format.dart';
import '../models/event.dart';
import '../models/family.dart';
import '../providers.dart';
import '../tts.dart';
import '../widgets/confirm_card.dart';
import '../widgets/glass.dart';

/// One turn in the conversation.
class _Msg {
  const _Msg({
    required this.fromUser,
    required this.text,
    this.subtitle,
    this.saved = false,
    this.isError = false,
  });

  final bool fromUser;
  final String text;
  final String? subtitle;
  final bool saved;
  final bool isError;
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
  final Tts _tts = Tts();
  bool _speechAvailable = false;
  bool _listening = false;
  bool _voiceArmed = false;
  bool _muted = false;

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
    _tts.stop();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    try {
      final available = await _speech.initialize(
        onStatus: (s) {
          if (!mounted || s == 'listening') return;
          if (_voiceArmed) {
            _finishVoice(); // pause/timeout -> auto-send, no button needed
          } else if (_listening) {
            setState(() => _listening = false);
          }
        },
        onError: (_) {
          _voiceArmed = false;
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
      _finishVoice();
      return;
    }
    final lang = ref.read(voiceLangProvider);
    _voiceArmed = true;
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (result) {
        setState(() {
          _input.text = result.recognizedWords;
          _input.selection =
              TextSelection.collapsed(offset: _input.text.length);
        });
        if (result.finalResult) _finishVoice();
      },
      listenOptions: SpeechListenOptions(
        partialResults: true,
        localeId: lang == 'ko' ? 'ko-KR' : 'en-US',
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 2),
      ),
    );
  }

  /// End the voice session and auto-send whatever was heard — so the caregiver
  /// never has to reach for the send button.
  void _finishVoice() {
    if (!_voiceArmed || !mounted) return;
    _voiceArmed = false;
    final hasText = _input.text.trim().isNotEmpty;
    setState(() => _listening = false);
    if (hasText) _submit();
  }

  Future<void> _submit() async {
    final text = _input.text.trim();
    if (text.isEmpty || _thinking) return;
    final api = ref.read(apiClientProvider);
    final lang = ref.read(voiceLangProvider);
    _lastText = text;
    _input.clear();
    setState(() {
      _history.add(_Msg(fromUser: true, text: text));
      _pending = null;
      _thinking = true;
    });
    _scrollToBottom();
    try {
      final result = await api.ingestText(text, lang: lang);
      if (!mounted) return;
      setState(() {
        _thinking = false;
        final reply = result.reply;
        if (reply != null && reply.isNotEmpty) {
          _history.add(_Msg(fromUser: false, text: reply));
        }
        if (result.action == 'create' && result.events.isNotEmpty) {
          _pending = result;
        } else if (reply == null || reply.isEmpty) {
          _history.add(_Msg(fromUser: false, text: _fallback(result)));
        }
      });
      final reply = result.reply;
      if (!_muted && reply != null && reply.isNotEmpty) {
        _tts.speak(reply, lang: result.lang);
      }
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _thinking = false;
        _history.add(_Msg(fromUser: false, text: friendlyError(e), isError: true));
      });
      _scrollToBottom();
    }
  }

  String _fallback(StructuredResult r) {
    if (r.needsClarification != null) return r.needsClarification!;
    if (r.action == 'query') return 'Asking about your logs is coming soon.';
    return "I couldn't catch that — try again.";
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
      // Keep the confirm card so the caregiver can retry.
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(err))));
    }
  }

  void _afterSave(Event saved) {
    ref.invalidate(eventsProvider(saved.babyId));
    setState(() {
      _saving = false;
      _pending = null;
      _history.add(_Msg(
        fromUser: false,
        text: eventSummary(saved.type, saved.subtype, saved.fields),
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
          IconButton(
            tooltip: _muted ? 'Unmute' : 'Mute',
            onPressed: () {
              if (!_muted) _tts.stop();
              setState(() => _muted = !_muted);
            },
            icon: Icon(_muted ? Icons.volume_off : Icons.volume_up),
          ),
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
        _appBubble(
          active == null
              ? 'Add a baby in Settings to start logging.'
              : 'Tap the mic and tell me what happened.',
        ),
        for (final m in _history)
          m.fromUser
              ? _userBubble(m.text)
              : _appBubble(m.text,
                  subtitle: m.subtitle, saved: m.saved, isError: m.isError),
        if (_thinking) _appBubble('…'),
        if (_pending != null && active != null)
          _confirmCard(_pending!.events.first, active, babies),
      ],
    );
  }

  Widget _userBubble(String text) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, left: 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(6),
          ),
        ),
        child: Text(text, style: TextStyle(color: scheme.onPrimary)),
      ),
    );
  }

  Widget _appBubble(String text,
      {String? subtitle, bool saved = false, bool isError = false}) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, right: 44),
        constraints: const BoxConstraints(maxWidth: 400),
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (saved) ...[
                Icon(Icons.check_circle, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
              ] else if (isError) ...[
                Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(text, style: theme.textTheme.bodyLarge),
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

  Widget _confirmCard(StructuredEvent e, Baby active, List<Baby> babies) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, right: 24),
        constraints: const BoxConstraints(maxWidth: 400),
        child: GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(eventSummary(e.type, e.subtype, e.fields),
                  style: theme.textTheme.titleMedium),
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
