import 'package:flutter/material.dart';

import '../../core/models/chat_message.dart';
import '../../core/models/nexus_project.dart';
import '../../core/services/local_coding_agent.dart';
import '../../core/services/local_llama_runtime.dart';
import '../../core/services/local_model_manager.dart';
import '../../core/services/project_build_service.dart';
import '../../core/storage/chat_repository.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.project,
  });

  final NexusProject project;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController input = TextEditingController();
  final ChatRepository repository = ChatRepository();
  List<ChatMessage> messages = const [];
  bool loading = true;
  bool generating = false;
  String workingStatus = 'Nexus is working locally with project tools…';

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
    final result = await repository.listMessages(widget.project.id);
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
      projectId: widget.project.id,
      role: 'user',
      content: text,
    );
    await loadMessages();

    await LocalModelManager.instance.initialize();
    if (!LocalModelManager.instance.hasActiveModel) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Install or link a Phone Local Model from the Models tab first.',
          ),
        ),
      );
      return;
    }

    setState(() {
      generating = true;
      workingStatus = 'Nexus is inspecting and editing the project locally…';
    });

    try {
      final history = await repository.listMessages(widget.project.id);
      final result = await LocalCodingAgent.instance.run(
        projectId: widget.project.id,
        projectName: widget.project.name,
        projectDescription: widget.project.description,
        framework: widget.project.framework,
        history: history,
      );

      var reply = result.response;
      final changed = result.actions.any(
        (action) => const {
          'create_file',
          'write_file',
          'replace_text',
          'delete_file',
        }.contains(action),
      );

      if (result.actions.isNotEmpty) {
        final unique = <String>[];
        for (final action in result.actions) {
          if (!unique.contains(action)) unique.add(action);
        }
        reply =
            '$reply\n\nNexus tools used: ${unique.join(', ')}'
            '${result.snapshotPath == null ? '' : '\nSafety snapshot created before edits.'}';
      }

      if (changed) {
        final build = await ProjectBuildService.instance.buildAndAutoFix(
          project: widget.project,
          conversation: history,
          onStatus: (status) {
            if (!mounted) return;
            setState(() => workingStatus = status);
          },
        );

        reply =
            '$reply\n\nBuild: ${build.message}'
            '${build.lastRun?.remoteRunId.isNotEmpty == true ? '\nGitHub Actions run #${build.lastRun!.remoteRunId}.' : ''}';
      }

      await repository.addMessage(
        projectId: widget.project.id,
        role: 'assistant',
        content: reply,
      );
      await loadMessages();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nexus agent error: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          generating = false;
          workingStatus = 'Nexus is working locally with project tools…';
        });
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
              'This removes this conversation history. Project Memory and project files are kept separately.',
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
    await repository.clearProjectChat(widget.project.id);
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
                child: AnimatedBuilder(
                  animation: LocalModelManager.instance,
                  builder: (context, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.project.name} Agent',
                        style:
                            Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      Text(
                        LocalModelManager.instance.activeDisplayName,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
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
                          'Describe what you want to build or change. Nexus keeps the project local first, then uses the selected local or GitHub build route when one is available.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length + (generating ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (generating && index == messages.length) {
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Flexible(child: Text(workingStatus)),
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
                      hintText: 'Ask Nexus to build or change something…',
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
