setup_psh_test() {
  PSH_REPO_ROOT=$(CDPATH= cd "$BATS_TEST_DIRNAME/.." && pwd)
  PSH_TEST_ROOT=$(mktemp -d "${BATS_TMPDIR:-/tmp}/psh-test.XXXXXX")
  PSH_MOCK_BIN=$PSH_TEST_ROOT/bin

  mkdir -p "$PSH_MOCK_BIN" "$PSH_TEST_ROOT/home"

  export PSH_REPO_ROOT
  export PSH_TEST_ROOT
  export PSH_MOCK_BIN
  export PATH="$PSH_MOCK_BIN:$PATH"
  export XDG_CONFIG_HOME="$PSH_TEST_ROOT/config"
  export HOME="$PSH_TEST_ROOT/home"

  unset OPENAI_API_KEY
  unset FIREWORKS_API_KEY
  unset PSH_API_KEY
  unset PSH_PROVIDER
  unset PSH_MODEL
  unset OPENAI_MODEL
  unset FIREWORKS_MODEL
  unset CODEX_MODEL
  unset GROK_MODEL
  unset CLAUDE_MODEL
  unset GEMINI_MODEL
  unset PSH_MOCK_RESPONSE
  unset PSH_CAPTURE_REQUEST
  unset PSH_CAPTURE_URL
  unset PSH_CODEX_JSONL
  unset PSH_CAPTURE_CODEX_PROMPT
  unset PSH_CAPTURE_CODEX_MODEL
  unset PSH_CAPTURE_HARNESS_ARGV
  unset PSH_HARNESS_OUTPUT
  unset PSH_INSTALL_DIR
  unset PSH_INSTALL_NAME
  unset PSH_RAW_BASE
  unset PSH_EXPECT_INSTALL_SOURCE
  unset PSH_INSTALL_SOURCE_FILE
  unset XDG_DATA_HOME
  unset XDG_BIN_HOME
}

teardown_psh_test() {
  rm -rf "$PSH_TEST_ROOT"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || skip "$1 is required"
}

assert_status() {
  local expected=$1

  if [ "$status" -ne "$expected" ]; then
    printf 'expected status %s, got %s\n' "$expected" "$status" >&2
    printf 'output:\n%s\n' "$output" >&2
    return 1
  fi
}

psh() {
  "$PSH_REPO_ROOT/bin/psh.sh" "$@"
}

psh_no_tty() {
  setsid "$PSH_REPO_ROOT/bin/psh.sh" "$@" </dev/null
}

psh_no_tty_stdin() {
  local input=$1
  shift

  printf '%s' "$input" | setsid "$PSH_REPO_ROOT/bin/psh.sh" "$@"
}

psh_pty() {
  local input=$1
  local command
  shift

  printf -v command '%q ' "$PSH_REPO_ROOT/bin/psh.sh" "$@"
  printf '%s' "$input" | script -qfec "$command" /dev/null
}

mock_hosted_content() {
  local content=$1

  install_mock_curl
  PSH_MOCK_RESPONSE=$(jq -cn --arg content "$content" '{choices: [{message: {content: $content}}]}')
  export PSH_MOCK_RESPONSE
}

mock_hosted_command() {
  local command=$1
  local explanation=${2:-}
  local risk=${3:-safe}
  local content

  content=$(jq -cn \
    --arg command "$command" \
    --arg explanation "$explanation" \
    --arg risk "$risk" \
    '{type: "command", command: $command, explanation: $explanation, risk: $risk, requires_approval: true}')

  mock_hosted_content "$content"
}

mock_hosted_question() {
  local content

  content=$(jq -cn '{type: "question", question: "Which target?", options: ["Docker", "Images"]}')
  mock_hosted_content "$content"
}

install_mock_curl() {
  cat >"$PSH_MOCK_BIN/curl" <<'MOCK_CURL'
#!/bin/sh

out=
data=
url=

while [ "$#" -gt 0 ]; do
  case $1 in
    -o)
      shift
      out=${1:-}
      ;;
    -d)
      shift
      data=${1:-}
      ;;
    -H)
      shift
      ;;
    http*)
      url=$1
      ;;
  esac

  shift || break
done

[ -n "$out" ] || exit 2

if [ -n "${PSH_CAPTURE_REQUEST:-}" ]; then
  printf '%s\n' "$data" >"$PSH_CAPTURE_REQUEST"
fi

if [ -n "${PSH_CAPTURE_URL:-}" ]; then
  printf '%s\n' "$url" >"$PSH_CAPTURE_URL"
fi

printf '%s\n' "$PSH_MOCK_RESPONSE" >"$out"
MOCK_CURL

  chmod +x "$PSH_MOCK_BIN/curl"
}

install_mock_raw_curl() {
  cat >"$PSH_MOCK_BIN/curl" <<'MOCK_RAW_CURL'
#!/bin/sh

out=
url=

while [ "$#" -gt 0 ]; do
  case $1 in
    -o)
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

if [ -n "$out" ]; then
  cp "$PSH_INSTALL_SOURCE_FILE" "$out"
else
  cat "$PSH_INSTALL_SOURCE_FILE"
fi
MOCK_RAW_CURL

  chmod +x "$PSH_MOCK_BIN/curl"
}

mock_codex_command() {
  local command=$1
  local explanation=${2:-}
  local risk=${3:-safe}
  local content

  install_mock_codex
  content=$(jq -cn \
    --arg command "$command" \
    --arg explanation "$explanation" \
    --arg risk "$risk" \
    '{type: "command", command: $command, explanation: $explanation, risk: $risk, requires_approval: true}')
  PSH_CODEX_JSONL=$(jq -cn --arg text "$content" '{type: "item.completed", item: {type: "agent_message", text: $text}}')
  export PSH_CODEX_JSONL
}

install_mock_codex() {
  cat >"$PSH_MOCK_BIN/codex" <<'MOCK_CODEX'
#!/bin/sh

model=
prompt=

[ "${1:-}" = exec ] || exit 2
shift

while [ "$#" -gt 0 ]; do
  case $1 in
    --json)
      shift
      ;;
    -m)
      shift
      model=${1:-}
      shift
      ;;
    *)
      prompt=$1
      shift
      ;;
  esac
done

if [ -n "${PSH_CAPTURE_CODEX_PROMPT:-}" ]; then
  printf '%s\n' "$prompt" >"$PSH_CAPTURE_CODEX_PROMPT"
fi

if [ -n "${PSH_CAPTURE_CODEX_MODEL:-}" ]; then
  printf '%s\n' "$model" >"$PSH_CAPTURE_CODEX_MODEL"
fi

printf '%s\n' "$PSH_CODEX_JSONL"
MOCK_CODEX

  chmod +x "$PSH_MOCK_BIN/codex"
}

command_json() {
  jq -cn \
    --arg command "$1" \
    --arg explanation "${2:-}" \
    --arg risk "${3:-safe}" \
    '{type: "command", command: $command, explanation: $explanation, risk: $risk, requires_approval: true}'
}

install_mock_harness() {
  cat >"$PSH_MOCK_BIN/$1" <<'MOCK_HARNESS'
#!/bin/sh

if [ -n "${PSH_CAPTURE_HARNESS_ARGV:-}" ]; then
  printf '%s\n' "$*" >"$PSH_CAPTURE_HARNESS_ARGV"
fi

printf '%s\n' "${PSH_HARNESS_OUTPUT:-}"
MOCK_HARNESS

  chmod +x "$PSH_MOCK_BIN/$1"
}

mock_harness_command() {
  local name=$1
  local field=$2
  shift 2

  install_mock_harness "$name"
  PSH_HARNESS_OUTPUT=$(jq -cn --arg field "$field" --arg value "$(command_json "$1" "${2:-}" "${3:-safe}")" '{($field): $value}')
  export PSH_HARNESS_OUTPUT
}

mock_grok_command() {
  mock_harness_command grok text "$@"
}

mock_claude_command() {
  mock_harness_command claude result "$@"
}

mock_gemini_command() {
  mock_harness_command gemini response "$@"
}
