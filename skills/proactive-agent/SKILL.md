---
name: proactive-agent
description: Proactive scheduling and reminder agent (Proactive Agent). Integrates with calendars, notifications and task stores to proactively surface actions and reminders.
---

# Proactive Agent

This skill provides proactive behavior: polling calendars/tasks, creating reminders, and notifying users. It is intended to run in a controlled environment with explicit domain and notification policies.

Integrations: calendar, notifications (Telegram/Email), task stores (Airtable/Notion).

Security: run in sandbox; explicit user approval required for actions that send messages or modify external resources.
