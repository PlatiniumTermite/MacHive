# MacHive

**Run Llama 3 70B across multiple Macs with one click. No terminal, no API keys, completely free.**

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen)](https://github.com/PlatiniumTermite/MacHive/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![macOS](https://img.shields.io/badge/macOS-13.0+-blue.svg)](https://www.apple.com/macos/)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1%2FM2%2FM3%2FM4-orange.svg)](https://www.apple.com/mac/)

MacHive turns your Apple Silicon Macs into a distributed AI cluster. Run large language models (Llama 3, Mistral, Qwen) locally by pooling RAM and compute across multiple Macs on your WiFi network.

**Perfect for:** Running 70B models without buying expensive hardware, privacy-focused AI inference, offline AI, homelab enthusiasts, AI researchers.

![MacHive Demo](https://via.placeholder.com/800x400.png?text=MacHive+Demo+Screenshot)

> Built on [exo](https://github.com/exo-explore/exo) — the distributed inference framework for Apple Silicon.

## Quick Start

1. Download `MacHive.app` from the [Releases](https://github.com/PlatiniumTermite/MacHive/releases) page.
2. Drag it to `/Applications` (required for network permissions).
3. Launch MacHive on each Mac you want in the cluster.
4. First launch installs dependencies automatically (10–30 minutes).
5. Click **Start AI Cluster** on each Mac.
6. Click **Open Chat** to use the cluster at `http://localhost:52415`.

That's it. No Python environments, no config files, no terminal commands.

## What each Mac shows

- **Peer list**: every Mac with its chip, RAM, model, macOS version, and IP address.
- **Combined RAM**: total RAM available for the selected model.
- **Model picker**: choose Llama 3, Mistral, or Qwen. MacHive tells you if the model fits.
- **Settings**: auto-start cluster, launch at login, show live exo logs, change cluster namespace.
- **Diagnostics**: one-click checks for macOS, app location, firewall, exo status, network.

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

1. Launch MacHive on **every Mac** you want in the cluster.
2. Wait for the first-time setup to finish on each Mac. The setup window shows a live checklist for Homebrew, Python 3.12, uv, Node.js, and the exo source, so you always know exactly what is happening.
3. Click the hive icon in the menu bar. MacHive uses both **Bonjour and UDP broadcast** to find peers for the UI display, showing each Mac's chip and RAM. If no other Mac is found, MacHive still works on this Mac as a single-node cluster.
4. If peers do not appear in the menu bar, click **Diagnostics** to check common issues, then click **Test exo** to verify the installation can run a simple command.
5. Select a model from the dropdown. Macs can have different RAM sizes; MacHive adds them together and disables any model that would not fit in the combined total.
6. **Important:** Click **Start AI Cluster** on **every Mac** in the cluster. exo uses its own libp2p mDNS discovery to find other exo instances running with the same namespace (`machive`). All Macs must be running exo simultaneously to form a cluster.
7. Once the status shows *Running*, the button becomes **Open Chat** and opens `http://localhost:52415` in your default browser.
8. Choose the same model in the exo chat UI and start chatting. You should see in the exo logs that multiple peers are connected.
9. Click **Stop Cluster** to stop the exo process on this Mac.

**Note:** The peer list in MacHive's menu bar shows which Macs are running MacHive. The actual AI cluster formation happens inside exo using libp2p. Check the exo logs (click "Copy exo Logs") to verify peers are connected.

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

### If clustering doesn't work:

**Symptom:** Only one Mac gets hot when asking questions

**Fixes:**
1. **Check same WiFi** - All Macs must be on the same WiFi network (not Ethernet + WiFi mix)
2. **Disable firewall** - Go to System Settings → Network → Firewall → Turn Off (or add MacHive to allowed apps)
3. **Check logs for errors** - Click "Copy exo Logs" and look for connection errors
4. **Restart both Macs** - Sometimes mDNS cache needs clearing
5. **Use same exo version** - Make sure all Macs installed MacHive at the same time

**Still not working?** Open an issue on GitHub with logs from both Macs.

## Known limitations

- MacHive disables the macOS app sandbox because it must install Homebrew, Python, uv, Node.js, and the exo source outside the app container, and run `uv run exo` as a subprocess. This means MacHive is distributed as a direct-download `.app`, not through the Mac App Store.
- Currently tested with 2 Macs; larger clusters are not yet verified.
- The model dropdown in the menu bar is used to validate that your combined RAM can fit the selected model. The actual model selection happens inside the exo chat UI.
- The menu bar only shows the four built-in choices: Llama 3 8B, Llama 3 70B, Qwen 2.5 32B, and Mistral 7B. Other exo-supported models must be selected from the chat UI or launched from the terminal.
- Launch-at-login uses `SMAppService` on macOS 13+ and may require approving MacHive in **System Settings → General → Login Items**.
- Running exo for the first time may download model weights, which can take several minutes depending on your internet connection.

## Credit

MacHive is a thin wrapper around the excellent [exo](https://github.com/exo-explore/exo) project by exo labs. All the heavy lifting of distributed inference, peer discovery, and model execution is done by exo itself.

## License

MIT License — see [LICENSE](LICENSE).
