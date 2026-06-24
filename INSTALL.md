# MacHive Installation Guide

This guide covers every way to install MacHive and its dependencies.

## Quick start (recommended)

1. Download `MacHive.app` from the [Releases](https://github.com/PlatiniumTermite/MacHive/releases) page.
2. **Important:** Move `MacHive.app` to `/Applications`. Dragging from Downloads often fails because of macOS permissions. Instead:
   - Right-click `MacHive.app` in Downloads → **Copy**
   - Open Finder, press **Cmd+Shift+G**, type `/Applications`, press Return
   - Right-click in the folder → **Paste Item**
3. Double-click MacHive in `/Applications`. It appears as a hive icon in the menu bar.
4. On first launch, MacHive installs these dependencies automatically:
   - Homebrew
   - Python 3.13
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
git clone https://github.com/PlatiniumTermite/MacHive.git
cd MacHive
./install-deps.sh
```

Then open `MacHive.xcodeproj` in Xcode and run the app, or build the `.app` yourself.

## Build from source

```bash
# 1. Clone the repo
git clone https://github.com/PlatiniumTermite/MacHive.git
cd MacHive

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
3. **Heterogeneous clusters are supported:** Each Mac can have different RAM and a different M-series chip. MacHive adds RAM and CPU cores together and shows each Mac in the peer list.
4. **Approve login item:** If you enable **Launch MacHive at login**, go to **System Settings → General → Login Items** and make sure MacHive is allowed.
5. **Network permission:** The first time MacHive runs, macOS may ask to allow local network access. Click **Allow**.
6. **Auto-start cluster:** In Settings, enable **Auto-start cluster on launch** so exo starts automatically when MacHive opens.
7. **Auto-sync namespace:** In Settings, enable **Auto-sync namespace with other Macs** so MacHive automatically matches the namespace used by other Macs. Default is `machive`.

## Perfect setup checklist for real-world use

Do this on every Mac in the cluster:

1. **Move MacHive.app to `/Applications`** — required for network permissions and launch-at-login.
2. **Allow local network access** when macOS asks. If you missed it, go to **System Settings → Privacy & Security → Local Network** and enable MacHive.
3. **Turn off macOS firewall** or add MacHive to the allowed list: **System Settings → Network → Firewall**.
4. **Connect all Macs to the same WiFi network**. Avoid guest networks.
5. **Use the same namespace** on every Mac. Default is `machive`. Enable **Auto-sync namespace** in Settings so MacHive handles this automatically.
6. **Click Start AI Cluster** on every Mac.
7. **Wait 30–60 seconds** for exo to discover peers and serve the chat page.
8. **Click Open Chat**.

If anything fails, click **Diagnostics** in the menu bar and use the matching fix button.

## Common Diagnostics fixes

Open the MacHive menu and click **Diagnostics**. If any check fails, use the matching button below:

### ❌ MacHive in /Applications

- Click **Open /Applications Folder** in Diagnostics.
- Drag `MacHive.app` into `/Applications`.
- Quit and relaunch MacHive from `/Applications`.

### ❌ Firewall status

- Click **Open Firewall Settings** in Diagnostics.
- Turn the firewall off, or add `MacHive.app` to the allowed apps list.
- The firewall cannot be disabled automatically by apps — macOS requires you to do it manually.

### ❌ exo running

- Click **Start AI Cluster** in Diagnostics.
- If the cluster exits immediately, click **Test exo** to see the exact error.
- If it still fails, click **Copy Logs** and paste the output into a GitHub issue.

### ❌ Network available

- Make sure WiFi is on.
- All Macs must be on the same WiFi network.
- Avoid guest networks or VLANs that block local traffic.

### Test exo is stuck

- MacHive now kills any stuck test after 10 seconds.
- If it still spins forever, the shell runner is blocked. Click **Copy Logs**, quit MacHive, and reopen it.

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

1. Click **Diagnostics** in the MacHive menu bar. It checks macOS version, app location, chip, exo installation, network, and firewall.
2. Click **Test exo** inside Diagnostics. This runs a quick `exo --help` check and tells you whether the installed environment is actually working.
3. Make sure all Macs are on the **same WiFi network**. Different VLANs or guest networks can block Bonjour.
4. MacHive uses both **Bonjour and UDP broadcast** to find peers, so it still works on many networks that block Bonjour alone.
5. Make sure MacHive is running on each Mac and first-time setup has finished.
6. Click **Refresh Peers** in the MacHive menu bar.
7. Check that macOS firewall is not blocking Bonjour or local network access. Go to **System Settings → Network → Firewall** and disable it temporarily to test.
8. Make sure the namespace is the same on all Macs. MacHive uses `--namespace machive` by default. If you changed it, all Macs must use the same value.
9. Restart MacHive on each Mac.

### Cluster starts but the chat page does not load

- Wait 10–30 seconds for exo to fully initialize.
- MacHive automatically retries starting exo up to 3 times if it exits unexpectedly.
- Click **Copy exo Logs** to copy the recent exo output to the clipboard, then paste it into a GitHub issue.
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
