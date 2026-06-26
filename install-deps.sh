#!/bin/zsh
# MacHive dependency installer
# Runs automatically in Terminal on first launch.

set -e

# Make sure the script is running in a proper interactive shell
export HOME="$HOME"
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

# Persistent MacHive support directory
SUPPORT_DIR="$HOME/Library/Application Support/MacHive"
LOG_FILE="$SUPPORT_DIR/setup.log"
EXO_DIR="$SUPPORT_DIR/exo"
mkdir -p "$SUPPORT_DIR"

# -----------------------------------------------------------------------------
# Logging helpers
# -----------------------------------------------------------------------------
log() {
    local line="$(date '+%Y-%m-%d %H:%M:%S') $1"
    echo "$line"
    echo "$line" >> "$LOG_FILE"
}

log_section() {
    log ""
    log "══════════════════════════════════════════════════════════════════════"
    log "$1"
    log "══════════════════════════════════════════════════════════════════════"
}

log "🐝 MacHive dependency installer"
log "This will install Homebrew, Python 3.13, uv, Node.js, and exo."
log "You may be asked for your Mac admin password."
log "Full log is saved to: $LOG_FILE"

# -----------------------------------------------------------------------------
# Ensure brew is in PATH for this session
# -----------------------------------------------------------------------------
ensure_brew_in_path() {
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)" &>/dev/null || true
    elif [[ -f /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)" &>/dev/null || true
    elif [[ -f /home/linuxbrew/.linuxbrew/bin/brew ]]; then
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" &>/dev/null || true
    fi
    export PATH="/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:$PATH"
}

# -----------------------------------------------------------------------------
# Run a command with retries
# -----------------------------------------------------------------------------
run_with_retry() {
    local desc="$1"
    local max_attempts="${2:-3}"
    shift 2
    local attempt=1
    while true; do
        log "▶️  $desc (attempt $attempt/$max_attempts)..."
        if "$@"; then
            log "✅ $desc succeeded"
            return 0
        fi
        if [[ $attempt -ge $max_attempts ]]; then
            log "❌ $desc failed after $max_attempts attempts"
            return 1
        fi
        attempt=$((attempt + 1))
        log "⏳ Retrying in 5 seconds..."
        sleep 5
    done
}

# -----------------------------------------------------------------------------
# 1. Xcode Command Line Tools
# -----------------------------------------------------------------------------
log_section "1. Checking Xcode Command Line Tools"
if ! xcode-select -p &>/dev/null; then
    log "Xcode Command Line Tools not found. Installing..."
    log "A system dialog will appear. Click 'Install' and wait."
    xcode-select --install 2>/dev/null || true
    # Wait for the user to install or for the tools to become available
    for i in {1..60}; do
        if xcode-select -p &>/dev/null; then
            log "✅ Xcode Command Line Tools installed"
            break
        fi
        log "⏳ Waiting for Xcode Command Line Tools... ($i/60)"
        sleep 10
    done
    if ! xcode-select -p &>/dev/null; then
        log "❌ Xcode Command Line Tools were not installed. Please install them manually and restart MacHive."
        exit 1
    fi
else
    log "✅ Xcode Command Line Tools already installed"
fi

# -----------------------------------------------------------------------------
# 2. Homebrew
# -----------------------------------------------------------------------------
log_section "2. Installing Homebrew"
ensure_brew_in_path
if ! command -v brew &>/dev/null; then
    log "Homebrew not found. Installing..."
    log "A password prompt will appear soon. Type your Mac admin password."
    run_with_retry "Homebrew install" 2 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    ensure_brew_in_path
    if ! command -v brew &>/dev/null; then
        log "❌ Homebrew installation failed. Please restart Terminal and try again."
        log "Common fix: run the following command, then close and reopen Terminal:"
        log '    echo "eval "$(/opt/homebrew/bin/brew shellenv)"" >> ~/.zprofile'
        exit 1
    fi
else
    log "✅ Homebrew already installed: $(command -v brew)"
fi

# -----------------------------------------------------------------------------
# 3. Python 3.13, uv, Node
# -----------------------------------------------------------------------------
log_section "3. Installing Python 3.13, uv, and Node.js"
run_with_retry "brew install python@3.13 uv node" 2 brew install python@3.13 uv node

# -----------------------------------------------------------------------------
# 4. exo source
# -----------------------------------------------------------------------------
log_section "4. Preparing exo source"
if [[ -d "$EXO_DIR/.git" ]]; then
    log "Updating existing exo clone..."
    cd "$EXO_DIR"
    run_with_retry "git pull" 2 git pull --ff-only
else
    log "Cloning exo..."
    rm -rf "$EXO_DIR"
    run_with_retry "git clone exo" 2 git clone --depth 1 https://github.com/exo-explore/exo.git "$EXO_DIR"
    cd "$EXO_DIR"
fi

# -----------------------------------------------------------------------------
# 5. Create Python environment for exo
# -----------------------------------------------------------------------------
log_section "5. Creating Python environment for exo"
cd "$EXO_DIR"
run_with_retry "uv venv" 2 uv venv

# On macOS we need the MLX backend for Apple Silicon.
# Use the optional dependency group if available, otherwise install mlx directly.
if [[ "$(uname -s)" == "Darwin" ]]; then
    log "Installing exo with Apple Silicon MLX support..."
    run_with_retry "uv sync with MLX extra" 2 uv sync --extra mlx || {
        log "Falling back to explicit MLX install..."
        run_with_retry "uv pip install mlx" 2 uv pip install mlx mlx-lm mlx-vlm
    }
else
    run_with_retry "uv sync" 2 uv sync
fi

# Verify MLX is usable on Apple Silicon
if [[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]]; then
    log "Verifying MLX installation..."
    if .venv/bin/python -c "import mlx.core as mx; print('MLX OK')" 2>> "$LOG_FILE"; then
        log "✅ MLX is ready for Apple Silicon"
    else
        log "❌ MLX verification failed. Installing mlx directly..."
        run_with_retry "uv pip install mlx" 2 uv pip install mlx mlx-lm mlx-vlm
        if .venv/bin/python -c "import mlx.core as mx; print('MLX OK')" 2>> "$LOG_FILE"; then
            log "✅ MLX is ready for Apple Silicon"
        else
            log "❌ MLX still cannot be imported. The cluster may not work on Apple Silicon."
            log "Please run this manually in Terminal:"
            log "    cd \"$EXO_DIR\" && uv pip install mlx mlx-lm mlx-vlm"
            exit 1
        fi
    fi
fi

# -----------------------------------------------------------------------------
# 6. Build exo dashboard
# -----------------------------------------------------------------------------

log_section "6. Building exo dashboard"
cd "$EXO_DIR/dashboard"
run_with_retry "npm install" 2 npm install
run_with_retry "npm run build" 2 npm run build

# -----------------------------------------------------------------------------
# 7. Verify exo can start
# -----------------------------------------------------------------------------
log_section "7. Verifying exo"
cd "$EXO_DIR"
if .venv/bin/exo --help &>/dev/null; then
    log "✅ exo is ready"
else
    log "❌ exo command failed. Trying uv run exo --help..."
    if uv run exo --help 2>> "$LOG_FILE" | head -1 &>/dev/null; then
        log "✅ exo is ready via uv run"
    else
        log "❌ exo cannot start. Please check the log above and try again."
        exit 1
    fi
fi

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
log_section "Setup complete"
log "✅ All dependencies are ready."
log "You can now close Terminal and return to MacHive."
log ""

# Create a completion marker so MacHive can detect it quickly
printf '%s' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$SUPPORT_DIR/.setup-complete"
