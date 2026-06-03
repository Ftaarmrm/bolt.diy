#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  🚀 Bolt.DIY Production Startup${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# ============================================================================
# SAFE DIAGNOSTICS: Log what's configured without exposing secrets
# ============================================================================

echo -e "\n${YELLOW}📋 Deployment Configuration:${NC}"
echo "  Node Environment: ${NODE_ENV:-production}"
echo "  Host: ${HOST:-0.0.0.0}"
echo "  Port: ${PORT:-5173}"
echo "  Running in Docker: ${RUNNING_IN_DOCKER:-false}"
echo "  Log Level: ${VITE_LOG_LEVEL:-debug}"
echo "  Default Context Window: ${DEFAULT_NUM_CTX:-8192}"

# ============================================================================
# ALLOWED HOSTS CONFIGURATION
# ============================================================================

echo -e "\n${YELLOW}🌐 Host/Domain Configuration:${NC}"

# Parse COOLIFY_FQDN if present (comma-separated for multiple domains)
ALLOWED_HOSTS=""

if [ -n "${COOLIFY_FQDN}" ]; then
  ALLOWED_HOSTS="${COOLIFY_FQDN}"
  echo "  Coolify FQDN detected: ${COOLIFY_FQDN}"
fi

# Parse VITE_PUBLIC_APP_URL if present
if [ -n "${VITE_PUBLIC_APP_URL}" ]; then
  echo "  Public App URL: ${VITE_PUBLIC_APP_URL}"
  if [ -z "${ALLOWED_HOSTS}" ]; then
    # Extract host from URL (e.g., https://example.com/path -> example.com)
    ALLOWED_HOSTS=$(echo "${VITE_PUBLIC_APP_URL}" | sed -E 's|^https?://([^/:]+).*$|\1|')
  fi
fi

# Allow localhost for development/debugging
if [ -z "${ALLOWED_HOSTS}" ]; then
  ALLOWED_HOSTS="localhost,127.0.0.1"
  echo "  No COOLIFY_FQDN or VITE_PUBLIC_APP_URL set, defaulting to: ${ALLOWED_HOSTS}"
else
  # Append localhost for debugging if not present
  if [[ ! "${ALLOWED_HOSTS}" =~ "localhost" ]]; then
    ALLOWED_HOSTS="${ALLOWED_HOSTS},localhost,127.0.0.1"
  fi
  echo "  Resolved allowed hosts: ${ALLOWED_HOSTS}"
fi

# Export for wrangler/app to use
export ALLOWED_HOSTS
export __VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS="${ALLOWED_HOSTS}"

# ============================================================================
# PROVIDER KEY PRESENCE LOGGING (safe: only log if present, never the value)
# ============================================================================

echo -e "\n${YELLOW}🔑 AI Provider Keys Status:${NC}"

check_provider() {
  local key_var=$1
  local provider_name=$2
  
  if [ -n "${!key_var}" ]; then
    # Key is present but we never log its value
    echo -e "  ${GREEN}✓${NC} ${provider_name}: configured (key length: ${#!key_var} chars)"
  else
    echo -e "  ${RED}✗${NC} ${provider_name}: not configured"
  fi
}

check_provider "GROQ_API_KEY" "Groq"
check_provider "OPENAI_API_KEY" "OpenAI"
check_provider "ANTHROPIC_API_KEY" "Anthropic"
check_provider "OPEN_ROUTER_API_KEY" "OpenRouter"
check_provider "GOOGLE_GENERATIVE_AI_API_KEY" "Google Gemini"
check_provider "XAI_API_KEY" "xAI"
check_provider "TOGETHER_API_KEY" "Together AI"
check_provider "DEEPSEEK_API_KEY" "DeepSeek"
check_provider "MISTRAL_API_KEY" "Mistral"
check_provider "PERPLEXITY_API_KEY" "Perplexity"

# ============================================================================
# CROSS-ORIGIN ISOLATION HEADERS STATUS
# ============================================================================

echo -e "\n${YELLOW}🔐 Cross-Origin Isolation:${NC}"
echo "  Cross-Origin-Embedder-Policy: require-corp"
echo "  Cross-Origin-Opener-Policy: same-origin"
echo "  Cross-Origin-Resource-Policy: cross-origin"
echo -e "  ${GREEN}✓${NC} Headers enabled (configured in app/entry.server.tsx)"
echo -e "  ${GREEN}✓${NC} WebContainer/SharedArrayBuffer support enabled"

# ============================================================================
# GROQ CONTEXT CONFIGURATION
# ============================================================================

echo -e "\n${YELLOW}⚙️  Groq Configuration:${NC}"
echo "  Default Context Window: ${DEFAULT_NUM_CTX:-8192} tokens"
if [ "${DEFAULT_NUM_CTX:-8192}" -gt 16000 ]; then
  echo -e "  ${YELLOW}⚠️  WARNING:${NC} Large context window may hit Groq rate limits"
  echo "    Recommended: 8192 or less for production"
fi

# ============================================================================
# DOCKER ENVIRONMENT SETUP
# ============================================================================

echo -e "\n${YELLOW}🐳 Docker Environment:${NC}"

# Ensure bindings script is executable
if [ ! -x "/app/bindings.sh" ]; then
  chmod +x /app/bindings.sh
  echo "  Made bindings.sh executable"
fi

# ============================================================================
# START APPLICATION
# ============================================================================

echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✨ Starting Bolt.DIY application...${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# Execute bindings script to get wrangler flags, then start the app
bindings=$(./bindings.sh)
exec pnpm run start:unix $bindings --ip 0.0.0.0 --port 5173 --no-show-interactive-dev-session
