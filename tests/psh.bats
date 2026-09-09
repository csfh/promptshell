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

@test "install launcher execs the XDG payload" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin
  local payload=$data_home/psh/psh.sh

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" install

  assert_status 0
  grep -qx '#!/bin/sh' "$bin_home/psh"
  grep -qx "exec '$payload' \"\$@\"" "$bin_home/psh"
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

@test "missing API key exits 2 before contacting provider" {
  require_command setsid

  run psh_no_tty run clean up docker

  assert_status 2
  [[ "$output" == *"API key is required"* ]]
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

@test "no arguments prints usage and exits 2" {
  require_command setsid

  run psh_no_tty

  assert_status 2
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

@test "uninstall rejects a launcher directory" {
  local data_home=$PSH_TEST_ROOT/xdg-data
  local bin_home=$PSH_TEST_ROOT/xdg-bin

  mkdir -p "$bin_home/psh"

  run env XDG_DATA_HOME="$data_home" XDG_BIN_HOME="$bin_home" "$PSH_REPO_ROOT/bin/psh.sh" uninstall

  assert_status 1
  [[ "$output" == *"expected a file at $bin_home/psh"* ]]
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

@test "install honors PSH_INSTALL_NAME for the launcher" {
  local install_dir=$PSH_TEST_ROOT/install-bin
  local data_home=$PSH_TEST_ROOT/xdg-data

  run env PSH_INSTALL_NAME=psh-alt PSH_INSTALL_DIR="$install_dir" XDG_DATA_HOME="$data_home" "$PSH_REPO_ROOT/bin/psh.sh" install

  assert_status 0
  [[ "$output" == *"launcher $install_dir/psh-alt"* ]]
  [ -x "$install_dir/psh-alt" ]
  [ ! -e "$install_dir/psh" ]
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

@test "verbose -v prints debug configuration" {
  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy

  run psh_no_tty -v run say hi

  assert_status 0
  [[ "$output" == *"psh debug: configuration provider=openai"* ]]
}

@test "verbose -vv prints structured response debug" {
  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy

  run psh_no_tty -vv run say hi

  assert_status 0
  [[ "$output" == *"psh debug: Structured response"* ]]
}

@test "verbose -vvv prints request JSON debug" {
  require_command setsid
  mock_hosted_command true
  export OPENAI_API_KEY=dummy

  run psh_no_tty -vvv run say hi

  assert_status 0
  [[ "$output" == *"psh debug: Request JSON"* ]]
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

@test "too many clarification rounds exits 1" {
  require_command script
  mock_hosted_question
  export OPENAI_API_KEY=dummy

  run psh_pty $'\n\n\n' run clean

  assert_status 1
  [[ "$output" == *"too many clarification rounds"* ]]
}
