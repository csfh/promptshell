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
  [ ! -e "$XDG_CONFIG_HOME/omarchy/plugins/com.mdtrr.promptshell" ]
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
