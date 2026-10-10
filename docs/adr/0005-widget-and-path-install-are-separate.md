---
status: accepted
---

# The widget and the PATH install are separate copies

The Omarchy bar widget launches the bundled `bin/psh.sh` from the plugin checkout. The XDG install writes a payload under `${XDG_DATA_HOME:-$HOME/.local/share}/psh` and a launcher on `PATH` that execs that payload. `install.sh` installs the CLI. It does not install the plugin.

The widget has to open when `psh` is absent from `PATH`. Each copy updates on its own path.
