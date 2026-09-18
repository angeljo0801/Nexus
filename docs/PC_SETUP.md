# Nexus PC Setup Guide

This guide will ship both inside Nexus and as a standalone document.

## Goal
Connect Nexus Android to a local AI model running on a computer without requiring a hosted AI provider.

## Planned setup flow
1. Install **Nexus Bridge** on the PC.
2. Let Nexus Bridge inspect available RAM/GPU and local AI runtimes.
3. Install or select a supported local runtime.
4. Download or select a compatible coding model.
5. Verify the model locally.
6. Open **Pair Device** in Nexus Bridge.
7. On Android, open **Settings → Devices → Connect a PC**.
8. Scan the QR code or enter the one-time pairing code.
9. Review and grant PC capabilities.
10. Run the built-in connection test.

## Connection test
Nexus checks:
- Bridge reachable.
- Secure channel established.
- Local AI available.
- Model load succeeds.
- Git available.
- Build tools available.
- Workspace permissions valid.

## Offline operation
Internet is not required for Phone ↔ PC communication when both devices can communicate over:
- the same LAN,
- phone hotspot,
- supported direct connection,
- or a configured USB transport.

GitHub synchronization naturally requires Internet, but local Git commits, AI inference, editing, tests and PC builds remain available offline when their dependencies are already installed.

## Troubleshooting
The finished guide will include:
- PC not discovered.
- Pairing code expired.
- Firewall blocking Nexus Bridge.
- Wrong model path.
- Insufficient RAM/VRAM.
- Model runtime not responding.
- Build tool missing.
- Git authentication unavailable.
- Phone and PC workspaces diverged.
