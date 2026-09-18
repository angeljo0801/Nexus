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
- **Persistent Chat**: multiple threads, search/rename/archive/delete, with chat history separated from Project Memory.
- **Model Manager**: Nexus Coding Lite (~2 GB), Nexus Coding Pro (~5 GB), external GGUF files, download/delete/storage management.
- **Safety**: snapshots, rollback, diff preview, sandbox, encrypted secrets, action history, repair limits, resource monitoring.
- **GitHub integration**: in-app authorization, repository selection, least-privilege permissions, Actions, PRs, and progressive permission requests including repository creation when enabled.

## Repository status

Construction has started. The first milestone is the Android control app and its architecture. PC-side Nexus Bridge and the local inference/build adapters will follow as independent modules.

See [docs/NEXUS_V1_SPEC.md](docs/NEXUS_V1_SPEC.md) for the approved product specification and [docs/PC_SETUP.md](docs/PC_SETUP.md) for the planned PC setup flow.
