#!/bin/zsh
# MacHive dependency installer
# Runs automatically in Terminal on first launch.

set -e

echo "🐝 MacHive dependency installer"
echo "This will install Homebrew, Python 3.13, uv, Node.js, and exo."
echo "You may be asked for your Mac admin password."
echo ""

# Ensure brew is in PATH for this session
ensure_brew_in_path() {
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
}

# -----------------------------------------------------------------------------
# 1. Homebrew
# -----------------------------------------------------------------------------
ensure_brew_in_path
if ! command -v brew &>/dev/null; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    ensure_brew_in_path
    if ! command -v brew &>/dev/null; then
        echo "❌ Homebrew installation failed. Please restart Terminal and try again."
        exit 1
    fi
else
    echo "✅ Homebrew already installed."
fi

# -----------------------------------------------------------------------------
# 2. Python 3.13, uv, Node
# -----------------------------------------------------------------------------
echo "Installing Python 3.13, uv, and Node.js..."
brew install python@3.13 uv node || {
    echo "❌ Failed to install Python/uv/Node. Check your internet and try again."
    exit 1
}

# -----------------------------------------------------------------------------
# 3. exo source
# -----------------------------------------------------------------------------
EXO_DIR="$HOME/Library/Application Support/MacHive/exo"
mkdir -p "$HOME/Library/Application Support/MacHive"

if [[ -d "$EXO_DIR/.git" ]]; then
    echo "Updating existing exo clone..."
    cd "$EXO_DIR"
    git pull --ff-only || true
else
    echo "Cloning exo..."
    rm -rf "$EXO_DIR"
    git clone --depth 1 https://github.com/exo-explore/exo.git "$EXO_DIR"
    cd "$EXO_DIR"
fi

# -----------------------------------------------------------------------------
# 4. Create Python environment for exo
# -----------------------------------------------------------------------------
echo "Creating Python environment for exo..."
cd "$EXO_DIR"
uv venv || {
    echo "❌ Failed to create Python environment."
    exit 1
}
uv sync || {
    echo "❌ Failed to install exo dependencies."
    exit 1
}

# -----------------------------------------------------------------------------
# 5. Build exo dashboard
# -----------------------------------------------------------------------------
echo "Building exo dashboard (this may take a few minutes)..."
cd "$EXO_DIR/dashboard"
npm install || {
    echo "❌ Failed to install dashboard dependencies."
    exit 1
}
npm run build || {
    echo "❌ Failed to build dashboard."
    exit 1
}

echo ""
echo "✅ All dependencies are ready."
echo "You can now close Terminal and return to MacHive."
