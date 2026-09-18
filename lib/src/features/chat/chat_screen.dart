import 'package:flutter/material.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatMessage {
  const _ChatMessage({required this.text, required this.fromUser});

  final String text;
  final bool fromUser;
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController input = TextEditingController();
  final List<_ChatMessage> messages = const [
    _ChatMessage(
      text: 'Nexus chat is ready. Connect a phone model or Nexus Bridge to enable local inference.',
      fromUser: false,
    ),
  ].toList();

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void send() {
    final text = input.text.trim();
    if (text.isEmpty) return;

    setState(() {
      messages.add(_ChatMessage(text: text, fromUser: true));
      messages.add(
        const _ChatMessage(
          text: 'No local model is connected yet. The chat UI is active; inference wiring is the next implementation step.',
          fromUser: false,
        ),
      );
      input.clear();
    });
  }

  void clearChat() {
    setState(messages.clear);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Chat',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              IconButton(
                tooltip: 'Clear chat',
                onPressed: messages.isEmpty ? null : clearChat,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
        Expanded(
          child: messages.isEmpty
              ? const Center(
                  child: Text('This chat is empty.'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    return Align(
                      alignment: message.fromUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 520),
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: message.fromUser
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(message.text),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    minLines: 1,
                    maxLines: 5,
                    onSubmitted: (_) => send(),
                    decoration: const InputDecoration(
                      hintText: 'Ask Nexus about your app or code…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: send,
                  icon: const Icon(Icons.arrow_upward),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
