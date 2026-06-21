# MacHive

> Combine your Apple Silicon Macs into one AI cluster. No terminal required.

MacHive is a tiny macOS menu-bar application that wraps the [exo](https://github.com/exo-explore/exo) distributed inference framework. It lets non-technical users join multiple Apple Silicon Macs on the same WiFi network and run large language models together, without editing config files or opening a terminal.

## Honest scope

MacHive currently supports **AI model inference only**, via exo. More features may come later.

This first release intentionally does **not** include: Blender rendering, video encoding, model training, or task queues.

## Requirements

- macOS 13 or later
- Apple Silicon Mac (M1, M2, M3, or M4)
- All Macs on the same WiFi network
- Internet connection for first-time setup

## Install

1. Download `MacHive.app` from the [Releases](https://github.com/yourusername/machive/releases) page, or build from source with Xcode.
2. Move `MacHive.app` to `/Applications`.
3. Launch MacHive. On first run it will silently install Homebrew, Python 3.12, uv, Node.js, and the exo source.

### Build from source

```bash
git clone https://github.com/yourusername/machive.git
cd machive
# Generate the Xcode project with XcodeGen
brew install xcodegen
xcodegen generate
open MacHive.xcodeproj
```

Then build (`Cmd+B`) and run (`Cmd+R`) in Xcode.

## How to use

1. Launch MacHive on every Mac you want in the cluster.
2. Wait for the first-time setup to finish on each Mac.
3. Click the hive icon in the menu bar. Within a few seconds all Macs on the network should appear.
4. Select a model from the dropdown. Models that do not fit in your combined RAM are disabled.
5. Click **Start AI Cluster**. Once the status shows *Running*, the button becomes **Open Chat** and opens `http://localhost:52415` in your default browser.
6. Click **Stop Cluster** to stop the exo process on this Mac.

## Known limitations

- Currently tested with 2 Macs; larger clusters are not yet verified.
- The model dropdown only shows the four built-in choices: Llama 3 8B, Llama 3 70B, Qwen 2.5 32B, and Mistral 7B. Other exo-supported models must be launched from the terminal.
- Launch-at-login uses `SMAppService` on macOS 13+ and may require approving MacHive in **System Settings → General → Login Items**.
- Running exo for the first time may download model weights, which can take several minutes depending on your internet connection.

## Credit

MacHive is a thin wrapper around the excellent [exo](https://github.com/exo-explore/exo) project by exo labs. All the heavy lifting of distributed inference, peer discovery, and model execution is done by exo itself.

## License

MIT License — see [LICENSE](LICENSE).
