import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../widgets/glass.dart';
import 'dashboard_screen.dart';
import 'log_screen.dart';
import 'messages_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'timeline_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  int _index = 0;
  bool _voiceOpen = false;

  static const _tabs = [
    DashboardScreen(),
    TimelineScreen(),
    StatsScreen(),
    SettingsScreen(),
  ];
  static const _labels = ['Dashboard', 'Records', 'Analysis', 'Settings'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _consumePendingIntent();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _consumePendingIntent();
    // Coming back to the app, catch up on anything the other parent did while it was
    // away: their logs and, above all, their messages.
    ref.invalidate(messagesProvider);
    final baby = ref.read(activeBabyProvider);
    if (baby != null) {
      ref.invalidate(eventsProvider(baby.id));
      ref.invalidate(tipsProvider(baby.id));
    }
  }

  Future<void> _consumePendingIntent() async {
    final action = await ref.read(intentBridgeProvider).takePendingAction();
    if (action == 'log_voice') ref.read(voiceLaunchProvider.notifier).request();
  }

  /// Open the voice chat over whatever tab is showing. One at a time — a second tap
  /// while it is up does nothing. Only a hands-free launch (the Action button or Siri)
  /// starts the mic on its own; a tap on the orb opens the chat with the mic ready.
  Future<void> _openVoice({bool startVoice = false}) async {
    if (_voiceOpen || !mounted) return;
    _voiceOpen = true;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => LogScreen(startVoice: startVoice)),
    );
    _voiceOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    // The Action button or Siri asked to log by voice: bring the voice chat up, already
    // listening.
    ref.listen(voiceLaunchProvider, (_, _) => _openVoice(startVoice: true));

    // Poll for the other parent's notes while the app is open, so a note and its unread
    // badge arrive without reopening. (Live events ride a change stream; messages do not
    // yet, so this is the cheap stand-in.)
    ref.listen(dashboardClockProvider, (_, _) => ref.invalidate(messagesProvider));

    // A log from the other parent's phone: everything derived from the timeline catches up.
    ref.listen(liveEventsProvider, (_, next) {
      final event = next.value;
      if (event == null) return;
      ref.invalidate(eventsProvider(event.babyId));
      ref.invalidate(tipsProvider(event.babyId));
      ref.invalidate(statsProvider(event.babyId));
      ref.invalidate(insightsProvider(event.babyId));
    });

    // Every recalculation replaces the pending nudge with the one true now.
    final baby = ref.watch(activeBabyProvider);
    if (baby != null) {
      ref.listen(tipsProvider(baby.id), (_, next) {
        final tips = next.value;
        if (tips == null) return;
        ref.read(remindersProvider).scheduleAll(
              [for (final s in tips.scheduled) (at: s.at, text: s.text)],
            );
      });
    }

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: GlassBackground()),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _TopBar(
                  index: _index,
                  labels: _labels,
                  onSelect: (i) => setState(() => _index = i),
                ),
                Expanded(
                  // The top bar already cleared the status bar, so the tab below it
                  // must not pad for it a second time.
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: IndexedStack(index: _index, children: _tabs),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 20,
            bottom: 24,
            // A tap opens the chat already listening: this app is for talking to.
            child: _VoiceOrb(onTap: () => _openVoice(startVoice: true)),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.index, required this.labels, required this.onSelect});

  final int index;
  final List<String> labels;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(
        children: [
          Expanded(child: _Segments(index: index, labels: labels, onSelect: onSelect)),
          if (ref.watch(sessionProvider).value != null) const _MessageButton(),
        ],
      ),
    );
  }
}

/// The tab switch: pills in a track, the selected one filled. Text only, like a
/// segmented control at the top of the screen.
class _Segments extends StatelessWidget {
  const _Segments({required this.index, required this.labels, required this.onSelect});

  final int index;
  final List<String> labels;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onSelect(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == index
                        ? theme.colorScheme.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: i == index
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: i == index ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MessageButton extends ConsumerWidget {
  const _MessageButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadMessagesProvider);
    return IconButton(
      tooltip: 'Messages',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const MessagesScreen()),
      ),
      icon: Badge.count(
        count: unread,
        isLabelVisible: unread > 0,
        child: const Icon(Icons.chat_bubble_outline),
      ),
    );
  }
}

/// The voice button, floating over every tab: this app is for talking to, so the way
/// in is always there in the corner a thumb reaches.
class _VoiceOrb extends StatelessWidget {
  const _VoiceOrb({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 62,
        height: 62,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF5B8DEF), Color(0xFF9B6DE0), Color(0xFF57C6A9)],
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x559B6DE0),
              blurRadius: 18,
              spreadRadius: 1,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.mic, color: Colors.white, size: 28),
      ),
    );
  }
}
