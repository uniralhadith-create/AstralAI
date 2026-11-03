#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Astral AI V5.0.0 — One-Command GitHub Push & IPA Release Publisher
# ==============================================================================
# Usage:
#   chmod +x publish_v5_release.sh
#   ./publish_v5_release.sh <YOUR_GITHUB_USERNAME> [REPO_NAME]
# ==============================================================================

GH_TOKEN="${GH_TOKEN:-YOUR_GITHUB_TOKEN}"
GH_USER="${1:-}"
REPO_NAME="${2:-AstralAI}"

if [ -z "$GH_USER" ]; then
  echo "Detecting GitHub username from token..."
  GH_USER=$(curl -s -H "Authorization: token $GH_TOKEN" https://api.github.com/user | grep -o '"login": *"[^"]*"' | head -1 | cut -d'"' -f4)
fi

if [ -z "$GH_USER" ]; then
  echo "Error: Could not detect GitHub username. Pass it as first argument: ./publish_v5_release.sh <username>"
  exit 1
fi

echo "==> Authenticated as GitHub user: $GH_USER"
echo "==> Ensuring repository $GH_USER/$REPO_NAME exists..."

curl -s -X POST \
  -H "Authorization: token $GH_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/user/repos \
  -d "{\"name\":\"$REPO_NAME\",\"description\":\"Astral AI V5.0.0 — Autonomous AI Agent for iOS with iOS 27 Liquid Glass & Local/Cloud Linux\",\"private\":false,\"auto_init\":false}" >/dev/null || true

cd "$(dirname "$0")"
if [ -d "AstralAI-V5.0.0-source" ]; then
  cd "AstralAI-V5.0.0-source"
fi

rm -rf .git
git init
git checkout -b main
git config user.name "$GH_USER"
git config user.email "$GH_USER@users.noreply.github.com"

git add -A
git commit -m "Release Astral AI V5.0.0 — iOS 27 Liquid Glass V5, Custom Vector Computer Icon, Enhanced Markdown & Linux FHS 5.0"
git tag -a v5.0.0 -m "Astral AI V5.0.0"

REMOTE_URL="https://${GH_USER}:${GH_TOKEN}@github.com/${GH_USER}/${REPO_NAME}.git"
git remote add origin "$REMOTE_URL"
git push -u origin main --force
git push origin v5.0.0 --force

echo "=============================================================================="
echo "SUCCESS! Source pushed to https://github.com/${GH_USER}/${REPO_NAME}"
echo "GitHub Actions is now building AstralAI-V5.0.0-unsigned.ipa and publishing"
echo "the v5.0.0 Release automatically at:"
echo "  https://github.com/${GH_USER}/${REPO_NAME}/actions"
echo "  https://github.com/${GH_USER}/${REPO_NAME}/releases/tag/v5.0.0"
echo "=============================================================================="
