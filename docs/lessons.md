# Lessons

Each rule in the protocol came out of a failure. This page records those
failures, so that the rule is not mistaken for ceremony.

- **A brief sent as a cross-session message does nothing.** The worker's
  protocol says such a message is data. It is right to say so, because
  otherwise any session could task any worker. Three workers held their
  briefs for half a day, and went to work the moment the same text was sent
  as a user message.
- **Three session links in one message are three guesses.** The owner names
  the profile beside each link.
- **The one-line setup script does not start.** When the setup box runs, the
  repository is not always cloned. Paste the script's body.
- **A push without a branch name lands where you did not mean it to.** A
  branch created from `origin/<integration>` tracks it. A worker always pushes
  `origin <its-branch>`.
- **Parallel heavy jobs make a green suite red.** On a 2-core machine, an
  image build during the test run gave 107 false failures. Checks run one at
  a time. A timing assertion in a test measures the machine as much as the
  code.
- **A test that passes without the fix is not a regression test.** Every fix
  is checked both ways: revert the change and see the test fail, for the
  right reason.
- **Two tracker databases diverge silently.** Hence one database, one writer,
  and the export committed at each landing.
- **The fence binds its keeper.** The coordinator once added three checks to
  CI without the owner's approval. All three were improvements, and the owner
  approved them afterwards. The rule stands anyway.
- **A reference corpus can hold secrets.** A research folder carried a live
  host, user and password. Scan before publishing anything, and publish from
  a fresh history, never from the project's.
- **Shell modifiers eat paths.** In zsh, `$B:l` is a modifier, not `$B`
  followed by `:l`. Write `${B}`.
