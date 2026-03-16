# OpenClaw

This repository is the workspace scaffold for OpenClaw AgentSkills and automation.

What's included:
- skills/ — placeholder for skill definitions (healthcheck example)
- .github/workflows/ci.yml — basic CI to run tests
- package.json — minimal scripts for development

Next steps:
- Fill skills/* with SKILL.md and implementation code
- Configure CI tests and linting
- Use ClawHub CLI to publish skills

## GitHub shortcuts menu

Run interactive menu with ready-to-use prompts:

```bash
npm run gh:menu
```

Utilities:

```bash
bash scripts/github_shortcuts_menu.sh --list
bash scripts/github_shortcuts_menu.sh --prompt 3
```

## System check

Quick status of skills, auth, env presence, and backups:

```bash
npm test
# or
npm run check:system
```

## Telegram bridge

Trigger the same system check from Telegram.

```bash
# 1) export bot token
export TELEGRAM_BOT_TOKEN=...

# 2) find your chat id (send any message to your bot first)
npm run tg:chatid
# or auto-bind last chat id to env:
npm run tg:bind

# 3) set default chat id and send one report
export TELEGRAM_CHAT_ID=...
npm run tg:send

# 4) keep polling to react to messages: /test, /status, "тест", "проверка систем"
npm run tg:poll
```

Optional:

```bash
export TELEGRAM_ALLOWED_CHAT_ID=...
```
