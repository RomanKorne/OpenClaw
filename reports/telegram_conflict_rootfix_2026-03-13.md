# Telegram Root-Fix Report (2026-03-13)

## Symptom
Bot returned irrelevant summaries and system-check trigger in Telegram was unstable.

## Root Cause
A second Telegram consumer was active on VPS and used the same bot token.
This created Bot API `409 Conflict` for `getUpdates`, so updates were racing between systems.

## Evidence Collected
1. Local bridge stopped fully, but `getUpdates` still returned `409 Conflict`.
2. VPS OpenClaw config had Telegram channel enabled with same bot token:
   - `/opt/openclaw/openclaw.json` -> `channels.telegram.botToken`.

## Actions Applied
1. On VPS:
   - Backed up `/opt/openclaw/openclaw.json`.
   - Set `channels.telegram.enabled=false`.
   - Cleared `channels.telegram.botToken`.
   - Restarted gateway container.
2. On Mac:
   - Restarted local launchd bridge `com.roman.codex.telegram.bridge`.
   - Cleared and monitored bridge logs.

## Final Validation
### Test 1 (PASS)
- `npm run -s tg:send`
- System report delivered.

### Test 2 (PASS)
- Direct Telegram API `sendMessage`
- Response `ok=true`.

### Health
- `launchd` bridge state: `running`
- `bridge.err.log`: `0` lines after final restart

## Operating Rule (Important)
Only one consumer may poll `getUpdates` for a bot token.
If you ever need VPS Telegram again, use a different token or disable local bridge first.
