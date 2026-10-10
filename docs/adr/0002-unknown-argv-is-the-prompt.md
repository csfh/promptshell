---
status: accepted
---

# Unknown argv is the prompt

Any argv that is not a known subcommand is the prompt, so `psh clean up docker` runs. The known names are `run`, `setup`, `install`, `update`, `uninstall`, `help`, and `up`.

Reserving names is the cost. A future subcommand has to be added to the known set, or people will keep typing it as a task.
