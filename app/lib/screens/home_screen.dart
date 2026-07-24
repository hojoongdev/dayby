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
  static const _icons = [
    Icons.dashboard_outlined,
    Icons.receipt_long_outlined,
    Icons.insights_outlined,
    Icons.settings_outlined,
  ];

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

  /// The conversation slides up over the tab you were on, as a sheet — it does not
  /// replace the screen. One at a time. Only a hands-free launch (the Action button or
  /// Siri) starts the mic on its own; a tap on the orb opens it ready to listen.
  Future<void> _openVoice({bool startVoice = false}) async {
    if (_voiceOpen || !mounted) return;
    _voiceOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (_) => Padding(
        // Leave the top of the screen showing, so it reads as a panel over the tab,
        // not a new page.
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 52),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          child: LogScreen(startVoice: startVoice),
        ),
      ),
    );
    _voiceOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    // The Action button or Siri asked to log by voice: bring the voice sheet up, already
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
      // Records and Analysis read their own windowed providers; catch them up too.
      ref.invalidate(rangeEventsProvider);
      ref.invalidate(statsRangeProvider);
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
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: GlassBackground()),
          SafeArea(
            bottom: false,
            child: IndexedStack(index: _index, children: _tabs),
          ),
          // Signed-in only: the other parent's notes. In no-login mode there is nobody
          // to message, so it stays hidden.
          if (ref.watch(sessionProvider).value != null)
            const Positioned(top: 0, right: 4, child: SafeArea(child: _MessageButton())),
          Positioned(
            right: 20,
            bottom: 92,
            child: _VoiceOrb(onTap: () => _openVoice(startVoice: true)),
          ),
        ],
      ),
      bottomNavigationBar: _GlassTabBar(
        index: _index,
        labels: _labels,
        icons: _icons,
        onSelect: (i) => setState(() => _index = i),
      ),
    );
  }
}

/// A floating glass tab bar (iOS 26 style): the bar sits above the content with a margin,
/// the content scrolls under it, and the selected tab is a filled pill.
class _GlassTabBar extends StatelessWidget {
  const _GlassTabBar({
    required this.index,
    required this.labels,
    required this.icons,
    required this.onSelect,
  });

  final int index;
  final List<String> labels;
  final List<IconData> icons;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottom > 0 ? bottom : 12),
      child: GlassCard(
        radius: 28,
        blur: 24,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: _NavItem(
                  icon: icons[i],
                  label: labels[i],
                  selected: i == index,
                  onTap: () => onSelect(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = selected
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurfaceVariant;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: on),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: on,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
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

/// The voice button, floating over every tab above the tab bar: this app is for talking
/// to, so the way in is always in the corner a thumb reaches. One accent colour, not a
/// gradient blob.
class _VoiceOrb extends StatelessWidget {
  const _VoiceOrb({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.primary,
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.45),
              blurRadius: 20,
              spreadRadius: 1,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Icon(Icons.mic, color: scheme.onPrimary, size: 28),
      ),
    );
  }
}
