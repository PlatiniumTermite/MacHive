#!/bin/zsh
# MacHive dependency installer (manual fallback)
# Run this in Terminal if the in-app installer fails.

set -e

echo "🐝 MacHive dependency installer"

# -----------------------------------------------------------------------------
# 1. Homebrew
# -----------------------------------------------------------------------------
if ! command -v brew &>/dev/null; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
else
    echo "Homebrew already installed."
fi

# -----------------------------------------------------------------------------
# 2. Python 3.13, uv, Node
# -----------------------------------------------------------------------------
echo "Installing Python 3.13, uv, and Node.js..."
brew install python@3.13 uv node

# -----------------------------------------------------------------------------
# 3. exo source
# -----------------------------------------------------------------------------
EXO_DIR="$HOME/Library/Application Support/MacHive/exo"
mkdir -p "$HOME/Library/Application Support/MacHive"

if [[ -d "$EXO_DIR" ]]; then
    echo "Updating existing exo clone..."
    cd "$EXO_DIR"
    git pull --ff-only
else
    echo "Cloning exo..."
    git clone --depth 1 https://github.com/exo-explore/exo.git "$EXO_DIR"
    cd "$EXO_DIR"
fi

# -----------------------------------------------------------------------------
# 4. Create Python environment for exo
# -----------------------------------------------------------------------------
echo "Creating Python environment for exo..."
cd "$EXO_DIR"
uv venv
uv sync

# -----------------------------------------------------------------------------
# 5. Build exo dashboard
# -----------------------------------------------------------------------------
echo "Building exo dashboard (this may take a few minutes)..."
cd "$EXO_DIR/dashboard"
npm install
npm run build

echo ""
echo "✅ All dependencies are ready."
echo "You can now launch MacHive."
