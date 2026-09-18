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
- **Model Manager**: Nexus Coding Lite (~2 GB), Nexus Coding Pro (~5 GB), external GGUF roadmap, download/delete/storage management.
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

GitHub Actions run 29 successfully passed analysis, tests, native Android build, and APK artifact upload for this local-AI baseline.

Still pending from the larger design: Nexus Bridge implementation, Git/GitHub project operations inside the app, autonomous coding tools, sync, external no-copy GGUF SAF adapter, Project Memory UI/indexing, and the remaining safety/agent features.

See [docs/NEXUS_V1_SPEC.md](docs/NEXUS_V1_SPEC.md) for the approved product specification and [docs/PC_SETUP.md](docs/PC_SETUP.md) for the planned PC setup flow.
