#!/usr/bin/env bash
# Runs once after the container is created.
set -euo pipefail

# Keep setup output clean: don't advertise npm self-updates.
export NPM_CONFIG_UPDATE_NOTIFIER=false

# Coding agents: Claude Code (talks to the Privatemode proxy via
# ANTHROPIC_BASE_URL, already set in devcontainer.json containerEnv),
# opencode, and pi (both configured below via config files)
# --allow-scripts: npm skips postinstall scripts unless allowlisted.
# claude-code and opencode need theirs to install platform binaries;
# @google/genai and protobufjs are pi dependencies (no-op / codegen).
# --loglevel=error hides noise (deprecation warnings from transitive
# deps, funding notices) but still shows real install failures.
npm install -g \
  --allow-scripts=@anthropic-ai/claude-code,opencode-ai,@google/genai,protobufjs \
  --loglevel=error --no-fund \
  @anthropic-ai/claude-code opencode-ai @earendil-works/pi-coding-agent

# opencode: register Privatemode as an OpenAI-compatible provider.
# The proxy handles API authentication itself, so the key is a placeholder.
mkdir -p ~/.config/opencode
cat > ~/.config/opencode/opencode.json <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "privatemode": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Privatemode",
      "options": {
        "baseURL": "http://privatemode-proxy:8080/v1",
        "apiKey": "unused"
      },
      "models": {
        "kimi-latest": {
          "name": "Kimi K2.6 (Privatemode)",
          "limit": { "context": 262144, "output": 32768 }
        },
        "gpt-oss-120b": {
          "name": "GPT-OSS 120B (Privatemode)",
          "limit": { "context": 131072, "output": 32768 }
        }
      }
    }
  },
  "model": "privatemode/kimi-latest"
}
EOF

# pi: register Privatemode in the models registry.
# Cost is set to 0 (flat-rate API, no per-token billing).
mkdir -p ~/.pi/agent
cat > ~/.pi/agent/models.json <<'EOF'
{
  "providers": {
    "privatemode": {
      "baseUrl": "http://privatemode-proxy:8080/v1",
      "apiKey": "unused",
      "api": "openai-completions",
      "models": [
        {
          "id": "kimi-latest",
          "name": "Kimi K2.6 (Privatemode)",
          "reasoning": false,
          "input": ["text", "image"],
          "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
          "contextWindow": 262144,
          "maxTokens": 32768
        },
        {
          "id": "gpt-oss-120b",
          "name": "GPT-OSS 120B (Privatemode)",
          "reasoning": true,
          "input": ["text"],
          "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
          "contextWindow": 131072,
          "maxTokens": 32768
        }
      ]
    }
  }
}
EOF

# pi reads its default model from settings.json (not models.json)
cat > ~/.pi/agent/settings.json <<'EOF'
{
  "defaultProvider": "privatemode",
  "defaultModel": "kimi-latest"
}
EOF

# Skip the Anthropic login/onboarding flow entirely.
# No Anthropic account is needed: the proxy authenticates itself
# against the Privatemode API; the key value below is a placeholder.
# customApiKeyResponses pre-approves the placeholder key so Claude Code
# doesn't ask "Detected a custom API key, do you want to use it?".
cat > ~/.claude.json <<'EOF'
{
  "hasCompletedOnboarding": true,
  "primaryApiKey": "sk-privatemode",
  "customApiKeyResponses": {
    "approved": ["sk-privatemode"],
    "rejected": []
  }
}
EOF

echo
echo "Setup complete."
echo "  Test the proxy:    curl http://privatemode-proxy:8080/v1/models"
echo "  Coding agents:     claude | opencode | pi"
