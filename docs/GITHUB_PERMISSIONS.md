# GitHub permissions strategy

Nexus requests GitHub permissions progressively instead of asking for broad access at first launch.

## Standard access
Used for normal code work:
- Repository metadata: read.
- Contents: read/write.
- Actions: read/write only when GitHub build execution is enabled.
- Pull Requests: read/write only when PR automation is enabled.
- Workflows: requested only if Nexus must edit workflow files.

## Advanced repository management
When the user enables **Create repositories**, Nexus requests the additional repository-administration capability required by GitHub for that operation.

The UI must clearly separate:
- **Create repository**.
- **Repository administration**.
- **Delete repository**.

Destructive operations are never silently executed by the autonomous agent. Deleting repositories, changing visibility, deleting branches with unmerged work, or similarly high-impact operations require an explicit confirmation.

## UX
Nexus should show:
1. Feature that needs the permission.
2. Permission being requested.
3. Why it is required.
4. Official GitHub authorization screen.
5. Result and currently granted capabilities.

Credentials are stored using platform-secure storage and are never committed to a project repository.
