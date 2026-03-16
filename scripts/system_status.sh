#!/usr/bin/env bash
set -euo pipefail

# Build a robust PATH for non-interactive runners (launchd/cron/etc.).
build_runtime_path() {
  local -a candidates=(
    "/Applications/Codex.app/Contents/Resources"
    "$HOME/.local/bin"
    "/opt/homebrew/bin"
    "/usr/local/bin"
    "/usr/bin"
    "/bin"
    "/usr/sbin"
    "/sbin"
  )

  local dir
  shopt -s nullglob
  for dir in "$HOME"/.nvm/versions/node/*/bin; do
    candidates+=("$dir")
  done
  shopt -u nullglob

  for dir in "${candidates[@]}"; do
    [[ -d "$dir" ]] || continue
    case ":$PATH:" in
      *":$dir:"*) ;;
      *) PATH="$dir:$PATH" ;;
    esac
  done
  export PATH
}

build_runtime_path

ok() { printf "[OK] %s\n" "$1"; }
warn() { printf "[WARN] %s\n" "$1"; }
err() { printf "[ERR] %s\n" "$1"; }
section() { printf "\n== %s ==\n" "$1"; }

check_cmd() {
  local cmd="$1"
  local label="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$label: $(command -v "$cmd")"
    return 0
  fi
  err "$label: command not found"
  return 1
}

check_env_present() {
  local name="$1"
  if [[ -n "${!name-}" ]]; then
    ok "env $name: configured"
  else
    warn "env $name: not set"
  fi
}

check_env_optional_with_auth() {
  local name="$1"
  local auth_ok="$2"
  local label="$3"
  if [[ -n "${!name-}" ]]; then
    ok "env $name: configured"
  elif [[ "$auth_ok" == "1" ]]; then
    ok "env $name: not set (covered by active $label auth)"
  else
    warn "env $name: not set"
  fi
}

check_skill_dir() {
  local dir="$1"
  if [[ -d "$dir" ]]; then
    local count
    count="$(find "$dir" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')"
    ok "skills dir: $dir ($count skills)"
  else
    err "skills dir missing: $dir"
  fi
}

check_skill_installed() {
  local dir="$1"
  local skill="$2"
  if [[ -f "$dir/$skill/SKILL.md" ]]; then
    ok "skill $skill: installed"
  else
    warn "skill $skill: missing"
  fi
}

section "Core CLIs"
check_cmd codex "codex"
check_cmd clawhub "clawhub"
check_cmd gh "gh"
check_cmd gog "gog"

section "Versions"
codex --version 2>/dev/null | sed 's/^/[INFO] codex: /' || warn "codex version: unavailable"
clawhub --cli-version 2>/dev/null | sed 's/^/[INFO] clawhub: /' || warn "clawhub version: unavailable"
gh --version 2>/dev/null | head -n 1 | sed 's/^/[INFO] gh: /' || warn "gh version: unavailable"
gog --version 2>/dev/null | sed 's/^/[INFO] gog: /' || warn "gog version: unavailable"

section "Runtime model"
if [[ -f "/Users/roman/.codex/config.toml" ]]; then
  model_line="$(awk -F'=' '/^model[[:space:]]*=/{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); gsub(/"/, "", $2); print $2; exit}' /Users/roman/.codex/config.toml)"
  if [[ -n "${model_line:-}" ]]; then
    ok "configured model: $model_line"
  else
    warn "configured model: not found in config.toml"
  fi
else
  warn "config file missing: /Users/roman/.codex/config.toml"
fi

section "Skills"
SKILLS_DIR="/Users/roman/.codex/skills"
check_skill_dir "$SKILLS_DIR"
check_skill_installed "$SKILLS_DIR" "gog"
check_skill_installed "$SKILLS_DIR" "github-cli"
check_skill_installed "$SKILLS_DIR" "github-ops"
check_skill_installed "$SKILLS_DIR" "github-workflow"
check_skill_installed "$SKILLS_DIR" "github-issue-resolver"
check_skill_installed "$SKILLS_DIR" "gh-fix-ci"
check_skill_installed "$SKILLS_DIR" "gh-address-comments"
check_skill_installed "$SKILLS_DIR" "healthcheck"

section "Auth/Connections"
clawhub_auth_ok=0
gh_auth_ok=0
gog_auth_ok=0

if clawhub whoami --no-input >/dev/null 2>&1; then
  clawhub_auth_ok=1
  ok "clawhub auth: active"
else
  warn "clawhub auth: not logged in"
fi

if gh auth status >/dev/null 2>&1; then
  gh_auth_ok=1
  ok "github auth (gh): active"
else
  warn "github auth (gh): not logged in"
fi

if gog auth list --no-input >/dev/null 2>&1; then
  gog_auth_ok=1
  ok "gog auth: active"
else
  warn "gog auth: not configured"
fi

section "Token/Env Presence (values hidden)"
check_env_optional_with_auth GH_TOKEN "$gh_auth_ok" "GitHub"
check_env_optional_with_auth GITHUB_TOKEN "$gh_auth_ok" "GitHub"
check_env_optional_with_auth CLAWHUB_TOKEN "$clawhub_auth_ok" "ClawHub"
check_env_optional_with_auth CLAWDHUB_TOKEN "$clawhub_auth_ok" "ClawHub"
check_env_optional_with_auth GOG_ACCOUNT "$gog_auth_ok" "gog"

# OPENAI_API_KEY is optional in this workspace; Codex can run with native auth.
if [[ -n "${OPENAI_API_KEY-}" ]]; then
  ok "env OPENAI_API_KEY: configured"
else
  ok "env OPENAI_API_KEY: not set (optional)"
fi

# ANTHROPIC_API_KEY is required for openclaw-local agent (Claude Haiku).
if [[ -n "${ANTHROPIC_API_KEY-}" ]]; then
  ok "env ANTHROPIC_API_KEY: configured"
else
  warn "env ANTHROPIC_API_KEY: not set (required for openclaw-local agent)"
fi

section "Backups"
if launchctl print "gui/$(id -u)/com.roman.codex.backup" >/dev/null 2>&1; then
  local_exit="$(launchctl print "gui/$(id -u)/com.roman.codex.backup" 2>/dev/null | awk -F'= ' '/last exit code/ {print $2; exit}')"
  ok "launchd backup job: loaded (last exit code ${local_exit:-unknown})"
else
  warn "launchd backup job: not loaded"
fi

latest_backup="$(ls -1t /Users/roman/.codex/backups/codex-backup-*.tgz 2>/dev/null | head -n 1 || true)"
if [[ -n "$latest_backup" ]]; then
  ok "latest backup: $latest_backup"
else
  warn "latest backup: none found"
fi

section "Airtable"
airtable_token="${AIRTABLE_TOKEN-}"
if [[ -z "$airtable_token" && -n "${AIRTABLE_API_KEY-}" ]]; then
  airtable_token="${AIRTABLE_API_KEY-}"
fi
airtable_base="${AIRTABLE_BASE_ID-}"

if [[ -z "$airtable_token" || -z "$airtable_base" ]]; then
  warn "airtable check: skipped (set AIRTABLE_TOKEN/AIRTABLE_API_KEY and AIRTABLE_BASE_ID)"
else
  http_code="$(curl -sS -o /tmp/airtable_health.$$ -w '%{http_code}' \
    -H "Authorization: Bearer $airtable_token" \
    "https://api.airtable.com/v0/meta/bases/$airtable_base/tables" || true)"
  if [[ "$http_code" == "200" ]]; then
    ok "airtable check: API access OK"
  else
    warn "airtable check: API returned HTTP $http_code"
  fi
  rm -f /tmp/airtable_health.$$ 2>/dev/null || true
fi

echo
echo "System check complete."
