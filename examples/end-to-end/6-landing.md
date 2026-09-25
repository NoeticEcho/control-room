# Landing wc-3

The coordinator's notes, by the landing checklist in docs/protocol.md.
Written by replay.sh from what the commands returned.

1. **Head and handoff.** `origin/claude/wc-3-count-words` is `bc20c175b461ac96643b6212e15d7939dc0f05d7`,
   the READY sha. The handoff there has status `ready`. Its lane ran at
   `c25fff009a37aa7cc3e776209868cc786fff6f43`; between that and the READY sha only these files changed:
   `handoff/wc-3.json runs/run-wc-3-1.json` (handoff and run files only).
2. **Scope.** Changed against main: `README.md check.sh handoff/wc-3.json runs/run-wc-3-1.json wordcount`. All inside the brief's scope
   (`wordcount check.sh README.md handoff/ runs/`); no grants were given.
3. **Security-sensitive.** Nothing: no access policy, no user text rendered,
   no configuration, nothing that looks like a secret.
4. **Merge** with `--no-ff` in a throwaway clone: `9baab710c16d4e16b1ce110f86601b5b3037a2f1`.
5. **Checks.** `sh check.sh` on the merge:

   ```text
   ok lines
   ok words
   ```

6. **Push** with an explicit refspec: `git push origin HEAD:refs/heads/main`.
   `main` is now `9baab710c16d4e16b1ce110f86601b5b3037a2f1`.
7. **CI.** The toy has no CI; on a real repository, read the run for
   `9baab710c16d4e16b1ce110f86601b5b3037a2f1` before going on.
8. **Close and file.**
   - wc-3.1 closed, with `c25fff009a37aa7cc3e776209868cc786fff6f43` and the run `run-wc-3-1` in the reason.
   - wc-3.2 stays open: it waits on the owner. Desk card `wc-3-unicode` made
     from the handoff's question (7-desk/).
   - The discovered item ("`sh wordcount file` silently ignores the
     argument") filed as a new task.
   - The worker's next brief opens with: wc-3 landed at `9baab710c16d4e16b1ce110f86601b5b3037a2f1`; wc-3.2
     waits on the desk; the argument bug is a new task.
