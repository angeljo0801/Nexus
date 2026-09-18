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

### Implemented phone-local baseline

The first Android phone-local inference baseline uses llama.cpp through llama_flutter_android and is ARM64/API 26+.

Current managed model mappings:
- **Nexus Coding Lite** → Qwen2.5-Coder-1.5B-Instruct Q8_0 GGUF (~1.65 GB).
- **Nexus Coding Pro** → Qwen2.5-Coder-7B-Instruct Q4_K_M GGUF (~4.68 GB).

The model manager currently supports download, progress, pause/resume, SHA-256 verification, active-model selection, deletion, and local storage accounting. Project chat can call the selected phone model locally and persist its response. External GGUF linking is also implemented: Nexus requests a persistent read-only Android SAF grant, stores the content URI, opens it through a native ParcelFileDescriptor, and exposes /proc/self/fd/<fd> to llama.cpp. This lets Nexus use the original model file without creating another multi-GB copy. Unlinking removes the Nexus reference but preserves the original file.

### Model management
- In-app download.
- Progress, pause/resume, checksum/verification.
- Update and delete.
- Show per-model and total storage usage.
- Nexus-managed models: Delete frees the actual model file.
- External models: Remove from Nexus unlinks only; deleting the device file requires explicit confirmation.

## 3. Project-first application creation
Application development is organized around **Projects**, not a single global coding chat.

A project contains:
- Its own AI coding conversation/history.
- Project Memory.
- Tasks/subtasks.
- Local Git workspace.
- Optional GitHub repository.
- AI target and build target preferences.
- Build/test history.
- Sync state across Phone ↔ PC ↔ GitHub.
- Snapshots and rollback history.

Nexus can:
- Create a new application project from an idea.
- Clone an existing GitHub repository into a Nexus project.
- Open an existing local repository as a Nexus project.
- Create a GitHub repository for a Nexus project when the user grants the required permission.

### Project chat
The selected local model talks with the user inside the project and can move from ideation to implementation without changing models:
1. Discuss the application idea.
2. Suggest features/architecture.
3. Turn the plan into tasks.
4. Create/edit code.
5. Build/test.
6. Repair errors.
7. Explain changes.

Project chat history is persistent and can be renamed, searched, archived or deleted. Chat History and Project Memory remain separate so deleting conversation history does not silently erase project rules or technical decisions.

A separate global assistant can remain optional for general questions, but coding work is project-scoped by default.

## 4. Coding agent
Modes:
- **Autonomous** — default recommended.
- Ask Before Editing.
- Read Only.

Agent tool families:
- Read/search/create/edit/delete project files. **Implemented on the phone baseline.**
- Git status/diff are available directly to the phone coding agent. Local commit, remote configuration, push and clone primitives are implemented through embedded JGit and orchestrated outside the prompt so credentials never enter the LLM context.
- Terminal commands within allowed workspaces remain planned through Nexus Bridge / approved execution adapters.
- GitHub Actions analyze/test/build dispatch, run monitoring and failed-log retrieval are implemented for configured projects.
- Auto-Fix can feed real failed build logs to the local model, apply file repairs, commit/push and rebuild within safety limits.
- GitHub in-app Device Flow authorization and encrypted token storage are implemented; builds require a configured Nexus GitHub App client ID.
- Documentation/web tools when Internet is explicitly available.
- Project indexing and embeddings.

### Autonomous repair loop
Target behavior:
1. Apply requested change.
2. Analyze/test/build.
3. Parse errors.
4. Locate cause.
5. Apply correction.
6. Retry.
7. Stop on success or a safety boundary.

Current phone baseline performs real sandboxed file inspection/editing with a maximum of 10 tool steps and creates a snapshot before the first mutation. GitHub Actions build/error-repair is connected. When no build runner is available, Nexus creates an offline local Git checkpoint rather than requiring GitHub. PC-local build execution remains pending Nexus Bridge; phone-local full Flutter/Android compilation remains unavailable until a supported local toolchain provider exists.

Safety boundaries include configurable maximum repair cycles, repeated-error detection, destructive operations, merge conflicts, resource constraints, and out-of-sandbox access.

## 5. Build routing
AI target and build target are independent.

### Build targets
- **GitHub Actions** — optional online runner.
- **PC** — local/offline through Nexus Bridge when paired.
- **Phone** — only where a supported phone toolchain is actually available.
- **Automatic** — local-first: prefer PC, then phone, then GitHub when GitHub is permitted and available.

Build routing and synchronization are independent per project.

### Sync targets
- **Local Only** — Nexus never pushes this project to GitHub.
- **GitHub** — remote operations are allowed when explicitly used.
- **Automatic** — local Git stays primary; GitHub is used only by selected features that require it.

A project may therefore use combinations such as Phone AI + Local Git + GitHub Actions, PC AI + PC Build + GitHub backup, or Phone AI + Local Only with no GitHub connection.

### Default hybrid profile
- AI Model: selectable Phone / PC / Automatic.
- Build On: Automatic.
- Agent Mode: Autonomous.
- Auto Fix: ON.
- Sync target: Automatic, with Local Only available per project.

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

## 14. Secondary enhancements
These are approved follow-on improvements and should fit the architecture without blocking the core:
- Automatic Nexus and Nexus Bridge updates.
- Backup/export/import for chats, Project Memory, settings and project profiles.
- Performance profiles: Battery Saver, Balanced, Maximum Performance.
- Context usage controls and automatic summarization for long conversations/projects.
- Job queue for multiple requested tasks.
- Notifications for builds, repairs, sync conflicts and device connection.
- Visual stable-version/project history on top of Git.
- Unified diagnostics/log panel.
- Recovery mode that starts Nexus without loading optional models/modules after a bad configuration.

## 15. Modular architecture
Integrations and tools are modules so Nexus can expand without rewriting the core. Initial modules include:
- Local models.
- Nexus Bridge.
- Git/GitHub.
- Build/test.
- Project-scoped chat.
- Project Memory.
- Indexing/embeddings.
- Secrets.
- Sync.
