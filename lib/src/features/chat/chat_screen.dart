import 'package:flutter/material.dart';

import '../../core/models/chat_message.dart';
import '../../core/services/local_llama_runtime.dart';
import '../../core/services/local_model_manager.dart';
import '../../core/storage/chat_repository.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.projectId,
    required this.projectName,
  });

  final String projectId;
  final String projectName;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController input = TextEditingController();
  final ChatRepository repository = ChatRepository();

  List<ChatMessage> messages = const [];
  bool loading = true;
  bool generating = false;

  @override
  void initState() {
    super.initState();
    LocalModelManager.instance.initialize();
    loadMessages();
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> loadMessages() async {
    final result = await repository.listMessages(widget.projectId);
    if (!mounted) return;
    setState(() {
      messages = result;
      loading = false;
    });
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || generating) return;

    input.clear();
    await repository.addMessage(
      projectId: widget.projectId,
      role: 'user',
      content: text,
    );
    await loadMessages();

    final active = LocalModelManager.instance.activeModel;
    if (active == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Install and select a Phone Local Model from the Models tab first.',
          ),
        ),
      );
      return;
    }

    setState(() => generating = true);

    try {
      final history = await repository.listMessages(widget.projectId);
      final reply = await LocalLlamaRuntime.instance.generateReply(
        projectName: widget.projectName,
        history: history,
      );

      await repository.addMessage(
        projectId: widget.projectId,
        role: 'assistant',
        content: reply,
      );
      await loadMessages();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Local model error: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => generating = false);
      }
    }
  }

  Future<void> stopGeneration() async {
    await LocalLlamaRuntime.instance.stop();
  }

  Future<void> clearChat() async {
    if (generating) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Clear project chat?'),
            content: const Text(
              'This removes this conversation history. Project Memory is kept separately.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Clear'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;
    await repository.clearProjectChat(widget.projectId);
    await loadMessages();
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
                  '${widget.projectName} Agent',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              if (generating)
                IconButton(
                  tooltip: 'Stop generation',
                  onPressed: stopGeneration,
                  icon: const Icon(Icons.stop_circle_outlined),
                ),
              IconButton(
                tooltip: 'Clear chat',
                onPressed:
                    messages.isEmpty || generating ? null : clearChat,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : messages.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Start by describing what you want to build or change in this application.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length + (generating ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (generating && index == messages.length) {
                          return const Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Text('Nexus is thinking locally…'),
                                ],
                              ),
                            ),
                          );
                        }

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
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                  : Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(message.content),
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
                    enabled: !generating,
                    minLines: 1,
                    maxLines: 5,
                    onSubmitted: (_) => send(),
                    decoration: const InputDecoration(
                      hintText: 'Ask Nexus about this project…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: generating ? null : send,
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
