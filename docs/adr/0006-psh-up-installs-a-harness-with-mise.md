---
status: accepted
---

# psh up installs a harness with mise

`psh up` takes one harness id: `codex`, `grok`, `claude`, or `gemini`. It runs `mise use -y -g <id>@latest`, which installs the tool and records `latest` in the user's global mise config. `-y` answers mise's confirmation prompts so the command can run without a controlling terminal. mise must already be on `PATH`. `psh` does not install mise. Running `up` again upgrades that harness. A missing mise, a missing id, an extra argument, or a hosted provider name exits 2. If mise fails, the config file is left as it was.

After a successful install, `psh` saves that harness as the provider and sets the model to the harness default. An existing API key stays in the file. A missing config file is created at `${XDG_CONFIG_HOME:-$HOME/.config}/psh/config.json` with mode 600 and an empty `api_key`. `PSH_PROVIDER` still overrides one run. Sign-in stays with the harness.

Later runs use the harness command lines already in the CLI. `psh` takes the binary from `PATH` when `command -v` finds it, and otherwise uses the path from `mise which`. If neither yields a binary, the run exits 2.

`mise install` by itself would leave the binary off `PATH`. A global `mise use` matches a tool the user runs from any directory.
