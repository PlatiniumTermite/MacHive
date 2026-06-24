# MacHive

**Run Llama 3 70B across multiple Macs with one click. No terminal, no API keys, completely free.**

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen)](https://github.com/PlatiniumTermite/MacHive/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![macOS](https://img.shields.io/badge/macOS-13.0+-blue.svg)](https://www.apple.com/macos/)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1%2FM2%2FM3%2FM4-orange.svg)](https://www.apple.com/mac/)
[![Download](https://img.shields.io/badge/Download-Latest%20DMG-amber.svg)](https://github.com/PlatiniumTermite/MacHive/releases/latest/download/MacHive.dmg)

🌐 **Landing page:** https://platiniumtermite.github.io/MacHive

MacHive turns your Apple Silicon Macs into a distributed AI cluster. Run large language models (Llama 3, Mistral, Qwen) locally by pooling RAM and compute across multiple Macs on your WiFi network.

**Perfect for:** Running 70B models without buying expensive hardware, privacy-focused AI inference, offline AI, homelab enthusiasts, AI researchers.

![MacHive Demo](https://via.placeholder.com/800x400.png?text=MacHive+Demo+Screenshot)

> Built on [exo](https://github.com/exo-explore/exo) — the distributed inference framework for Apple Silicon.

## Download

[![Download MacHive](https://img.shields.io/badge/Download-MacHive%20DMG-ffcc00?style=for-the-badge&logo=apple&logoColor=black)](https://github.com/PlatiniumTermite/MacHive/releases/latest/download/MacHive.dmg)

Click the badge above, open the DMG, drag MacHive to Applications, and launch.

## Perfect Setup Checklist (do this on every Mac)

- [ ] macOS 13 or later (Apple Silicon M1/M2/M3/M4)
- [ ] Download `MacHive.app` from [Releases](https://github.com/PlatiniumTermite/MacHive/releases)
- [ ] Move `MacHive.app` to `/Applications` (right-click → Copy, then paste into `/Applications`)
- [ ] Launch MacHive. If macOS asks, click **Allow** for Local Network access
- [ ] Wait for first-time setup to finish (10–30 minutes, installs Homebrew/Python/uv/Node/exo)
- [ ] Turn OFF macOS firewall: System Settings → Network → Firewall → OFF
- [ ] Connect all Macs to the same WiFi network (not guest networks)
- [ ] Click **Start AI Cluster** on every Mac
- [ ] Wait for status to show **Ready**, then click **Open Chat**

## Quick Start

1. Download `MacHive.app` from the [Releases](https://github.com/PlatiniumTermite/MacHive/releases) page.
2. Move it to `/Applications` (dragging from Downloads often fails; use Copy + Paste).
3. Launch MacHive. It appears as a hive icon in the menu bar.
4. First launch installs dependencies automatically. A setup window shows live progress.
5. Once setup finishes, click the menu bar icon and click **Start AI Cluster**.
6. Repeat on every Mac you want in the cluster.
7. When status shows **Ready**, click **Open Chat** to use the cluster at `http://localhost:52415`.

That's it. No Python environments, no config files, no terminal commands.

## What each Mac shows

- **Peer list**: every Mac with chip, RAM, CPU cores, model, macOS version, and IP address.
- **Combined RAM & CPU**: total resources available for the selected model.
- **Model picker**: choose Llama 3, Mistral, Qwen, DeepSeek, Mixtral. MacHive tells you if it fits and recommends the best one.
- **Auto-sync namespace**: MacHive automatically matches the namespace used by other Macs.
- **Settings**: auto-start cluster, launch at login, show live exo logs, auto-sync namespace.
- **Diagnostics**: one-click checks for macOS, app location, firewall, exo status, network.
- **Test Cluster**: verifies the server is responding before opening the chat.

## Why MacHive?

- ✅ **Pool RAM across Macs** - Run 70B models by combining 8GB + 16GB Macs
- ✅ **Zero configuration** - Auto-installs dependencies, discovers peers automatically
- ✅ **Completely local** - No data leaves your network, no API keys needed
- ✅ **Free forever** - Open source models, no subscriptions
- ✅ **Menu bar app** - Native macOS experience, not a terminal tool
- ✅ **Works offline** - After initial model download

## Honest scope

MacHive currently supports **AI model inference only**, via exo. More features may come later.

This first release intentionally does **not** include: Blender rendering, video encoding, model training, or task queues.

## Cost

**MacHive is completely free.** No API keys, no subscriptions, no hidden costs.

- All AI models run **locally on your Macs**, not in the cloud
- Uses free, open-source models (Llama 3, Mistral, Qwen)
- No data is sent to external servers
- Internet is only needed once to download model weights (a few GB per model)

## Requirements

- macOS 13 or later
- Apple Silicon Mac (M1, M2, M3, or M4)
- All Macs on the same WiFi network
- Internet connection for first-time setup
- MacHive.app must be in `/Applications`
- macOS firewall should be off or MacHive added to allowed apps
- First-time setup installs Homebrew, Python 3.13, uv, Node.js, and exo source

## Install

The easiest way is to download `MacHive.app` from the [Releases](https://github.com/PlatiniumTermite/MacHive/releases) page, move it to `/Applications`, and launch it.

For a complete step-by-step guide, manual dependency installation, and troubleshooting, see [INSTALL.md](INSTALL.md).

### Build from source

```bash
git clone https://github.com/PlatiniumTermite/MacHive.git
cd MacHive
# Generate the Xcode project with XcodeGen
brew install xcodegen
xcodegen generate
open MacHive.xcodeproj
```

Then build (`Cmd+B`) and run (`Cmd+R`) in Xcode.

### Release a new version

1. Update `MARKETING_VERSION` in `project.yml` and the version string in `README.md` if needed.
2. Build an archive: in Xcode select **Product → Archive**.
3. In the Organizer, click **Distribute App → Copy App**.
4. Upload the exported `MacHive.app` to a GitHub Release.
5. Attach `install-deps.sh` to the release for users who need the manual fallback.

## How to use

1. **Install on every Mac** using the Perfect Setup Checklist above.
2. **Launch MacHive** on each Mac. It installs dependencies automatically on first launch.
3. **Click the hive icon** in the menu bar.
4. MacHive discovers other Macs automatically using **Bonjour + UDP broadcast + UDP multicast**. You see them in the peer list.
5. If a different namespace is detected, MacHive shows a banner. With **Auto-sync namespace** enabled (default ON), it switches automatically.
6. Select a model. MacHive shows if it fits and recommends the largest model that fits your combined RAM.
7. Click **Start AI Cluster** on **every Mac**. All Macs must be running exo at the same time.
8. Wait for status to show **Ready** (green dot, 2+ Macs, model fits).
9. Click **Open Chat** or **Test Cluster** to open the chat at `http://localhost:52415`.
10. Choose the model in the exo chat UI and start chatting.
11. Click **Stop Cluster** to stop exo on this Mac.

**Tip:** If peers do not appear, click **Diagnostics** and fix any red checks. Then click **Run Checks Again**.

## Troubleshooting Clustering

### How to verify clustering is working:

1. **Start exo on BOTH Macs** - Click "Start AI Cluster" on every Mac
2. **Check the logs** - Click "Copy exo Logs" and look for:
   ```
   Connected to peer: 12D3KooW...
   Partition assigned: layers 0-20
   ```
3. **Monitor CPU usage** - Open Activity Monitor on both Macs, look for `exo` process
4. **Ask a question** - Both Macs should show 20-40% CPU usage simultaneously

### Common problems and fixes

| Problem | Cause | Fix |
|---------|-------|-----|
| "MacHive not in /Applications" | App is in Downloads | Copy `MacHive.app` to `/Applications` and relaunch |
| "Firewall is ON" | macOS firewall blocks discovery | Turn OFF firewall in System Settings → Network → Firewall |
| "daemon already running" | Old exo process is stuck | Click **Stop Cluster**, wait 5 seconds, click **Start AI Cluster** |
| "Different namespaces" | Macs use different cluster names | Enable **Auto-sync namespace** in Settings, or click **Switch to match** |
| "Cluster start timed out" | exo took too long | Click **Stop Cluster**, then **Start AI Cluster** again. First launch downloads models. |
| Peers don't appear | Network/firewall issue | Check same WiFi, firewall off, Local Network permission allowed. Click **Diagnostics**. |
| Only one Mac works | exo did not connect peers | Wait 60 seconds. Check exo logs for "Connected to peer". Restart both Macs. |

### If clustering still doesn't work:

1. **Check same WiFi** - All Macs must be on the same WiFi network (avoid Ethernet + WiFi mix, avoid guest networks)
2. **Disable firewall** - Go to System Settings → Network → Firewall → Turn Off
3. **Check logs** - Click **Copy exo Logs** in MacHive and look for connection errors
4. **Check namespace** - All Macs must show the same namespace under Status
5. **Restart both Macs** - Sometimes mDNS cache needs clearing
6. **Same MacHive version** - Install the same release on all Macs

**Still not working?** Open an issue on GitHub and paste the exo logs from both Macs.

## Known limitations

- MacHive disables the macOS app sandbox because it must install Homebrew, Python, uv, Node.js, and the exo source outside the app container, and run `uv run exo` as a subprocess. This means MacHive is distributed as a direct-download `.app`, not through the Mac App Store.
- Multi-Mac clustering is provided by exo. MacHive makes it easy to start and monitor, but the actual distributed inference is done by exo.
- The model dropdown in the menu bar is used to validate that your combined RAM can fit the selected model. The actual model selection happens inside the exo chat UI.
- Launch-at-login uses `SMAppService` on macOS 13+ and may require approving MacHive in **System Settings → General → Login Items**.
- Running exo for the first time may download model weights, which can take several minutes depending on your internet connection.

## Credit

MacHive is a thin wrapper around the excellent [exo](https://github.com/exo-explore/exo) project by exo labs. All the heavy lifting of distributed inference, peer discovery, and model execution is done by exo itself.

## License

MIT License — see [LICENSE](LICENSE).
