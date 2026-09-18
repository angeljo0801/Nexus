# Nexus v1 — Approved Product Specification

## 1. Product identity
Nexus is a standalone local-first AI coding application. It is separate from Memora.

The Android application is the primary user interface. Nexus can route AI inference and development work to either the phone or a paired computer.

## 2. Local AI architecture
Nexus must not require hosted AI providers.

### AI execution targets
- **PC Local Model** — default.
- **Phone Local Model**.
- **Automatic** — chooses based on availability/resources/task complexity while preserving manual override.

### Phone models
- **Nexus Coding Lite** — approximately 2 GB class; Chat + Coding + Agent.
- **Nexus Coding Pro** — approximately 5 GB class; Chat + Coding + Agent; preferred for more complex work.
- External compatible GGUF models selectable from Android shared storage without duplicating the file.

### Model management
- In-app download.
- Progress, pause/resume, checksum/verification.
- Update and delete.
- Show per-model and total storage usage.
- Nexus-managed models: Delete frees the actual model file.
- External models: Remove from Nexus unlinks only; deleting the device file requires explicit confirmation.

## 3. Chat
- Built-in chat with the selected local model.
- Multiple chat threads.
- Persistent local history.
- Rename, search, archive, delete individual chats, clear history.
- Chat History and Project Memory are separate concepts.
- Deleting a chat must not silently delete project rules/memory.

## 4. Coding agent
Modes:
- **Autonomous** — default recommended.
- Ask Before Editing.
- Read Only.

Agent tool families:
- Read/search/create/edit/delete project files.
- Git status/diff/commit/branch/push/pull.
- Terminal commands within allowed workspaces.
- Analyze/test/build.
- GitHub operations.
- Documentation/web tools when Internet is explicitly available.
- Project indexing and embeddings.

### Autonomous repair loop
1. Apply requested change.
2. Analyze/test/build.
3. Parse errors.
4. Locate cause.
5. Apply correction.
6. Retry.
7. Stop on success or a safety boundary.

Safety boundaries include configurable maximum repair cycles, repeated-error detection, destructive operations, merge conflicts, resource constraints, and out-of-sandbox access.

## 5. Build routing
AI target and build target are independent.

### Build targets
- **GitHub Actions** — recommended when Internet is available.
- **PC**.
- **Phone** where the project/toolchain supports it.
- **Automatic**.

### Recommended online profile
- AI Model: PC Local Model
- Build On: GitHub Actions
- Agent Mode: Autonomous
- Auto Fix: ON
- Sync: Automatic

### Offline profiles
- PC AI + PC Build.
- Phone AI + Phone Build.
- Any manually selected combination that is technically available.

## 6. Project synchronization
Nexus maintains Git-backed workspaces on phone and/or PC.

Required sync paths:
- Phone ↔ PC.
- Phone ↔ GitHub.
- PC ↔ GitHub.
- Three-way coordination when all are present.

Rules:
- Never blind-overwrite divergent work.
- Detect base commit, ahead/behind status and conflicts.
- Auto-merge only when unambiguous.
- Ask the user to resolve ambiguous same-line conflicts.
- Offline commits queue for later remote sync.

## 7. GitHub integration
Connection is initiated inside Nexus.

Preferred authentication model:
- GitHub App / official authorization flow.
- Least privilege.
- Selected repositories where possible.
- No manual PAT requirement for normal setup.

Permission groups are progressive:
- Contents: read/write.
- Actions: read/write when GitHub builds are enabled.
- Workflows: only when workflow editing is enabled.
- Pull Requests: only when PR features are enabled.
- Repository administration/create-repository permission only when the user enables repository creation.

Nexus should expose:
- Connect GitHub.
- Review permissions.
- Select repositories.
- Grant additional permission when a feature first needs it.
- Disconnect/revoke access.
- Create repositories when the user has explicitly enabled the required advanced permission.

Destructive repository operations require explicit confirmation even if the token/app permission technically allows them.

## 8. Nexus Bridge
Nexus Bridge is a lightweight PC companion, not a second full desktop application.

Responsibilities:
- Pair securely with the Android app.
- Expose PC local-model inference.
- Expose approved Git/terminal/build/test capabilities.
- Manage local Nexus workspaces.
- Report PC capabilities and resource status.

Pairing methods:
- Local network discovery.
- QR code / one-time pairing code.
- Manual IP.
- Phone hotspot.
- Wi-Fi Direct where supported.
- USB path as an additional stable transport.

Pairing creates durable device trust using generated keys; temporary pairing tokens expire.

PC permissions are granular:
- Local AI inference.
- Nexus workspaces.
- Git.
- Builds/tests.
- Terminal.
- Files outside workspaces only if explicitly granted.

## 9. PC setup guide
Nexus includes an in-app guide and standalone README-style documentation covering:
- Nexus Bridge installation.
- Supported local runtime installation/configuration.
- Model choice based on RAM/GPU.
- Model download/selection/verification.
- Pairing.
- Connection test.
- Git/build environment checks.
- Troubleshooting.
- Model/Bridge removal.

## 10. Project Memory
Each repository gets persistent structured memory containing:
- Framework/language/toolchain.
- Architecture decisions.
- Branch conventions.
- Preferred AI target.
- Preferred build target.
- Test/build commands.
- Protected paths.
- Project rules.
- Important past decisions.
- Last meaningful agent state.

Code indexing/embeddings are local and can be rebuilt.

## 11. Safety and observability
- Automatic snapshots before substantial agent changes.
- One-tap restore points.
- Commit/build rollback.
- Optional diff preview.
- Sandbox restricting agent access.
- Encrypted secrets store.
- Never place secrets into prompts/logs/commits unless explicitly required and approved.
- Agent action history: files read/changed, commands, builds, retries and commits.
- Resource monitor: RAM, CPU/GPU, battery and temperature.
- Recommend moving work to PC when phone resources are constrained.

## 12. Task system
Large requests can be broken into tasks/subtasks with status:
- Pending.
- In progress.
- Completed.
- Blocked.

## 13. Explain Changes
After work completes, Nexus summarizes:
- What changed.
- Why it changed.
- Files modified.
- Tests/builds performed.
- Remaining warnings.

## 14. Modular architecture
Integrations and tools are modules so Nexus can expand without rewriting the core. Initial modules include:
- Local models.
- Nexus Bridge.
- Git/GitHub.
- Build/test.
- Chat.
- Project Memory.
- Indexing/embeddings.
- Secrets.
- Sync.
