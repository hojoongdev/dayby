import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../lang.dart';
import '../providers.dart';
import '../widgets/glass.dart';

/// Both of these are personal, not shared. Two parents can read the same feed as 120 ml
/// or 4 oz, because what is stored is neither — it is the amount, and the unit is only
/// how you would rather see it.
class UnitsScreen extends ConsumerWidget {
  const UnitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(unitPrefsProvider);
    final set = ref.read(unitPrefsProvider.notifier);

    return _Sheet(
      title: 'Units',
      caption: 'Yours alone. The other parent can read the same records in theirs.',
      children: [
        _Choice(
          label: 'Temperature',
          value: units.temp,
          options: const {'c': '°C', 'f': '°F'},
          onChanged: (v) => set.set(temp: v),
        ),
        _Choice(
          label: 'Weight',
          value: units.weight,
          options: const {'kg': 'kg', 'g': 'g', 'lb': 'lb'},
          onChanged: (v) => set.set(weight: v),
        ),
        _Choice(
          label: 'Length',
          value: units.length,
          options: const {'cm': 'cm', 'm': 'm', 'in': 'inch'},
          onChanged: (v) => set.set(length: v),
        ),
        _Choice(
          label: 'Feeding volume',
          value: units.volume,
          options: const {'ml': 'ml', 'oz': 'oz'},
          onChanged: (v) => set.set(volume: v),
        ),
      ],
    );
  }
}

class LanguagesScreen extends ConsumerWidget {
  const LanguagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spoken = ref.watch(spokenLanguagesProvider);
    final assistant = ref.watch(assistantLangProvider);

    return _Sheet(
      title: 'Languages',
      caption: 'Dayby listens without being told a language, so it can hear you switch '
          'mid-sentence — but left to guess at anything, it will guess at anything. '
          'Naming the ones you actually speak is what keeps a muttered Korean sentence '
          'from coming back as Chinese.',
      children: [
        const _Heading('You speak'),
        for (final entry in kLanguages.entries)
          CheckboxListTile(
            title: Text(entry.value),
            value: spoken.contains(entry.key),
            // The last one cannot be unticked: no languages at all does not mean "any
            // language", it means the guessing this setting exists to stop.
            onChanged: spoken.length == 1 && spoken.contains(entry.key)
                ? null
                : (on) {
                    final next = [...spoken];
                    (on ?? false) ? next.add(entry.key) : next.remove(entry.key);
                    ref.read(spokenLanguagesProvider.notifier).set(next);
                  },
          ),
        const Divider(height: 32),
        const _Heading('Dayby answers in'),
        // Only where there is nothing to detect from: the tips on Home, and the keepsake.
        // A reply to something you said is always in the language you said it in.
        _Choice(
          label: 'Language',
          value: spoken.contains(assistant) ? assistant : spoken.first,
          options: {for (final code in spoken) code: languageName(code)},
          onChanged: (v) => ref.read(assistantLangProvider.notifier).set(v),
        ),
      ],
    );
  }
}

class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Sheet(
      title: 'Appearance',
      caption: 'Follow the phone, or pick one yourself. A lot of Dayby gets read in a '
          'dark room with a baby on your arm.',
      children: [
        _Choice(
          label: 'Theme',
          value: ref.watch(themeModeProvider).name,
          options: const {'system': 'System', 'light': 'Light', 'dark': 'Dark'},
          onChanged: (v) =>
              ref.read(themeModeProvider.notifier).set(ThemeMode.values.byName(v)),
        ),
      ],
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.title,
    required this.caption,
    required this.children,
  });

  final String title;
  final String caption;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: Text(title), backgroundColor: Colors.transparent),
      body: Stack(
        children: [
          const Positioned.fill(child: GlassBackground()),
          SafeArea(
            child: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Text(
                    caption,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                ...children,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      trailing: DropdownButton<String>(
        value: value,
        items: [
          for (final e in options.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}
