# Nexus

Nexus is a local-first AI coding agent for Android. The Android app is the main control surface; AI inference can run locally on the phone or on a paired PC through Nexus Bridge.

## Core design

- **Local AI only**: no required ChatGPT, Gemini, Claude, or other hosted AI provider.
- **AI target**: PC Local Model (default), Phone Local Model, or Automatic.
- **Build target**: GitHub Actions (recommended when online), PC, Phone, or Automatic.
- **Recommended profile**: PC AI + GitHub Actions + Autonomous Agent + Auto Fix + Automatic Sync.
- **Offline**: work from local Git repositories on the PC or phone.
- **Autonomous repair loop**: edit → analyze/test/build → read errors → fix → retry with safety limits.
- **Three-way sync**: Phone ↔ PC ↔ GitHub using Git history and conflict detection.
- **Nexus Bridge**: lightweight PC companion for secure pairing, local model inference, Git, terminal, tests, and builds.
- **Project Memory**: per-repository architecture, branch, rules, build preferences, decisions, and indexed code knowledge.
- **Persistent project chat**: chat history is stored per project and kept separate from Project Memory.
- **Model Manager**: Nexus Coding Lite (~2 GB), Nexus Coding Pro (~5 GB), and external GGUF models linked from Android storage without duplicating the file.
- **Safety**: snapshots, rollback, diff preview, sandbox, encrypted secrets, action history, repair limits, resource monitoring.
- **GitHub integration**: in-app authorization, repository selection, least-privilege permissions, Actions, PRs, and progressive permission requests including repository creation when enabled.

## Current implementation status

The Android app now has a project-first workspace and persistent local SQLite data for projects and project chat.

Phone-local AI is wired using llama_flutter_android / llama.cpp:
- **Nexus Coding Lite** maps to Qwen2.5-Coder-1.5B-Instruct Q8_0 GGUF (~1.65 GB).
- **Nexus Coding Pro** maps to Qwen2.5-Coder-7B-Instruct Q4_K_M GGUF (~4.68 GB).
- Models can be downloaded in-app, paused/resumed, SHA-256 verified, selected, and deleted.
- The selected phone model is loaded locally and project chat responses are generated on-device.
- Generation can be stopped from the chat.
- Android builds target ARM64 and API 26+ for the native llama.cpp runtime.
- External GGUF models can be linked through Android SAF with persistent read-only permission. Nexus keeps the original file in place and opens it through a native ParcelFileDescriptor (/proc/self/fd/...) while llama.cpp is using it.
- If Vulkan loading fails for a GGUF, Nexus retries that model on CPU automatically.

The first local coding-agent tool loop is also implemented:
- Each project has a private sandboxed workspace.
- The local model can list files, read files, search code, create files, rewrite files, replace exact text, and delete project files.
- A safety snapshot is created automatically before the first mutating tool call in an agent run.
- The new Files tab lets the user inspect the workspace directly in Nexus.
- Project deletion removes the project database records, workspace, and snapshots without touching models or other projects.
- Agent runs are capped at 10 tool steps for this baseline.

GitHub Actions run 29 successfully passed analysis, tests, native Android build, and APK artifact upload for the first local-AI baseline. Newer runs validate the external-model and coding-agent additions.

Still pending from the larger design: Nexus Bridge implementation, Git/GitHub project operations inside the app, Git-backed diff/commit/sync, actual analyze/test/build execution from the phone-agent loop, automatic repair from real build logs, Project Memory UI/indexing, and the remaining safety/agent features.

See [docs/NEXUS_V1_SPEC.md](docs/NEXUS_V1_SPEC.md) for the approved product specification and [docs/PC_SETUP.md](docs/PC_SETUP.md) for the planned PC setup flow.
