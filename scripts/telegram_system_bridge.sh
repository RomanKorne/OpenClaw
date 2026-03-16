#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${TELEGRAM_ENV_FILE:-$HOME/.codex/telegram.env}"
BOT_TOKEN=""
DEFAULT_CHAT_ID=""
ALLOWED_CHAT_ID=""
API_BASE=""
STATE_DIR="${HOME}/.codex/telegram"
OFFSET_FILE="${STATE_DIR}/last_offset"
RKS_URL="http://localhost:8000"
RKS_TOKEN=""

load_env() {
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
  fi
  BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
  DEFAULT_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
  ALLOWED_CHAT_ID="${TELEGRAM_ALLOWED_CHAT_ID:-}"
  RKS_URL="${RKS_URL:-http://localhost:8000}"
  RKS_TOKEN="${RKS_WEBHOOK_TOKEN:-}"
}

require_bin() {
  local bin="$1"
  command -v "$bin" >/dev/null 2>&1 || {
    echo "Missing required command: $bin" >&2
    exit 1
  }
}

init_api() {
  load_env
  if [[ -z "$BOT_TOKEN" ]]; then
    echo "Set TELEGRAM_BOT_TOKEN first (env or $ENV_FILE)." >&2
    exit 1
  fi
  API_BASE="https://api.telegram.org/bot${BOT_TOKEN}"
}

run_system_check() {
  (
    cd "$ROOT_DIR"
    npm run -s check:system
  )
}

send_text() {
  local chat_id="$1"
  local text="$2"

  # Telegram limit is 4096 chars; keep headroom.
  while [[ -n "$text" ]]; do
    local chunk="${text:0:3800}"
    text="${text:3800}"
    local resp
    resp="$(curl -sS -X POST "${API_BASE}/sendMessage" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg chat_id "$chat_id" --arg text "$chunk" \
            '{chat_id:$chat_id, text:$text}')")"
    local ok_flag
    ok_flag="$(echo "$resp" | jq -r '.ok // false')"
    if [[ "$ok_flag" != "true" ]]; then
      local desc
      desc="$(echo "$resp" | jq -r '.description // "sendMessage failed"')"
      echo "Telegram send error: $desc" >&2
      return 1
    fi
  done
}

_rks_curl() {
  # Usage: _rks_curl METHOD endpoint [payload] [timeout]
  local method="$1" endpoint="$2" payload="${3:-}" timeout="${4:-30}"
  local args=(-sS -X "$method" "${RKS_URL}/api/${endpoint}"
              --connect-timeout 5 --max-time "$timeout")
  [[ "$method" != "GET" ]] && args+=(-H "Content-Type: application/json")
  [[ -n "$RKS_TOKEN" ]]    && args+=(-H "X-RKS-Token: $RKS_TOKEN")
  [[ -n "$payload" ]]      && args+=(-d "$payload")
  curl "${args[@]}"
}

call_rks_webhook() {
  local chat_id="$1"
  local text="$2"
  local mode="${3:-sun}"

  local payload resp reply err
  payload="$(jq -n --arg msg "$text" --arg mode "$mode" '{message:$msg,mode:$mode}')"

  resp="$(_rks_curl POST webhook "$payload" 60)" || {
    send_text "$chat_id" "⚠ RKS недоступен. Запущен?"
    return 1
  }

  reply="$(echo "$resp" | jq -r '.reply // empty' 2>/dev/null)"
  if [[ -z "$reply" ]]; then
    err="$(echo "$resp" | jq -r '.error // "нет ответа"' 2>/dev/null || echo "нет ответа")"
    send_text "$chat_id" "⚠ RKS: $err"
    return 1
  fi

  send_text "$chat_id" "$reply"
}

call_rks_compass() {
  local chat_id="$1"
  local resp narrative

  resp="$(_rks_curl GET rks "" 30)" || {
    send_text "$chat_id" "⚠ RKS недоступен."
    return 1
  }

  narrative="$(echo "$resp" | jq -r '.narrative // empty' 2>/dev/null)"

  if [[ -z "$narrative" ]]; then
    resp="$(_rks_curl POST rks "" 90)" || {
      send_text "$chat_id" "⚠ RKS Compass недоступен."
      return 1
    }
    narrative="$(echo "$resp" | jq -r '.narrative // "нет данных"' 2>/dev/null)"
  fi

  send_text "$chat_id" "◈ COMPASS
${narrative}"
}

send_system_report() {
  local chat_id="$1"
  local report
  report="$(run_system_check 2>&1)"
  local header
  header="OpenClaw system check ($(date '+%Y-%m-%d %H:%M:%S'))"
  send_text "$chat_id" "$header"
  send_text "$chat_id" "$report"
}

get_updates() {
  local offset="$1"
  local timeout="${2:-30}"
  curl -sS "${API_BASE}/getUpdates?timeout=${timeout}&offset=${offset}"
}

print_api_error_if_any() {
  local res="$1"
  local is_ok
  is_ok="$(echo "$res" | jq -r '.ok // false')"
  if [[ "$is_ok" != "true" ]]; then
    local desc
    desc="$(echo "$res" | jq -r '.description // "unknown Telegram API error"')"
    echo "Telegram API error: $desc" >&2
    return 1
  fi
  return 0
}

upsert_env_var() {
  local key="$1"
  local value="$2"
  mkdir -p "$(dirname "$ENV_FILE")"
  touch "$ENV_FILE"
  chmod 600 "$ENV_FILE"

  local tmp
  tmp="$(mktemp)"
  if rg -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
    awk -v k="$key" -v v="$value" '
      BEGIN { done=0 }
      $0 ~ ("^" k "=") { print k "=" v; done=1; next }
      { print }
      END { if (!done) print k "=" v }
    ' "$ENV_FILE" > "$tmp"
  else
    cat "$ENV_FILE" > "$tmp"
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
  fi
  mv "$tmp" "$ENV_FILE"
}

bind_chat_id_from_updates() {
  init_api
  local res
  res="$(get_updates 0)"
  print_api_error_if_any "$res" || exit 1

  local chat_id
  chat_id="$(echo "$res" | jq -r '[((.result // [])[] | select(.message != null) | .message.chat.id)] | last // empty')"
  if [[ -z "$chat_id" ]]; then
    echo "No messages found yet. Send any message to the bot, then run bind-chat again." >&2
    exit 1
  fi

  upsert_env_var TELEGRAM_CHAT_ID "$chat_id"
  upsert_env_var TELEGRAM_ALLOWED_CHAT_ID "$chat_id"
  echo "Bound TELEGRAM_CHAT_ID and TELEGRAM_ALLOWED_CHAT_ID to: $chat_id"
}

print_chat_ids() {
  init_api
  local res
  res="$(get_updates 0)"
  print_api_error_if_any "$res" || exit 1
  echo "$res" | jq -r '
    (.result // [])[]
    | select(.message != null)
    | [
        (.update_id|tostring),
        (.message.chat.id|tostring),
        (.message.chat.type // "unknown"),
        (.message.chat.username // "-"),
        (.message.from.username // "-"),
        (.message.text // "")
      ]
    | @tsv
  ' | sed 's/\t/ | /g'
}

should_trigger_check() {
  local msg="$1"
  [[ "$msg" == "/test" ]] \
    || [[ "$msg" == "/Test" ]] \
    || [[ "$msg" == "/TEST" ]] \
    || [[ "$msg" == "/status" ]] \
    || [[ "$msg" == "/Status" ]] \
    || [[ "$msg" == "/STATUS" ]] \
    || [[ "$msg" == *"тест"* ]] \
    || [[ "$msg" == *"Тест"* ]] \
    || [[ "$msg" == *"ТЕСТ"* ]] \
    || [[ "$msg" == *"проверка систем"* ]] \
    || [[ "$msg" == *"Проверка систем"* ]] \
    || [[ "$msg" == *"ПРОВЕРКА СИСТЕМ"* ]] \
    || [[ "$msg" == *"system check"* ]] \
    || [[ "$msg" == *"System check"* ]] \
    || [[ "$msg" == *"SYSTEM CHECK"* ]]
}

load_saved_offset() {
  if [[ -f "$OFFSET_FILE" ]]; then
    local val
    val="$(tr -d '[:space:]' < "$OFFSET_FILE" 2>/dev/null || true)"
    if [[ "$val" =~ ^[0-9]+$ ]]; then
      echo "$val"
      return 0
    fi
  fi
  return 1
}

save_offset() {
  local offset="$1"
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$offset" > "$OFFSET_FILE"
}

bootstrap_offset_from_latest() {
  local res
  res="$(get_updates 0 1)"
  print_api_error_if_any "$res" || return 1

  local max_seen
  max_seen="$(echo "$res" | jq -r '[((.result // [])[] | .update_id)] | max // empty')"
  if [[ -n "$max_seen" ]]; then
    echo $((max_seen + 1))
  else
    echo 0
  fi
}

poll_loop() {
  local lock_dir="/tmp/openclaw_telegram_poll.lock"
  local pid_file="${lock_dir}/pid"

  if ! mkdir "$lock_dir" 2>/dev/null; then
    local lock_pid=""
    if [[ -f "$pid_file" ]]; then
      lock_pid="$(tr -d '[:space:]' < "$pid_file" 2>/dev/null || true)"
    fi

    if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
      echo "Another poll instance is already running (pid=$lock_pid). Exit." >&2
      exit 1
    fi

    if [[ -n "$lock_pid" ]]; then
      # Pid file exists but process is gone: stale lock, reclaim.
      rm -rf "$lock_dir" 2>/dev/null || true
      if ! mkdir "$lock_dir" 2>/dev/null; then
        echo "Failed to acquire poll lock at $lock_dir" >&2
        exit 1
      fi
    else
      # No pid file: avoid reclaim races on concurrent startup.
      local now_ts lock_ts lock_age
      now_ts="$(date +%s)"
      lock_ts="$(stat -f '%m' "$lock_dir" 2>/dev/null || echo "$now_ts")"
      lock_age=$((now_ts - lock_ts))
      if (( lock_age >= 30 )); then
        rm -rf "$lock_dir" 2>/dev/null || true
        if ! mkdir "$lock_dir" 2>/dev/null; then
          echo "Failed to acquire poll lock at $lock_dir" >&2
          exit 1
        fi
      else
        echo "Another poll instance is likely starting/running. Exit." >&2
        exit 1
      fi
    fi
  fi
  printf '%s\n' "$$" > "$pid_file"
  trap 'rm -f "$pid_file" 2>/dev/null || true; rmdir "$lock_dir" 2>/dev/null || true' EXIT

  init_api
  local offset
  if ! offset="$(load_saved_offset)"; then
    if ! offset="$(bootstrap_offset_from_latest)"; then
      offset=0
    fi
  fi
  echo "Telegram polling started. Commands: /rks, /week, /test. Regular messages → Sashimi. offset=${offset}"

  while true; do
    local res
    res="$(get_updates "$offset")"
    if ! print_api_error_if_any "$res"; then
      sleep 3
      continue
    fi

    local max_seen
    max_seen="$(echo "$res" | jq -r '[((.result // [])[] | .update_id)] | max // empty')"
    if [[ -n "$max_seen" ]]; then
      offset=$((max_seen + 1))
      save_offset "$offset"
    fi

    while IFS=$'\t' read -r upd_id chat_id text; do
      [[ -z "$upd_id" || -z "$chat_id" ]] && continue

      if [[ -n "$ALLOWED_CHAT_ID" && "$chat_id" != "$ALLOWED_CHAT_ID" ]]; then
        continue
      fi

      if should_trigger_check "$text"; then
        send_system_report "$chat_id" || echo "Failed to send report to ${chat_id}" >&2
      elif [[ "$text" == "/rks" || "$text" == "/compass" ]]; then
        call_rks_compass "$chat_id" || true
      elif [[ "$text" == "/week" || "$text" == "/weekly" ]]; then
        call_rks_webhook "$chat_id" "/week" "command" || true
      elif [[ -n "$text" && "$text" != /* ]]; then
        call_rks_webhook "$chat_id" "$text" "sun" || true
      elif [[ -n "$text" ]]; then
        # Любая /команда не обработанная выше → command mode
        call_rks_webhook "$chat_id" "$text" "command" || true
      fi
    done < <(
      echo "$res" | jq -r '
        (.result // [])[]
        | select(.message != null)
        | [
            (.update_id|tostring),
            (.message.chat.id|tostring),
            (.message.text // "")
          ]
        | @tsv
      '
    )
  done
}

send_once() {
  init_api
  local chat_id="${1:-$DEFAULT_CHAT_ID}"
  if [[ -z "$chat_id" ]]; then
    echo "Set TELEGRAM_CHAT_ID or pass chat_id as an argument." >&2
    exit 1
  fi
  send_system_report "$chat_id"
}

usage() {
  cat <<'EOF'
Usage:
  bash scripts/telegram_system_bridge.sh send [chat_id]
  bash scripts/telegram_system_bridge.sh poll
  bash scripts/telegram_system_bridge.sh get-chat-id
  bash scripts/telegram_system_bridge.sh bind-chat
  bash scripts/telegram_system_bridge.sh local

Required env:
  TELEGRAM_BOT_TOKEN

Optional env:
  TELEGRAM_CHAT_ID         Default chat for "send"
  TELEGRAM_ALLOWED_CHAT_ID Restrict poll responses to one chat id
EOF
}

main() {
  require_bin curl
  require_bin jq
  require_bin npm

  local cmd="${1:-}"
  case "$cmd" in
    send)
      send_once "${2:-}"
      ;;
    poll)
      poll_loop
      ;;
    get-chat-id)
      print_chat_ids
      ;;
    bind-chat)
      bind_chat_id_from_updates
      ;;
    local)
      run_system_check
      ;;
    -h|--help|help|"")
      usage
      ;;
    *)
      echo "Unknown command: $cmd" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
