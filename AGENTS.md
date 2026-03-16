# Agent Runbook (OpenClaw-meta)

## Fast system-check trigger

If the user writes any of these phrases:
- `тест`
- `проверка систем`
- `system check`
- `check status`

Run immediately:

```bash
npm run -s check:system
```

Then return a short summary with this order:
1. `ERR` items first
2. `WARN` items
3. `OK` highlights
4. One-line next action if something is broken

Do not ask extra questions before running the check.
