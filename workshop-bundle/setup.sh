#!/bin/bash
# Setup script for SANS Offensive AI Workshop
# This script automates the setup of Shannon and PentestGPT tools

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$SCRIPT_DIR/tools"
WORKSPACE_DIR="$SCRIPT_DIR/workspace"
CONFIGS_DIR="$TOOLS_DIR/shannon/configs"

# Upstream PentestGPT removed the `pentestgpt` CLI on 2026-07-13 (commit ab5fbb4).
# Pin to the last commit that still ships it.
PENTESTGPT_REF="b986930"
# Pin Shannon and Juice Shop too, so upstream changes can't break the workshop.
# The Juice Shop source tag matches the bkimminich/juice-shop image tag in docker-compose.yml.
SHANNON_REF="4bd88c1"
JUICE_SHOP_REF="v20.3.0"
# ARTEX (optional 4th tool) — BillReyor/ARTEX english-ui branch; built from source.
ARTEX_REF="59373e358851db86597d1e8d399957a43eab6dd9"

# Clone with LF line endings on every platform. Git for Windows defaults to
# CRLF, which breaks the bash entrypoints that get copied into the images.
GIT_CLONE=(git clone -c core.autocrlf=input -c core.eol=lf)

echo "========================================="
echo "SANS Offensive AI Workshop - Setup"
echo "========================================="
echo ""

# Check if .env file exists
if [ ! -f "$SCRIPT_DIR/.env" ]; then
    echo "⚠️  No .env file found!"
    echo "Creating .env from .env.example..."
    cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
    echo ""
    if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
        # Codespaces secret (or exported variable): Docker Compose reads it from
        # the environment, which takes priority over .env.
        echo "✓ Using ANTHROPIC_API_KEY from the environment (e.g. a Codespaces secret)"
    elif [ -t 0 ]; then
        echo "⚠️  IMPORTANT: Please edit .env and add your ANTHROPIC_API_KEY"
        echo "   File location: $SCRIPT_DIR/.env"
        echo ""
        read -p "Press Enter after you've added your API key to continue..."
    else
        echo "⚠️  No ANTHROPIC_API_KEY yet. Add it to $SCRIPT_DIR/.env (or as a"
        echo "   Codespaces secret) before running Shannon or PentestGPT."
    fi
fi

# On Linux and WSL2, bind mounts keep host file ownership, so Shannon must run
# as the host user to write findings. (Docker Desktop on macOS doesn't need this.)
if [ "$(uname -s)" = "Linux" ] && ! grep -q "^SHANNON_HOST_UID=" "$SCRIPT_DIR/.env"; then
    echo "Recording host user ID in .env for Shannon..."
    printf '\nSHANNON_HOST_UID=%s\nSHANNON_HOST_GID=%s\n' "$(id -u)" "$(id -g)" >> "$SCRIPT_DIR/.env"
fi

# Create tools directory
echo "Creating tools directory..."
mkdir -p "$TOOLS_DIR"

# Clone Shannon if not already cloned
if [ ! -d "$TOOLS_DIR/shannon" ]; then
    echo "Cloning Shannon repository..."
    "${GIT_CLONE[@]}" https://github.com/KeygraphHQ/shannon "$TOOLS_DIR/shannon"
else
    echo "✓ Shannon repository already exists"
fi

# Clone PentestGPT if not already cloned
if [ ! -d "$TOOLS_DIR/PentestGPT" ]; then
    echo "Cloning PentestGPT repository..."
    "${GIT_CLONE[@]}" https://github.com/greydgl/pentestgpt "$TOOLS_DIR/PentestGPT"
else
    echo "✓ PentestGPT repository already exists"
fi

# Clone ARTEX (optional 4th tool) if not already cloned
if [ ! -d "$TOOLS_DIR/artex" ]; then
    echo "Cloning ARTEX repository..."
    "${GIT_CLONE[@]}" https://github.com/BillReyor/ARTEX "$TOOLS_DIR/artex"
else
    echo "✓ ARTEX repository already exists"
fi

echo "Pinning Shannon to $SHANNON_REF, PentestGPT to $PENTESTGPT_REF, ARTEX to $ARTEX_REF..."
git -C "$TOOLS_DIR/shannon" checkout -q "$SHANNON_REF"
git -C "$TOOLS_DIR/PentestGPT" checkout -q "$PENTESTGPT_REF"
git -C "$TOOLS_DIR/artex" checkout -q "$ARTEX_REF"

# Copy Dockerfiles if they don't exist
echo ""
echo "Setting up Dockerfiles..."

if [ ! -f "$TOOLS_DIR/shannon/Dockerfile" ]; then
    echo "Copying Shannon Dockerfile..."
    cp "$SCRIPT_DIR/dockerfiles/shannon.Dockerfile" "$TOOLS_DIR/shannon/Dockerfile"
else
    echo "✓ Using Shannon's own Dockerfile"
fi

if [ ! -f "$TOOLS_DIR/PentestGPT/Dockerfile" ]; then
    echo "Copying PentestGPT Dockerfile..."
    cp "$SCRIPT_DIR/dockerfiles/pentestgpt.Dockerfile" "$TOOLS_DIR/PentestGPT/Dockerfile"
else
    echo "✓ Using PentestGPT's own Dockerfile"
fi

# ARTEX: upstream's own Dockerfile only assembles a pre-built binary, so always
# use our multi-stage build Dockerfile (copied in as workshop.Dockerfile).
if [ -d "$TOOLS_DIR/artex" ]; then
    echo "Copying ARTEX workshop build Dockerfile..."
    cp "$SCRIPT_DIR/dockerfiles/artex.Dockerfile" "$TOOLS_DIR/artex/workshop.Dockerfile"
fi

# Create Shannon configs directory and copy juice-shop.yaml
echo ""
echo "Setting up Shannon configuration..."
mkdir -p "$CONFIGS_DIR"

for config in juice-shop.yaml juice-shop-lite.yaml; do
    if [ -f "$SCRIPT_DIR/../$config" ]; then
        echo "Copying $config to Shannon configs..."
        cp "$SCRIPT_DIR/../$config" "$CONFIGS_DIR/$config"
    else
        echo "⚠️  $config not found in parent directory"
    fi
done

# Create workspace directory structure
echo ""
echo "Creating workspace directory structure..."
mkdir -p "$WORKSPACE_DIR"
mkdir -p "$SCRIPT_DIR/out/zap"
mkdir -p "$SCRIPT_DIR/out/shannon"
# ARTEX (optional 4th tool) writes findings/sessions here (bind-mounted to /app/data).
mkdir -p "$SCRIPT_DIR/out/artex"
# Strix (optional 5th tool) writes its runs here (bind-mounted to /work/strix_runs).
# Nothing to clone: docker compose installs the pinned strix-agent wheel.
mkdir -p "$SCRIPT_DIR/out/strix"

# Clone Juice Shop source code
if [ ! -d "$WORKSPACE_DIR/juice-shop" ]; then
    echo "Cloning Juice Shop source code for Shannon analysis..."
    "${GIT_CLONE[@]}" --branch "$JUICE_SHOP_REF" https://github.com/juice-shop/juice-shop.git "$WORKSPACE_DIR/juice-shop"

    # Set git config for the juice-shop repo
    cd "$WORKSPACE_DIR/juice-shop"
    git config user.email "pentest@localhost"
    git config user.name "Pentest Agent"
    cd "$SCRIPT_DIR"
else
    echo "✓ Juice Shop source already exists"
fi

echo ""
echo "========================================="
echo "✓ Setup Complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Ensure your ANTHROPIC_API_KEY is set in .env"
echo "2. Start all services:"
echo "   cd workshop-bundle"
echo "   docker compose up -d"
echo ""
echo "3. Wait for services to be healthy (check with: docker compose ps)"
echo ""
echo "4. Run Shannon pentest:"
echo "   docker compose run --rm shannon-worker node apps/worker/dist/temporal/worker.js \\"
echo "     http://juice-shop:3000 \\"
echo "     /app/repos/juice-shop \\"
echo "     --task-queue shannon \\"
echo "     --config /app/configs/juice-shop-lite.yaml"
echo ""
echo "5. Or connect to PentestGPT interactively:"
echo "   docker compose exec -it pentestgpt bash"
echo "   pentestgpt --target juice-shop:3000 --no-telemetry"
echo ""
echo "For more information, see README.md"
echo ""
