# Prompt Shell Omarchy plugin

Bar widget that opens a prompt panel and runs `psh` in a terminal.

## Install

```sh
omarchy plugin add https://github.com/modoterra/promptshell.git --enable
```

`omarchy plugin install` is the same command. This clones the repository as a Quickshell plugin. It does not install the `psh` CLI.

Install the CLI separately:

```sh
bash install.sh
```

Or:

```sh
curl -fsSL https://raw.githubusercontent.com/modoterra/promptshell/main/install.sh | bash
```

If you omit `--enable`:

```sh
omarchy plugin enable modoterra.promptshell
```

## Usage

Click **psh** on the bar, type a natural-language shell task, and press Enter. The panel launches `omarchy-launch-tui psh run <prompt>` so approval still happens in a real terminal.

## Remove

```sh
omarchy plugin remove modoterra.promptshell
psh uninstall
```
