#!/usr/bin/env bash
set -euo pipefail

show_menu() {
  cat <<'EOF'
GitHub Shortcuts Menu
=====================
1. triage issue
   Быстро понять, что чинить первым.
   Подсказка: repo=<owner/repo>, окно=<7d|14d>, max=<20>

2. review PR + risks
   Не пропустить поломки до релиза.
   Подсказка: repo=<owner/repo>, окно=<7d>, include=<open,merged>

3. fix CI
   Быстро поднять красный pipeline.
   Подсказка: repo=<owner/repo>, branch=<main|feature/*>, run=<id|latest>

4. workflow
   Автоматически держать CI в порядке.
   Подсказка: stack=<node|python|go>, jobs=<lint,test,build>

5. release readiness
   Выпускать без хаоса.
   Подсказка: repo=<owner/repo>, version=<semver>, from=<tag|date>

q. Выход
EOF
}

get_prompt() {
  case "${1:-}" in
    1)
      cat <<'EOF'
Сделай triage по открытым issue в репозитории <owner/repo>: разложи по приоритету, риску регрессий и дай план фиксов на 1 спринт. Окно анализа: <7d|14d>. Лимит: <20>.
EOF
      ;;
    2)
      cat <<'EOF'
Проверь последние PR в <owner/repo> (open + merged за <7d>): выдели риски (security, data-loss, perf, compatibility), укажи что обязательно протестировать перед релизом.
EOF
      ;;
    3)
      cat <<'EOF'
Разбери упавший CI в <owner/repo> для ветки <branch> (run=<id|latest>): найди root cause, предложи минимальный фикс и подготовь патч.
EOF
      ;;
    4)
      cat <<'EOF'
Сгенерируй/обнови GitHub Actions workflow для <stack> проекта: jobs=<lint,test,build>, кэширование зависимостей, fail-fast, и короткий summary в конце.
EOF
      ;;
    5)
      cat <<'EOF'
Сделай release readiness check для <owner/repo> перед версией <semver>: changelog, breaking changes, миграции, semver-check и draft release notes.
EOF
      ;;
    *)
      return 1
      ;;
  esac
}

copy_to_clipboard_if_possible() {
  local text="$1"
  if command -v pbcopy >/dev/null 2>&1; then
    printf '%s' "$text" | pbcopy
    echo
    echo "Скопировано в буфер обмена."
  elif command -v xclip >/dev/null 2>&1; then
    printf '%s' "$text" | xclip -selection clipboard
    echo
    echo "Скопировано в буфер обмена."
  else
    echo
    echo "Буфер обмена не найден (pbcopy/xclip). Скопируй текст вручную."
  fi
}

if [[ "${1:-}" == "--list" ]]; then
  show_menu
  exit 0
fi

if [[ "${1:-}" == "--prompt" ]]; then
  if [[ -z "${2:-}" ]]; then
    echo "Usage: $0 --prompt <1..5>" >&2
    exit 1
  fi
  get_prompt "$2"
  exit 0
fi

show_menu
printf "\nВыбери пункт (1-5 или q): "
read -r choice

if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
  echo "Пока."
  exit 0
fi

if ! prompt="$(get_prompt "$choice")"; then
  echo "Неверный выбор: $choice" >&2
  exit 1
fi

echo
echo "Готовый промпт:"
echo "--------------"
echo "$prompt"

copy_to_clipboard_if_possible "$prompt"
