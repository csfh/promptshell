#!/usr/bin/env bash
# Install Prompt Shell (psh) into XDG directories. Does not install the Omarchy plugin.
# Plugin install: omarchy plugin add https://github.com/modoterra/promptshell.git

set -euo pipefail

if [[ $# -gt 0 ]]; then
  printf 'usage: install.sh\n' >&2
  exit 2
fi

script_path=${BASH_SOURCE[0]:-}
repo_psh=

if [[ -n $script_path && -f $script_path ]]; then
  script_dir=$(CDPATH= cd "$(dirname "$script_path")" && pwd)
  if [[ -f $script_dir/bin/psh.sh ]]; then
    repo_psh=$script_dir/bin/psh.sh
  fi
fi

if [[ -n $repo_psh ]]; then
  exec sh "$repo_psh" install
fi

raw_base=${PSH_RAW_BASE:-https://raw.githubusercontent.com/modoterra/promptshell/main}
source_url=$raw_base/bin/psh.sh
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
payload=$work_dir/psh.sh

if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$source_url" -o "$payload"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$payload" "$source_url"
else
  printf 'install.sh: curl or wget is required\n' >&2
  exit 2
fi

sh "$payload" install
