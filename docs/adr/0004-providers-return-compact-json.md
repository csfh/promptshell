---
status: accepted
---

# Providers return compact JSON

A provider result is compact JSON. It is either a command, carrying risk and explanation, or a clarification question. `psh` strips `<think>` blocks before parsing. Invalid JSON fails the run.

That object is how a provider asks a question, and how reasoning text stays out of the command string.
