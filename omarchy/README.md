# Prompt Shell Omarchy plugin

Bar widget that opens a prompt panel and runs `psh` in a terminal.

Do not install this repository with `omarchy plugin add`. That clones the whole CLI tree into the shell plugin directory. Use `psh install omarchy` instead.

## Install

```sh
psh install omarchy
omarchy plugin enable com.modoterra.promptshell
```

`psh install omarchy` also performs the XDG CLI install. Enabling the plugin is separate so bar layout stays under your control.

## Usage

Click **psh** on the bar, type a natural-language shell task, and press Enter. The panel launches `omarchy-launch-tui psh run <prompt>` so approval still happens in a real terminal.

## Remove

```sh
psh uninstall
```

That removes the plugin directory. Config under `~/.config/psh` stays unless you pass `--purge`.
