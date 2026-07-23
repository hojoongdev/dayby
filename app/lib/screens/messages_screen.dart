import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../format.dart';
import '../models/message.dart';
import '../providers.dart';
import '../widgets/glass.dart';

/// The notes between the two caregivers. Opening it marks the unread ones read, so the
/// badge on the dashboard clears.
class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  final _input = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(apiClientProvider).markMessagesRead();
      ref.invalidate(messagesProvider);
    });
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(apiClientProvider).sendMessage(text);
      _input.clear();
      ref.invalidate(messagesProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final messages = ref.watch(messagesProvider);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Messages'),
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: GlassBackground()),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: messages.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Could not load messages: $e')),
                    data: (list) => list.isEmpty
                        ? _empty(theme)
                        : ListView(
                            reverse: true,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            children: [for (final m in list) _bubble(theme, m)],
                          ),
                  ),
                ),
                _composer(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(ThemeData theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No messages yet.\nSay "tell mum to buy diapers" to leave one.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );

  Widget _bubble(ThemeData theme, Message m) {
    final scheme = theme.colorScheme;
    return Align(
      alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
            bottom: 10, left: m.mine ? 44 : 0, right: m.mine ? 0 : 44),
        constraints: const BoxConstraints(maxWidth: 320),
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment:
                m.mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!m.mine && m.fromName != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(m.fromName!,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: scheme.primary)),
                ),
              Text(m.text, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 2),
              Text(formatTime(m.createdAt),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _composer(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: GlassCard(
        radius: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration.collapsed(
                    hintText: 'Message the other parent…'),
              ),
            ),
            IconButton(
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
