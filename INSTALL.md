# MacHive Installation Guide

This guide covers every way to install MacHive and its dependencies.

## Quick start (recommended)

1. Download `MacHive.app` from the [Releases](https://github.com/yourusername/machive/releases) page.
2. Drag `MacHive.app` into `/Applications`.
3. Double-click MacHive. It appears as a hive icon in the menu bar.
4. On first launch, MacHive silently installs:
   - Homebrew
   - Python 3.12
   - uv (Python package manager)
   - Node.js
   - exo source code
   - exo dashboard build
5. Wait for the progress bar to finish. This can take 10–30 minutes depending on your internet speed.
6. Repeat on every Mac you want in the cluster.

## If automatic setup fails

If you see an error during setup, click **Copy Manual Command** in the setup window, then paste it into Terminal and press Return.

The command runs the bundled `install-deps.sh` script, which installs the same dependencies manually. Example:

```bash
chmod +x "$HOME/Library/Application Support/MacHive/install-deps.sh" && "$HOME/Library/Application Support/MacHive/install-deps.sh"
```

After the script finishes, quit and reopen MacHive.

## Manual install (if you prefer the terminal)

You can also run the script directly from the cloned repo:

```bash
git clone https://github.com/yourusername/machive.git
cd machive
./install-deps.sh
```

Then open `MacHive.xcodeproj` in Xcode and run the app, or build the `.app` yourself.

## Build from source

```bash
# 1. Clone the repo
git clone https://github.com/yourusername/machive.git
cd machive

# 2. Generate the Xcode project
brew install xcodegen
xcodegen generate

# 3. Open in Xcode
open MacHive.xcodeproj
```

In Xcode:

- Select the **MacHive** scheme.
- Choose **My Mac** as the destination.
- Press **Cmd+B** to build.
- Press **Cmd+R** to run.

To create a release `.app`:

- Select **Product → Archive**.
- In the Organizer, click **Distribute App → Copy App**.
- Move the exported `MacHive.app` to `/Applications`.

## Post-install steps

1. **Move to /Applications:** MacHive must be in `/Applications` for launch-at-login and some system permissions to work reliably.
2. **Sandbox note:** MacHive disables the app sandbox because it needs to install Homebrew, Python, uv, Node.js, and the exo source on your Mac, and run `uv run exo` as a subprocess. This is why MacHive is distributed as a direct-download `.app` rather than through the Mac App Store.
3. **Heterogeneous clusters are supported:** Each Mac in the cluster can have a different amount of RAM and a different M-series chip. MacHive adds the RAM together and shows each Mac's chip and RAM in the peer list.
4. **Approve login item:** If you enable **Launch MacHive at login**, go to **System Settings → General → Login Items** and make sure MacHive is allowed.
5. **Network permission:** The first time MacHive runs, macOS may ask to allow local network access. Click **Allow**.

## Troubleshooting

### "Couldn't install Homebrew"

Homebrew needs permission to create `/opt/homebrew`. If the automatic installer fails:

1. Open Terminal.
2. Run the official install script manually:
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```
3. Follow the prompts, then relaunch MacHive.

### "Couldn't install Python / uv / Node.js"

Make sure Homebrew is in your PATH:

```bash
brew --version
```

If that fails, add Homebrew to your shell profile and restart Terminal:

```bash
# For Apple Silicon Macs
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Then run the manual install script:

```bash
"$HOME/Library/Application Support/MacHive/install-deps.sh"
```

### "Couldn't download exo"

Check your internet connection and make sure GitHub is reachable. Try again or run the manual install script.

### "Couldn't build exo"

This usually means Node.js is missing or broken. Reinstall Node.js:

```bash
brew reinstall node
"$HOME/Library/Application Support/MacHive/install-deps.sh"
```

### MacHive icon does not appear in the menu bar

- Make sure MacHive is running. Look for it in **Activity Monitor**.
- The app is a menu-bar-only app (no Dock icon). The icon is in the top-right menu bar.
- If you have many menu bar icons, the MacHive icon may be hidden. Click the hidden-icons chevron to find it.

### Other Macs do not appear in the peer list

- Make sure all Macs are on the **same WiFi network**.
- Make sure MacHive is running on each Mac.
- Check that macOS firewall is not blocking Bonjour or local network access. Go to **System Settings → Network → Firewall** and disable it temporarily to test.

### Cluster starts but the chat page does not load

- Wait 10–30 seconds for exo to fully initialize.
- Make sure `http://localhost:52415` is not blocked by another service.
- Click **Stop Cluster** and then **Start AI Cluster** again.

### Launch at login does not work

- The app must be in `/Applications`.
- The app must be code-signed (ad-hoc signing is enough for local use).
- Go to **System Settings → General → Login Items** and add MacHive manually if needed.

## Uninstall

1. Quit MacHive.
2. Move `MacHive.app` to Trash.
3. Remove dependencies if desired:
   ```bash
   rm -rf "$HOME/Library/Application Support/MacHive"
   ```

Homebrew, Python, uv, and Node.js are not removed automatically because you may use them for other projects.
