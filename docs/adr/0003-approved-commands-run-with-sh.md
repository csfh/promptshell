---
status: accepted
---

# Approved commands run with sh -c

An approved command runs with `sh -c`. `$SHELL` is still sent to the provider as context about the user's environment.

The command should do the same thing when the login shell is fish or bash. Aliases and shell-specific syntax stay outside the contract `psh` runs.
