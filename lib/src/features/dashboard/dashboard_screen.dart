import 'package:flutter/material.dart';

import '../../core/models/nexus_preferences.dart';
import '../../core/state/nexus_controller.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.controller});

  final NexusController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Nexus',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Local-first AI coding agent',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            _StatusCard(
              title: 'Recommended profile',
              icon: Icons.auto_awesome,
              child: const Text(
                'PC Local Model · GitHub Actions · Autonomous · Auto Fix · Automatic Sync',
              ),
            ),
            const SizedBox(height: 12),
            _StatusCard(
              title: 'Execution',
              icon: Icons.route,
              child: Column(
                children: [
                  DropdownButtonFormField<AiTarget>(
                    value: controller.aiTarget,
                    decoration: const InputDecoration(
                      labelText: 'AI Model',
                      border: OutlineInputBorder(),
                    ),
                    items: AiTarget.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) controller.setAiTarget(value);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<BuildTarget>(
                    value: controller.buildTarget,
                    decoration: const InputDecoration(
                      labelText: 'Build On',
                      border: OutlineInputBorder(),
                    ),
                    items: BuildTarget.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) controller.setBuildTarget(value);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _StatusCard(
              title: 'Agent',
              icon: Icons.smart_toy_outlined,
              child: Column(
                children: [
                  DropdownButtonFormField<AgentMode>(
                    value: controller.agentMode,
                    decoration: const InputDecoration(
                      labelText: 'Agent Mode',
                      border: OutlineInputBorder(),
                    ),
                    items: AgentMode.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) controller.setAgentMode(value);
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Auto Fix'),
                    subtitle: const Text(
                      'Build, read errors, repair and retry within safety limits.',
                    ),
                    value: controller.autoFix,
                    onChanged: controller.setAutoFix,
                  ),
                  DropdownButtonFormField<SyncMode>(
                    value: controller.syncMode,
                    decoration: const InputDecoration(
                      labelText: 'Sync Mode',
                      border: OutlineInputBorder(),
                    ),
                    items: SyncMode.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) controller.setSyncMode(value);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const _StatusCard(
              title: 'Current status',
              icon: Icons.health_and_safety_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatusLine(label: 'Phone model', value: 'Not installed'),
                  _StatusLine(label: 'Nexus Bridge', value: 'Not paired'),
                  _StatusLine(label: 'GitHub', value: 'Setup pending'),
                  _StatusLine(label: 'Workspace', value: 'No project open'),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
