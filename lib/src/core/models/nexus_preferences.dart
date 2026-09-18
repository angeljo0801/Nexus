enum AiTarget {
  pc,
  phone,
  automatic,
}

enum BuildTarget {
  github,
  pc,
  phone,
  automatic,
}

enum AgentMode {
  autonomous,
  askBeforeEditing,
  readOnly,
}

enum SyncMode {
  automatic,
  askBeforeSync,
  manual,
}

extension AiTargetLabel on AiTarget {
  String get label => switch (this) {
        AiTarget.pc => 'PC Local Model',
        AiTarget.phone => 'Phone Local Model',
        AiTarget.automatic => 'Automatic',
      };
}

extension BuildTargetLabel on BuildTarget {
  String get label => switch (this) {
        BuildTarget.github => 'GitHub Actions',
        BuildTarget.pc => 'PC',
        BuildTarget.phone => 'This Phone',
        BuildTarget.automatic => 'Automatic',
      };
}

extension AgentModeLabel on AgentMode {
  String get label => switch (this) {
        AgentMode.autonomous => 'Autonomous',
        AgentMode.askBeforeEditing => 'Ask Before Editing',
        AgentMode.readOnly => 'Read Only',
      };
}

extension SyncModeLabel on SyncMode {
  String get label => switch (this) {
        SyncMode.automatic => 'Automatic',
        SyncMode.askBeforeSync => 'Ask Before Sync',
        SyncMode.manual => 'Manual',
      };
}
