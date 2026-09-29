---
description: land-ready - several READY pull requests, one slow check, a generated lockfile
max_turns: 12
allowed_tools: [Skill, Read, Glob, Grep]
---

Three workers wrote READY at once: `EPIC API-7 READY 3f2a9c1e0b7d4a6f8e2c5b9d1a3f7e6c4b2d8a0f https://github.com/acme/shop/pull/41`, `EPIC WEB-4 READY 8c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d https://github.com/acme/shop/pull/42` and `EPIC DOC-2 READY 0a9b8c7d6e5f4a3b2c1d0e9f8a7b6c5d4e3f2a1b https://github.com/acme/shop/pull/43`. Our full check takes 40 minutes on the one machine we have. API-7 and WEB-4 each changed package-lock.json. Land all three on main: give me the plan and the commands, in order. Don't run anything yet.
