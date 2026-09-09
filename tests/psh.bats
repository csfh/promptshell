#!/usr/bin/env bats

load 'helpers/psh'

setup() {
  setup_psh_test
}

teardown() {
  teardown_psh_test
}

@test "help prints usage" {
  run psh --help

  assert_status 0
  [[ "$output" == *"usage: psh"* ]]
  [[ "$output" == *"psh [-v|-vv|-vvv] run PROMPT"* ]]
  [[ "$output" == *"psh install"* ]]
  [[ "$output" == *"psh update"* ]]
  [[ "$output" == *"psh uninstall"* ]]
  [[ "$output" != *"psh install omarchy"* ]]
}

@test "omarchy panel launches bundled CLI rather than PATH psh" {
  [[ -f "$PSH_REPO_ROOT/Panel.qml" ]]
  grep -q 'Qt.resolvedUrl("bin/psh.sh")' "$PSH_REPO_ROOT/Panel.qml"
  grep -q 'omarchy-launch-tui' "$PSH_REPO_ROOT/Panel.qml"
  grep -q 'bundledPshPath()' "$PSH_REPO_ROOT/Panel.qml"
  if grep -q 'execDetached(\["omarchy-launch-tui", "psh"' "$PSH_REPO_ROOT/Panel.qml"; then
    printf 'panel must not launch PATH psh\n' >&2
    return 1
  fi
}

@test "install writes XDG payload, launcher, and completion" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" install

  assert_status 0
  [[ "$output" == *"payload $data_home/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [[ "$output" == *"completion $data_home/bash-completion/completions/psh"* ]]
  [ -x "$data_home/psh/psh.sh" ]
  [ -x "$bin_home/psh" ]
  [ -f "$data_home/bash-completion/completions/psh" ]
  [ ! -e "$data_home/psh/omarchy" ]

  run "$bin_home/psh" --help

  assert_status 0
  [[ "$output" == *"usage: psh"* ]]
}

@test "install writes payload launcher and completion modes" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" install

  assert_status 0
  [ "$(stat -c '%a' "$data_home/psh/psh.sh")" = 755 ]
  [ "$(stat -c '%a' "$bin_home/psh")" = 755 ]
  [ "$(stat -c '%a' "$data_home/bash-completion/completions/psh")" = 644 ]
}

@test "install from a checkout does not download psh" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  cat >"$PSH_MOCK_BIN/curl" <<'EOF'
#!/bin/sh
printf 'curl should not be called for checkout install\n' >&2
exit 1
EOF
  chmod +x "$PSH_MOCK_BIN/curl"

  cat >"$PSH_MOCK_BIN/wget" <<'EOF'
#!/bin/sh
printf 'wget should not be called for checkout install\n' >&2
exit 1
EOF
  chmod +x "$PSH_MOCK_BIN/wget"

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" install

  assert_status 0
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [ -x "$bin_home/psh" ]
  [ -x "$data_home/psh/psh.sh" ]
  grep -q 'usage: psh' "$data_home/psh/psh.sh"
}

@test "install from a PATH psh does not download" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local path_dir=$PSH_TEST_ROOT/path-bin
  local workdir=$PSH_TEST_ROOT/workdir

  mkdir -p "$path_dir" "$workdir"
  cp "$PSH_REPO_ROOT/bin/psh.sh" "$path_dir/psh"
  chmod +x "$path_dir/psh"

  cat >"$PSH_MOCK_BIN/curl" <<'EOF'
#!/bin/sh
printf 'curl should not be called for PATH install\n' >&2
exit 1
EOF
  chmod +x "$PSH_MOCK_BIN/curl"

  cat >"$PSH_MOCK_BIN/wget" <<'EOF'
#!/bin/sh
printf 'wget should not be called for PATH install\n' >&2
exit 1
EOF
  chmod +x "$PSH_MOCK_BIN/wget"

  run env PATH="$path_dir:$PATH" XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" \
    sh -c 'cd "$1" && psh install' sh "$workdir"

  assert_status 0
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [ -x "$bin_home/psh" ]
  [ -x "$data_home/psh/psh.sh" ]
  grep -q 'usage: psh' "$data_home/psh/psh.sh"
}

@test "install downloads when the script is not named psh" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local renamed=$PSH_TEST_ROOT/promptshell
  local downloaded=$PSH_TEST_ROOT/downloaded-psh.sh
  local raw_base=https://example.test/promptshell

  cp "$PSH_REPO_ROOT/bin/psh.sh" "$renamed"
  cp "$PSH_REPO_ROOT/bin/psh.sh" "$downloaded"
  printf '\n# downloaded-source-marker\n' >>"$downloaded"

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$downloaded

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" sh "$renamed" install

  assert_status 0
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [ -x "$bin_home/psh" ]
  [ -x "$data_home/psh/psh.sh" ]
  grep -q 'downloaded-source-marker' "$data_home/psh/psh.sh"
}

@test "install falls back to cp when install is missing" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local limited=$PSH_TEST_ROOT/limited-bin
  local cmd

  mkdir -p "$limited"
  for cmd in mktemp rm mkdir chmod cp dirname sed sh basename cat; do
    command -v "$cmd" >/dev/null 2>&1 || continue
    ln -s "$(command -v "$cmd")" "$limited/$cmd"
  done

  run env PATH="$limited" XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" install

  assert_status 0
  [ -x "$data_home/psh/psh.sh" ]
  [ -x "$bin_home/psh" ]
  [ -f "$data_home/bash-completion/completions/psh" ]
  [ "$(stat -c '%a' "$data_home/psh/psh.sh")" = 755 ]
  [ "$(stat -c '%a' "$bin_home/psh")" = 755 ]
  [ "$(stat -c '%a' "$data_home/bash-completion/completions/psh")" = 644 ]
}

@test "install launcher execs the XDG payload" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local payload=$data_home/psh/psh.sh

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" install

  assert_status 0
  grep -qx '#!/bin/sh' "$bin_home/psh"
  grep -qx "exec '$payload' \"\$@\"" "$bin_home/psh"
}

@test "install launcher quotes payload path with apostrophes" {
  local data_home="$PSH_TEST_ROOT/xdg-data/o's"
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" install

  assert_status 0
  grep -F "exec '$(printf '%s' "$data_home/psh/psh.sh" | sed "s/'/'\\\\''/g")' \"\$@\"" "$bin_home/psh"

  run "$bin_home/psh" --help

  assert_status 0
  [[ "$output" == *"usage: psh"* ]]
}

@test "install writes bash completion for psh commands" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local completion=$data_home/bash-completion/completions/psh

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" install

  assert_status 0
  [ -f "$completion" ]
  grep -q 'complete -F _psh psh' "$completion"
  grep -q 'compgen -W "model"' "$completion"
  grep -q 'compgen -W "--purge"' "$completion"
  grep -q 'compgen -W "-v -vv -vvv run setup install update uninstall help --help"' "$completion"
}

@test "install reports config path and setup hint" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" install

  assert_status 0
  [[ "$output" == *"config $XDG_CONFIG_HOME/psh/config.json"* ]]
  [[ "$output" == *"run \`psh setup\` before the first hosted-provider request"* ]]
}

@test "install reports config under HOME/.config when XDG_CONFIG_HOME is unset" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  run env -u XDG_CONFIG_HOME XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" install

  assert_status 0
  [[ "$output" == *"config $HOME/.config/psh/config.json"* ]]
}

@test "install hints when launcher directory is not on PATH" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" install

  assert_status 0
  [[ "$output" == *"add $bin_home to PATH to run \`psh\` directly"* ]]
}

@test "install does not hint when launcher directory is on PATH" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  mkdir -p "$bin_home"
  run env PATH="$bin_home:$PATH" XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" install

  assert_status 0
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [[ "$output" != *"add $bin_home to PATH to run \`psh\` directly"* ]]
}

@test "install honors PSH_INSTALL_DIR for the launcher" {
  local install_dir=$PSH_TEST_ROOT/install-bin
  local data_home=$PSH_TEST_ROOT/xdg-data

  run env PSH_INSTALL_DIR="$install_dir" XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" install

  assert_status 0
  [[ "$output" == *"launcher $install_dir/psh"* ]]
  [ -x "$install_dir/psh" ]
  [ -x "$data_home/psh/psh.sh" ]
}

@test "install hints when PSH_INSTALL_DIR is not on PATH" {
  local install_dir=$PSH_TEST_ROOT/install-bin
  local data_home=$PSH_TEST_ROOT/xdg-data

  run env PSH_INSTALL_DIR="$install_dir" XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" install

  assert_status 0
  [[ "$output" == *"add $install_dir to PATH to run \`psh\` directly"* ]]
}

@test "install does not hint when PSH_INSTALL_DIR is on PATH" {
  local install_dir=$PSH_TEST_ROOT/install-bin
  local data_home=$PSH_TEST_ROOT/xdg-data

  mkdir -p "$install_dir"
  run env PATH="$install_dir:$PATH" PSH_INSTALL_DIR="$install_dir" XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" install

  assert_status 0
  [[ "$output" == *"launcher $install_dir/psh"* ]]
  [[ "$output" != *"add $install_dir to PATH to run \`psh\` directly"* ]]
}

@test "install prefers PSH_INSTALL_DIR over XDG_BIN_HOME" {
  local install_dir=$PSH_TEST_ROOT/install-bin
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local data_home=$PSH_TEST_ROOT/xdg-data

  run env PSH_INSTALL_DIR="$install_dir" XDG_BIN_HOME="$bin_home" XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" install

  assert_status 0
  [[ "$output" == *"launcher $install_dir/psh"* ]]
  [ -x "$install_dir/psh" ]
  [ ! -e "$bin_home/psh" ]
}

@test "install uses XDG_BIN_HOME when PSH_INSTALL_DIR is empty" {
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local data_home=$PSH_TEST_ROOT/xdg-data

  run env PSH_INSTALL_DIR= XDG_BIN_HOME="$bin_home" XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" install

  assert_status 0
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [ -x "$bin_home/psh" ]
  [ -x "$data_home/psh/psh.sh" ]
}

@test "install uses HOME local bin when XDG_BIN_HOME is empty" {
  local data_home=$PSH_TEST_ROOT/xdg-data

  run env XDG_BIN_HOME= XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" install

  assert_status 0
  [[ "$output" == *"payload $data_home/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $HOME/.local/bin/psh"* ]]
  [ -x "$data_home/psh/psh.sh" ]
  [ -x "$HOME/.local/bin/psh" ]
}

@test "install uses HOME local share when XDG_DATA_HOME is empty" {
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  run env XDG_DATA_HOME= XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" install

  assert_status 0
  [[ "$output" == *"payload $HOME/.local/share/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [[ "$output" == *"completion $HOME/.local/share/bash-completion/completions/psh"* ]]
  [ -x "$HOME/.local/share/psh/psh.sh" ]
  [ -x "$bin_home/psh" ]
  [ -f "$HOME/.local/share/bash-completion/completions/psh" ]
}

@test "uninstall removes launcher payload and completion and leaves config" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local config_dir=$XDG_CONFIG_HOME/psh

  mkdir -p "$config_dir"
  printf '%s\n' '{"provider":"openai"}' >"$config_dir/config.json"

  env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" install >/dev/null

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" uninstall

  assert_status 0
  [[ "$output" == *"removed $bin_home/psh"* ]]
  [[ "$output" == *"removed $data_home/psh/psh.sh"* ]]
  [ ! -e "$bin_home/psh" ]
  [ ! -e "$data_home/psh/psh.sh" ]
  [ ! -e "$data_home/bash-completion/completions/psh" ]
  [ -f "$config_dir/config.json" ]
}

@test "uninstall removes empty payload directory" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" install >/dev/null

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" uninstall

  assert_status 0
  [ ! -e "$data_home/psh" ]
}

@test "uninstall leaves a non-empty payload directory" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" install >/dev/null
  printf 'keep\n' >"$data_home/psh/extra"

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" uninstall

  assert_status 0
  [ ! -e "$data_home/psh/psh.sh" ]
  [ -f "$data_home/psh/extra" ]
}

@test "uninstall --purge removes config" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local config_dir=$XDG_CONFIG_HOME/psh

  mkdir -p "$config_dir"
  printf '%s\n' '{"provider":"openai"}' >"$config_dir/config.json"

  env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" install >/dev/null

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" uninstall --purge

  assert_status 0
  [ ! -e "$config_dir/config.json" ]
}

@test "uninstall --purge removes empty config directory" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local config_dir=$XDG_CONFIG_HOME/psh

  mkdir -p "$config_dir"
  printf '%s\n' '{"provider":"openai"}' >"$config_dir/config.json"

  env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" install >/dev/null

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" uninstall --purge

  assert_status 0
  [ ! -e "$config_dir" ]
}

@test "uninstall --purge leaves a non-empty config directory" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local config_dir=$XDG_CONFIG_HOME/psh

  mkdir -p "$config_dir"
  printf '%s\n' '{"provider":"openai"}' >"$config_dir/config.json"
  printf 'keep\n' >"$config_dir/extra"

  env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" install >/dev/null

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" uninstall --purge

  assert_status 0
  [ ! -e "$config_dir/config.json" ]
  [ -f "$config_dir/extra" ]
}

@test "piped script can install with sh -s -- install" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local install_dir=$PSH_TEST_ROOT/pipe-install-bin
  local raw_base=https://example.test/promptshell

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run sh -c 'curl -fsSL "$1" | PSH_INSTALL_DIR="$2" XDG_DATA_HOME="$3" PSH_RAW_BASE="$4" sh -s -- install' sh "$PSH_EXPECT_INSTALL_SOURCE" "$install_dir" "$data_home" "$PSH_RAW_BASE"

  assert_status 0
  [[ "$output" == *"launcher $install_dir/psh"* ]]
  [ -x "$install_dir/psh" ]
  [ -x "$data_home/psh/psh.sh" ]
}

@test "piped install downloads from the default GitHub raw URL" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local install_dir=$PSH_TEST_ROOT/pipe-install-bin

  install_mock_raw_curl
  export PSH_EXPECT_INSTALL_SOURCE=https://raw.githubusercontent.com/csfh/promptshell/main/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run sh -c 'cat "$1" | PSH_INSTALL_DIR="$2" XDG_DATA_HOME="$3" sh -s -- install' sh "$PSH_REPO_ROOT/bin/psh.sh" "$install_dir" "$data_home"

  assert_status 0
  [[ "$output" == *"launcher $install_dir/psh"* ]]
  [ -x "$install_dir/psh" ]
  [ -x "$data_home/psh/psh.sh" ]
}

@test "piped install falls back to HOME local share and bin directories" {
  local raw_base=https://example.test/promptshell

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run sh -c 'cat "$1" | PSH_RAW_BASE="$2" sh -s -- install' sh "$PSH_REPO_ROOT/bin/psh.sh" "$PSH_RAW_BASE"

  assert_status 0
  [[ "$output" == *"payload $HOME/.local/share/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $HOME/.local/bin/psh"* ]]
  [[ "$output" == *"completion $HOME/.local/share/bash-completion/completions/psh"* ]]
  [ -x "$HOME/.local/share/psh/psh.sh" ]
  [ -x "$HOME/.local/bin/psh" ]
  [ -f "$HOME/.local/share/bash-completion/completions/psh" ]
}

@test "piped install honors PSH_INSTALL_NAME when falling back to HOME local bin" {
  local raw_base=https://example.test/promptshell

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run sh -c 'cat "$1" | PSH_INSTALL_NAME=psh-alt PSH_RAW_BASE="$2" sh -s -- install' sh "$PSH_REPO_ROOT/bin/psh.sh" "$PSH_RAW_BASE"

  assert_status 0
  [[ "$output" == *"launcher $HOME/.local/bin/psh-alt"* ]]
  [ -x "$HOME/.local/bin/psh-alt" ]
  [ -x "$HOME/.local/share/psh/psh.sh" ]
  [ ! -e "$HOME/.local/bin/psh" ]
}

@test "piped install honors PSH_INSTALL_NAME" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local install_dir=$PSH_TEST_ROOT/pipe-install-bin
  local raw_base=https://example.test/promptshell

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run sh -c 'cat "$1" | PSH_INSTALL_NAME=psh-alt PSH_INSTALL_DIR="$2" XDG_DATA_HOME="$3" PSH_RAW_BASE="$4" sh -s -- install' sh "$PSH_REPO_ROOT/bin/psh.sh" "$install_dir" "$data_home" "$PSH_RAW_BASE"

  assert_status 0
  [[ "$output" == *"launcher $install_dir/psh-alt"* ]]
  [ -x "$install_dir/psh-alt" ]
  [ -x "$data_home/psh/psh.sh" ]
  [ ! -e "$install_dir/psh" ]
}

@test "piped install prefers PSH_INSTALL_DIR over XDG_BIN_HOME" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local install_dir=$PSH_TEST_ROOT/pipe-install-bin
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local raw_base=https://example.test/promptshell

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run sh -c 'cat "$1" | PSH_INSTALL_DIR="$2" XDG_BIN_HOME="$3" XDG_DATA_HOME="$4" PSH_RAW_BASE="$5" sh -s -- install' sh "$PSH_REPO_ROOT/bin/psh.sh" "$install_dir" "$bin_home" "$data_home" "$PSH_RAW_BASE"

  assert_status 0
  [[ "$output" == *"launcher $install_dir/psh"* ]]
  [ -x "$install_dir/psh" ]
  [ -x "$data_home/psh/psh.sh" ]
  [ ! -e "$bin_home/psh" ]
}

@test "piped install uses XDG_BIN_HOME when PSH_INSTALL_DIR is empty" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local raw_base=https://example.test/promptshell

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run sh -c 'cat "$1" | PSH_INSTALL_DIR= XDG_BIN_HOME="$2" XDG_DATA_HOME="$3" PSH_RAW_BASE="$4" sh -s -- install' sh "$PSH_REPO_ROOT/bin/psh.sh" "$bin_home" "$data_home" "$PSH_RAW_BASE"

  assert_status 0
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [ -x "$bin_home/psh" ]
  [ -x "$data_home/psh/psh.sh" ]
}

@test "piped install uses HOME local bin when XDG_BIN_HOME is empty" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local raw_base=https://example.test/promptshell

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run sh -c 'cat "$1" | XDG_BIN_HOME= XDG_DATA_HOME="$2" PSH_RAW_BASE="$3" sh -s -- install' sh "$PSH_REPO_ROOT/bin/psh.sh" "$data_home" "$PSH_RAW_BASE"

  assert_status 0
  [[ "$output" == *"payload $data_home/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $HOME/.local/bin/psh"* ]]
  [ -x "$data_home/psh/psh.sh" ]
  [ -x "$HOME/.local/bin/psh" ]
}

@test "piped install uses HOME local share when XDG_DATA_HOME is empty" {
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local raw_base=https://example.test/promptshell

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run sh -c 'cat "$1" | XDG_DATA_HOME= XDG_BIN_HOME="$2" PSH_RAW_BASE="$3" sh -s -- install' sh "$PSH_REPO_ROOT/bin/psh.sh" "$bin_home" "$PSH_RAW_BASE"

  assert_status 0
  [[ "$output" == *"payload $HOME/.local/share/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [[ "$output" == *"completion $HOME/.local/share/bash-completion/completions/psh"* ]]
  [ -x "$HOME/.local/share/psh/psh.sh" ]
  [ -x "$bin_home/psh" ]
  [ -f "$HOME/.local/share/bash-completion/completions/psh" ]
}

@test "piped install succeeds without HOME when PSH_INSTALL_DIR is set" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local install_dir=$PSH_TEST_ROOT/pipe-install-bin
  local raw_base=https://example.test/promptshell

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run env -u HOME sh -c 'cat "$1" | PSH_INSTALL_DIR="$2" XDG_DATA_HOME="$3" PSH_RAW_BASE="$4" sh -s -- install' sh "$PSH_REPO_ROOT/bin/psh.sh" "$install_dir" "$data_home" "$PSH_RAW_BASE"

  assert_status 0
  [[ "$output" == *"payload $data_home/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $install_dir/psh"* ]]
  [[ "$output" == *"completion $data_home/bash-completion/completions/psh"* ]]
  [ -x "$data_home/psh/psh.sh" ]
  [ -x "$install_dir/psh" ]
  [ -f "$data_home/bash-completion/completions/psh" ]
}

@test "piped install succeeds without HOME when XDG install paths are set" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local raw_base=https://example.test/promptshell

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run env -u HOME sh -c 'cat "$1" | XDG_DATA_HOME="$2" XDG_BIN_HOME="$3" PSH_RAW_BASE="$4" sh -s -- install' sh "$PSH_REPO_ROOT/bin/psh.sh" "$data_home" "$bin_home" "$PSH_RAW_BASE"

  assert_status 0
  [[ "$output" == *"payload $data_home/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [[ "$output" == *"completion $data_home/bash-completion/completions/psh"* ]]
  [ -x "$data_home/psh/psh.sh" ]
  [ -x "$bin_home/psh" ]
  [ -f "$data_home/bash-completion/completions/psh" ]
}

@test "install.sh installs the CLI from a checkout" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" bash "$PSH_REPO_ROOT/install.sh"

  assert_status 0
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [ -x "$bin_home/psh" ]
  [ -x "$data_home/psh/psh.sh" ]
  [ ! -e "$XDG_CONFIG_HOME/omarchy/plugins/com.csfh.promptshell" ]
}

@test "install.sh writes bash completion for psh commands" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local completion=$data_home/bash-completion/completions/psh

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" bash "$PSH_REPO_ROOT/install.sh"

  assert_status 0
  [ -f "$completion" ]
  grep -q 'complete -F _psh psh' "$completion"
  grep -q 'compgen -W "model"' "$completion"
  grep -q 'compgen -W "--purge"' "$completion"
  grep -q 'compgen -W "-v -vv -vvv run setup install update uninstall help --help"' "$completion"
}

@test "install.sh writes payload launcher and completion modes" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" bash "$PSH_REPO_ROOT/install.sh"

  assert_status 0
  [ "$(stat -c '%a' "$data_home/psh/psh.sh")" = 755 ]
  [ "$(stat -c '%a' "$bin_home/psh")" = 755 ]
  [ "$(stat -c '%a' "$data_home/bash-completion/completions/psh")" = 644 ]
}

@test "install.sh launcher execs the XDG payload" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local payload=$data_home/psh/psh.sh

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" bash "$PSH_REPO_ROOT/install.sh"

  assert_status 0
  grep -qx '#!/bin/sh' "$bin_home/psh"
  grep -qx "exec '$payload' \"\$@\"" "$bin_home/psh"
}

@test "install.sh launcher quotes payload path with apostrophes" {
  local data_home="$PSH_TEST_ROOT/xdg-data/o's"
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" bash "$PSH_REPO_ROOT/install.sh"

  assert_status 0
  grep -F "exec '$(printf '%s' "$data_home/psh/psh.sh" | sed "s/'/'\\\\''/g")' \"\$@\"" "$bin_home/psh"

  run "$bin_home/psh" --help

  assert_status 0
  [[ "$output" == *"usage: psh"* ]]
}

@test "install.sh reports config path and setup hint" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" bash "$PSH_REPO_ROOT/install.sh"

  assert_status 0
  [[ "$output" == *"config $XDG_CONFIG_HOME/psh/config.json"* ]]
  [[ "$output" == *"run \`psh setup\` before the first hosted-provider request"* ]]
}

@test "install.sh reports config under HOME/.config when XDG_CONFIG_HOME is unset" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  run env -u XDG_CONFIG_HOME XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" bash "$PSH_REPO_ROOT/install.sh"

  assert_status 0
  [[ "$output" == *"config $HOME/.config/psh/config.json"* ]]
}

@test "install.sh hints when launcher directory is not on PATH" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" bash "$PSH_REPO_ROOT/install.sh"

  assert_status 0
  [[ "$output" == *"add $bin_home to PATH to run \`psh\` directly"* ]]
}

@test "install.sh does not hint when launcher directory is on PATH" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  mkdir -p "$bin_home"
  run env PATH="$bin_home:$PATH" XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" bash "$PSH_REPO_ROOT/install.sh"

  assert_status 0
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [[ "$output" != *"add $bin_home to PATH to run \`psh\` directly"* ]]
}

@test "install.sh hints when PSH_INSTALL_DIR is not on PATH" {
  local install_dir=$PSH_TEST_ROOT/install-bin
  local data_home=$PSH_TEST_ROOT/xdg-data

  run env PSH_INSTALL_DIR="$install_dir" XDG_DATA_HOME="$data_home" bash "$PSH_REPO_ROOT/install.sh"

  assert_status 0
  [[ "$output" == *"add $install_dir to PATH to run \`psh\` directly"* ]]
}

@test "install.sh does not hint when PSH_INSTALL_DIR is on PATH" {
  local install_dir=$PSH_TEST_ROOT/install-bin
  local data_home=$PSH_TEST_ROOT/xdg-data

  mkdir -p "$install_dir"
  run env PATH="$install_dir:$PATH" PSH_INSTALL_DIR="$install_dir" XDG_DATA_HOME="$data_home" bash "$PSH_REPO_ROOT/install.sh"

  assert_status 0
  [[ "$output" == *"launcher $install_dir/psh"* ]]
  [[ "$output" != *"add $install_dir to PATH to run \`psh\` directly"* ]]
}

@test "install.sh from a checkout does not download psh" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  cat >"$PSH_MOCK_BIN/curl" <<'EOF'
#!/bin/sh
printf 'curl should not be called for checkout install\n' >&2
exit 1
EOF
  chmod +x "$PSH_MOCK_BIN/curl"

  cat >"$PSH_MOCK_BIN/wget" <<'EOF'
#!/bin/sh
printf 'wget should not be called for checkout install\n' >&2
exit 1
EOF
  chmod +x "$PSH_MOCK_BIN/wget"

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" bash "$PSH_REPO_ROOT/install.sh"

  assert_status 0
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [ -x "$bin_home/psh" ]
  [ -x "$data_home/psh/psh.sh" ]
  grep -q 'usage: psh' "$data_home/psh/psh.sh"
}

@test "install.sh from a relative checkout path does not download psh" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  cat >"$PSH_MOCK_BIN/curl" <<'EOF'
#!/bin/sh
printf 'curl should not be called for checkout install\n' >&2
exit 1
EOF
  chmod +x "$PSH_MOCK_BIN/curl"

  cat >"$PSH_MOCK_BIN/wget" <<'EOF'
#!/bin/sh
printf 'wget should not be called for checkout install\n' >&2
exit 1
EOF
  chmod +x "$PSH_MOCK_BIN/wget"

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" \
    bash -c 'cd "$1" && bash ./install.sh' bash "$PSH_REPO_ROOT"

  assert_status 0
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [ -x "$bin_home/psh" ]
  [ -x "$data_home/psh/psh.sh" ]
  grep -q 'usage: psh' "$data_home/psh/psh.sh"
}

@test "install.sh from a checkout falls back to HOME local share and bin directories" {
  run bash "$PSH_REPO_ROOT/install.sh"

  assert_status 0
  [[ "$output" == *"payload $HOME/.local/share/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $HOME/.local/bin/psh"* ]]
  [[ "$output" == *"completion $HOME/.local/share/bash-completion/completions/psh"* ]]
  [ -x "$HOME/.local/share/psh/psh.sh" ]
  [ -x "$HOME/.local/bin/psh" ]
  [ -f "$HOME/.local/share/bash-completion/completions/psh" ]
}

@test "install.sh honors PSH_INSTALL_NAME when falling back to HOME local bin from a checkout" {
  run env PSH_INSTALL_NAME=psh-alt bash "$PSH_REPO_ROOT/install.sh"

  assert_status 0
  [[ "$output" == *"launcher $HOME/.local/bin/psh-alt"* ]]
  [ -x "$HOME/.local/bin/psh-alt" ]
  [ -x "$HOME/.local/share/psh/psh.sh" ]
  [ ! -e "$HOME/.local/bin/psh" ]
}

@test "install.sh honors PSH_INSTALL_DIR from a checkout" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local install_dir=$PSH_TEST_ROOT/install-bin
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  run env PSH_INSTALL_DIR="$install_dir" XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" bash "$PSH_REPO_ROOT/install.sh"

  assert_status 0
  [[ "$output" == *"launcher $install_dir/psh"* ]]
  [ -x "$install_dir/psh" ]
  [ -x "$data_home/psh/psh.sh" ]
  [ ! -e "$bin_home/psh" ]
}

@test "install.sh from a checkout uses XDG_BIN_HOME when PSH_INSTALL_DIR is empty" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  run env PSH_INSTALL_DIR= XDG_BIN_HOME="$bin_home" XDG_DATA_HOME="$data_home" bash "$PSH_REPO_ROOT/install.sh"

  assert_status 0
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [ -x "$bin_home/psh" ]
  [ -x "$data_home/psh/psh.sh" ]
}

@test "install.sh from a checkout uses HOME local bin when XDG_BIN_HOME is empty" {
  local data_home=$PSH_TEST_ROOT/xdg-data

  run env XDG_BIN_HOME= XDG_DATA_HOME="$data_home" bash "$PSH_REPO_ROOT/install.sh"

  assert_status 0
  [[ "$output" == *"payload $data_home/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $HOME/.local/bin/psh"* ]]
  [ -x "$data_home/psh/psh.sh" ]
  [ -x "$HOME/.local/bin/psh" ]
}

@test "install.sh from a checkout uses HOME local share when XDG_DATA_HOME is empty" {
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  run env XDG_DATA_HOME= XDG_BIN_HOME="$bin_home" bash "$PSH_REPO_ROOT/install.sh"

  assert_status 0
  [[ "$output" == *"payload $HOME/.local/share/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [[ "$output" == *"completion $HOME/.local/share/bash-completion/completions/psh"* ]]
  [ -x "$HOME/.local/share/psh/psh.sh" ]
  [ -x "$bin_home/psh" ]
  [ -f "$HOME/.local/share/bash-completion/completions/psh" ]
}

@test "install.sh honors PSH_INSTALL_NAME from a checkout" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local install_dir=$PSH_TEST_ROOT/install-bin

  run env PSH_INSTALL_NAME=psh-alt PSH_INSTALL_DIR="$install_dir" XDG_DATA_HOME="$data_home" bash "$PSH_REPO_ROOT/install.sh"

  assert_status 0
  [[ "$output" == *"launcher $install_dir/psh-alt"* ]]
  [ -x "$install_dir/psh-alt" ]
  [ -x "$data_home/psh/psh.sh" ]
  [ ! -e "$install_dir/psh" ]
}

@test "install.sh from a checkout succeeds without HOME when XDG install paths are set" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  run env -u HOME XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" bash "$PSH_REPO_ROOT/install.sh"

  assert_status 0
  [[ "$output" == *"payload $data_home/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [[ "$output" == *"completion $data_home/bash-completion/completions/psh"* ]]
  [ -x "$data_home/psh/psh.sh" ]
  [ -x "$bin_home/psh" ]
  [ -f "$data_home/bash-completion/completions/psh" ]
}

@test "install.sh from a checkout succeeds without HOME when PSH_INSTALL_DIR is set" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local install_dir=$PSH_TEST_ROOT/install-bin

  run env -u HOME PSH_INSTALL_DIR="$install_dir" XDG_DATA_HOME="$data_home" bash "$PSH_REPO_ROOT/install.sh"

  assert_status 0
  [[ "$output" == *"payload $data_home/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $install_dir/psh"* ]]
  [[ "$output" == *"completion $data_home/bash-completion/completions/psh"* ]]
  [ -x "$data_home/psh/psh.sh" ]
  [ -x "$install_dir/psh" ]
  [ -f "$data_home/bash-completion/completions/psh" ]
}

@test "piped install.sh downloads psh and installs the CLI" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local install_dir=$PSH_TEST_ROOT/pipe-install-bin
  local raw_base=https://example.test/promptshell

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run bash -c 'cat "$1" | PSH_INSTALL_DIR="$2" XDG_DATA_HOME="$3" PSH_RAW_BASE="$4" bash' bash "$PSH_REPO_ROOT/install.sh" "$install_dir" "$data_home" "$PSH_RAW_BASE"

  assert_status 0
  [[ "$output" == *"launcher $install_dir/psh"* ]]
  [ -x "$install_dir/psh" ]
  [ -x "$data_home/psh/psh.sh" ]
}

@test "piped install.sh downloads from the default GitHub raw URL" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local install_dir=$PSH_TEST_ROOT/pipe-install-bin

  install_mock_raw_curl
  export PSH_EXPECT_INSTALL_SOURCE=https://raw.githubusercontent.com/csfh/promptshell/main/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run bash -c 'cat "$1" | PSH_INSTALL_DIR="$2" XDG_DATA_HOME="$3" bash' bash "$PSH_REPO_ROOT/install.sh" "$install_dir" "$data_home"

  assert_status 0
  [[ "$output" == *"launcher $install_dir/psh"* ]]
  [ -x "$install_dir/psh" ]
  [ -x "$data_home/psh/psh.sh" ]
}

@test "piped install.sh falls back to HOME local share and bin directories" {
  local raw_base=https://example.test/promptshell

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run bash -c 'cat "$1" | PSH_RAW_BASE="$2" bash' bash "$PSH_REPO_ROOT/install.sh" "$PSH_RAW_BASE"

  assert_status 0
  [[ "$output" == *"payload $HOME/.local/share/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $HOME/.local/bin/psh"* ]]
  [[ "$output" == *"completion $HOME/.local/share/bash-completion/completions/psh"* ]]
  [ -x "$HOME/.local/share/psh/psh.sh" ]
  [ -x "$HOME/.local/bin/psh" ]
  [ -f "$HOME/.local/share/bash-completion/completions/psh" ]
}

@test "piped install.sh honors PSH_INSTALL_NAME when falling back to HOME local bin" {
  local raw_base=https://example.test/promptshell

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run bash -c 'cat "$1" | PSH_INSTALL_NAME=psh-alt PSH_RAW_BASE="$2" bash' bash "$PSH_REPO_ROOT/install.sh" "$PSH_RAW_BASE"

  assert_status 0
  [[ "$output" == *"launcher $HOME/.local/bin/psh-alt"* ]]
  [ -x "$HOME/.local/bin/psh-alt" ]
  [ -x "$HOME/.local/share/psh/psh.sh" ]
  [ ! -e "$HOME/.local/bin/psh" ]
}

@test "piped install.sh honors PSH_INSTALL_NAME" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local install_dir=$PSH_TEST_ROOT/pipe-install-bin
  local raw_base=https://example.test/promptshell

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run bash -c 'cat "$1" | PSH_INSTALL_NAME=psh-alt PSH_INSTALL_DIR="$2" XDG_DATA_HOME="$3" PSH_RAW_BASE="$4" bash' bash "$PSH_REPO_ROOT/install.sh" "$install_dir" "$data_home" "$PSH_RAW_BASE"

  assert_status 0
  [[ "$output" == *"launcher $install_dir/psh-alt"* ]]
  [ -x "$install_dir/psh-alt" ]
  [ -x "$data_home/psh/psh.sh" ]
  [ ! -e "$install_dir/psh" ]
}

@test "piped install.sh prefers PSH_INSTALL_DIR over XDG_BIN_HOME" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local install_dir=$PSH_TEST_ROOT/pipe-install-bin
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local raw_base=https://example.test/promptshell

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run bash -c 'cat "$1" | PSH_INSTALL_DIR="$2" XDG_BIN_HOME="$3" XDG_DATA_HOME="$4" PSH_RAW_BASE="$5" bash' bash "$PSH_REPO_ROOT/install.sh" "$install_dir" "$bin_home" "$data_home" "$PSH_RAW_BASE"

  assert_status 0
  [[ "$output" == *"launcher $install_dir/psh"* ]]
  [ -x "$install_dir/psh" ]
  [ -x "$data_home/psh/psh.sh" ]
  [ ! -e "$bin_home/psh" ]
}

@test "piped install.sh uses XDG_BIN_HOME when PSH_INSTALL_DIR is empty" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local raw_base=https://example.test/promptshell

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run bash -c 'cat "$1" | PSH_INSTALL_DIR= XDG_BIN_HOME="$2" XDG_DATA_HOME="$3" PSH_RAW_BASE="$4" bash' bash "$PSH_REPO_ROOT/install.sh" "$bin_home" "$data_home" "$PSH_RAW_BASE"

  assert_status 0
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [ -x "$bin_home/psh" ]
  [ -x "$data_home/psh/psh.sh" ]
}

@test "piped install.sh uses HOME local bin when XDG_BIN_HOME is empty" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local raw_base=https://example.test/promptshell

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run bash -c 'cat "$1" | XDG_BIN_HOME= XDG_DATA_HOME="$2" PSH_RAW_BASE="$3" bash' bash "$PSH_REPO_ROOT/install.sh" "$data_home" "$PSH_RAW_BASE"

  assert_status 0
  [[ "$output" == *"payload $data_home/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $HOME/.local/bin/psh"* ]]
  [ -x "$data_home/psh/psh.sh" ]
  [ -x "$HOME/.local/bin/psh" ]
}

@test "piped install.sh uses HOME local share when XDG_DATA_HOME is empty" {
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local raw_base=https://example.test/promptshell

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run bash -c 'cat "$1" | XDG_DATA_HOME= XDG_BIN_HOME="$2" PSH_RAW_BASE="$3" bash' bash "$PSH_REPO_ROOT/install.sh" "$bin_home" "$PSH_RAW_BASE"

  assert_status 0
  [[ "$output" == *"payload $HOME/.local/share/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [[ "$output" == *"completion $HOME/.local/share/bash-completion/completions/psh"* ]]
  [ -x "$HOME/.local/share/psh/psh.sh" ]
  [ -x "$bin_home/psh" ]
  [ -f "$HOME/.local/share/bash-completion/completions/psh" ]
}

@test "piped install.sh succeeds without HOME when PSH_INSTALL_DIR is set" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local install_dir=$PSH_TEST_ROOT/pipe-install-bin
  local raw_base=https://example.test/promptshell

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run env -u HOME bash -c 'cat "$1" | PSH_INSTALL_DIR="$2" XDG_DATA_HOME="$3" PSH_RAW_BASE="$4" bash' bash "$PSH_REPO_ROOT/install.sh" "$install_dir" "$data_home" "$PSH_RAW_BASE"

  assert_status 0
  [[ "$output" == *"payload $data_home/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $install_dir/psh"* ]]
  [[ "$output" == *"completion $data_home/bash-completion/completions/psh"* ]]
  [ -x "$data_home/psh/psh.sh" ]
  [ -x "$install_dir/psh" ]
  [ -f "$data_home/bash-completion/completions/psh" ]
}

@test "piped install.sh succeeds without HOME when XDG install paths are set" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local raw_base=https://example.test/promptshell

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run env -u HOME bash -c 'cat "$1" | XDG_DATA_HOME="$2" XDG_BIN_HOME="$3" PSH_RAW_BASE="$4" bash' bash "$PSH_REPO_ROOT/install.sh" "$data_home" "$bin_home" "$PSH_RAW_BASE"

  assert_status 0
  [[ "$output" == *"payload $data_home/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [[ "$output" == *"completion $data_home/bash-completion/completions/psh"* ]]
  [ -x "$data_home/psh/psh.sh" ]
  [ -x "$bin_home/psh" ]
  [ -f "$data_home/bash-completion/completions/psh" ]
}

@test "install.sh downloads psh when checkout payload is missing" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local installer_dir=$PSH_TEST_ROOT/standalone
  local raw_base=https://example.test/promptshell

  mkdir -p "$installer_dir"
  cp "$PSH_REPO_ROOT/install.sh" "$installer_dir/install.sh"

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" bash "$installer_dir/install.sh"

  assert_status 0
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [ -x "$bin_home/psh" ]
  [ -x "$data_home/psh/psh.sh" ]
}

@test "install.sh falls back to HOME local share and bin directories when checkout payload is missing" {
  local installer_dir=$PSH_TEST_ROOT/standalone
  local raw_base=https://example.test/promptshell

  mkdir -p "$installer_dir"
  cp "$PSH_REPO_ROOT/install.sh" "$installer_dir/install.sh"

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run bash "$installer_dir/install.sh"

  assert_status 0
  [[ "$output" == *"payload $HOME/.local/share/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $HOME/.local/bin/psh"* ]]
  [[ "$output" == *"completion $HOME/.local/share/bash-completion/completions/psh"* ]]
  [ -x "$HOME/.local/share/psh/psh.sh" ]
  [ -x "$HOME/.local/bin/psh" ]
  [ -f "$HOME/.local/share/bash-completion/completions/psh" ]
}

@test "install.sh honors PSH_INSTALL_NAME when falling back to HOME local bin when checkout payload is missing" {
  local installer_dir=$PSH_TEST_ROOT/standalone
  local raw_base=https://example.test/promptshell

  mkdir -p "$installer_dir"
  cp "$PSH_REPO_ROOT/install.sh" "$installer_dir/install.sh"

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run env PSH_INSTALL_NAME=psh-alt bash "$installer_dir/install.sh"

  assert_status 0
  [[ "$output" == *"launcher $HOME/.local/bin/psh-alt"* ]]
  [ -x "$HOME/.local/bin/psh-alt" ]
  [ -x "$HOME/.local/share/psh/psh.sh" ]
  [ ! -e "$HOME/.local/bin/psh" ]
}

@test "install.sh honors PSH_INSTALL_DIR when checkout payload is missing" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local install_dir=$PSH_TEST_ROOT/install-bin
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local installer_dir=$PSH_TEST_ROOT/standalone
  local raw_base=https://example.test/promptshell

  mkdir -p "$installer_dir"
  cp "$PSH_REPO_ROOT/install.sh" "$installer_dir/install.sh"

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run env PSH_INSTALL_DIR="$install_dir" XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" bash "$installer_dir/install.sh"

  assert_status 0
  [[ "$output" == *"launcher $install_dir/psh"* ]]
  [ -x "$install_dir/psh" ]
  [ -x "$data_home/psh/psh.sh" ]
  [ ! -e "$bin_home/psh" ]
}

@test "install.sh uses XDG_BIN_HOME when PSH_INSTALL_DIR is empty when checkout payload is missing" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local installer_dir=$PSH_TEST_ROOT/standalone
  local raw_base=https://example.test/promptshell

  mkdir -p "$installer_dir"
  cp "$PSH_REPO_ROOT/install.sh" "$installer_dir/install.sh"

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run env PSH_INSTALL_DIR= XDG_BIN_HOME="$bin_home" XDG_DATA_HOME="$data_home" bash "$installer_dir/install.sh"

  assert_status 0
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [ -x "$bin_home/psh" ]
  [ -x "$data_home/psh/psh.sh" ]
}

@test "install.sh uses HOME local bin when XDG_BIN_HOME is empty when checkout payload is missing" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local installer_dir=$PSH_TEST_ROOT/standalone
  local raw_base=https://example.test/promptshell

  mkdir -p "$installer_dir"
  cp "$PSH_REPO_ROOT/install.sh" "$installer_dir/install.sh"

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run env XDG_BIN_HOME= XDG_DATA_HOME="$data_home" bash "$installer_dir/install.sh"

  assert_status 0
  [[ "$output" == *"payload $data_home/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $HOME/.local/bin/psh"* ]]
  [ -x "$data_home/psh/psh.sh" ]
  [ -x "$HOME/.local/bin/psh" ]
}

@test "install.sh uses HOME local share when XDG_DATA_HOME is empty when checkout payload is missing" {
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local installer_dir=$PSH_TEST_ROOT/standalone
  local raw_base=https://example.test/promptshell

  mkdir -p "$installer_dir"
  cp "$PSH_REPO_ROOT/install.sh" "$installer_dir/install.sh"

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run env XDG_DATA_HOME= XDG_BIN_HOME="$bin_home" bash "$installer_dir/install.sh"

  assert_status 0
  [[ "$output" == *"payload $HOME/.local/share/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [[ "$output" == *"completion $HOME/.local/share/bash-completion/completions/psh"* ]]
  [ -x "$HOME/.local/share/psh/psh.sh" ]
  [ -x "$bin_home/psh" ]
  [ -f "$HOME/.local/share/bash-completion/completions/psh" ]
}

@test "install.sh honors PSH_INSTALL_NAME when checkout payload is missing" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local install_dir=$PSH_TEST_ROOT/install-bin
  local installer_dir=$PSH_TEST_ROOT/standalone
  local raw_base=https://example.test/promptshell

  mkdir -p "$installer_dir"
  cp "$PSH_REPO_ROOT/install.sh" "$installer_dir/install.sh"

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run env PSH_INSTALL_NAME=psh-alt PSH_INSTALL_DIR="$install_dir" XDG_DATA_HOME="$data_home" bash "$installer_dir/install.sh"

  assert_status 0
  [[ "$output" == *"launcher $install_dir/psh-alt"* ]]
  [ -x "$install_dir/psh-alt" ]
  [ -x "$data_home/psh/psh.sh" ]
  [ ! -e "$install_dir/psh" ]
}

@test "install.sh succeeds without HOME when checkout payload is missing and XDG install paths are set" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local installer_dir=$PSH_TEST_ROOT/standalone
  local raw_base=https://example.test/promptshell

  mkdir -p "$installer_dir"
  cp "$PSH_REPO_ROOT/install.sh" "$installer_dir/install.sh"

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run env -u HOME XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" bash "$installer_dir/install.sh"

  assert_status 0
  [[ "$output" == *"payload $data_home/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [[ "$output" == *"completion $data_home/bash-completion/completions/psh"* ]]
  [ -x "$data_home/psh/psh.sh" ]
  [ -x "$bin_home/psh" ]
  [ -f "$data_home/bash-completion/completions/psh" ]
}

@test "install.sh succeeds without HOME when checkout payload is missing and PSH_INSTALL_DIR is set" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local install_dir=$PSH_TEST_ROOT/install-bin
  local installer_dir=$PSH_TEST_ROOT/standalone
  local raw_base=https://example.test/promptshell

  mkdir -p "$installer_dir"
  cp "$PSH_REPO_ROOT/install.sh" "$installer_dir/install.sh"

  install_mock_raw_curl
  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run env -u HOME PSH_INSTALL_DIR="$install_dir" XDG_DATA_HOME="$data_home" bash "$installer_dir/install.sh"

  assert_status 0
  [[ "$output" == *"payload $data_home/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $install_dir/psh"* ]]
  [[ "$output" == *"completion $data_home/bash-completion/completions/psh"* ]]
  [ -x "$data_home/psh/psh.sh" ]
  [ -x "$install_dir/psh" ]
  [ -f "$data_home/bash-completion/completions/psh" ]
}

@test "install.sh downloads from the default GitHub raw URL when checkout payload is missing" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local installer_dir=$PSH_TEST_ROOT/standalone

  mkdir -p "$installer_dir"
  cp "$PSH_REPO_ROOT/install.sh" "$installer_dir/install.sh"

  install_mock_raw_curl
  export PSH_EXPECT_INSTALL_SOURCE=https://raw.githubusercontent.com/csfh/promptshell/main/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" bash "$installer_dir/install.sh"

  assert_status 0
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [ -x "$bin_home/psh" ]
  [ -x "$data_home/psh/psh.sh" ]
}

@test "install.sh uses wget when checkout payload is missing" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local installer_dir=$PSH_TEST_ROOT/standalone
  local limited=$PSH_TEST_ROOT/limited-bin
  local raw_base=https://example.test/promptshell
  local cmd

  mkdir -p "$installer_dir" "$limited"
  cp "$PSH_REPO_ROOT/install.sh" "$installer_dir/install.sh"

  for cmd in bash mktemp rm mkdir chmod cp dirname sed install sh basename cat; do
    command -v "$cmd" >/dev/null 2>&1 || continue
    ln -s "$(command -v "$cmd")" "$limited/$cmd"
  done

  cat >"$limited/wget" <<'MOCK_WGET'
#!/bin/sh

out=
url=

while [ "$#" -gt 0 ]; do
  case $1 in
    -qO)
      shift
      out=${1:-}
      ;;
    http*)
      url=$1
      ;;
  esac
  shift || break
done

if [ -n "${PSH_EXPECT_INSTALL_SOURCE:-}" ] && [ "$url" != "$PSH_EXPECT_INSTALL_SOURCE" ]; then
  printf 'unexpected install source: %s\n' "$url" >&2
  exit 2
fi

if [ -z "${PSH_INSTALL_SOURCE_FILE:-}" ]; then
  printf 'missing PSH_INSTALL_SOURCE_FILE\n' >&2
  exit 2
fi

[ -n "$out" ] || exit 2
cp "$PSH_INSTALL_SOURCE_FILE" "$out"
MOCK_WGET
  chmod +x "$limited/wget"

  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run env PATH="$limited" XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" PSH_RAW_BASE="$raw_base" bash "$installer_dir/install.sh"

  assert_status 0
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [ -x "$bin_home/psh" ]
  [ -x "$data_home/psh/psh.sh" ]
}

@test "install.sh requires curl or wget when checkout payload is missing" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local installer_dir=$PSH_TEST_ROOT/standalone
  local limited=$PSH_TEST_ROOT/limited-bin
  local cmd

  mkdir -p "$installer_dir" "$limited"
  cp "$PSH_REPO_ROOT/install.sh" "$installer_dir/install.sh"

  for cmd in bash mktemp rm dirname; do
    command -v "$cmd" >/dev/null 2>&1 || continue
    ln -s "$(command -v "$cmd")" "$limited/$cmd"
  done

  run env PATH="$limited" XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" bash "$installer_dir/install.sh"

  assert_status 2
  [[ "$output" == *"install.sh: curl or wget is required"* ]]
}

@test "run requires jq" {
  local limited=$PSH_TEST_ROOT/limited-bin
  local orig_path=$PATH

  require_command setsid
  mkdir -p "$limited"
  ln -s "$(command -v setsid)" "$limited/setsid"
  export PATH="$limited"
  export OPENAI_API_KEY=dummy

  run psh_no_tty run say hi
  export PATH="$orig_path"

  assert_status 2
  [[ "$output" == *"jq is required"* ]]
}

@test "hosted generation requires curl" {
  local limited=$PSH_TEST_ROOT/limited-bin
  local orig_path=$PATH

  require_command setsid
  mkdir -p "$limited"
  ln -s "$(command -v setsid)" "$limited/setsid"
  ln -s "$(command -v jq)" "$limited/jq"
  ln -s "$(command -v awk)" "$limited/awk"
  ln -s "$(command -v cat)" "$limited/cat"
  export PATH="$limited"
  export OPENAI_API_KEY=dummy

  run psh_no_tty run say hi
  export PATH="$orig_path"

  assert_status 2
  [[ "$output" == *"curl is required"* ]]
}

@test "missing API key exits 2 before contacting provider" {
  require_command setsid

  run psh_no_tty run clean up docker

  assert_status 2
  [[ "$output" == *"API key is required"* ]]
}

@test "fireworks ignores OPENAI_API_KEY and requires FIREWORKS_API_KEY" {
  require_command setsid

  export PSH_PROVIDER=fireworks
  export OPENAI_API_KEY=dummy

  run psh_no_tty run say hi

  assert_status 2
  [[ "$output" == *"API key is required"* ]]
}

@test "openai ignores FIREWORKS_API_KEY and requires OPENAI_API_KEY" {
  require_command setsid

  export PSH_PROVIDER=openai
  export FIREWORKS_API_KEY=dummy

  run psh_no_tty run say hi

  assert_status 2
  [[ "$output" == *"API key is required"* ]]
}

@test "PSH_API_KEY is accepted as a fireworks key fallback" {
  require_command setsid
  mock_hosted_command true
  export PSH_PROVIDER=fireworks
  export PSH_API_KEY=fallback-key

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
}

@test "unsupported provider exits 2 before contacting provider" {
  require_command setsid

  export PSH_PROVIDER=nope

  run psh_no_tty run say hi

  assert_status 2
  [[ "$output" == *"unsupported provider: nope"* ]]
}

@test "non-interactive run prints only the generated command" {
  require_command setsid

  mock_hosted_command "printf psh-ran" "prints a marker" needs_approval
  export OPENAI_API_KEY=dummy

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = "printf psh-ran" ]
}

@test "implicit run treats unknown argv as the prompt" {
  local request_file=$PSH_TEST_ROOT/request.json

  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy
  export PSH_CAPTURE_REQUEST=$request_file

  run psh_no_tty clean up docker

  assert_status 0
  [ "$output" = true ]
  jq -e '(.messages[1].content | fromjson | .prompt) == "clean up docker"' "$request_file" >/dev/null
}

@test "run reads prompt from stdin when no prompt argv is supplied" {
  local request_file=$PSH_TEST_ROOT/request.json

  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy
  export PSH_CAPTURE_REQUEST=$request_file

  run psh_no_tty_stdin "clean up docker" run

  assert_status 0
  [ "$output" = true ]
  jq -e '(.messages[1].content | fromjson | .prompt) == "clean up docker"' "$request_file" >/dev/null
}

@test "run prefers prompt argv over stdin" {
  local request_file=$PSH_TEST_ROOT/request.json

  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy
  export PSH_CAPTURE_REQUEST=$request_file

  run psh_no_tty_stdin "from stdin" run from argv

  assert_status 0
  [ "$output" = true ]
  jq -e '(.messages[1].content | fromjson | .prompt) == "from argv"' "$request_file" >/dev/null
}

@test "empty prompt from stdin exits 2" {
  require_command setsid

  run psh_no_tty_stdin "" run

  assert_status 2
  [[ "$output" == *"empty prompt"* ]]
}

@test "empty prompt argv exits 2" {
  require_command setsid

  run psh_no_tty run ""

  assert_status 2
  [[ "$output" == *"empty prompt"* ]]
}

@test "interactive run without a prompt prints usage" {
  require_command script

  run psh_pty n run

  assert_status 2
  [[ "$output" == *"usage: psh"* ]]
}

@test "hosted request uses deterministic decoding and tiny prompt context" {
  local request_file=$PSH_TEST_ROOT/request.json

  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy
  export PSH_CAPTURE_REQUEST=$request_file

  run psh_no_tty run say hi

  assert_status 0
  jq -e '
    .temperature == 0
    and .top_p == 1
    and .max_tokens == 192
    and (.messages[1].content | fromjson | .prompt == "say hi")
    and (.messages[1].content | fromjson | has("cwd"))
    and (.messages[1].content | fromjson | has("os"))
    and (.messages[1].content | fromjson | has("shell"))
    and (.messages[1].content | fromjson | has("package_manager"))
  ' "$request_file" >/dev/null
}

@test "hosted request includes the generation system prompt" {
  local request_file=$PSH_TEST_ROOT/request.json

  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy
  export PSH_CAPTURE_REQUEST=$request_file

  run psh_no_tty run say hi

  assert_status 0
  jq -e '
    .messages[0].role == "system"
    and (.messages[0].content | test("Convert natural language into one safe POSIX shell command"))
    and (.messages[0].content | test("Return only compact JSON"))
    and (.messages[1].role == "user")
  ' "$request_file" >/dev/null
}

@test "hosted request prompt context includes the current working directory" {
  local request_file=$PSH_TEST_ROOT/request.json

  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy
  export PSH_CAPTURE_REQUEST=$request_file

  run psh_no_tty run say hi

  assert_status 0
  jq -e --arg cwd "$PWD" '(.messages[1].content | fromjson | .cwd) == $cwd' "$request_file" >/dev/null
}

@test "hosted request prompt context includes the shell" {
  local request_file=$PSH_TEST_ROOT/request.json

  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy
  export PSH_CAPTURE_REQUEST=$request_file
  export SHELL=/bin/testh

  run psh_no_tty run say hi

  assert_status 0
  jq -e '(.messages[1].content | fromjson | .shell) == "/bin/testh"' "$request_file" >/dev/null
}

@test "hosted request prompt context includes the os" {
  local request_file=$PSH_TEST_ROOT/request.json

  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy
  export PSH_CAPTURE_REQUEST=$request_file

  run psh_no_tty run say hi

  assert_status 0
  jq -e --arg os "$(uname -s)" '(.messages[1].content | fromjson | .os) == $os' "$request_file" >/dev/null
}

@test "hosted request prompt context includes the package manager" {
  local request_file=$PSH_TEST_ROOT/request.json

  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy
  export PSH_CAPTURE_REQUEST=$request_file

  cat >"$PSH_MOCK_BIN/brew" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "$PSH_MOCK_BIN/brew"

  run psh_no_tty run say hi

  assert_status 0
  jq -e '(.messages[1].content | fromjson | .package_manager) == "brew"' "$request_file" >/dev/null
}

@test "non-interactive clarification exits 2 and shows available options" {
  require_command setsid

  mock_hosted_question
  export OPENAI_API_KEY=dummy

  run psh_no_tty run clean

  assert_status 2
  [[ "$output" == *"clarification required: Which target?"* ]]
  [[ "$output" == *"psh: option: Docker"* ]]
  [[ "$output" == *"psh: option: Images"* ]]
}

@test "non-interactive clarification without options exits 2" {
  require_command setsid

  mock_hosted_content '{"type":"question","question":"Which target?"}'
  export OPENAI_API_KEY=dummy

  run psh_no_tty run clean

  assert_status 2
  [[ "$output" == *"clarification required: Which target?"* ]]
  [[ "$output" != *"psh: option:"* ]]
}

@test "interactive clarification without an answer exits 2" {
  require_command script

  mock_hosted_content '{"type":"question","question":"Which target?"}'
  export OPENAI_API_KEY=dummy

  run psh_pty $'\n' run clean

  assert_status 2
  [[ "$output" == *"clarification answer is required"* ]]
}

@test "fireworks provider uses hosted generation path" {
  local url_file=$PSH_TEST_ROOT/url.txt

  require_command setsid
  mock_hosted_command true
  export PSH_PROVIDER=fireworks
  export FIREWORKS_API_KEY=dummy
  export PSH_CAPTURE_URL=$url_file

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
  [ "$(<"$url_file")" = "https://api.fireworks.ai/inference/v1/chat/completions" ]
}

@test "codex provider parses JSONL agent messages" {
  require_command setsid

  local model_file=$PSH_TEST_ROOT/codex-model.txt

  mock_codex_command true
  export PSH_PROVIDER=codex
  export PSH_CAPTURE_CODEX_MODEL=$model_file

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
  [ "$(<"$model_file")" = "gpt-5.5" ]
}

@test "codex receives a combined system prompt and user request" {
  require_command setsid

  local prompt_file=$PSH_TEST_ROOT/codex-prompt.txt

  mock_codex_command true
  export PSH_PROVIDER=codex
  export PSH_CAPTURE_CODEX_PROMPT=$prompt_file

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
  [[ "$(<"$prompt_file")" == *"Convert natural language into one safe POSIX shell command"* ]]
  [[ "$(<"$prompt_file")" == *$'\n\nUser request:\n'* ]]
  awk 'f; $0 == "User request:" { f = 1 }' "$prompt_file" | jq -e '.prompt == "say hi"' >/dev/null
}

@test "codex falls back to raw output when JSONL has no agent message" {
  require_command setsid

  install_mock_codex
  PSH_CODEX_JSONL=$(command_json true)
  export PSH_CODEX_JSONL
  export PSH_PROVIDER=codex

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
}

@test "grok provider parses JSON text and uses propose-only flags" {
  require_command setsid

  local argv_file=$PSH_TEST_ROOT/grok-argv.txt

  mock_grok_command true
  export PSH_PROVIDER=grok
  export PSH_CAPTURE_HARNESS_ARGV=$argv_file

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
  [[ "$(<"$argv_file")" == *"-p "* ]]
  [[ "$(<"$argv_file")" == *"--output-format json"* ]]
  [[ "$(<"$argv_file")" == *"--max-turns 1"* ]]
  [[ "$(<"$argv_file")" == *"--tools read_file,grep,list_dir"* ]]
  [[ "$(<"$argv_file")" != *"--always-approve"* ]]
  [[ "$(<"$argv_file")" != *"--yolo"* ]]
}

@test "grok receives a combined system prompt and user request" {
  require_command setsid

  local argv_file=$PSH_TEST_ROOT/grok-argv.txt

  mock_grok_command true
  export PSH_PROVIDER=grok
  export PSH_CAPTURE_HARNESS_ARGV=$argv_file

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
  [[ "$(<"$argv_file")" == *"Convert natural language into one safe POSIX shell command"* ]]
  [[ "$(<"$argv_file")" == *$'\n\nUser request:\n'* ]]
  grep -qE '"prompt": ?"say hi"' "$argv_file"
}

@test "grok falls back to raw output when JSON text field is missing" {
  require_command setsid

  install_mock_harness grok
  PSH_HARNESS_OUTPUT=$(command_json true)
  export PSH_HARNESS_OUTPUT
  export PSH_PROVIDER=grok

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
}

@test "grok provider requires the grok binary" {
  require_command setsid

  export PATH="$PSH_MOCK_BIN:/usr/bin:/bin"
  export PSH_PROVIDER=grok

  run psh_no_tty run say hi

  assert_status 2
  [[ "$output" == *"grok is required for the grok provider"* ]]
}

@test "claude provider requires the claude binary" {
  require_command setsid

  export PATH="$PSH_MOCK_BIN:/usr/bin:/bin"
  export PSH_PROVIDER=claude

  run psh_no_tty run say hi

  assert_status 2
  [[ "$output" == *"claude is required for the claude provider"* ]]
}

@test "gemini provider requires the gemini binary" {
  require_command setsid

  export PATH="$PSH_MOCK_BIN:/usr/bin:/bin"
  export PSH_PROVIDER=gemini

  run psh_no_tty run say hi

  assert_status 2
  [[ "$output" == *"gemini is required for the gemini provider"* ]]
}

@test "codex provider requires the codex binary" {
  require_command setsid

  export PATH="$PSH_MOCK_BIN:/usr/bin:/bin"
  export PSH_PROVIDER=codex

  run psh_no_tty run say hi

  assert_status 2
  [[ "$output" == *"codex is required for the codex provider"* ]]
}

@test "claude provider parses JSON result and disallows mutating tools" {
  require_command setsid

  local argv_file=$PSH_TEST_ROOT/claude-argv.txt

  mock_claude_command true
  export PSH_PROVIDER=claude
  export PSH_CAPTURE_HARNESS_ARGV=$argv_file

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
  [[ "$(<"$argv_file")" == *"-p "* ]]
  [[ "$(<"$argv_file")" == *"--output-format json"* ]]
  [[ "$(<"$argv_file")" == *"--disallowedTools Bash Edit Write"* ]]
}

@test "claude receives a combined system prompt and user request" {
  require_command setsid

  local argv_file=$PSH_TEST_ROOT/claude-argv.txt

  mock_claude_command true
  export PSH_PROVIDER=claude
  export PSH_CAPTURE_HARNESS_ARGV=$argv_file

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
  [[ "$(<"$argv_file")" == *"Convert natural language into one safe POSIX shell command"* ]]
  [[ "$(<"$argv_file")" == *$'\n\nUser request:\n'* ]]
  grep -qE '"prompt": ?"say hi"' "$argv_file"
}

@test "claude falls back to raw output when JSON result field is missing" {
  require_command setsid

  install_mock_harness claude
  PSH_HARNESS_OUTPUT=$(command_json true)
  export PSH_HARNESS_OUTPUT
  export PSH_PROVIDER=claude

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
}

@test "gemini provider parses JSON response without yolo" {
  require_command setsid

  local argv_file=$PSH_TEST_ROOT/gemini-argv.txt

  mock_gemini_command true
  export PSH_PROVIDER=gemini
  export PSH_CAPTURE_HARNESS_ARGV=$argv_file

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
  [[ "$(<"$argv_file")" == *"-p "* ]]
  [[ "$(<"$argv_file")" == *"--output-format json"* ]]
  [[ "$(<"$argv_file")" != *"--yolo"* ]]
}

@test "gemini receives a combined system prompt and user request" {
  require_command setsid

  local argv_file=$PSH_TEST_ROOT/gemini-argv.txt

  mock_gemini_command true
  export PSH_PROVIDER=gemini
  export PSH_CAPTURE_HARNESS_ARGV=$argv_file

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
  [[ "$(<"$argv_file")" == *"Convert natural language into one safe POSIX shell command"* ]]
  [[ "$(<"$argv_file")" == *$'\n\nUser request:\n'* ]]
  grep -qE '"prompt": ?"say hi"' "$argv_file"
}

@test "gemini falls back to raw output when JSON response field is missing" {
  require_command setsid

  install_mock_harness gemini
  PSH_HARNESS_OUTPUT=$(command_json true)
  export PSH_HARNESS_OUTPUT
  export PSH_PROVIDER=gemini

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
}

@test "codex provider passes configured model with -m" {
  require_command setsid

  local config_dir=$XDG_CONFIG_HOME/psh
  local model_file=$PSH_TEST_ROOT/codex-model.txt

  mkdir -p "$config_dir"
  jq -n '{provider: "codex", model: "gpt-5.4", api_key: ""}' >"$config_dir/config.json"
  mock_codex_command true
  export PSH_CAPTURE_CODEX_MODEL=$model_file

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
  [ "$(<"$model_file")" = "gpt-5.4" ]
}

@test "setup can save a selected codex model" {
  require_command script

  local input=$'3\n2\n'

  install_mock_codex

  run psh_pty "$input" setup

  assert_status 0
  jq -e '.provider == "codex" and .model == "gpt-5.4" and .api_key == ""' "$XDG_CONFIG_HOME/psh/config.json" >/dev/null
}

@test "setup can save a hosted provider API key" {
  require_command script

  run psh_pty $'\n\nsk-test\n' setup

  assert_status 0
  jq -e '.provider == "openai" and .model == "gpt-4.1-mini" and .api_key == "sk-test"' "$XDG_CONFIG_HOME/psh/config.json" >/dev/null
}

@test "setup can save a fireworks provider API key" {
  require_command script

  run psh_pty $'\033[B\n\nsk-fw\n' setup

  assert_status 0
  jq -e '.provider == "fireworks" and .model == "accounts/fireworks/models/deepseek-v3p1" and .api_key == "sk-fw"' "$XDG_CONFIG_HOME/psh/config.json" >/dev/null
}

@test "setup requires an API key for hosted providers" {
  require_command script

  run psh_pty $'\n\n\n' setup

  assert_status 2
  [[ "$output" == *"API key is required"* ]]
  [ ! -e "$XDG_CONFIG_HOME/psh/config.json" ]
}

@test "setup keeps existing API key when the prompt is blank" {
  require_command script

  mkdir -p "$XDG_CONFIG_HOME/psh"
  jq -n '{provider: "openai", model: "gpt-4.1-mini", api_key: "keep-me"}' >"$XDG_CONFIG_HOME/psh/config.json"

  run psh_pty $'\n\n\n' setup

  assert_status 0
  jq -e '.provider == "openai" and .model == "gpt-4.1-mini" and .api_key == "keep-me"' "$XDG_CONFIG_HOME/psh/config.json" >/dev/null
}

@test "setup writes config with mode 600" {
  require_command script

  install_mock_codex

  run psh_pty $'3\n1\n' setup

  assert_status 0
  [ "$(stat -c '%a' "$XDG_CONFIG_HOME/psh/config.json")" = 600 ]
}

@test "setup provider and model prompts support arrow selection" {
  require_command script

  local input=$'\033[B\033[B\n\033[B\n'

  install_mock_codex

  run psh_pty "$input" setup

  assert_status 0
  jq -e '.provider == "codex" and .model == "gpt-5.4" and .api_key == ""' "$XDG_CONFIG_HOME/psh/config.json" >/dev/null
}

@test "interactive cancel does not execute the generated command" {
  local marker=$PSH_TEST_ROOT/cancel-marker

  require_command script
  mock_hosted_command "touch $marker" "creates a marker" destructive
  export OPENAI_API_KEY=dummy

  run psh_pty n run test cancel

  assert_status 1
  [ ! -e "$marker" ]
}

@test "interactive enter does not execute the generated command" {
  local marker=$PSH_TEST_ROOT/enter-marker

  local input=$'\n'

  require_command script
  mock_hosted_command "touch $marker" "creates a marker" destructive
  export OPENAI_API_KEY=dummy

  run psh_pty "$input" run test enter

  assert_status 1
  [ ! -e "$marker" ]
}

@test "interactive approval executes the generated command" {
  local marker=$PSH_TEST_ROOT/approve-marker

  require_command script
  mock_hosted_command "touch $marker" "creates a marker" needs_approval
  export OPENAI_API_KEY=dummy

  run psh_pty y run test approve

  assert_status 0
  [ -e "$marker" ]
}

@test "interactive uppercase Y executes the generated command" {
  local marker=$PSH_TEST_ROOT/approve-Y-marker

  require_command script
  mock_hosted_command "touch $marker" "creates a marker" needs_approval
  export OPENAI_API_KEY=dummy

  run psh_pty Y run test approve

  assert_status 0
  [ -e "$marker" ]
}

@test "interactive metadata shows review notice and normalized risk" {
  require_command script

  mock_hosted_command true "runs a harmless marker command" unknown
  export OPENAI_API_KEY=dummy

  run psh_pty n run test metadata

  assert_status 1
  [[ "$output" == *"AI-generated command. Review before running."* ]]
  [[ "$output" == *"Risk:"* ]]
  [[ "$output" == *"needs_approval"* ]]
  [[ "$output" == *"runs a harmless marker command"* ]]
}

@test "help -h prints usage" {
  run psh -h

  assert_status 0
  [[ "$output" == *"usage: psh"* ]]
}

@test "help subcommand prints usage" {
  run psh help

  assert_status 0
  [[ "$output" == *"usage: psh"* ]]
}

@test "help extra still prints usage" {
  run psh help extra

  assert_status 0
  [[ "$output" == *"usage: psh"* ]]
}

@test "--help extra still prints usage" {
  run psh --help extra

  assert_status 0
  [[ "$output" == *"usage: psh"* ]]
}

@test "no arguments prints usage and exits 2" {
  require_command setsid

  run psh_no_tty

  assert_status 2
  [[ "$output" == *"usage: psh"* ]]
}

@test "verbose flags without a command print usage and exit 2" {
  require_command setsid

  run psh_no_tty -v

  assert_status 2
  [[ "$output" == *"usage: psh"* ]]
  [[ "$output" != *"API key is required"* ]]
}

@test "double dash without a command prints usage and exits 2" {
  require_command setsid

  run psh_no_tty --

  assert_status 2
  [[ "$output" == *"usage: psh"* ]]
}

@test "verbose --help still prints usage" {
  run psh -v --help

  assert_status 0
  [[ "$output" == *"usage: psh"* ]]
}

@test "install rejects extra arguments" {
  run psh install extra

  assert_status 2
  [[ "$output" == *"usage: psh"* ]]
}

@test "update rejects extra arguments" {
  run psh update extra

  assert_status 2
  [[ "$output" == *"usage: psh"* ]]
}

@test "uninstall rejects unknown flags" {
  run psh uninstall --nope

  assert_status 2
  [[ "$output" == *"usage: psh"* ]]
}

@test "uninstall --purge rejects extra arguments" {
  run psh uninstall --purge extra

  assert_status 2
  [[ "$output" == *"usage: psh"* ]]
}

@test "install.sh rejects extra arguments" {
  run bash "$PSH_REPO_ROOT/install.sh" extra

  assert_status 2
  [[ "$output" == *"usage: install.sh"* ]]
}

@test "uninstall reports when nothing is installed" {
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  run env XDG_BIN_HOME="$bin_home" XDG_DATA_HOME="$PSH_TEST_ROOT/xdg-data" "$PSH_REPO_ROOT/bin/psh.sh" uninstall

  assert_status 0
  [[ "$output" == *"not installed at $bin_home/psh"* ]]
}

@test "uninstall --purge reports when nothing is installed" {
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  run env XDG_BIN_HOME="$bin_home" XDG_DATA_HOME="$PSH_TEST_ROOT/xdg-data" "$PSH_REPO_ROOT/bin/psh.sh" uninstall --purge

  assert_status 0
  [[ "$output" == *"not installed at $bin_home/psh"* ]]
}

@test "uninstall --purge removes config when CLI is not installed" {
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local config_dir=$XDG_CONFIG_HOME/psh

  mkdir -p "$config_dir"
  printf '%s\n' '{"provider":"openai"}' >"$config_dir/config.json"

  run env XDG_BIN_HOME="$bin_home" XDG_DATA_HOME="$PSH_TEST_ROOT/xdg-data" "$PSH_REPO_ROOT/bin/psh.sh" uninstall --purge

  assert_status 0
  [[ "$output" == *"removed $config_dir/config.json"* ]]
  [[ "$output" != *"not installed at $bin_home/psh"* ]]
  [ ! -e "$config_dir/config.json" ]
}

@test "uninstall --purge removes config under HOME/.config when XDG_CONFIG_HOME is unset" {
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local config_dir=$HOME/.config/psh

  mkdir -p "$config_dir"
  printf '%s\n' '{"provider":"openai"}' >"$config_dir/config.json"

  run env -u XDG_CONFIG_HOME XDG_BIN_HOME="$bin_home" XDG_DATA_HOME="$PSH_TEST_ROOT/xdg-data" "$PSH_REPO_ROOT/bin/psh.sh" uninstall --purge

  assert_status 0
  [[ "$output" == *"removed $config_dir/config.json"* ]]
  [ ! -e "$config_dir/config.json" ]
}

@test "uninstall rejects a launcher directory" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  mkdir -p "$bin_home/psh"

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" uninstall

  assert_status 1
  [[ "$output" == *"expected a file at $bin_home/psh"* ]]
}

@test "uninstall removes a dangling launcher symlink" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  mkdir -p "$bin_home"
  ln -s "$bin_home/missing-psh" "$bin_home/psh"

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" uninstall

  assert_status 0
  [[ "$output" == *"removed $bin_home/psh"* ]]
  [ ! -L "$bin_home/psh" ]
  [ ! -e "$bin_home/psh" ]
}

@test "uninstall removes a dangling payload symlink" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  mkdir -p "$data_home/psh"
  ln -s "$data_home/psh/missing-psh.sh" "$data_home/psh/psh.sh"

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" uninstall

  assert_status 0
  [[ "$output" == *"removed $data_home/psh/psh.sh"* ]]
  [[ "$output" != *"not installed at $bin_home/psh"* ]]
  [ ! -L "$data_home/psh/psh.sh" ]
  [ ! -e "$data_home/psh/psh.sh" ]
}

@test "uninstall removes a dangling completion symlink" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local completion=$data_home/bash-completion/completions/psh

  mkdir -p "$(dirname "$completion")"
  ln -s "$data_home/bash-completion/completions/missing-psh" "$completion"

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" uninstall

  assert_status 0
  [[ "$output" == *"removed $completion"* ]]
  [[ "$output" != *"not installed at $bin_home/psh"* ]]
  [ ! -L "$completion" ]
  [ ! -e "$completion" ]
}

@test "uninstall removes payload when launcher is missing" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" install >/dev/null
  rm -f "$bin_home/psh"

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" uninstall

  assert_status 0
  [[ "$output" == *"removed $data_home/psh/psh.sh"* ]]
  [[ "$output" == *"removed $data_home/bash-completion/completions/psh"* ]]
  [[ "$output" != *"not installed at $bin_home/psh"* ]]
  [ ! -e "$data_home/psh/psh.sh" ]
  [ ! -e "$data_home/bash-completion/completions/psh" ]
}

@test "uninstall honors PSH_INSTALL_DIR for the launcher" {
  local install_dir=$PSH_TEST_ROOT/install-bin
  local data_home=$PSH_TEST_ROOT/xdg-data

  env PSH_INSTALL_DIR="$install_dir" XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" install >/dev/null

  run env PSH_INSTALL_DIR="$install_dir" XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" uninstall

  assert_status 0
  [[ "$output" == *"removed $install_dir/psh"* ]]
  [ ! -e "$install_dir/psh" ]
  [ ! -e "$data_home/psh/psh.sh" ]
}

@test "uninstall prefers PSH_INSTALL_DIR over XDG_BIN_HOME" {
  local install_dir=$PSH_TEST_ROOT/install-bin
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local data_home=$PSH_TEST_ROOT/xdg-data

  env PSH_INSTALL_DIR="$install_dir" XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" install >/dev/null
  mkdir -p "$bin_home"
  printf 'other\n' >"$bin_home/psh"

  run env PSH_INSTALL_DIR="$install_dir" XDG_BIN_HOME="$bin_home" XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" uninstall

  assert_status 0
  [[ "$output" == *"removed $install_dir/psh"* ]]
  [ ! -e "$install_dir/psh" ]
  [ -f "$bin_home/psh" ]
}

@test "uninstall uses XDG_BIN_HOME when PSH_INSTALL_DIR is empty" {
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local data_home=$PSH_TEST_ROOT/xdg-data

  env XDG_BIN_HOME="$bin_home" XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" install >/dev/null

  run env PSH_INSTALL_DIR= XDG_BIN_HOME="$bin_home" XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" uninstall

  assert_status 0
  [[ "$output" == *"removed $bin_home/psh"* ]]
  [ ! -e "$bin_home/psh" ]
  [ ! -e "$data_home/psh/psh.sh" ]
}

@test "uninstall uses HOME local bin when XDG_BIN_HOME is empty" {
  local data_home=$PSH_TEST_ROOT/xdg-data

  env XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" install >/dev/null

  run env XDG_BIN_HOME= XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" uninstall

  assert_status 0
  [[ "$output" == *"removed $HOME/.local/bin/psh"* ]]
  [[ "$output" == *"removed $data_home/psh/psh.sh"* ]]
  [ ! -e "$HOME/.local/bin/psh" ]
  [ ! -e "$data_home/psh/psh.sh" ]
}

@test "uninstall uses HOME local share when XDG_DATA_HOME is empty" {
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  env XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" install >/dev/null

  run env XDG_DATA_HOME= XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" uninstall

  assert_status 0
  [[ "$output" == *"removed $bin_home/psh"* ]]
  [[ "$output" == *"removed $HOME/.local/share/psh/psh.sh"* ]]
  [[ "$output" == *"removed $HOME/.local/share/bash-completion/completions/psh"* ]]
  [ ! -e "$bin_home/psh" ]
  [ ! -e "$HOME/.local/share/psh/psh.sh" ]
  [ ! -e "$HOME/.local/share/bash-completion/completions/psh" ]
}

@test "update reinstalls launcher and payload" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" install >/dev/null
  printf 'stale\n' >"$data_home/psh/psh.sh"

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" update

  assert_status 0
  [[ "$output" == *"payload $data_home/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  grep -q 'usage: psh' "$data_home/psh/psh.sh"
}

@test "update from a checkout does not download psh" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" install >/dev/null
  printf 'stale\n' >"$data_home/psh/psh.sh"

  cat >"$PSH_MOCK_BIN/curl" <<'EOF'
#!/bin/sh
printf 'curl should not be called for checkout update\n' >&2
exit 1
EOF
  chmod +x "$PSH_MOCK_BIN/curl"

  cat >"$PSH_MOCK_BIN/wget" <<'EOF'
#!/bin/sh
printf 'wget should not be called for checkout update\n' >&2
exit 1
EOF
  chmod +x "$PSH_MOCK_BIN/wget"

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" update

  assert_status 0
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [ -x "$bin_home/psh" ]
  [ -x "$data_home/psh/psh.sh" ]
  grep -q 'usage: psh' "$data_home/psh/psh.sh"
}

@test "update via installed launcher does not download" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" install >/dev/null

  cat >"$PSH_MOCK_BIN/curl" <<'EOF'
#!/bin/sh
printf 'curl should not be called for launcher update\n' >&2
exit 1
EOF
  chmod +x "$PSH_MOCK_BIN/curl"

  cat >"$PSH_MOCK_BIN/wget" <<'EOF'
#!/bin/sh
printf 'wget should not be called for launcher update\n' >&2
exit 1
EOF
  chmod +x "$PSH_MOCK_BIN/wget"

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$bin_home/psh" update

  assert_status 0
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [ -x "$bin_home/psh" ]
  [ -x "$data_home/psh/psh.sh" ]
  grep -q 'usage: psh' "$data_home/psh/psh.sh"
}

@test "update installs when nothing is already installed" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" update

  assert_status 0
  [[ "$output" == *"payload $data_home/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [[ "$output" == *"completion $data_home/bash-completion/completions/psh"* ]]
  [ -x "$data_home/psh/psh.sh" ]
  [ -x "$bin_home/psh" ]
  [ -f "$data_home/bash-completion/completions/psh" ]
}

@test "update reports config path and setup hint" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" update

  assert_status 0
  [[ "$output" == *"config $XDG_CONFIG_HOME/psh/config.json"* ]]
  [[ "$output" == *"run \`psh setup\` before the first hosted-provider request"* ]]
}

@test "update reports config under HOME/.config when XDG_CONFIG_HOME is unset" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  run env -u XDG_CONFIG_HOME XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" update

  assert_status 0
  [[ "$output" == *"config $HOME/.config/psh/config.json"* ]]
}

@test "update hints when launcher directory is not on PATH" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" update

  assert_status 0
  [[ "$output" == *"add $bin_home to PATH to run \`psh\` directly"* ]]
}

@test "update does not hint when launcher directory is on PATH" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  mkdir -p "$bin_home"
  run env PATH="$bin_home:$PATH" XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" update

  assert_status 0
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [[ "$output" != *"add $bin_home to PATH to run \`psh\` directly"* ]]
}

@test "update hints when PSH_INSTALL_DIR is not on PATH" {
  local install_dir=$PSH_TEST_ROOT/install-bin
  local data_home=$PSH_TEST_ROOT/xdg-data

  run env PSH_INSTALL_DIR="$install_dir" XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" update

  assert_status 0
  [[ "$output" == *"add $install_dir to PATH to run \`psh\` directly"* ]]
}

@test "update does not hint when PSH_INSTALL_DIR is on PATH" {
  local install_dir=$PSH_TEST_ROOT/install-bin
  local data_home=$PSH_TEST_ROOT/xdg-data

  mkdir -p "$install_dir"
  run env PATH="$install_dir:$PATH" PSH_INSTALL_DIR="$install_dir" XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" update

  assert_status 0
  [[ "$output" == *"launcher $install_dir/psh"* ]]
  [[ "$output" != *"add $install_dir to PATH to run \`psh\` directly"* ]]
}

@test "update reinstalls bash completion" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local completion=$data_home/bash-completion/completions/psh

  env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" install >/dev/null
  rm -f "$completion"

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" update

  assert_status 0
  [[ "$output" == *"completion $completion"* ]]
  [ -f "$completion" ]
  grep -q 'complete -F _psh psh' "$completion"
}

@test "install honors PSH_INSTALL_NAME for the launcher" {
  local install_dir=$PSH_TEST_ROOT/install-bin
  local data_home=$PSH_TEST_ROOT/xdg-data

  run env PSH_INSTALL_NAME=psh-alt PSH_INSTALL_DIR="$install_dir" XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" install

  assert_status 0
  [[ "$output" == *"launcher $install_dir/psh-alt"* ]]
  [ -x "$install_dir/psh-alt" ]
  [ ! -e "$install_dir/psh" ]
}

@test "uninstall honors PSH_INSTALL_NAME for the launcher" {
  local install_dir=$PSH_TEST_ROOT/install-bin
  local data_home=$PSH_TEST_ROOT/xdg-data

  env PSH_INSTALL_NAME=psh-alt PSH_INSTALL_DIR="$install_dir" XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" install >/dev/null

  run env PSH_INSTALL_NAME=psh-alt PSH_INSTALL_DIR="$install_dir" XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" uninstall

  assert_status 0
  [[ "$output" == *"removed $install_dir/psh-alt"* ]]
  [ ! -e "$install_dir/psh-alt" ]
  [ ! -e "$data_home/psh/psh.sh" ]
}

@test "update honors PSH_INSTALL_NAME for the launcher" {
  local install_dir=$PSH_TEST_ROOT/install-bin
  local data_home=$PSH_TEST_ROOT/xdg-data

  env PSH_INSTALL_NAME=psh-alt PSH_INSTALL_DIR="$install_dir" XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" install >/dev/null
  printf 'stale\n' >"$data_home/psh/psh.sh"

  run env PSH_INSTALL_NAME=psh-alt PSH_INSTALL_DIR="$install_dir" XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" update

  assert_status 0
  [[ "$output" == *"launcher $install_dir/psh-alt"* ]]
  [ -x "$install_dir/psh-alt" ]
  [ ! -e "$install_dir/psh" ]
  grep -q 'usage: psh' "$data_home/psh/psh.sh"
}

@test "update honors PSH_INSTALL_DIR for the launcher" {
  local install_dir=$PSH_TEST_ROOT/install-bin
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  env PSH_INSTALL_DIR="$install_dir" XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" install >/dev/null
  printf 'stale\n' >"$data_home/psh/psh.sh"

  run env PSH_INSTALL_DIR="$install_dir" XDG_BIN_HOME="$bin_home" XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" update

  assert_status 0
  [[ "$output" == *"launcher $install_dir/psh"* ]]
  [ -x "$install_dir/psh" ]
  [ ! -e "$bin_home/psh" ]
  grep -q 'usage: psh' "$data_home/psh/psh.sh"
}

@test "update uses XDG_BIN_HOME when PSH_INSTALL_DIR is empty" {
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local data_home=$PSH_TEST_ROOT/xdg-data

  env XDG_BIN_HOME="$bin_home" XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" install >/dev/null
  printf 'stale\n' >"$data_home/psh/psh.sh"

  run env PSH_INSTALL_DIR= XDG_BIN_HOME="$bin_home" XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" update

  assert_status 0
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [ -x "$bin_home/psh" ]
  [ -x "$data_home/psh/psh.sh" ]
  grep -q 'usage: psh' "$data_home/psh/psh.sh"
}

@test "update uses HOME local bin when XDG_BIN_HOME is empty" {
  local data_home=$PSH_TEST_ROOT/xdg-data

  env XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" install >/dev/null
  printf 'stale\n' >"$data_home/psh/psh.sh"

  run env XDG_BIN_HOME= XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" update

  assert_status 0
  [[ "$output" == *"payload $data_home/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $HOME/.local/bin/psh"* ]]
  [ -x "$data_home/psh/psh.sh" ]
  [ -x "$HOME/.local/bin/psh" ]
  grep -q 'usage: psh' "$data_home/psh/psh.sh"
}

@test "update uses HOME local share when XDG_DATA_HOME is empty" {
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  env XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" install >/dev/null
  printf 'stale\n' >"$HOME/.local/share/psh/psh.sh"

  run env XDG_DATA_HOME= XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" update

  assert_status 0
  [[ "$output" == *"payload $HOME/.local/share/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [[ "$output" == *"completion $HOME/.local/share/bash-completion/completions/psh"* ]]
  [ -x "$HOME/.local/share/psh/psh.sh" ]
  [ -x "$bin_home/psh" ]
  [ -f "$HOME/.local/share/bash-completion/completions/psh" ]
  grep -q 'usage: psh' "$HOME/.local/share/psh/psh.sh"
}

@test "install completion stays named psh when launcher name changes" {
  local install_dir=$PSH_TEST_ROOT/install-bin
  local data_home=$PSH_TEST_ROOT/xdg-data

  run env PSH_INSTALL_NAME=psh-alt PSH_INSTALL_DIR="$install_dir" XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" install

  assert_status 0
  [[ "$output" == *"completion $data_home/bash-completion/completions/psh"* ]]
  [ -f "$data_home/bash-completion/completions/psh" ]
  [ ! -e "$data_home/bash-completion/completions/psh-alt" ]
}

@test "install falls back to HOME local share and bin directories" {
  run psh install

  assert_status 0
  [[ "$output" == *"payload $HOME/.local/share/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $HOME/.local/bin/psh"* ]]
  [[ "$output" == *"completion $HOME/.local/share/bash-completion/completions/psh"* ]]
  [ -x "$HOME/.local/share/psh/psh.sh" ]
  [ -x "$HOME/.local/bin/psh" ]
  [ -f "$HOME/.local/share/bash-completion/completions/psh" ]
}

@test "install honors PSH_INSTALL_NAME when falling back to HOME local bin" {
  run env PSH_INSTALL_NAME=psh-alt "$PSH_REPO_ROOT/bin/psh.sh" install

  assert_status 0
  [[ "$output" == *"launcher $HOME/.local/bin/psh-alt"* ]]
  [ -x "$HOME/.local/bin/psh-alt" ]
  [ -x "$HOME/.local/share/psh/psh.sh" ]
  [ ! -e "$HOME/.local/bin/psh" ]
}

@test "uninstall honors PSH_INSTALL_NAME when falling back to HOME local bin" {
  env PSH_INSTALL_NAME=psh-alt "$PSH_REPO_ROOT/bin/psh.sh" install >/dev/null

  run env PSH_INSTALL_NAME=psh-alt "$PSH_REPO_ROOT/bin/psh.sh" uninstall

  assert_status 0
  [[ "$output" == *"removed $HOME/.local/bin/psh-alt"* ]]
  [[ "$output" == *"removed $HOME/.local/share/psh/psh.sh"* ]]
  [ ! -e "$HOME/.local/bin/psh-alt" ]
  [ ! -e "$HOME/.local/share/psh/psh.sh" ]
}

@test "update honors PSH_INSTALL_NAME when falling back to HOME local bin" {
  env PSH_INSTALL_NAME=psh-alt "$PSH_REPO_ROOT/bin/psh.sh" install >/dev/null
  printf 'stale\n' >"$HOME/.local/share/psh/psh.sh"

  run env PSH_INSTALL_NAME=psh-alt "$PSH_REPO_ROOT/bin/psh.sh" update

  assert_status 0
  [[ "$output" == *"launcher $HOME/.local/bin/psh-alt"* ]]
  [ -x "$HOME/.local/bin/psh-alt" ]
  [ ! -e "$HOME/.local/bin/psh" ]
  grep -q 'usage: psh' "$HOME/.local/share/psh/psh.sh"
}

@test "uninstall falls back to HOME local share and bin directories" {
  psh install >/dev/null

  run psh uninstall

  assert_status 0
  [[ "$output" == *"removed $HOME/.local/bin/psh"* ]]
  [[ "$output" == *"removed $HOME/.local/share/psh/psh.sh"* ]]
  [[ "$output" == *"removed $HOME/.local/share/bash-completion/completions/psh"* ]]
  [ ! -e "$HOME/.local/bin/psh" ]
  [ ! -e "$HOME/.local/share/psh/psh.sh" ]
  [ ! -e "$HOME/.local/share/bash-completion/completions/psh" ]
}

@test "update falls back to HOME local share and bin directories" {
  psh install >/dev/null
  printf 'stale\n' >"$HOME/.local/share/psh/psh.sh"

  run psh update

  assert_status 0
  [[ "$output" == *"payload $HOME/.local/share/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $HOME/.local/bin/psh"* ]]
  [[ "$output" == *"completion $HOME/.local/share/bash-completion/completions/psh"* ]]
  [ -x "$HOME/.local/share/psh/psh.sh" ]
  [ -x "$HOME/.local/bin/psh" ]
  grep -q 'usage: psh' "$HOME/.local/share/psh/psh.sh"
}

@test "install requires HOME when install path env vars are unset" {
  run env -u HOME -u XDG_DATA_HOME -u XDG_BIN_HOME -u PSH_INSTALL_DIR "$PSH_REPO_ROOT/bin/psh.sh" install

  assert_status 1
  [[ "$output" == *"psh install: HOME is required unless install path env vars are set"* ]]
}

@test "install.sh requires HOME when install path env vars are unset" {
  run env -u HOME -u XDG_DATA_HOME -u XDG_BIN_HOME -u PSH_INSTALL_DIR bash "$PSH_REPO_ROOT/install.sh"

  assert_status 1
  [[ "$output" == *"psh install: HOME is required unless install path env vars are set"* ]]
}

@test "install succeeds without HOME when XDG install paths are set" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  run env -u HOME XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" install

  assert_status 0
  [[ "$output" == *"payload $data_home/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [[ "$output" == *"completion $data_home/bash-completion/completions/psh"* ]]
  [ -x "$data_home/psh/psh.sh" ]
  [ -x "$bin_home/psh" ]
  [ -f "$data_home/bash-completion/completions/psh" ]
}

@test "uninstall succeeds without HOME when XDG install paths are set" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" install >/dev/null

  run env -u HOME XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" uninstall

  assert_status 0
  [[ "$output" == *"removed $bin_home/psh"* ]]
  [[ "$output" == *"removed $data_home/psh/psh.sh"* ]]
  [[ "$output" == *"removed $data_home/bash-completion/completions/psh"* ]]
  [ ! -e "$bin_home/psh" ]
  [ ! -e "$data_home/psh/psh.sh" ]
  [ ! -e "$data_home/bash-completion/completions/psh" ]
}

@test "update succeeds without HOME when XDG install paths are set" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" install >/dev/null
  printf 'stale\n' >"$data_home/psh/psh.sh"

  run env -u HOME XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" update

  assert_status 0
  [[ "$output" == *"payload $data_home/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $bin_home/psh"* ]]
  [ -x "$data_home/psh/psh.sh" ]
  [ -x "$bin_home/psh" ]
  grep -q 'usage: psh' "$data_home/psh/psh.sh"
}

@test "install succeeds without HOME when PSH_INSTALL_DIR is set" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local install_dir=$PSH_TEST_ROOT/install-bin

  run env -u HOME PSH_INSTALL_DIR="$install_dir" XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" install

  assert_status 0
  [[ "$output" == *"payload $data_home/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $install_dir/psh"* ]]
  [[ "$output" == *"completion $data_home/bash-completion/completions/psh"* ]]
  [ -x "$data_home/psh/psh.sh" ]
  [ -x "$install_dir/psh" ]
  [ -f "$data_home/bash-completion/completions/psh" ]
}

@test "uninstall succeeds without HOME when PSH_INSTALL_DIR is set" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local install_dir=$PSH_TEST_ROOT/install-bin

  env PSH_INSTALL_DIR="$install_dir" XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" install >/dev/null

  run env -u HOME PSH_INSTALL_DIR="$install_dir" XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" uninstall

  assert_status 0
  [[ "$output" == *"removed $install_dir/psh"* ]]
  [[ "$output" == *"removed $data_home/psh/psh.sh"* ]]
  [[ "$output" == *"removed $data_home/bash-completion/completions/psh"* ]]
  [ ! -e "$install_dir/psh" ]
  [ ! -e "$data_home/psh/psh.sh" ]
  [ ! -e "$data_home/bash-completion/completions/psh" ]
}

@test "update succeeds without HOME when PSH_INSTALL_DIR is set" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local install_dir=$PSH_TEST_ROOT/install-bin

  env PSH_INSTALL_DIR="$install_dir" XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" install >/dev/null
  printf 'stale\n' >"$data_home/psh/psh.sh"

  run env -u HOME PSH_INSTALL_DIR="$install_dir" XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" update

  assert_status 0
  [[ "$output" == *"payload $data_home/psh/psh.sh"* ]]
  [[ "$output" == *"launcher $install_dir/psh"* ]]
  [ -x "$data_home/psh/psh.sh" ]
  [ -x "$install_dir/psh" ]
  grep -q 'usage: psh' "$data_home/psh/psh.sh"
}

@test "piped install.sh requires curl or wget" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local install_dir=$PSH_TEST_ROOT/pipe-install-bin
  local limited=$PSH_TEST_ROOT/limited-bin
  local bash_bin

  bash_bin=$(command -v bash)
  mkdir -p "$limited"
  ln -s "$(command -v mktemp)" "$limited/mktemp"
  ln -s "$(command -v rm)" "$limited/rm"

  run bash -c 'cat "$1" | PATH="$2" PSH_INSTALL_DIR="$3" XDG_DATA_HOME="$4" "$5"' bash "$PSH_REPO_ROOT/install.sh" "$limited" "$install_dir" "$data_home" "$bash_bin"

  assert_status 2
  [[ "$output" == *"install.sh: curl or wget is required"* ]]
}

@test "piped install.sh uses wget when curl is missing" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local install_dir=$PSH_TEST_ROOT/pipe-install-bin
  local limited=$PSH_TEST_ROOT/limited-bin
  local bash_bin
  local raw_base=https://example.test/promptshell
  local cmd

  bash_bin=$(command -v bash)
  mkdir -p "$limited"
  for cmd in mktemp rm mkdir chmod cp dirname sed install sh basename cat; do
    command -v "$cmd" >/dev/null 2>&1 || continue
    ln -s "$(command -v "$cmd")" "$limited/$cmd"
  done

  cat >"$limited/wget" <<'MOCK_WGET'
#!/bin/sh

out=
url=

while [ "$#" -gt 0 ]; do
  case $1 in
    -qO)
      shift
      out=${1:-}
      ;;
    http*)
      url=$1
      ;;
  esac
  shift || break
done

if [ -n "${PSH_EXPECT_INSTALL_SOURCE:-}" ] && [ "$url" != "$PSH_EXPECT_INSTALL_SOURCE" ]; then
  printf 'unexpected install source: %s\n' "$url" >&2
  exit 2
fi

if [ -z "${PSH_INSTALL_SOURCE_FILE:-}" ]; then
  printf 'missing PSH_INSTALL_SOURCE_FILE\n' >&2
  exit 2
fi

[ -n "$out" ] || exit 2
cp "$PSH_INSTALL_SOURCE_FILE" "$out"
MOCK_WGET
  chmod +x "$limited/wget"

  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run bash -c 'cat "$1" | PATH="$2" PSH_INSTALL_DIR="$3" XDG_DATA_HOME="$4" PSH_RAW_BASE="$5" "$6"' bash "$PSH_REPO_ROOT/install.sh" "$limited" "$install_dir" "$data_home" "$raw_base" "$bash_bin"

  assert_status 0
  [[ "$output" == *"launcher $install_dir/psh"* ]]
  [ -x "$install_dir/psh" ]
  [ -x "$data_home/psh/psh.sh" ]
}

@test "piped install requires curl or wget" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local install_dir=$PSH_TEST_ROOT/pipe-install-bin
  local limited=$PSH_TEST_ROOT/limited-bin
  local sh_bin

  sh_bin=$(command -v sh)
  mkdir -p "$limited"
  ln -s "$(command -v mktemp)" "$limited/mktemp"
  ln -s "$(command -v rm)" "$limited/rm"

  run sh -c 'cat "$1" | PATH="$2" PSH_INSTALL_DIR="$3" XDG_DATA_HOME="$4" "$5" -s -- install' sh "$PSH_REPO_ROOT/bin/psh.sh" "$limited" "$install_dir" "$data_home" "$sh_bin"

  assert_status 2
  [[ "$output" == *"psh install: curl or wget is required"* ]]
}

@test "piped install uses wget when curl is missing" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local install_dir=$PSH_TEST_ROOT/pipe-install-bin
  local limited=$PSH_TEST_ROOT/limited-bin
  local sh_bin
  local raw_base=https://example.test/promptshell
  local cmd

  sh_bin=$(command -v sh)
  mkdir -p "$limited"
  for cmd in mktemp rm mkdir chmod cp dirname sed install sh basename cat; do
    command -v "$cmd" >/dev/null 2>&1 || continue
    ln -s "$(command -v "$cmd")" "$limited/$cmd"
  done

  cat >"$limited/wget" <<'MOCK_WGET'
#!/bin/sh

out=
url=

while [ "$#" -gt 0 ]; do
  case $1 in
    -qO)
      shift
      out=${1:-}
      ;;
    http*)
      url=$1
      ;;
  esac
  shift || break
done

if [ -n "${PSH_EXPECT_INSTALL_SOURCE:-}" ] && [ "$url" != "$PSH_EXPECT_INSTALL_SOURCE" ]; then
  printf 'unexpected install source: %s\n' "$url" >&2
  exit 2
fi

if [ -z "${PSH_INSTALL_SOURCE_FILE:-}" ]; then
  printf 'missing PSH_INSTALL_SOURCE_FILE\n' >&2
  exit 2
fi

[ -n "$out" ] || exit 2
cp "$PSH_INSTALL_SOURCE_FILE" "$out"
MOCK_WGET
  chmod +x "$limited/wget"

  export PSH_RAW_BASE=$raw_base
  export PSH_EXPECT_INSTALL_SOURCE=$raw_base/bin/psh.sh
  export PSH_INSTALL_SOURCE_FILE=$PSH_REPO_ROOT/bin/psh.sh

  run sh -c 'cat "$1" | PATH="$2" PSH_INSTALL_DIR="$3" XDG_DATA_HOME="$4" PSH_RAW_BASE="$5" "$6" -s -- install' sh "$PSH_REPO_ROOT/bin/psh.sh" "$limited" "$install_dir" "$data_home" "$raw_base" "$sh_bin"

  assert_status 0
  [[ "$output" == *"launcher $install_dir/psh"* ]]
  [ -x "$install_dir/psh" ]
  [ -x "$data_home/psh/psh.sh" ]
}

@test "setup without a tty exits 2" {
  require_command setsid

  run psh_no_tty setup

  assert_status 2
  [[ "$output" == *"setup requires an interactive terminal"* ]]
}

@test "setup model without a tty exits 2" {
  require_command setsid

  run psh_no_tty setup model

  assert_status 2
  [[ "$output" == *"setup model requires an interactive terminal"* ]]
}

@test "setup model without saved config exits 2" {
  require_command script

  run psh_pty n setup model

  assert_status 2
  [[ "$output" == *"run \`psh setup\` before changing only the model"* ]]
}

@test "setup model without saved API key exits 2" {
  require_command script

  mkdir -p "$XDG_CONFIG_HOME/psh"
  jq -n '{provider: "openai", model: "gpt-4.1-mini", api_key: ""}' >"$XDG_CONFIG_HOME/psh/config.json"

  run psh_pty n setup model

  assert_status 2
  [[ "$output" == *"run \`psh setup\` before changing only the model"* ]]
}

@test "setup model can change a CLI provider model without an API key" {
  require_command script

  mkdir -p "$XDG_CONFIG_HOME/psh"
  jq -n '{provider: "codex", model: "gpt-5.5", api_key: ""}' >"$XDG_CONFIG_HOME/psh/config.json"

  run psh_pty $'\033[B\n' setup model

  assert_status 0
  jq -e '.provider == "codex" and .model == "gpt-5.4" and .api_key == ""' "$XDG_CONFIG_HOME/psh/config.json" >/dev/null
}

@test "setup model rejects unsupported provider in config" {
  require_command script

  mkdir -p "$XDG_CONFIG_HOME/psh"
  jq -n '{provider: "nope", model: "x", api_key: "k"}' >"$XDG_CONFIG_HOME/psh/config.json"

  run psh_pty n setup model

  assert_status 2
  [[ "$output" == *"unsupported provider in config: nope"* ]]
}

@test "setup rejects extra arguments" {
  require_command script

  run psh_pty n setup extra

  assert_status 2
  [[ "$output" == *"usage: psh"* ]]
}

@test "setup model rejects extra arguments" {
  run psh setup model extra

  assert_status 2
  [[ "$output" == *"usage: psh"* ]]
}

@test "setup model changes only the model" {
  require_command script

  mkdir -p "$XDG_CONFIG_HOME/psh"
  jq -n '{provider: "openai", model: "gpt-4.1-mini", api_key: "keep-me"}' >"$XDG_CONFIG_HOME/psh/config.json"

  run psh_pty $'\033[B\n' setup model

  assert_status 0
  jq -e '.provider == "openai" and .model == "gpt-4.1" and .api_key == "keep-me"' "$XDG_CONFIG_HOME/psh/config.json" >/dev/null
}

@test "OPENAI_MODEL is sent in the hosted request" {
  local request_file=$PSH_TEST_ROOT/request.json

  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy
  export OPENAI_MODEL=gpt-4.1
  export PSH_CAPTURE_REQUEST=$request_file

  run psh_no_tty run say hi

  assert_status 0
  jq -e '.model == "gpt-4.1"' "$request_file" >/dev/null
}

@test "FIREWORKS_MODEL is sent in the hosted request" {
  local request_file=$PSH_TEST_ROOT/request.json

  require_command setsid
  mock_hosted_command true
  export PSH_PROVIDER=fireworks
  export FIREWORKS_API_KEY=dummy
  export FIREWORKS_MODEL=accounts/fireworks/models/deepseek-r1
  export PSH_CAPTURE_REQUEST=$request_file

  run psh_no_tty run say hi

  assert_status 0
  jq -e '.model == "accounts/fireworks/models/deepseek-r1"' "$request_file" >/dev/null
}

@test "PSH_MODEL is used when provider-specific model env is unset" {
  local request_file=$PSH_TEST_ROOT/request.json

  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy
  export PSH_MODEL=gpt-4o-mini
  export PSH_CAPTURE_REQUEST=$request_file

  run psh_no_tty run say hi

  assert_status 0
  jq -e '.model == "gpt-4o-mini"' "$request_file" >/dev/null
}

@test "OPENAI_MODEL overrides PSH_MODEL" {
  local request_file=$PSH_TEST_ROOT/request.json

  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy
  export OPENAI_MODEL=gpt-4.1
  export PSH_MODEL=gpt-4o-mini
  export PSH_CAPTURE_REQUEST=$request_file

  run psh_no_tty run say hi

  assert_status 0
  jq -e '.model == "gpt-4.1"' "$request_file" >/dev/null
}

@test "FIREWORKS_MODEL overrides PSH_MODEL" {
  local request_file=$PSH_TEST_ROOT/request.json

  require_command setsid
  mock_hosted_command true
  export PSH_PROVIDER=fireworks
  export FIREWORKS_API_KEY=dummy
  export FIREWORKS_MODEL=accounts/fireworks/models/deepseek-r1
  export PSH_MODEL=accounts/fireworks/models/deepseek-v3p1
  export PSH_CAPTURE_REQUEST=$request_file

  run psh_no_tty run say hi

  assert_status 0
  jq -e '.model == "accounts/fireworks/models/deepseek-r1"' "$request_file" >/dev/null
}

@test "PSH_MODEL overrides saved config model" {
  local request_file=$PSH_TEST_ROOT/request.json

  require_command setsid
  mock_hosted_command true
  mkdir -p "$XDG_CONFIG_HOME/psh"
  jq -n '{provider: "openai", model: "gpt-4o-mini", api_key: "from-config"}' >"$XDG_CONFIG_HOME/psh/config.json"
  export PSH_MODEL=gpt-4.1
  export PSH_CAPTURE_REQUEST=$request_file

  run psh_no_tty run say hi

  assert_status 0
  jq -e '.model == "gpt-4.1"' "$request_file" >/dev/null
}

@test "PSH_API_KEY is accepted as a hosted key fallback" {
  require_command setsid
  mock_hosted_command true
  export PSH_API_KEY=fallback-key

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
}

@test "saved config api_key is used when env keys are unset" {
  require_command setsid
  mock_hosted_command true
  mkdir -p "$XDG_CONFIG_HOME/psh"
  jq -n '{provider: "openai", model: "gpt-4.1-mini", api_key: "from-config"}' >"$XDG_CONFIG_HOME/psh/config.json"

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
}

@test "saved config provider is used when PSH_PROVIDER is unset" {
  local url_file=$PSH_TEST_ROOT/url.txt

  require_command setsid
  mock_hosted_command true
  mkdir -p "$XDG_CONFIG_HOME/psh"
  jq -n '{provider: "fireworks", model: "", api_key: "from-config"}' >"$XDG_CONFIG_HOME/psh/config.json"
  export PSH_CAPTURE_URL=$url_file

  run psh_no_tty run say hi

  assert_status 0
  [ "$(<"$url_file")" = "https://api.fireworks.ai/inference/v1/chat/completions" ]
}

@test "PSH_PROVIDER overrides saved config provider" {
  local url_file=$PSH_TEST_ROOT/url.txt

  require_command setsid
  mock_hosted_command true
  mkdir -p "$XDG_CONFIG_HOME/psh"
  jq -n '{provider: "fireworks", model: "", api_key: "from-config"}' >"$XDG_CONFIG_HOME/psh/config.json"
  export PSH_PROVIDER=openai
  export OPENAI_API_KEY=dummy
  export PSH_CAPTURE_URL=$url_file

  run psh_no_tty run say hi

  assert_status 0
  [ "$(<"$url_file")" = "https://api.openai.com/v1/chat/completions" ]
}

@test "saved config model is sent in the hosted request" {
  local request_file=$PSH_TEST_ROOT/request.json

  require_command setsid
  mock_hosted_command true
  mkdir -p "$XDG_CONFIG_HOME/psh"
  jq -n '{provider: "openai", model: "gpt-4o-mini", api_key: "from-config"}' >"$XDG_CONFIG_HOME/psh/config.json"
  export PSH_CAPTURE_REQUEST=$request_file

  run psh_no_tty run say hi

  assert_status 0
  jq -e '.model == "gpt-4o-mini"' "$request_file" >/dev/null
}

@test "openai hosted URL is used by default" {
  local url_file=$PSH_TEST_ROOT/url.txt

  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy
  export PSH_CAPTURE_URL=$url_file

  run psh_no_tty run say hi

  assert_status 0
  [ "$(<"$url_file")" = "https://api.openai.com/v1/chat/completions" ]
}

@test "hosted openai uses the default model when none is configured" {
  local request_file=$PSH_TEST_ROOT/request.json

  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy
  export PSH_CAPTURE_REQUEST=$request_file

  run psh_no_tty run say hi

  assert_status 0
  jq -e '.model == "gpt-4.1-mini"' "$request_file" >/dev/null
}

@test "hosted fireworks uses the default model when none is configured" {
  local request_file=$PSH_TEST_ROOT/request.json

  require_command setsid
  mock_hosted_command true
  export PSH_PROVIDER=fireworks
  export FIREWORKS_API_KEY=dummy
  export PSH_CAPTURE_REQUEST=$request_file

  run psh_no_tty run say hi

  assert_status 0
  jq -e '.model == "accounts/fireworks/models/deepseek-v3p1"' "$request_file" >/dev/null
}

@test "CODEX_MODEL is passed to codex with -m" {
  require_command setsid

  local model_file=$PSH_TEST_ROOT/codex-model.txt

  mock_codex_command true
  export PSH_PROVIDER=codex
  export CODEX_MODEL=gpt-5.4-mini
  export PSH_CAPTURE_CODEX_MODEL=$model_file

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
  [ "$(<"$model_file")" = "gpt-5.4-mini" ]
}

@test "PSH_MODEL is used for codex when CODEX_MODEL is unset" {
  require_command setsid

  local model_file=$PSH_TEST_ROOT/codex-model.txt

  mock_codex_command true
  export PSH_PROVIDER=codex
  export PSH_MODEL=gpt-5.4-mini
  export PSH_CAPTURE_CODEX_MODEL=$model_file

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
  [ "$(<"$model_file")" = "gpt-5.4-mini" ]
}

@test "CODEX_MODEL overrides PSH_MODEL" {
  require_command setsid

  local model_file=$PSH_TEST_ROOT/codex-model.txt

  mock_codex_command true
  export PSH_PROVIDER=codex
  export CODEX_MODEL=gpt-5.4-mini
  export PSH_MODEL=gpt-5.5
  export PSH_CAPTURE_CODEX_MODEL=$model_file

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
  [ "$(<"$model_file")" = "gpt-5.4-mini" ]
}

@test "GROK_MODEL is passed to grok with -m" {
  require_command setsid

  local argv_file=$PSH_TEST_ROOT/grok-argv.txt

  mock_grok_command true
  export PSH_PROVIDER=grok
  export GROK_MODEL=grok-4.5
  export PSH_CAPTURE_HARNESS_ARGV=$argv_file

  run psh_no_tty run say hi

  assert_status 0
  [[ "$(<"$argv_file")" == *"-m grok-4.5"* ]]
}

@test "PSH_MODEL is used for grok when GROK_MODEL is unset" {
  require_command setsid

  local argv_file=$PSH_TEST_ROOT/grok-argv.txt

  mock_grok_command true
  export PSH_PROVIDER=grok
  export PSH_MODEL=grok-4.5
  export PSH_CAPTURE_HARNESS_ARGV=$argv_file

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
  [[ "$(<"$argv_file")" == *"-m grok-4.5"* ]]
}

@test "GROK_MODEL overrides PSH_MODEL" {
  require_command setsid

  local argv_file=$PSH_TEST_ROOT/grok-argv.txt

  mock_grok_command true
  export PSH_PROVIDER=grok
  export GROK_MODEL=grok-4.5
  export PSH_MODEL=grok-4.6
  export PSH_CAPTURE_HARNESS_ARGV=$argv_file

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
  [[ "$(<"$argv_file")" == *"-m grok-4.5"* ]]
  [[ "$(<"$argv_file")" != *"-m grok-4.6"* ]]
}

@test "grok uses the default model when none is configured" {
  require_command setsid

  local argv_file=$PSH_TEST_ROOT/grok-argv.txt

  mock_grok_command true
  export PSH_PROVIDER=grok
  export PSH_CAPTURE_HARNESS_ARGV=$argv_file

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
  [[ "$(<"$argv_file")" == *"-m grok-4.6"* ]]
}

@test "config model matching the provider id uses the default model" {
  require_command setsid

  local argv_file=$PSH_TEST_ROOT/grok-argv.txt

  mkdir -p "$XDG_CONFIG_HOME/psh"
  jq -n '{provider: "grok", model: "grok", api_key: ""}' >"$XDG_CONFIG_HOME/psh/config.json"
  mock_grok_command true
  export PSH_CAPTURE_HARNESS_ARGV=$argv_file

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
  [[ "$(<"$argv_file")" == *"-m grok-4.6"* ]]
}

@test "CLAUDE_MODEL is passed to claude with --model" {
  require_command setsid

  local argv_file=$PSH_TEST_ROOT/claude-argv.txt

  mock_claude_command true
  export PSH_PROVIDER=claude
  export CLAUDE_MODEL=opus
  export PSH_CAPTURE_HARNESS_ARGV=$argv_file

  run psh_no_tty run say hi

  assert_status 0
  [[ "$(<"$argv_file")" == *"--model opus"* ]]
}

@test "PSH_MODEL is used for claude when CLAUDE_MODEL is unset" {
  require_command setsid

  local argv_file=$PSH_TEST_ROOT/claude-argv.txt

  mock_claude_command true
  export PSH_PROVIDER=claude
  export PSH_MODEL=opus
  export PSH_CAPTURE_HARNESS_ARGV=$argv_file

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
  [[ "$(<"$argv_file")" == *"--model opus"* ]]
}

@test "CLAUDE_MODEL overrides PSH_MODEL" {
  require_command setsid

  local argv_file=$PSH_TEST_ROOT/claude-argv.txt

  mock_claude_command true
  export PSH_PROVIDER=claude
  export CLAUDE_MODEL=opus
  export PSH_MODEL=sonnet
  export PSH_CAPTURE_HARNESS_ARGV=$argv_file

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
  [[ "$(<"$argv_file")" == *"--model opus"* ]]
  [[ "$(<"$argv_file")" != *"--model sonnet"* ]]
}

@test "claude uses the default model when none is configured" {
  require_command setsid

  local argv_file=$PSH_TEST_ROOT/claude-argv.txt

  mock_claude_command true
  export PSH_PROVIDER=claude
  export PSH_CAPTURE_HARNESS_ARGV=$argv_file

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
  [[ "$(<"$argv_file")" == *"--model sonnet"* ]]
}

@test "GEMINI_MODEL is passed to gemini with -m" {
  require_command setsid

  local argv_file=$PSH_TEST_ROOT/gemini-argv.txt

  mock_gemini_command true
  export PSH_PROVIDER=gemini
  export GEMINI_MODEL=gemini-2.5-pro
  export PSH_CAPTURE_HARNESS_ARGV=$argv_file

  run psh_no_tty run say hi

  assert_status 0
  [[ "$(<"$argv_file")" == *"-m gemini-2.5-pro"* ]]
}

@test "PSH_MODEL is used for gemini when GEMINI_MODEL is unset" {
  require_command setsid

  local argv_file=$PSH_TEST_ROOT/gemini-argv.txt

  mock_gemini_command true
  export PSH_PROVIDER=gemini
  export PSH_MODEL=gemini-2.5-pro
  export PSH_CAPTURE_HARNESS_ARGV=$argv_file

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
  [[ "$(<"$argv_file")" == *"-m gemini-2.5-pro"* ]]
}

@test "GEMINI_MODEL overrides PSH_MODEL" {
  require_command setsid

  local argv_file=$PSH_TEST_ROOT/gemini-argv.txt

  mock_gemini_command true
  export PSH_PROVIDER=gemini
  export GEMINI_MODEL=gemini-2.5-pro
  export PSH_MODEL=gemini-2.5-flash
  export PSH_CAPTURE_HARNESS_ARGV=$argv_file

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
  [[ "$(<"$argv_file")" == *"-m gemini-2.5-pro"* ]]
  [[ "$(<"$argv_file")" != *"-m gemini-2.5-flash"* ]]
}

@test "gemini uses the default model when none is configured" {
  require_command setsid

  local argv_file=$PSH_TEST_ROOT/gemini-argv.txt

  mock_gemini_command true
  export PSH_PROVIDER=gemini
  export PSH_CAPTURE_HARNESS_ARGV=$argv_file

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
  [[ "$(<"$argv_file")" == *"-m gemini-2.5-flash"* ]]
}

@test "invalid model JSON exits 1" {
  require_command setsid
  mock_hosted_content 'not-json'
  export OPENAI_API_KEY=dummy

  run psh_no_tty run say hi

  assert_status 1
  [[ "$output" == *"model returned invalid structured response"* ]]
}

@test "command result missing command exits 1" {
  require_command setsid
  mock_hosted_content '{"type":"command","explanation":"none"}'
  export OPENAI_API_KEY=dummy

  run psh_no_tty run say hi

  assert_status 1
  [[ "$output" == *"generated command is missing a command"* ]]
}

@test "question result missing question exits 1" {
  require_command setsid
  mock_hosted_content '{"type":"question","options":["A"]}'
  export OPENAI_API_KEY=dummy

  run psh_no_tty run say hi

  assert_status 1
  [[ "$output" == *"generated clarification is missing a question"* ]]
}

@test "unknown structured type exits 1" {
  require_command setsid
  mock_hosted_content '{"type":"nope"}'
  export OPENAI_API_KEY=dummy

  run psh_no_tty run say hi

  assert_status 1
  [[ "$output" == *"generated invalid structured response"* ]]
}

@test "think content is stripped from the generated command" {
  require_command setsid
  mock_hosted_content "$(printf '<think>\nhidden-reasoning\n</think>\n%s' "$(command_json true)")"
  export OPENAI_API_KEY=dummy

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
  [[ "$output" != *"hidden-reasoning"* ]]
}

@test "structured JSON is extracted from surrounding text" {
  require_command setsid
  mock_hosted_content "$(printf 'Here you go:\n%s\nThanks.' "$(command_json true)")"
  export OPENAI_API_KEY=dummy

  run psh_no_tty run say hi

  assert_status 0
  [ "$output" = true ]
}

@test "verbose -v prints thinking debug" {
  require_command setsid
  mock_hosted_content "$(printf '<think>\nhidden-reasoning\n</think>\n%s' "$(command_json true)")"
  export OPENAI_API_KEY=dummy

  run psh_no_tty -v run say hi

  assert_status 0
  [[ "$output" == *"psh debug: thinking"* ]]
  [[ "$output" == *"hidden-reasoning"* ]]
}

@test "verbose -v prints debug configuration" {
  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy

  run psh_no_tty -v run say hi

  assert_status 0
  [[ "$output" == *"psh debug: configuration provider=openai"* ]]
}

@test "verbose -v prints hosted request model" {
  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy

  run psh_no_tty -v run say hi

  assert_status 0
  [[ "$output" == *"psh debug: request model=gpt-4.1-mini"* ]]
}

@test "verbose -v prints api response received" {
  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy

  run psh_no_tty -v run say hi

  assert_status 0
  [[ "$output" == *"psh debug: api response received"* ]]
}

@test "verbose -v prints structured parse=direct" {
  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy

  run psh_no_tty -v run say hi

  assert_status 0
  [[ "$output" == *"psh debug: structured parse=direct"* ]]
}

@test "verbose -v prints structured parse=extracted" {
  require_command setsid
  mock_hosted_content "$(printf 'Here you go:\n%s\nThanks.' "$(command_json true)")"
  export OPENAI_API_KEY=dummy

  run psh_no_tty -v run say hi

  assert_status 0
  [[ "$output" == *"psh debug: structured parse=extracted"* ]]
}

@test "verbose -v prints structured parse=invalid" {
  require_command setsid
  mock_hosted_content 'not-json'
  export OPENAI_API_KEY=dummy

  run psh_no_tty -v run say hi

  assert_status 1
  [[ "$output" == *"psh debug: structured parse=invalid"* ]]
}

@test "verbose -v prints structured response type" {
  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy

  run psh_no_tty -v run say hi

  assert_status 0
  [[ "$output" == *"psh debug: structured response type=command"* ]]
}

@test "verbose -v prints structured response type=question" {
  require_command setsid
  mock_hosted_question
  export OPENAI_API_KEY=dummy

  run psh_no_tty -v run say hi

  assert_status 2
  [[ "$output" == *"psh debug: structured response type=question"* ]]
}

@test "verbose -v prints CLI request provider" {
  require_command setsid
  mock_grok_command true
  export PSH_PROVIDER=grok

  run psh_no_tty -v run say hi

  assert_status 0
  [[ "$output" == *"psh debug: request provider=grok"* ]]
}

@test "verbose -v prints CLI provider response received" {
  require_command setsid
  mock_grok_command true
  export PSH_PROVIDER=grok

  run psh_no_tty -v run say hi

  assert_status 0
  [[ "$output" == *"psh debug: grok response received"* ]]
}

@test "verbose -vv prints structured response debug" {
  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy

  run psh_no_tty -vv run say hi

  assert_status 0
  [[ "$output" == *"psh debug: Structured response"* ]]
}

@test "verbose -vv prints Model content debug" {
  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy

  run psh_no_tty -vv run say hi

  assert_status 0
  [[ "$output" == *"psh debug: Model content"* ]]
}

@test "verbose -vv prints message role debug" {
  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy

  run psh_no_tty -vv run say hi

  assert_status 0
  [[ "$output" == *"psh debug: message role=system"* ]]
  [[ "$output" == *"psh debug: message role=user"* ]]
}

@test "verbose -vvv prints request JSON debug" {
  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy

  run psh_no_tty -vvv run say hi

  assert_status 0
  [[ "$output" == *"psh debug: Request JSON"* ]]
}

@test "verbose -vvv prints API response JSON debug" {
  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy

  run psh_no_tty -vvv run say hi

  assert_status 0
  [[ "$output" == *"psh debug: API response JSON"* ]]
}

@test "verbose -vvv prints invalid json placeholder for harness response" {
  require_command setsid
  install_mock_harness grok
  export PSH_HARNESS_OUTPUT='not-json'
  export PSH_PROVIDER=grok

  run psh_no_tty -vvv run say hi

  assert_status 1
  [[ "$output" == *"psh debug: Harness JSON"* ]]
  [[ "$output" == *"<invalid json>"* ]]
}

@test "verbose -vvv prints Codex JSONL debug" {
  require_command setsid
  mock_codex_command true
  export PSH_PROVIDER=codex

  run psh_no_tty -vvv run say hi

  assert_status 0
  [[ "$output" == *"psh debug: Codex JSONL"* ]]
}

@test "verbose -vvv prints Harness JSON debug" {
  require_command setsid
  mock_grok_command true
  export PSH_PROVIDER=grok

  run psh_no_tty -vvv run say hi

  assert_status 0
  [[ "$output" == *"psh debug: Harness JSON"* ]]
}

@test "double dash ends verbosity flags" {
  local request_file=$PSH_TEST_ROOT/request.json

  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy
  export PSH_CAPTURE_REQUEST=$request_file

  run psh_no_tty -- run say hi

  assert_status 0
  jq -e '(.messages[1].content | fromjson | .prompt) == "say hi"' "$request_file" >/dev/null
}

@test "repeated -v does not raise verbosity to -vv" {
  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy

  run psh_no_tty -v -v run say hi

  assert_status 0
  [[ "$output" == *"psh debug: configuration provider=openai"* ]]
  [[ "$output" != *"psh debug: Structured response"* ]]
  [[ "$output" != *"psh debug: Model content"* ]]
}

@test "-v -vv raises verbosity to -vv" {
  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy

  run psh_no_tty -v -vv run say hi

  assert_status 0
  [[ "$output" == *"psh debug: Structured response"* ]]
}

@test "-v -vvv raises verbosity to -vvv" {
  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy

  run psh_no_tty -v -vvv run say hi

  assert_status 0
  [[ "$output" == *"psh debug: Request JSON"* ]]
}

@test "-vv -v does not lower verbosity" {
  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy

  run psh_no_tty -vv -v run say hi

  assert_status 0
  [[ "$output" == *"psh debug: Structured response"* ]]
}

@test "-vvv -v does not lower verbosity" {
  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy

  run psh_no_tty -vvv -v run say hi

  assert_status 0
  [[ "$output" == *"psh debug: Request JSON"* ]]
}

@test "generated command non-zero status is preserved" {
  local marker=$PSH_TEST_ROOT/fail-marker

  require_command script
  mock_hosted_command "touch $marker; exit 7" "fails after touch" safe
  export OPENAI_API_KEY=dummy

  run psh_pty y run test fail

  assert_status 7
  [ -e "$marker" ]
}

@test "interactive clarification uses the selected option then generates a command" {
  require_command script

  install_mock_curl_queue \
    "$(chat_completion '{"type":"question","question":"Which target?","options":["Docker","Images"]}')" \
    "$(chat_completion "$(command_json true)")"
  export OPENAI_API_KEY=dummy

  run psh_pty $'\ny' run clean

  assert_status 0
}

@test "interactive clarification without options uses the typed answer" {
  local request_file=$PSH_TEST_ROOT/request.json

  require_command script

  install_mock_curl_queue \
    "$(chat_completion '{"type":"question","question":"Which target?"}')" \
    "$(chat_completion "$(command_json true)")"
  export OPENAI_API_KEY=dummy
  export PSH_CAPTURE_REQUEST=$request_file

  run psh_pty $'custom-target\n' run clean

  assert_status 1
  jq -e '
    (.messages[1].content | fromjson | .prompt) | test("Clarification: Which target?") and test("Answer: custom-target")
  ' "$request_file" >/dev/null
}

@test "interactive clarification Custom option uses the typed answer" {
  local request_file=$PSH_TEST_ROOT/request.json

  require_command script

  install_mock_curl_queue \
    "$(chat_completion '{"type":"question","question":"Which target?","options":["Docker","Images"]}')" \
    "$(chat_completion "$(command_json true)")"
  export OPENAI_API_KEY=dummy
  export PSH_CAPTURE_REQUEST=$request_file

  run psh_pty $'\033[B\033[B\ncustom-target\n' run clean

  assert_status 1
  jq -e '
    (.messages[1].content | fromjson | .prompt) | test("Clarification: Which target?") and test("Answer: custom-target")
  ' "$request_file" >/dev/null
}

@test "too many clarification rounds exits 1" {
  require_command script
  mock_hosted_question
  export OPENAI_API_KEY=dummy

  run psh_pty $'\n\n\n' run clean

  assert_status 1
  [[ "$output" == *"too many clarification rounds"* ]]
}
