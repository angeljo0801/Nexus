enum GitHubCapability {
  repositoryContents,
  actions,
  workflows,
  pullRequests,
  createRepositories,
  repositoryAdministration,
  deleteRepositories,
}

extension GitHubCapabilityInfo on GitHubCapability {
  String get label => switch (this) {
        GitHubCapability.repositoryContents => 'Repository contents',
        GitHubCapability.actions => 'GitHub Actions',
        GitHubCapability.workflows => 'Workflow editing',
        GitHubCapability.pullRequests => 'Pull requests',
        GitHubCapability.createRepositories => 'Create repositories',
        GitHubCapability.repositoryAdministration => 'Repository administration',
        GitHubCapability.deleteRepositories => 'Delete repositories',
      };

  bool get requiresExplicitConfirmation => switch (this) {
        GitHubCapability.createRepositories => true,
        GitHubCapability.repositoryAdministration => true,
        GitHubCapability.deleteRepositories => true,
        _ => false,
      };
}
