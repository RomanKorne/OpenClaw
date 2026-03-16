# OpenClaw Telegram Integration Report (2026-03-13)

## Objective
Configure and stabilize Telegram integration for OpenClaw system checks (`тест` / `/test`) with autonomous diagnostics and fix cycle.

## Work Performed
1. Telegram bridge created and wired into npm scripts.
2. Environment-based config enabled via `~/.codex/telegram.env`.
3. Numeric chat binding completed (`TELEGRAM_CHAT_ID` + `TELEGRAM_ALLOWED_CHAT_ID`).
4. Launchd background service configured and restarted.
5. `sendMessage` validation added (script now fails explicitly on Telegram API errors).
6. API error handling hardened (no more `jq` null-iteration crash).
7. Added auto bind command (`tg:bind`) to map last incoming chat ID to env file.

## Root Causes Found
1. Commands were launched from wrong directory/host (`/root` on VPS) where `package.json` is absent.
2. Non-numeric `TELEGRAM_CHAT_ID` (username instead of numeric id) caused `chat not found`.
3. Duplicate/parallel `getUpdates` consumers caused intermittent conflict logs.

## Detailed Correction Instruction
1. Use local project path:
   - `cd /Users/roman/Projects/OpenClaw/OpenClaw-meta`
2. Ensure env file exists and is filled:
   - `/Users/roman/.codex/telegram.env`
   - Required keys: `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`, `TELEGRAM_ALLOWED_CHAT_ID`
3. Restart background bridge:
   - `launchctl kickstart -k gui/$(id -u)/com.roman.codex.telegram.bridge`
4. Validate one-shot send:
   - `npm run -s tg:send`
5. Validate chat-id binding utility (if needed):
   - Send any message to bot in Telegram
   - `npm run -s tg:bind`

## Final Validation Cycle
### Final Test 1 (PASS)
- Command: `npm run -s tg:send`
- Result: Report delivered successfully.

### Final Test 2 (PASS)
- Command: direct Telegram API `sendMessage` using configured bot token and chat id
- Result: `ok=true`, message delivered.

## Current State
- Telegram bridge service is running via launchd.
- Integration is operational.
- System check command remains available via `npm test` / `npm run check:system`.

## Residual Note
- Periodic `getUpdates` conflict is still observed in bridge logs, which indicates at least one additional consumer polling the same bot token in parallel.

### Final Hard-Fix (to remove conflicts completely)
1. Stop any other process using this bot token (other terminals/servers/workers).
2. In BotFather run `/revoke` for this bot to generate a fresh token.
3. Update `/Users/roman/.codex/telegram.env` with the new token.
4. Restart bridge:
   - `launchctl kickstart -k gui/$(id -u)/com.roman.codex.telegram.bridge`
5. Re-run:
   - `npm run -s tg:send`
   - Send `тест` to the bot and verify one response.
