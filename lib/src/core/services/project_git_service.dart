import 'package:nexus_git_bridge/nexus_git_bridge.dart';

import 'project_workspace_service.dart';

class ProjectGitService {
  ProjectGitService._();

  static final ProjectGitService instance = ProjectGitService._();

  final ProjectWorkspaceService _workspace = ProjectWorkspaceService.instance;

  Future<String> _path(String projectId) async {
    return (await _workspace.workspaceDirectory(projectId)).path;
  }

  Future<void> ensureRepository(
    String projectId, {
    String branch = 'main',
  }) async {
    await NexusGitBridge.init(
      repoPath: await _path(projectId),
      branch: branch,
    );
  }

  Future<NexusGitStatus> status(String projectId) async {
    await ensureRepository(projectId);
    return NexusGitBridge.status(await _path(projectId));
  }

  Future<String> diff(String projectId) async {
    await ensureRepository(projectId);
    return NexusGitBridge.diff(await _path(projectId));
  }

  Future<NexusGitCommitResult> commitAll({
    required String projectId,
    required String message,
    String branch = 'main',
  }) async {
    await ensureRepository(projectId, branch: branch);
    return NexusGitBridge.commitAll(
      repoPath: await _path(projectId),
      message: message,
    );
  }

  Future<void> configureRemote({
    required String projectId,
    required String repositoryFullName,
  }) async {
    final clean = repositoryFullName.trim();
    if (!RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(clean)) {
      throw ArgumentError('GitHub repository must be owner/name.');
    }
    await ensureRepository(projectId);
    await NexusGitBridge.setRemote(
      repoPath: await _path(projectId),
      remoteUrl: 'https://github.com/$clean.git',
    );
  }

  Future<void> push({
    required String projectId,
    required String token,
    required String branch,
  }) async {
    await ensureRepository(projectId, branch: branch);
    await NexusGitBridge.push(
      repoPath: await _path(projectId),
      token: token,
      branch: branch,
    );
  }

  Future<void> cloneIntoWorkspace({
    required String projectId,
    required String repositoryFullName,
    required String branch,
    String? token,
  }) async {
    final workspace = await _workspace.workspaceDirectory(projectId);
    final existing = await workspace.list(followLinks: false).toList();
    if (existing.isNotEmpty) {
      throw StateError('Project workspace must be empty before cloning.');
    }

    await NexusGitBridge.clone(
      remoteUrl: 'https://github.com/${repositoryFullName.trim()}.git',
      destinationPath: workspace.path,
      token: token,
      branch: branch,
    );
  }
}
