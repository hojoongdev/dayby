import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'dashboard_screen.dart';
import 'log_screen.dart';
import 'settings_screen.dart';
import 'timeline_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _index = 0;

  static const _tabs = [
    DashboardScreen(),
    LogScreen(),
    TimelineScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // A log from the other parent's phone arrives here. It is the same event the
    // server just wrote, so everything derived from the timeline has to catch up.
    // Listening once, above the tabs, covers all of them.
    ref.listen(liveEventsProvider, (_, next) {
      final event = next.value;
      if (event == null) return;
      ref.invalidate(eventsProvider(event.babyId));
      ref.invalidate(tipsProvider(event.babyId));
    });

    // Every time the assistant recalculates -- on launch, on a save, on the other
    // parent's save -- the pending nudge is replaced with the one that is true now.
    // Logging the feed is what cancels the reminder about the feed.
    final baby = ref.watch(activeBabyProvider);
    if (baby != null) {
      ref.listen(tipsProvider(baby.id), (_, next) {
        final tips = next.value;
        if (tips == null) return;
        ref.read(remindersProvider).schedule(at: tips.remindAt, text: tips.reminder);
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
