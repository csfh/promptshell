---
status: accepted
---

# Approval is a keypress on /dev/tty

A generated command runs only after `y` or `Y` on `/dev/tty`, and that keypress accepts the exact string on screen. Risk and `requires_approval` stay advisory. Harnesses start without a shell tool, so Codex, Grok, Claude, and Gemini can read the workspace and the command still comes back through this check. With no controlling terminal, stdout is the command and the exit status is 0. A decline exits non-zero.

The other candidates were a `--yes` flag and an edit step. Scripts need the command text on stdout, and the person at the terminal has to accept the string the provider returned.
