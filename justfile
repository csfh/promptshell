set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

bats := "node_modules/bats/bin/bats"

default:
    @just --list

deps:
    npm install

syntax:
    sh -n bin/psh.sh
    bash -n install.sh
    bash -n tests/helpers/psh.bash

test: syntax
    @test -x {{ bats }} || { printf '%s\n' 'missing Bats runner; run `npm install`' >&2; exit 2; }
    @command -v setsid >/dev/null 2>&1 || { printf '%s\n' 'setsid is required for tests' >&2; exit 2; }
    @command -v script >/dev/null 2>&1 || { printf '%s\n' 'script is required for tests' >&2; exit 2; }
    {{ bats }} tests

install-smoke:
    #!/usr/bin/env bash
    set -euo pipefail
    data_home=$(mktemp -d)
    install_dir=$(mktemp -d)
    XDG_DATA_HOME=$data_home PSH_INSTALL_DIR=$install_dir bash install.sh
    test -x "$install_dir/psh"
    test -x "$data_home/psh/psh.sh"
    XDG_DATA_HOME=$data_home PSH_INSTALL_DIR=$install_dir "$install_dir/psh" uninstall
    test ! -e "$install_dir/psh"
    test ! -e "$data_home/psh/psh.sh"
