# Owner interview: what to decide before the build

The master prompt asks all of this itself. This list is for an owner who wants to prepare, or to answer in writing.

1. **Goal and milestone**
   - What are you building, in one paragraph?
   - Which nearest result will show that it works? (e.g. "the site is open to its first users")
2. **Directions of work (worker profiles)**
   - Which parts can move independently? Name 2–6.
   - For each: which folders or modules are its, which tools it needs (languages, databases, a browser for checks)?
   - Which is most urgent? The pilot starts there.
3. **Runners**
   - Claude Code cloud sessions, Codex cloud tasks, e2b sandboxes, local worktrees, or a mix? Which plan and limits?
   - Where will the coordinator run, and on how many cores? It sets the speed of landings.
4. **Tracker**: beads (bd), GitHub Issues, Linear, Jira, other? Are there tasks to move over?
5. **Decision desk**
   - Where do you like to answer: GitHub, a static page, Notion, Telegram, a claude.ai artifact?
   - How often should waiting decisions be raised? (default: hourly)
6. **Branches and releases**
   - Main branch, integration branch, the workers' branch prefix?
   - Are there versions and releases, and who decides when?
7. **Checks**
   - What must pass before code reaches the integration branch? How long does the full check take?
   - May the coordinator skip rerunning it when the worker ran it and the merge is clean?
8. **Boundaries**
   - Which files change only with your approval? (usually: agent instructions, CI, dependencies, configuration, architecture decisions)
   - What may the coordinator decide alone?
9. **Secrets and services**
   - Which services are needed (databases, APIs, hosting), and where are the credentials kept?
   - Confirm: secrets never reach chats or worker environments.
