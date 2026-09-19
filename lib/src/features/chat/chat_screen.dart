import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/chat_message.dart';
import '../../core/models/nexus_project.dart';
import '../../core/services/background_work_coordinator.dart';
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
  final NexusBackgroundWorkCoordinator background =
      NexusBackgroundWorkCoordinator.instance;

  List<ChatMessage> messages = const [];
  bool loading = true;
  bool generating = false;
  bool _sendLocked = false;

  String workingStatus = 'Nexus is working locally with project tools…';
  String elapsedText = '00:00';
  DateTime? _generationStartedAt;
  Timer? _elapsedTicker;
  String? _activeBackgroundTaskId;

  String get _backgroundTitle => 'Nexus · ${widget.project.name}';

  @override
  void initState() {
    super.initState();
    LocalModelManager.instance.initialize();
    background.addListener(_syncBackgroundState);
    _syncBackgroundState();
    loadMessages();
  }

  @override
  void dispose() {
    background.removeListener(_syncBackgroundState);
    _elapsedTicker?.cancel();
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

  void _syncBackgroundState() {
    NexusBackgroundTask? task;
    for (final candidate in background.activeTasks.reversed) {
      if (candidate.title == _backgroundTitle) {
        task = candidate;
        break;
      }
    }

    if (!mounted) return;

    if (task != null) {
      final activeTask = task;
      final newStart = _generationStartedAt?.millisecondsSinceEpoch !=
          activeTask.startedAt.millisecondsSinceEpoch;
      setState(() {
        generating = true;
        _activeBackgroundTaskId = activeTask.id;
        _generationStartedAt = activeTask.startedAt;
        workingStatus = activeTask.status;
        elapsedText = NexusBackgroundWorkCoordinator.formatElapsed(
          DateTime.now().difference(activeTask.startedAt),
        );
      });
      if (newStart) {
        _startElapsedTicker(activeTask.startedAt);
      }
      return;
    }

    if (generating && !_sendLocked) {
      _elapsedTicker?.cancel();
      setState(() {
        generating = false;
        _activeBackgroundTaskId = null;
        _generationStartedAt = null;
        elapsedText = '00:00';
        workingStatus = 'Nexus is working locally with project tools…';
      });
      unawaited(loadMessages());
    }
  }

  void _startElapsedTicker(DateTime startedAt) {
    _elapsedTicker?.cancel();
    _elapsedTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        elapsedText = NexusBackgroundWorkCoordinator.formatElapsed(
          DateTime.now().difference(startedAt),
        );
      });
    });
  }

  Future<void> _setWorkingStatus(String status) async {
    final taskId = _activeBackgroundTaskId;
    if (taskId != null) {
      await background.update(taskId, status: status);
    }
    if (mounted) {
      setState(() => workingStatus = status);
    }
  }

  Future<void> send() async {
    if (_sendLocked || generating) return;

    final text = input.text.trim();
    if (text.isEmpty) return;

    _sendLocked = true;
    final startedAt = DateTime.now();
    _generationStartedAt = startedAt;
    _startElapsedTicker(startedAt);

    if (mounted) {
      setState(() {
        generating = true;
        elapsedText = '00:00';
        workingStatus = 'Preparing Nexus local agent…';
      });
    }

    try {
      _activeBackgroundTaskId = await background.begin(
        title: _backgroundTitle,
        status: 'Preparing Nexus local agent…',
      );

      input.clear();
      await repository.addMessage(
        projectId: widget.project.id,
        role: 'user',
        content: text,
      );
      await loadMessages();

      await LocalModelManager.instance.initialize();
      if (!LocalModelManager.instance.hasActiveModel) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Install or link a Phone Local Model from the Models tab first.',
              ),
            ),
          );
        }
        return;
      }

      await _setWorkingStatus(
        'Nexus is inspecting and editing the project locally…',
      );

      final history = await repository.listMessages(widget.project.id);
      final result = await LocalCodingAgent.instance.run(
        projectId: widget.project.id,
        projectName: widget.project.name,
        projectDescription: widget.project.description,
        framework: widget.project.framework,
        history: history,
        onStatus: (status) {
          unawaited(_setWorkingStatus(status));
        },
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
            unawaited(_setWorkingStatus(status));
          },
        );

        reply =
            '$reply\n\nBuild: ${build.message}'
            '${build.lastRun?.remoteRunId.isNotEmpty == true ? '\nGitHub Actions run #${build.lastRun!.remoteRunId}.' : ''}';
      }

      await _setWorkingStatus('Saving Nexus response…');
      await repository.addMessage(
        projectId: widget.project.id,
        role: 'assistant',
        content: reply,
      );
      await loadMessages();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nexus agent error: $error')),
        );
      }
    } finally {
      _sendLocked = false;
      final taskId = _activeBackgroundTaskId;
      _activeBackgroundTaskId = null;
      if (taskId != null) {
        await background.end(taskId);
      }
      _elapsedTicker?.cancel();
      if (mounted) {
        setState(() {
          generating = false;
          _generationStartedAt = null;
          elapsedText = '00:00';
          workingStatus = 'Nexus is working locally with project tools…';
        });
      }
    }
  }

  Future<void> stopGeneration() async {
    await _setWorkingStatus('Stopping local generation…');
    await LocalLlamaRuntime.instance.stop();
  }

  Future<void> clearChat() async {
    if (generating) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Clear project chat?'),
            content: const Text(
              'This removes this conversation history. Project Memory and '
              'project files are kept separately.',
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

  Widget _workingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(workingStatus),
                  const SizedBox(height: 4),
                  Text(
                    'Elapsed $elapsedText',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
              : messages.isEmpty && !generating
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Describe what you want to build or change. '
                          'Nexus keeps the project local first, then uses the '
                          'selected local or GitHub build route when available.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length + (generating ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (generating && index == messages.length) {
                          return _workingBubble();
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
