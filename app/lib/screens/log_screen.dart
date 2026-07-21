import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../format.dart';
import '../models/event.dart';
import '../models/family.dart';
import '../models/routine.dart';
import '../providers.dart';
import '../tts.dart';
import '../voice.dart';
import '../widgets/confirm_card.dart';
import '../widgets/glass.dart';

/// How many chat bubbles go to the server as context. Enough for a correction or a
/// follow-up question without sending the whole day every time.
const _rememberedTurns = 10;

/// One turn in the conversation.
class _Msg {
  const _Msg({
    required this.fromUser,
    required this.text,
    this.photo,
    this.subtitle,
    this.saved = false,
    this.isError = false,
  });

  final bool fromUser;
  final String text;

  /// The picture that was sent with this message, if any.
  final Uint8List? photo;
  final String? subtitle;
  final bool saved;
  final bool isError;
}

/// A picture the caregiver attached but has not sent yet.
class _Attachment {
  const _Attachment({
    required this.bytes,
    required this.filename,
    required this.mime,
  });

  final Uint8List bytes;
  final String filename;
  final String mime;
}

class LogScreen extends ConsumerStatefulWidget {
  const LogScreen({super.key});

  @override
  ConsumerState<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends ConsumerState<LogScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final VoiceRecorder _voice = ref.read(voiceRecorderProvider);
  final Tts _tts = Tts();
  StreamSubscription<double>? _levels;
  bool _voiceAvailable = false;
  bool _listening = false;
  /// Between the tap and the mic actually being open. Neither listening nor idle.
  bool _opening = false;
  double _level = 0;
  bool _muted = false;
  /// Whether there is anything typed. The send button only exists while there is.
  bool _typing = false;
  /// An Action-button launch that arrived before the mic finished setting up. Start the
  /// moment it is ready, once.
  bool _startWhenReady = false;

  final List<_Msg> _history = [];
  StructuredResult? _pending;
  _Attachment? _photo;
  String _lastText = '';
  bool _thinking = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _initVoice();
    _input.addListener(() {
      final typing = _input.text.trim().isNotEmpty;
      if (typing != _typing) setState(() => _typing = typing);
    });
  }

  @override
  void dispose() {
    // The recorder belongs to the provider, which closes it. Only the listening on it
    // is ours to let go of.
    _levels?.cancel();
    _tts.stop();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _initVoice() async {
    try {
      final available = await _voice.isSupported();
      _levels = _voice.level.listen((l) {
        if (mounted) setState(() => _level = l);
      });
      if (mounted) setState(() => _voiceAvailable = available);
      if (available && _startWhenReady) {
        _startWhenReady = false;
        _toggleMic();
      }
    } catch (_) {
      if (mounted) setState(() => _voiceAvailable = false);
    }
  }

  /// Start recording because the Action button (or Siri) asked to. If the mic is still
  /// being set up, remember to start the moment it is ready; if a recording is already
  /// running, leave it alone.
  void _startFromIntent() {
    if (_listening || _opening) return;
    if (!_voiceAvailable) {
      _startWhenReady = true;
      return;
    }
    _toggleMic();
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
      await _finishVoice();
      return;
    }
    // Asking for the microphone and opening it are both slow, and _listening does not
    // become true until they are done. Without this, a second tap in that gap starts a
    // whole second recording on top of the first.
    if (_opening) return;
    _opening = true;
    try {
      if (!await _voice.hasPermission()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dayby needs the microphone to hear you.')),
        );
        return;
      }
      await _voice.start(onEnd: _finishVoice);
      if (mounted) setState(() => _listening = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      _opening = false;
    }
  }

  /// They stopped talking, or they tapped stop. Either way the recording goes off to be
  /// transcribed without anyone reaching for a send button — the whole point of the mic.
  Future<void> _finishVoice() async {
    if (!_listening || !mounted) return;
    setState(() {
      _listening = false;
      _level = 0;
    });
    final audio = await _voice.stop();
    if (audio == null || !mounted) return;
    await _sendVoice(audio);
  }

  Future<void> _sendVoice(Uint8List audio) async {
    final history = _turns();
    final languages = ref.read(spokenLanguagesProvider);
    setState(() {
      _pending = null;
      _thinking = true;
    });
    _scrollToBottom();
    try {
      final heard = await ref.read(apiClientProvider).ingestVoice(
            bytes: audio,
            mimeType: VoiceRecorder.mimeType,
            history: history,
            languages: languages,
          );
      if (!mounted) return;
      // The transcript is the caregiver's own bubble: with the server listening, this is
      // the first they see of the words it understood.
      _lastText = heard.transcript;
      setState(() => _history.add(_Msg(fromUser: true, text: heard.transcript)));
      _handleResult(heard.result);
    } catch (e) {
      _showFailure(e);
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picked = await ref.read(imagePickerProvider).pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() => _photo = _Attachment(
            bytes: bytes,
            filename: picked.name,
            mime: _mimeOf(picked),
          ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  /// The picker only promises a name on some platforms, so fall back to the
  /// extension. The server rejects anything that isn't an image either way.
  String _mimeOf(XFile file) {
    final reported = file.mimeType;
    if (reported != null && reported.isNotEmpty) return reported;
    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  void _attachSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from library'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// The chat as shown, which is what the server reads the next utterance against. Error
  /// bubbles are plumbing, not conversation, so they stay out.
  List<Turn> _turns() {
    final said = _history.where((m) => !m.isError).toList();
    final recent = said.length <= _rememberedTurns
        ? said
        : said.sublist(said.length - _rememberedTurns);
    return [for (final m in recent) Turn(fromUser: m.fromUser, text: _lineOf(m))];
  }

  /// A bubble as one line of dialogue. The subtitle comes along so a saved event reads as
  /// saved: an event that was only offered was never written, and must not be corrected.
  String _lineOf(_Msg m) => [
        if (m.photo != null) '(sent a photo)',
        if (m.text.isNotEmpty) m.text,
        if (m.subtitle != null) '— ${m.subtitle!.toLowerCase()}',
      ].join(' ');

  Future<void> _submit() async {
    final text = _input.text.trim();
    final photo = _photo;
    // A picture on its own is a perfectly good log.
    if ((text.isEmpty && photo == null) || _thinking) return;
    final api = ref.read(apiClientProvider);
    final baby = ref.read(activeBabyProvider);
    if (photo != null && baby == null) return;
    // Read off before the new message is appended: it is the utterance, not the context.
    final history = _turns();
    final languages = ref.read(spokenLanguagesProvider);
    _lastText = text;
    _input.clear();
    setState(() {
      _history.add(_Msg(fromUser: true, text: text, photo: photo?.bytes));
      _pending = null;
      _photo = null;
      _thinking = true;
    });
    _scrollToBottom();
    try {
      final result = photo == null
          ? await api.ingestText(text, history: history, languages: languages)
          : (await api.ingestPhoto(
              babyId: baby!.id,
              bytes: photo.bytes,
              filename: photo.filename,
              mimeType: photo.mime,
              text: text,
              history: history,
              languages: languages,
            ))
              .result;
      if (!mounted) return;
      _handleResult(result);
    } catch (e) {
      _showFailure(e);
    }
  }

  /// What the app makes of the server's answer, however the utterance got there — typed,
  /// photographed or spoken.
  void _handleResult(StructuredResult result) {
    setState(() {
      _thinking = false;
      if (result.settings != null && result.settings!.isNotEmpty) {
        _applySettings(result.settings!);
      }
      final reply = result.reply;
      if (reply != null && reply.isNotEmpty) {
        _history.add(_Msg(fromUser: false, text: reply));
      }
      if (result.routine != null) {
        // A reminder rule to set up, not an event to log. Ask before saving it.
        _pending = result;
      } else if (result.action == 'create' && result.events.isNotEmpty) {
        _pending = result;
      } else if ((result.isUpdate || result.isDelete) && result.target != null) {
        // Something real is about to be changed or removed. Show which, and ask.
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
  }

  void _showFailure(Object e) {
    if (!mounted) return;
    setState(() {
      _thinking = false;
      _history.add(_Msg(fromUser: false, text: friendlyError(e), isError: true));
    });
    _scrollToBottom();
  }

  void _applySettings(Map<String, dynamic> s) {
    ref.read(unitPrefsProvider.notifier).set(
          temp: s['temp'] as String?,
          weight: s['weight'] as String?,
          length: s['length'] as String?,
          volume: s['volume'] as String?,
        );
  }

  String _fallback(StructuredResult r) {
    if (r.needsClarification != null) return r.needsClarification!;
    if (r.isUpdate || r.isDelete) {
      return "I'm not sure which one you mean — say a bit more about it.";
    }
    if (r.action == 'query') return 'Asking about your logs is coming soon.';
    return "I couldn't catch that — try again.";
  }

  /// What the record becomes once the correction is merged in. The server merges
  /// the same way, so this is what will actually be there.
  Map<String, dynamic> _merged(Event target, StructuredEvent patch) =>
      {...target.fields, ...patch.fields};

  Future<void> _applyUpdate(StructuredResult result) async {
    final target = result.target!;
    final patch = result.events.first;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final updated = await ref.read(apiClientProvider).updateEvent(
            target.id,
            type: patch.type,
            subtype: patch.subtype,
            fields: patch.fields,
            time: patch.time?.toUtc(),
            note: patch.note,
          );
      _afterChange(updated.babyId, updated.type, updated.subtype, updated.fields,
          'Updated');
    } catch (err) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(err))));
    }
  }

  Future<void> _applyDelete(StructuredResult result) async {
    final target = result.target!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).deleteEvent(target.id);
      _afterChange(
          target.babyId, target.type, target.subtype, target.fields, 'Deleted');
    } catch (err) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(err))));
    }
  }

  void _afterChange(String babyId, String type, String? subtype,
      Map<String, dynamic> fields, String what) {
    final units = ref.read(unitPrefsProvider);
    ref.invalidate(eventsProvider(babyId));
    ref.invalidate(tipsProvider(babyId));
    ref.invalidate(statsProvider(babyId));
    setState(() {
      _saving = false;
      _pending = null;
      _history.add(_Msg(
        fromUser: false,
        text: eventSummary(type, subtype, fields, units: units),
        subtitle: what,
        saved: true,
      ));
    });
    _scrollToBottom();
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
    final units = ref.read(unitPrefsProvider);
    ref.invalidate(eventsProvider(saved.babyId));
    // The new event may be exactly what the assistant was nudging about.
    ref.invalidate(tipsProvider(saved.babyId));
    ref.invalidate(statsProvider(saved.babyId));
    setState(() {
      _saving = false;
      _pending = null;
      _history.add(_Msg(
        fromUser: false,
        text: eventSummary(saved.type, saved.subtype, saved.fields, units: units),
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

    // The Action button or Siri asked to log by voice. Open the mic off the same tick the
    // shell used to switch here.
    ref.listen(voiceLaunchProvider, (_, _) => _startFromIntent());

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
              ? _userBubble(m.text, photo: m.photo)
              : _appBubble(m.text,
                  subtitle: m.subtitle, saved: m.saved, isError: m.isError),
        if (_thinking) _appBubble('…'),
        if (_pending?.routine != null)
          _routineCard(_pending!.routine!)
        else if (_pending != null && active != null)
          switch (_pending!.action) {
            'update' => _changeCard(_pending!),
            'delete' => _deleteCard(_pending!),
            _ => _confirmCard(_pending!.events.first, active, babies),
          },
      ],
    );
  }

  /// A card wrapper for the two cards that act on a record that already exists.
  Widget _actOnRecord({required Widget child}) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, right: 24),
        constraints: const BoxConstraints(maxWidth: 400),
        child: GlassCard(child: child),
      ),
    );
  }

  static const _triggerLabels = {
    'feeding': 'a feeding',
    'diaper': 'a diaper change',
    'sleep': 'a sleep',
    'bath': 'a bath',
    'medicine': 'medicine',
    'pumping': 'pumping',
  };

  String _describeSpec(RoutineSpec r) {
    if (r.kind == 'daily') return 'Every day at ${r.timeLocal}';
    final after = _triggerLabels[r.triggerType] ?? r.triggerType ?? 'an event';
    final delay = r.delayMin ?? 0;
    return delay > 0 ? 'After $after, $delay min later' : 'After $after';
  }

  Future<void> _saveRoutine(RoutineSpec r) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).createRoutine(
            kind: r.kind == 'daily' ? RoutineKind.daily : RoutineKind.afterEvent,
            message: r.message,
            triggerType: r.triggerType,
            delayMin: r.delayMin,
            timeLocal: r.timeLocal,
          );
      ref.invalidate(routinesProvider);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _pending = null;
        _history.add(_Msg(
          fromUser: false,
          text: r.message,
          subtitle: 'Reminder set',
          saved: true,
        ));
      });
      _scrollToBottom();
    } catch (err) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(err))));
    }
  }

  Widget _routineCard(RoutineSpec r) {
    final theme = Theme.of(context);
    return _actOnRecord(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.alarm_add_outlined,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text('Set this reminder?', style: theme.textTheme.labelLarge),
            ],
          ),
          const SizedBox(height: 8),
          Text(r.message, style: theme.textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(_describeSpec(r),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: _saving ? null : () => setState(() => _pending = null),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _saving ? null : () => _saveRoutine(r),
                child: _saving ? _spinner() : const Text('Set reminder'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _changeCard(StructuredResult result) {
    final theme = Theme.of(context);
    final units = ref.watch(unitPrefsProvider);
    final target = result.target!;
    final patch = result.events.first;

    return _actOnRecord(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Change this?', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Text(
            eventSummary(target.type, target.subtype, target.fields, units: units),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              decoration: TextDecoration.lineThrough,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            eventSummary(
              patch.type,
              patch.subtype ?? target.subtype,
              _merged(target, patch),
              units: units,
            ),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(formatTime(patch.time ?? target.time),
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: _saving ? null : () => setState(() => _pending = null),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _saving ? null : () => _applyUpdate(result),
                child: _saving ? _spinner() : const Text('Change'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _deleteCard(StructuredResult result) {
    final theme = Theme.of(context);
    final units = ref.watch(unitPrefsProvider);
    final target = result.target!;

    return _actOnRecord(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.error),
              const SizedBox(width: 6),
              Text('Delete this?',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: theme.colorScheme.error)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            eventSummary(target.type, target.subtype, target.fields, units: units),
            style: theme.textTheme.titleMedium,
          ),
          Text(formatTime(target.time),
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: _saving ? null : () => setState(() => _pending = null),
                child: const Text('Keep it'),
              ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                ),
                onPressed: _saving ? null : () => _applyDelete(result),
                child: _saving ? _spinner() : const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _spinner() => const SizedBox(
        height: 18,
        width: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );

  Widget _userBubble(String text, {Uint8List? photo}) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, left: 44),
        padding: EdgeInsets.symmetric(
          horizontal: photo == null ? 16 : 10,
          vertical: 10,
        ),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (photo != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(photo, width: 200, fit: BoxFit.cover),
              ),
            if (text.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(
                  top: photo == null ? 0 : 8,
                  right: photo == null ? 0 : 6,
                  left: photo == null ? 0 : 6,
                ),
                child: Text(text, style: TextStyle(color: scheme.onPrimary)),
              ),
          ],
        ),
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
    final units = ref.watch(unitPrefsProvider);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, right: 24),
        constraints: const BoxConstraints(maxWidth: 400),
        child: GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(eventSummary(e.type, e.subtype, e.fields, units: units),
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
                    child: _saving ? _spinner() : const Text('Save'),
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
    final canType = active != null;
    // A photo on its own is a log, so having attached one is already something to send.
    final sending = _typing || _photo != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_photo != null) _attachedPreview(_photo!),
          GlassCard(
            radius: 28,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  onPressed: canType ? _attachSheet : null,
                  tooltip: 'Attach a photo',
                  icon: const Icon(Icons.add_a_photo_outlined),
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
                // The mic sits where a thumb actually lands, because the other arm is
                // holding the baby. It stands aside for send only once there is typing
                // to send — and typing is not what this app is for.
                if (sending)
                  IconButton(
                    onPressed: (_thinking || !canType) ? null : _submit,
                    tooltip: 'Send',
                    icon: const Icon(Icons.send),
                  )
                else
                  _mic(canType),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Filled and full-size, because it is the one control this app is really for, and it
  /// is pressed by a thumb on a phone the same hand is holding.
  ///
  /// The words no longer appear as they are spoken — the server does the listening now —
  /// so while it listens the button swells with your voice. Otherwise there would be no
  /// way to tell a mic that is hearing you from one that is dead.
  Widget _mic(bool canType) {
    final scheme = Theme.of(context).colorScheme;
    final listening = _listening;
    return SizedBox(
      height: 48,
      width: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (listening)
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 44 + _level * 14,
              height: 44 + _level * 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.error.withValues(alpha: 0.22),
              ),
            ),
          SizedBox(
            height: 44,
            width: 44,
            child: FilledButton(
              onPressed: _voiceAvailable && canType ? _toggleMic : null,
              style: FilledButton.styleFrom(
                shape: const CircleBorder(),
                padding: EdgeInsets.zero,
                backgroundColor: listening ? scheme.error : scheme.primary,
                foregroundColor: listening ? scheme.onError : scheme.onPrimary,
              ),
              child: Icon(listening ? Icons.stop_rounded : Icons.mic, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _attachedPreview(_Attachment photo) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(photo.bytes,
                width: 64, height: 64, fit: BoxFit.cover),
          ),
          Positioned(
            top: -10,
            right: -10,
            child: IconButton(
              tooltip: 'Remove',
              iconSize: 18,
              onPressed: () => setState(() => _photo = null),
              icon: const CircleAvatar(
                radius: 11,
                backgroundColor: Colors.black54,
                child: Icon(Icons.close, size: 13, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
