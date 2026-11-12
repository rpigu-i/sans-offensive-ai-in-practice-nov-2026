#!/bin/bash
# Verification script for SANS Offensive AI Workshop setup
# This script checks if all components are properly configured


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Git Bash on Windows rewrites arguments like /app/repos into Windows paths;
# turn that off so the container paths below reach Docker unchanged.
export MSYS_NO_PATHCONV=1
TOOLS_DIR="$SCRIPT_DIR/tools"
WORKSPACE_DIR="$SCRIPT_DIR/workspace"

echo "========================================="
echo "SANS Workshop - Setup Verification"
echo "========================================="
echo ""

ERRORS=0
WARNINGS=0
KEY_CONFIGURED=0

# Function to check if a file exists
check_file() {
    local file="$1"
    local description="$2"
    if [ -f "$file" ]; then
        echo "✓ $description"
        return 0
    else
        echo "✗ $description (missing: $file)"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
}

# Function to check if a directory exists
check_dir() {
    local dir="$1"
    local description="$2"
    if [ -d "$dir" ]; then
        echo "✓ $description"
        return 0
    else
        echo "✗ $description (missing: $dir)"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
}

# Function to check if a service is running
check_service() {
    local service="$1"
    if docker compose ps --status running --services 2>/dev/null | grep -qx "$service"; then
        echo "✓ Service $service is running"
        return 0
    else
        echo "⚠ Service $service is not running"
        WARNINGS=$((WARNINGS + 1))
        return 1
    fi
}

# Check environment file
echo "Checking environment configuration..."
if [ -n "${ANTHROPIC_API_KEY:-}" ] && [ "$ANTHROPIC_API_KEY" != "<add key>" ]; then
    # Set in the environment (e.g. a Codespaces secret); Compose prefers it over .env
    echo "✓ ANTHROPIC_API_KEY is set in the environment"
    KEY_CONFIGURED=1
elif check_file "$SCRIPT_DIR/.env" "Environment file (.env)"; then
    if grep -q "ANTHROPIC_API_KEY=<add key>" "$SCRIPT_DIR/.env" || grep -q "ANTHROPIC_API_KEY=$" "$SCRIPT_DIR/.env"; then
        echo "  ⚠ Warning: ANTHROPIC_API_KEY appears to be unset in .env"
        WARNINGS=$((WARNINGS + 1))
    else
        echo "  ✓ ANTHROPIC_API_KEY appears to be configured"
        KEY_CONFIGURED=1
    fi
fi
echo ""

# Check tool repositories
echo "Checking tool repositories..."
check_dir "$TOOLS_DIR/shannon" "Shannon repository"
check_dir "$TOOLS_DIR/PentestGPT" "PentestGPT repository"
echo ""

# Check Dockerfiles
echo "Checking Dockerfiles..."
check_file "$TOOLS_DIR/shannon/Dockerfile" "Shannon Dockerfile"
check_file "$TOOLS_DIR/PentestGPT/Dockerfile" "PentestGPT Dockerfile"
echo ""

# Check line endings. Git for Windows converts to CRLF by default, which
# breaks bash scripts and the containers' entrypoint scripts.
echo "Checking line endings..."
CRLF_FOUND=0
for f in "$SCRIPT_DIR/setup.sh" "$SCRIPT_DIR/reset-workspace.sh" \
         "$TOOLS_DIR/shannon/entrypoint.sh" "$TOOLS_DIR/PentestGPT/scripts/entrypoint.sh"; do
    if [ -f "$f" ] && grep -q $'\r' "$f"; then
        echo "✗ Windows (CRLF) line endings in $f"
        ERRORS=$((ERRORS + 1))
        CRLF_FOUND=1
    fi
done
if [ "$CRLF_FOUND" -eq 1 ]; then
    echo "  Fix: run 'git config --global core.autocrlf input', delete the tools/ folder"
    echo "  and this repository, then clone again and re-run setup.sh (see README, Windows)"
else
    echo "✓ Scripts use LF line endings"
fi
echo ""

# Check free disk. ZAP, ARTEX, Strix and scan output still need room after setup,
# and a 4-core Codespace only has 32 GB.
echo "Checking free disk space..."
FREE_GB=$(df -Pk "$SCRIPT_DIR" | awk 'NR==2 {print int($4 / 1048576)}')
if [ "$FREE_GB" -lt 8 ]; then
    echo "⚠ Only ${FREE_GB} GB free — ZAP, ARTEX, Strix and scans may run out of space"
    echo "  Free build cache with: docker builder prune -af"
    WARNINGS=$((WARNINGS + 1))
else
    echo "✓ ${FREE_GB} GB free"
fi
if docker info >/dev/null 2>&1; then
    CACHE=$(docker system df --format '{{.Type}}\t{{.Size}}' 2>/dev/null | awk -F'\t' '$1=="Build Cache" {print $2}')
    case "$CACHE" in
        ""|0B|*kB|*KB) ;;
        *) echo "  Docker build cache is using $CACHE; 'docker builder prune -af' frees it" ;;
    esac
fi
echo ""

# Check Shannon configuration
echo "Checking Shannon configuration..."
check_file "$TOOLS_DIR/shannon/configs/juice-shop.yaml" "Shannon juice-shop.yaml config"
check_file "$TOOLS_DIR/shannon/configs/juice-shop-lite.yaml" "Shannon juice-shop-lite.yaml config (workshop)"
echo ""

# Check workspace
echo "Checking workspace..."
check_dir "$WORKSPACE_DIR" "Workspace directory"
if check_dir "$WORKSPACE_DIR/juice-shop" "Juice Shop source code"; then
    if [ -d "$WORKSPACE_DIR/juice-shop/.git" ]; then
        echo "  ✓ Juice Shop is a valid git repository"
    else
        echo "  ✗ Juice Shop directory exists but is not a git repository"
        ERRORS=$((ERRORS + 1))
    fi
fi
echo ""

# Check output directories
echo "Checking output directories..."
check_dir "$SCRIPT_DIR/out" "Output directory"
check_dir "$SCRIPT_DIR/out/zap" "ZAP output directory"
check_dir "$SCRIPT_DIR/out/shannon" "Shannon output directory"
echo ""

# Check Docker services if docker is running
echo "Checking Docker services (if running)..."
if command -v docker &> /dev/null; then
    if docker compose ps &> /dev/null; then
        check_service "juice-shop"
        check_service "shannon-postgres"
        check_service "shannon-temporal"
        check_service "shannon-temporal-ui"
        check_service "pentestgpt"
        echo ""
        echo "To check service health: docker compose ps"
    else
        echo "⚠ Docker Compose services are not running yet"
        echo "  Start with: docker compose up -d"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo "⚠ Docker command not found - cannot check service status"
    WARNINGS=$((WARNINGS + 1))
fi
echo ""

# Check the API key with one live model call (costs a few cents, runs no scan).
# Each participant uses their own key, so catch bad keys before the workshop.
echo "Checking Anthropic API key with Shannon (--validate-model)..."
if [ "$KEY_CONFIGURED" -ne 1 ]; then
    echo "⚠ Skipped: ANTHROPIC_API_KEY is not set in .env"
    WARNINGS=$((WARNINGS + 1))
elif ! (cd "$SCRIPT_DIR" && docker compose ps --status running --services 2>/dev/null | grep -qx "shannon-temporal"); then
    echo "⚠ Skipped: start the services first (docker compose up -d)"
    WARNINGS=$((WARNINGS + 1))
else
    KEY_CHECK_LOG="$(mktemp)"
    (cd "$SCRIPT_DIR" && docker compose run --rm shannon-worker node apps/worker/dist/temporal/worker.js \
        http://juice-shop:3000 /app/repos/juice-shop \
        --task-queue shannon --config /app/configs/juice-shop-lite.yaml --validate-model) > "$KEY_CHECK_LOG" 2>&1
    if grep -q "Model validated" "$KEY_CHECK_LOG"; then
        echo "✓ API key works and passes Shannon's security-access check"
    else
        echo "✗ API key check failed. Last errors from Shannon:"
        sed 's/\x1b\[[0-9;]*m//g' "$KEY_CHECK_LOG" | grep -E "\[(WARN|ERROR)\]|[Ee]rror" | tail -5 | sed 's/^/    /'
        ERRORS=$((ERRORS + 1))
    fi
    rm -f "$KEY_CHECK_LOG"
fi
echo ""

# Summary
echo "========================================="
echo "Verification Summary"
echo "========================================="
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo "✓ All checks passed! Setup is complete."
    echo ""
    echo "Next steps:"
    echo "1. Start services if not running: docker compose up -d"
    echo "2. Wait for services to be healthy: docker compose ps"
    echo "3. Run tools as described in README.md"
elif [ $ERRORS -eq 0 ]; then
    echo "⚠ Setup is mostly complete with $WARNINGS warning(s)"
    echo "Review warnings above and fix if needed"
else
    echo "✗ Setup is incomplete with $ERRORS error(s) and $WARNINGS warning(s)"
    echo "Please run setup.sh or follow manual setup instructions in README.md"
    exit 1
fi
