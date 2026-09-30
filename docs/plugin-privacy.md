# Privacy: the control-room plugin

This page covers `noetic-control-room`, the Claude plugin in
[`plugin/`](../plugin/README.md), made by NoeticEcho.

**The plugin collects nothing and sends nothing to NoeticEcho.** It has no
server, no telemetry, no analytics and no account. It stores no data of its
own, and it asks you for no token or password.

**What it does instead.** Its skills tell Claude to run commands on your
machine, with your permission, through tools you already use and already
signed in to:

- `git`, on your own repository; `git push` sends a landing to your own
  remote, after you say yes;
- `gh`, the GitHub CLI, which reads your pull requests and CI runs and
  writes the desk's issues, comments and labels in the repository you work
  in;
- Claude Code, which runs the plugin, and `claude -p --cloud`, which sends a
  brief to your own Claude Code cloud session, after you say yes.

What those tools send, and what is kept, is governed by their providers'
policies, not by NoeticEcho: GitHub's
[privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement)
and Anthropic's [privacy policy](https://www.anthropic.com/legal/privacy).
The plugin's [README](../plugin/README.md) lists every command it runs and
where each one sends data, and its "Credentials" section says whose sign-in
each one uses.

**This documentation site** loads no analytics and no third-party scripts,
and sets no cookies. It remembers only your choice of light or dark theme,
in your browser's local storage.

**Questions** go to the repository's issues:
<https://github.com/NoeticEcho/control-room/issues>.
