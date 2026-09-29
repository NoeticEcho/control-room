---
description: land-ready - land the READY sha, not a later head, by the checklist
max_turns: 12
allowed_tools: [Skill, Read, Glob, Grep]
---

The backend worker just wrote: `EPIC API-7 READY 3f2a9c1e0b7d4a6f8e2c5b9d1a3f7e6c4b2d8a0f https://github.com/acme/shop/pull/41`. Its brief's scope was services/api/. Since then it pushed one more commit to its branch claude/api-7-rate-limits, which merges main into it. The integration branch is main. Tell me, step by step, exactly what you will check and run to land it, with the commands. Don't run anything yet.
