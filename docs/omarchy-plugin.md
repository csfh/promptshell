# Prompt Shell Omarchy plugin

Bar widget that opens a prompt panel and runs the bundled CLI in a terminal. Putting `psh` on `PATH` is optional for Omarchy users. The standalone CLI install (`install.sh`) does not require Omarchy.

## Install

```sh
omarchy plugin add https://github.com/csfh/promptshell.git --enable
```

`omarchy plugin install` is the same command. This clones the repository as a Quickshell plugin. It does not put `psh` on `PATH`.

If you omit `--enable`:

```sh
omarchy plugin enable com.csfh.promptshell
```

Optional PATH install, if you also want `psh` in a regular terminal:

```sh
bash install.sh
```

Or:

```sh
curl -fsSL https://raw.githubusercontent.com/csfh/promptshell/main/install.sh | bash
```

## Usage

Click **psh** on the bar, type a natural-language shell task, and press Enter. The panel launches `omarchy-launch-tui` with the plugin's `bin/psh.sh`, so approval still happens in a real terminal without a PATH install.

## Remove

```sh
omarchy plugin remove com.csfh.promptshell
```

If you installed the optional CLI:

```sh
psh uninstall
```
