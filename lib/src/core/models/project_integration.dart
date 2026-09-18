class ProjectIntegration {
  const ProjectIntegration({
    required this.projectId,
    this.githubRepo = '',
    this.githubBranch = 'main',
    this.githubWorkflow = 'nexus-build.yml',
    this.autoFixEnabled = true,
    this.maxFixCycles = 3,
    required this.updatedAt,
  });

  final String projectId;
  final String githubRepo;
  final String githubBranch;
  final String githubWorkflow;
  final bool autoFixEnabled;
  final int maxFixCycles;
  final DateTime updatedAt;

  bool get githubConfigured =>
      githubRepo.trim().isNotEmpty &&
      githubBranch.trim().isNotEmpty &&
      githubWorkflow.trim().isNotEmpty;

  ProjectIntegration copyWith({
    String? githubRepo,
    String? githubBranch,
    String? githubWorkflow,
    bool? autoFixEnabled,
    int? maxFixCycles,
  }) {
    return ProjectIntegration(
      projectId: projectId,
      githubRepo: githubRepo ?? this.githubRepo,
      githubBranch: githubBranch ?? this.githubBranch,
      githubWorkflow: githubWorkflow ?? this.githubWorkflow,
      autoFixEnabled: autoFixEnabled ?? this.autoFixEnabled,
      maxFixCycles: maxFixCycles ?? this.maxFixCycles,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, Object?> toMap() => {
        'project_id': projectId,
        'github_repo': githubRepo,
        'github_branch': githubBranch,
        'github_workflow': githubWorkflow,
        'auto_fix_enabled': autoFixEnabled ? 1 : 0,
        'max_fix_cycles': maxFixCycles,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory ProjectIntegration.fromMap(Map<String, Object?> map) {
    return ProjectIntegration(
      projectId: map['project_id']! as String,
      githubRepo: (map['github_repo'] as String?) ?? '',
      githubBranch: (map['github_branch'] as String?) ?? 'main',
      githubWorkflow:
          (map['github_workflow'] as String?) ?? 'nexus-build.yml',
      autoFixEnabled: (map['auto_fix_enabled'] as int? ?? 1) != 0,
      maxFixCycles: (map['max_fix_cycles'] as int? ?? 3).clamp(1, 10).toInt(),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        map['updated_at']! as int,
      ),
    );
  }
}

class ProjectBuildRun {
  const ProjectBuildRun({
    required this.id,
    required this.projectId,
    required this.provider,
    required this.remoteRunId,
    required this.status,
    required this.conclusion,
    required this.attempt,
    required this.commitSha,
    required this.summary,
    required this.logExcerpt,
    required this.startedAt,
    this.finishedAt,
  });

  final String id;
  final String projectId;
  final String provider;
  final String remoteRunId;
  final String status;
  final String conclusion;
  final int attempt;
  final String commitSha;
  final String summary;
  final String logExcerpt;
  final DateTime startedAt;
  final DateTime? finishedAt;

  bool get succeeded => conclusion == 'success';
  bool get failed =>
      conclusion == 'failure' ||
      conclusion == 'cancelled' ||
      conclusion == 'timed_out';

  Map<String, Object?> toMap() => {
        'id': id,
        'project_id': projectId,
        'provider': provider,
        'remote_run_id': remoteRunId,
        'status': status,
        'conclusion': conclusion,
        'attempt': attempt,
        'commit_sha': commitSha,
        'summary': summary,
        'log_excerpt': logExcerpt,
        'started_at': startedAt.millisecondsSinceEpoch,
        'finished_at': finishedAt?.millisecondsSinceEpoch,
      };

  factory ProjectBuildRun.fromMap(Map<String, Object?> map) {
    return ProjectBuildRun(
      id: map['id']! as String,
      projectId: map['project_id']! as String,
      provider: map['provider']! as String,
      remoteRunId: (map['remote_run_id'] as String?) ?? '',
      status: map['status']! as String,
      conclusion: (map['conclusion'] as String?) ?? '',
      attempt: (map['attempt'] as int?) ?? 1,
      commitSha: (map['commit_sha'] as String?) ?? '',
      summary: (map['summary'] as String?) ?? '',
      logExcerpt: (map['log_excerpt'] as String?) ?? '',
      startedAt: DateTime.fromMillisecondsSinceEpoch(
        map['started_at']! as int,
      ),
      finishedAt: map['finished_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              map['finished_at']! as int,
            ),
    );
  }
}
