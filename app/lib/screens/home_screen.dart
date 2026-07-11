import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final babies = ref.watch(babiesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Dayby')),
      body: babies.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Something went wrong: $e')),
        data: (list) {
          final name = list.isEmpty ? 'there' : list.first.name;
          return Center(child: Text('Hi, $name'));
        },
      ),
    );
  }
}
