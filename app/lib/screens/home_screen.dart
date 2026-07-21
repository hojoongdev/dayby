import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'dashboard_screen.dart';
import 'log_screen.dart';
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
  static const _logTab = 1;

  static const _tabs = [
    DashboardScreen(),
    LogScreen(),
    StatsScreen(),
    TimelineScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The Action button may have launched us straight into this shell.
    _consumePendingIntent();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Or it may have brought an already-running app to the front.
    if (state == AppLifecycleState.resumed) _consumePendingIntent();
  }

  Future<void> _consumePendingIntent() async {
    final action = await ref.read(intentBridgeProvider).takePendingAction();
    if (action == 'log_voice') {
      ref.read(voiceLaunchProvider.notifier).request();
    }
  }

  @override
  Widget build(BuildContext context) {
    // The Action button (or Siri) asked to start a voice log: show the Log tab. The log
    // screen, always built inside the IndexedStack, opens the mic off the same tick.
    ref.listen(voiceLaunchProvider, (_, _) {
      if (_index != _logTab) setState(() => _index = _logTab);
    });

    // A log from the other parent's phone arrives here. It is the same event the
    // server just wrote, so everything derived from the timeline has to catch up.
    // Listening once, above the tabs, covers all of them.
    ref.listen(liveEventsProvider, (_, next) {
      final event = next.value;
      if (event == null) return;
      ref.invalidate(eventsProvider(event.babyId));
      ref.invalidate(tipsProvider(event.babyId));
      ref.invalidate(statsProvider(event.babyId));
      ref.invalidate(insightsProvider(event.babyId));
    });

    // Every time the assistant recalculates -- on launch, on a save, on the other
    // parent's save -- the pending nudge is replaced with the one that is true now.
    // Logging the feed is what cancels the reminder about the feed.
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
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.mic_none_outlined),
            selectedIcon: Icon(Icons.mic),
            label: 'Log',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Stats',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'Timeline',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
