#!/bin/sh

set -eu

verbosity=0

usage() {
  printf 'usage: psh [-v|-vv|-vvv] run PROMPT...\n'
  printf '       printf %%s "PROMPT" | psh [-v|-vv|-vvv] run\n'
  printf '       psh [-v|-vv|-vvv] setup\n'
  printf '       psh [-v|-vv|-vvv] setup model\n'
  printf '       psh install\n'
  printf '       psh update\n'
  printf '       psh uninstall [--purge]\n'
}

config_file() {
  printf '%s/psh/config.json\n' "${XDG_CONFIG_HOME:-$HOME/.config}"
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    printf 'psh: jq is required\n' >&2
    exit 2
  fi
}

require_home() {
  action=$1

  if [ -z "${HOME:-}" ]; then
    printf 'psh %s: HOME is required unless install path env vars are set\n' "$action" >&2
    exit 2
  fi
}

xdg_data_home() {
  if [ -n "${XDG_DATA_HOME:-}" ]; then
    printf '%s\n' "$XDG_DATA_HOME"
    return 0
  fi

  require_home "$1"
  printf '%s/.local/share\n' "$HOME"
}

xdg_bin_home() {
  if [ -n "${PSH_INSTALL_DIR:-}" ]; then
    printf '%s\n' "$PSH_INSTALL_DIR"
    return 0
  fi

  if [ -n "${XDG_BIN_HOME:-}" ]; then
    printf '%s\n' "$XDG_BIN_HOME"
    return 0
  fi

  require_home "$1"
  printf '%s/.local/bin\n' "$HOME"
}

payload_dir() {
  printf '%s/psh\n' "$(xdg_data_home "$1")"
}

payload_path() {
  printf '%s/psh.sh\n' "$(payload_dir "$1")"
}

launcher_path() {
  printf '%s/%s\n' "$(xdg_bin_home "$1")" "${PSH_INSTALL_NAME:-psh}"
}

completion_path() {
  printf '%s/bash-completion/completions/psh\n' "$(xdg_data_home "$1")"
}

shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

install_file() {
  inst_src=$1
  inst_dst=$2
  inst_mode=${3:-0755}

  mkdir -p "$(dirname "$inst_dst")"

  if command -v install >/dev/null 2>&1; then
    install -m "$inst_mode" "$inst_src" "$inst_dst"
  else
    cp "$inst_src" "$inst_dst"
    chmod "$inst_mode" "$inst_dst"
  fi
}

resolve_current_script() {
  case ${0##*/} in
    psh|psh.sh)
      if [ -f "$0" ]; then
        script_dir=$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd || printf '')
        if [ -n "$script_dir" ]; then
          printf '%s/%s\n' "$script_dir" "$(basename "$0")"
          return 0
        fi
      fi

      script_path=$(command -v "$0" 2>/dev/null || true)
      if [ -n "$script_path" ] && [ -f "$script_path" ]; then
        script_dir=$(CDPATH= cd "$(dirname "$script_path")" 2>/dev/null && pwd || printf '')
        if [ -n "$script_dir" ]; then
          printf '%s/%s\n' "$script_dir" "$(basename "$script_path")"
          return 0
        fi
      fi
      ;;
  esac

  return 1
}

download_install_source() {
  destination=$1
  repo_raw_base=${PSH_RAW_BASE:-https://raw.githubusercontent.com/csfh/promptshell/main}
  source_url=$repo_raw_base/bin/psh.sh

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$source_url" -o "$destination"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$destination" "$source_url"
  else
    printf 'psh install: curl or wget is required\n' >&2
    exit 2
  fi
}

write_launcher() {
  launcher_payload=$1
  launcher_dst=$2
  launcher_tmp=$(mktemp)

  printf '#!/bin/sh\nexec %s "$@"\n' "$(shell_quote "$launcher_payload")" >"$launcher_tmp"
  install_file "$launcher_tmp" "$launcher_dst" 0755
  rm -f "$launcher_tmp"
}

write_bash_completion() {
  completion_dst=$1
  completion_tmp=$(mktemp)

  cat >"$completion_tmp" <<'EOF'
_psh() {
  local cur prev
  COMPREPLY=()
  cur=${COMP_WORDS[COMP_CWORD]}
  prev=${COMP_WORDS[COMP_CWORD-1]}

  case $prev in
    setup)
      COMPREPLY=($(compgen -W "model" -- "$cur"))
      return 0
      ;;
    uninstall)
      COMPREPLY=($(compgen -W "--purge" -- "$cur"))
      return 0
      ;;
  esac

  if [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=($(compgen -W "-v -vv -vvv run setup install update uninstall help --help" -- "$cur"))
  fi
}

complete -F _psh psh
EOF

  install_file "$completion_tmp" "$completion_dst" 0644
  rm -f "$completion_tmp"
}

install_xdg() {
  payload=$(payload_path install)
  launcher=$(launcher_path install)
  completion=$(completion_path install)
  install_tmp=$(mktemp)

  trap 'rm -f "$install_tmp"' EXIT HUP INT TERM

  source_script=$(resolve_current_script 2>/dev/null || true)
  if [ -n "$source_script" ]; then
    cp "$source_script" "$install_tmp"
  else
    download_install_source "$install_tmp"
  fi

  install_file "$install_tmp" "$payload" 0755
  write_launcher "$payload" "$launcher"
  write_bash_completion "$completion"

  rm -f "$install_tmp"
  trap - EXIT HUP INT TERM

  printf 'psh install: payload %s\n' "$payload"
  printf 'psh install: launcher %s\n' "$launcher"
  printf 'psh install: config %s\n' "$(config_file)"
  printf 'psh install: completion %s\n' "$completion"
  printf 'psh install: run `psh setup` before the first hosted-provider request\n'

  bin_dir=$(xdg_bin_home install)
  case :$PATH: in
    *:"$bin_dir":*) ;;
    *)
      printf 'psh install: add %s to PATH to run `psh` directly\n' "$bin_dir"
      ;;
  esac
}

install_command() {
  if [ "$#" -gt 0 ]; then
    usage >&2
    exit 2
  fi

  install_xdg
}

update_command() {
  if [ "$#" -gt 0 ]; then
    usage >&2
    exit 2
  fi

  install_xdg
}

uninstall_command() {
  purge=0

  while [ "$#" -gt 0 ]; do
    case $1 in
      --purge)
        purge=1
        shift
        ;;
      *)
        usage >&2
        exit 2
        ;;
    esac
  done

  launcher=$(launcher_path uninstall)
  payload=$(payload_path uninstall)
  completion=$(completion_path uninstall)
  data_dir=$(payload_dir uninstall)
  removed=0

  if [ -d "$launcher" ]; then
    printf 'psh uninstall: expected a file at %s\n' "$launcher" >&2
    exit 1
  fi

  if [ -f "$launcher" ] || [ -L "$launcher" ]; then
    rm -f "$launcher"
    printf 'psh uninstall: removed %s\n' "$launcher"
    removed=1
  fi

  if [ -f "$payload" ] || [ -L "$payload" ]; then
    rm -f "$payload"
    printf 'psh uninstall: removed %s\n' "$payload"
    removed=1
  fi

  if [ -f "$completion" ] || [ -L "$completion" ]; then
    rm -f "$completion"
    printf 'psh uninstall: removed %s\n' "$completion"
    removed=1
  fi

  if [ -d "$data_dir" ]; then
    rmdir "$data_dir" 2>/dev/null || true
  fi

  if [ "$purge" -eq 1 ]; then
    config=$(config_file)
    config_dir=$(dirname "$config")
    if [ -f "$config" ]; then
      rm -f "$config"
      printf 'psh uninstall: removed %s\n' "$config"
      removed=1
    fi
    rmdir "$config_dir" 2>/dev/null || true
  fi

  if [ "$removed" -eq 0 ]; then
    printf 'psh uninstall: not installed at %s\n' "$launcher"
  fi
}

terminal_printf() {
  printf "$@" >/dev/tty
}

terminal_read_line() {
  line=
  IFS= read -r line </dev/tty || line=
  printf '%s\n' "$line"
}

terminal_read_key() {
  tty_state=$(stty -g </dev/tty 2>/dev/null || printf '')
  esc=$(printf '\033')
  cr=$(printf '\r')
  up=$(printf '\033[A')
  down=$(printf '\033[B')

  if [ -n "$tty_state" ]; then
    stty -echo -icanon min 1 time 0 </dev/tty 2>/dev/null || true
  fi

  key=$(dd bs=1 count=1 2>/dev/null </dev/tty || true)

  if [ "$key" = "$esc" ]; then
    if [ -n "$tty_state" ]; then
      stty min 0 time 1 </dev/tty 2>/dev/null || true
    fi
    rest=$(dd bs=2 count=1 2>/dev/null </dev/tty || true)
    key=$(printf '\033%s' "$rest")
  fi

  if [ -n "$tty_state" ]; then
    stty "$tty_state" </dev/tty 2>/dev/null || true
  fi

  case $key in
    "$up")
      printf 'up\n'
      ;;
    "$down")
      printf 'down\n'
      ;;
    "$esc")
      printf 'esc\n'
      ;;
    ""|"$cr")
      printf 'enter\n'
      ;;
    *)
      printf 'char:%s\n' "$key"
      ;;
  esac
}

terminal_spacer() {
  terminal_printf '\n'
}

terminal_spaces() {
  count=$1
  spaces=

  while [ "$count" -gt 0 ]; do
    spaces="${spaces} "
    count=$((count - 1))
  done

  printf '%s' "$spaces"
}

terminal_panel_line() {
  text=$1

  terminal_printf '  \033[48;5;235m\033[38;5;252m%s\033[0m\n' "$text"
}

terminal_panel_content_line() {
  line=$1
  width=100
  text="  $line"
  text_length=${#text}

  if [ "$text_length" -lt "$width" ]; then
    text="${text}$(terminal_spaces $((width - text_length)))"
  fi

  terminal_panel_line "$text"
}

terminal_render_panel() {
  content=$1
  width=100

  terminal_spacer
  terminal_panel_line "$(terminal_spaces "$width")"
  printf '%s\n' "$content" | while IFS= read -r line; do
    terminal_panel_content_line "$line"
  done
  terminal_panel_line "$(terminal_spaces "$width")"
}

terminal_log() {
  level=$1
  message=$2

  case $level in
    error)
      label=ERROR
      color=39
      ;;
    info)
      label=INFO
      color=36
      ;;
    *)
      label=DEBUG
      color=244
      ;;
  esac

  terminal_printf '\033[38;5;%sm%s\033[0m \033[1mpsh:\033[0m %s\n' "$color" "$label" "$message"
}

terminal_panel() {
  title=$1
  value=$2

  terminal_render_panel "$(printf '[ %s ]\n%s' "$title" "$value")"
}

terminal_highlight_command() {
  command_text=$1

  if ! command -v awk >/dev/null 2>&1; then
    printf '%s' "$command_text"
    return
  fi

  awk -v s="$command_text" '
    function emit(style, text) {
      printf "%s%s%s", style, text, reset
    }

    function is_space(c) {
      return c == " " || c == "\t"
    }

    function is_operator(op) {
      return op == "|" || op == "&&" || op == "||" || op == ">" || op == ">>" || op == "<" || op == "<<" || op == ";"
    }

    function emit_operator(op) {
      emit(dim, op)
      expect_command = 1
    }

    function emit_token(token) {
      if (token ~ /^https?:\/\//) {
        emit(url, token)
      } else if (token ~ /^--?[^[:space:]]+/) {
        emit(dim, token)
      } else if (token ~ /^\$/) {
        emit(cyan, token)
      } else if (expect_command) {
        emit(bold, token)
      } else {
        printf "%s", token
      }

      expect_command = 0
    }

    function read_quoted(quote,    start, c, escaped) {
      start = i
      i++
      escaped = 0

      while (i <= length(s)) {
        c = substr(s, i, 1)
        if (quote == "\"" && c == "\\" && !escaped) {
          escaped = 1
          i++
          continue
        }
        if (c == quote && !escaped) {
          i++
          break
        }
        escaped = 0
        i++
      }

      return substr(s, start, i - start)
    }

    function read_substitution(    start, c, pair, depth, quote, escaped) {
      start = i
      if (substr(s, i, 2) == "$(") {
        i += 2
        depth = 1
        quote = ""
        escaped = 0

        while (i <= length(s) && depth > 0) {
          c = substr(s, i, 1)
          pair = substr(s, i, 2)

          if (quote != "") {
            if (quote == "\"" && c == "\\" && !escaped) {
              escaped = 1
              i++
              continue
            }
            if (c == quote && !escaped) {
              quote = ""
            }
            escaped = 0
            i++
            continue
          }

          if (c == "\"" || c == "\047") {
            quote = c
            i++
            continue
          }
          if (pair == "$(") {
            depth++
            i += 2
            continue
          }
          if (c == ")") {
            depth--
          }
          i++
        }
      } else if (substr(s, i, 2) == "${") {
        i += 2
        while (i <= length(s)) {
          c = substr(s, i, 1)
          i++
          if (c == "}") {
            break
          }
        }
      } else {
        i++
        while (i <= length(s) && substr(s, i, 1) ~ /[A-Za-z0-9_]/) {
          i++
        }
      }

      return substr(s, start, i - start)
    }

    function emit_double_quoted(    c, rest) {
      emit(yellow, "\"")
      i++

      while (i <= length(s)) {
        c = substr(s, i, 1)
        rest = substr(s, i)

        if (c == "\\") {
          emit(yellow, substr(s, i, 2))
          i += 2
          continue
        }

        if (c == "\"") {
          emit(yellow, "\"")
          i++
          break
        }

        if (c == "$") {
          emit(cyan, read_substitution())
          continue
        }

        if (match(rest, /^https?:\/\/[^"[:space:]]+/)) {
          emit(url, substr(rest, 1, RLENGTH))
          i += RLENGTH
          continue
        }

        emit(yellow, c)
        i++
      }
    }

    BEGIN {
      reset = "\033[0m"
      dim = "\033[2m"
      bold = "\033[1m"
      cyan = "\033[36m"
      url = "\033[4;36m"
      yellow = "\033[33m"
      expect_command = 1
      i = 1

      while (i <= length(s)) {
        c = substr(s, i, 1)
        two = substr(s, i, 2)

        if (is_space(c)) {
          printf "%s", c
          i++
          continue
        }

        if (is_operator(two)) {
          emit_operator(two)
          i += 2
          continue
        }

        if (is_operator(c)) {
          emit_operator(c)
          i++
          continue
        }

        if (c == "\"") {
          emit_double_quoted()
          expect_command = 0
          continue
        }

        if (c == "\047") {
          emit(yellow, read_quoted(c))
          expect_command = 0
          continue
        }

        if (c == "$") {
          emit(cyan, read_substitution())
          expect_command = 0
          continue
        }

        start = i
        while (i <= length(s)) {
          c = substr(s, i, 1)
          two = substr(s, i, 2)
          if (is_space(c) || is_operator(c) || is_operator(two) || c == "\"" || c == "\047" || c == "$") {
            break
          }
          i++
        }

        emit_token(substr(s, start, i - start))
      }
    }
  '
}

terminal_command_preview() {
  command_text=$1

  terminal_printf '\033[2m$\033[0m '
  terminal_highlight_command "$command_text" >/dev/tty
  terminal_printf '\n'
}

terminal_command_metadata() {
  risk=$1
  explanation=$2

  terminal_spacer
  terminal_printf '\033[2mAI-generated command. Review before running.\033[0m\n'

  case $risk in
    needs_approval|destructive)
      terminal_printf '\033[2mRisk:\033[0m %s\n' "$risk"
      if [ -n "$explanation" ]; then
        terminal_printf '\033[2m%s\033[0m\n' "$explanation"
      fi
      ;;
  esac
}

package_manager() {
  if command -v brew >/dev/null 2>&1; then
    printf 'brew\n'
  elif command -v apt >/dev/null 2>&1; then
    printf 'apt\n'
  elif command -v dnf >/dev/null 2>&1; then
    printf 'dnf\n'
  elif command -v pacman >/dev/null 2>&1; then
    printf 'pacman\n'
  else
    printf 'unknown\n'
  fi
}

prompt_context() {
  user_prompt=$1

  jq -n \
    --arg cwd "$(pwd)" \
    --arg os "$(uname -s 2>/dev/null || printf unknown)" \
    --arg shell "${SHELL:-unknown}" \
    --arg package_manager "$(package_manager)" \
    --arg prompt "$user_prompt" \
    '{cwd: $cwd, os: $os, shell: $shell, package_manager: $package_manager, prompt: $prompt}'
}

spinner_title() {
  seed=$(date +%s 2>/dev/null || printf 0)
  index=$(((seed + $$) % 12))

  case $index in
    0) printf 'Thinking' ;;
    1) printf 'Pondering' ;;
    2) printf 'Reasoning' ;;
    3) printf 'Translating' ;;
    4) printf 'Composing' ;;
    5) printf 'Distilling' ;;
    6) printf 'Weighing' ;;
    7) printf 'Shaping' ;;
    8) printf 'Resolving' ;;
    9) printf 'Drafting' ;;
    10) printf 'Inspecting' ;;
    *) printf 'Summoning' ;;
  esac
}

run_with_spinner() {
  title=$1
  shift

  if ! have_tty; then
    "$@"
    return
  fi

  loader_stderr_file=$(mktemp)
  terminal_spacer
  terminal_printf '\033[?25l'
  "$@" 2>"$loader_stderr_file" &
  loader_pid=$!
  loader_frame=0

  while kill -0 "$loader_pid" 2>/dev/null; do
    case $loader_frame in
      0)
        dots='.'
        shade=244
        ;;
      1)
        dots='..'
        shade=248
        ;;
      2)
        dots='...'
        shade=252
        ;;
      3)
        dots='..'
        shade=248
        ;;
      *)
        dots='.'
        shade=244
        ;;
    esac

    terminal_printf '\r\033[38;5;%sm%s%s\033[0m   ' "$shade" "$title" "$dots"
    loader_frame=$(((loader_frame + 1) % 5))
    sleep 0.2
  done

  if wait "$loader_pid"; then
    loader_status=0
  else
    loader_status=$?
  fi

  terminal_printf '\r\033[K\033[?25h'

  if [ "$loader_status" -ne 0 ] && [ -s "$loader_stderr_file" ]; then
    while IFS= read -r line; do
      terminal_printf '%s\n' "$line"
    done <"$loader_stderr_file"
  fi

  rm -f "$loader_stderr_file"

  return "$loader_status"
}

debug_enabled() {
  [ "$verbosity" -ge "$1" ]
}

debug_log() {
  level=$1
  shift

  if debug_enabled "$level"; then
    if have_tty; then
      terminal_printf 'psh debug: %s\n' "$*"
    else
      printf 'psh debug: %s\n' "$*" >&2
    fi
  fi
}

debug_panel() {
  level=$1
  title=$2
  value=$3

  if debug_enabled "$level"; then

    if have_tty; then
      terminal_panel "$title" "$value"
    else
      printf '\npsh debug: %s\n' "$title" >&2
      printf '%s\n' "$value" | while IFS= read -r line; do
        printf '  %s\n' "$line" >&2
      done
    fi
  fi
}

debug_json_panel() {
  level=$1
  title=$2
  value=$3

  if debug_enabled "$level"; then
    formatted=$(printf '%s\n' "$value" | jq . 2>/dev/null || printf '<invalid json>')

    debug_panel "$level" "$title" "$formatted"
  fi
}

debug_json_file_panel() {
  level=$1
  title=$2
  file=$3

  if debug_enabled "$level"; then
    formatted=$(jq . "$file" 2>/dev/null || printf '<invalid json>')

    debug_panel "$level" "$title" "$formatted"
  fi
}

model_think_content() {
  content=$1

  printf '%s\n' "$content" | jq -Rrs -r 'capture("(?s)<think>\\n?(?<think>.*?)\\n?</think>")?.think // empty'
}

model_content_without_think() {
  content=$1

  printf '%s\n' "$content" | jq -Rrs -r 'gsub("(?s)<think>.*?</think>"; "") | sub("^\\s+"; "") | sub("\\s+$"; "")'
}

debug_model_content() {
  content=$1

  if ! debug_enabled 1 && ! debug_enabled 2; then
    return
  fi

  think=$(model_think_content "$content")
  without_think=$(model_content_without_think "$content")

  if [ -n "$think" ] && debug_enabled 1; then
    debug_panel 1 'thinking' "$think"
  fi

  if [ -n "$without_think" ] && debug_enabled 2; then
    debug_panel 2 'Model content' "$without_think"
  fi
}

debug_messages() {
  request=$1

  if debug_enabled 2; then
    printf '%s\n' "$request" | jq -r '.messages[] | @base64' | while IFS= read -r encoded; do
      role=$(printf '%s\n' "$encoded" | jq -rR '@base64d | fromjson | .role')
      message=$(printf '%s\n' "$encoded" | jq -rR '@base64d | fromjson | .content')

      debug_panel 2 "message role=$role" "$message"
    done
  fi
}

log_info() {
  message=$1

  if have_tty; then
    terminal_log info "$message"
  else
    printf 'psh: %s\n' "$message"
  fi
}

log_error() {
  message=$1

  if have_tty; then
    terminal_log error "$message"
  else
    printf 'psh: %s\n' "$message" >&2
  fi
}

display_command() {
  command_text=$1

  if have_tty; then
    terminal_command_preview "$command_text"
  else
    printf '%s\n' "$command_text"
  fi
}

have_tty() {
  ( : </dev/tty ) >/dev/null 2>&1
}

config_value() {
  file=$(config_file)
  key=$1

  if [ -f "$file" ]; then
    jq -r --arg key "$key" '.[$key] // empty' "$file"
  fi
}

cli_provider_ids() {
  printf '%s\n' codex grok claude gemini
}

provider_kind() {
  case $1 in
    openai|fireworks)
      printf 'hosted\n'
      ;;
    codex|grok|claude|gemini)
      printf 'cli\n'
      ;;
    *)
      return 1
      ;;
  esac
}

provider_binary() {
  case $1 in
    codex)
      printf 'codex\n'
      ;;
    grok)
      printf 'grok\n'
      ;;
    claude)
      printf 'claude\n'
      ;;
    gemini)
      printf 'gemini\n'
      ;;
    *)
      return 1
      ;;
  esac
}

provider_label() {
  case $1 in
    openai)
      printf 'OpenAI\n'
      ;;
    fireworks)
      printf 'Fireworks\n'
      ;;
    codex)
      printf 'Codex\n'
      ;;
    grok)
      printf 'Grok\n'
      ;;
    claude)
      printf 'Claude\n'
      ;;
    gemini)
      printf 'Gemini\n'
      ;;
    *)
      return 1
      ;;
  esac
}

provider_from_choice() {
  case $1 in
    1|openai|OpenAI|OPENAI)
      printf 'openai\n'
      ;;
    2|fireworks|Fireworks|FIREWORKS)
      printf 'fireworks\n'
      ;;
    3|codex|Codex|CODEX)
      printf 'codex\n'
      ;;
    grok|Grok|GROK)
      printf 'grok\n'
      ;;
    claude|Claude|CLAUDE)
      printf 'claude\n'
      ;;
    gemini|Gemini|GEMINI)
      printf 'gemini\n'
      ;;
    *)
      for id in openai fireworks $(cli_provider_ids); do
        label=$(provider_label "$id" 2>/dev/null || true)
        if [ "$1" = "$id" ] || { [ -n "$label" ] && [ "$1" = "$label" ]; }; then
          printf '%s\n' "$id"
          return 0
        fi
      done
      return 1
      ;;
  esac
}

provider_default_model() {
  case $1 in
    openai)
      printf 'gpt-4.1-mini\n'
      ;;
    fireworks)
      printf 'accounts/fireworks/models/deepseek-v3p1\n'
      ;;
    codex)
      printf 'gpt-5.5\n'
      ;;
    grok)
      printf 'grok-4.6\n'
      ;;
    claude)
      printf 'sonnet\n'
      ;;
    gemini)
      printf 'gemini-2.5-flash\n'
      ;;
    *)
      return 1
      ;;
  esac
}

provider_url() {
  case $1 in
    openai)
      printf 'https://api.openai.com/v1/chat/completions\n'
      ;;
    fireworks)
      printf 'https://api.fireworks.ai/inference/v1/chat/completions\n'
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

provider_requires_api_key() {
  kind=$(provider_kind "$1") || return 1
  [ "$kind" = hosted ]
}

cli_provider_available() {
  binary=$(provider_binary "$1") || return 1
  command -v "$binary" >/dev/null 2>&1
}

prompt_provider() {
  default=$1
  set -- OpenAI Fireworks
  for id in $(cli_provider_ids); do
    if cli_provider_available "$id"; then
      set -- "$@" "$(provider_label "$id")"
    fi
  done
  prompt_choice 'Provider' "$default" "$@"
}

setup_model_default() {
  provider=$1
  existing_model=$2

  default_model=$(provider_default_model "$provider" 2>/dev/null || true)
  if [ -z "$default_model" ]; then
    return 1
  fi

  if [ -n "$existing_model" ] && { [ "$(provider_kind "$provider")" != cli ] || [ "$existing_model" != "$provider" ]; }; then
    printf '%s\n' "$existing_model"
  else
    printf '%s\n' "$default_model"
  fi
}

resolve_generation_provider() {
  provider=${PSH_PROVIDER:-$(config_value provider)}
  provider=${provider:-openai}
  kind=$(provider_kind "$provider" 2>/dev/null || true)

  if [ -z "$kind" ]; then
    printf 'psh: unsupported provider: %s\n' "$provider" >&2
    exit 2
  fi

  case $provider in
    openai)
      model=${OPENAI_MODEL:-${PSH_MODEL:-$(config_value model)}}
      model=${model:-$(provider_default_model openai)}
      api_key=${OPENAI_API_KEY:-${PSH_API_KEY:-$(config_value api_key)}}
      ;;
    fireworks)
      model=${FIREWORKS_MODEL:-${PSH_MODEL:-$(config_value model)}}
      model=${model:-$(provider_default_model fireworks)}
      api_key=${FIREWORKS_API_KEY:-${PSH_API_KEY:-$(config_value api_key)}}
      ;;
    *)
      case $kind in
        cli)
          case $provider in
            codex)
              model=${CODEX_MODEL:-${PSH_MODEL:-$(config_value model)}}
              ;;
            grok)
              model=${GROK_MODEL:-${PSH_MODEL:-$(config_value model)}}
              ;;
            claude)
              model=${CLAUDE_MODEL:-${PSH_MODEL:-$(config_value model)}}
              ;;
            gemini)
              model=${GEMINI_MODEL:-${PSH_MODEL:-$(config_value model)}}
              ;;
            *)
              model=${PSH_MODEL:-$(config_value model)}
              ;;
          esac
          if [ -z "$model" ] || [ "$model" = "$provider" ]; then
            model=$(provider_default_model "$provider")
          fi
          api_key=
          ;;
        *)
          printf 'psh: unsupported provider: %s\n' "$provider" >&2
          exit 2
          ;;
      esac
      ;;
  esac

  url=$(provider_url "$provider")

  if [ "$kind" = cli ]; then
    binary=$(provider_binary "$provider")
    if ! command -v "$binary" >/dev/null 2>&1; then
      printf 'psh: %s is required for the %s provider\n' "$binary" "$provider" >&2
      exit 2
    fi
  elif ! command -v curl >/dev/null 2>&1; then
    printf 'psh: curl is required\n' >&2
    exit 2
  fi

  if provider_requires_api_key "$provider" && [ -z "$api_key" ]; then
    printf 'psh: API key is required; run `psh setup` or set provider API key env var\n' >&2
    exit 2
  fi
}

generate_provider_response() {
  system=$1
  prompt=$2

  case $(provider_kind "$provider") in
    cli)
      generate_cli_response "$system" "$prompt"
      ;;
    hosted)
      generate_response "$url" "$api_key" "$model" "$system" "$prompt"
      ;;
    *)
      printf 'psh: unsupported provider: %s\n' "$provider" >&2
      exit 2
      ;;
  esac
}

generate_cli_response() {
  system=$1
  prompt=$2

  case $provider in
    codex)
      generate_codex_response "$system" "$prompt"
      ;;
    grok)
      generate_grok_response "$system" "$prompt"
      ;;
    claude)
      generate_claude_response "$system" "$prompt"
      ;;
    gemini)
      generate_gemini_response "$system" "$prompt"
      ;;
    *)
      printf 'psh: unsupported provider: %s\n' "$provider" >&2
      exit 2
      ;;
  esac
}

normalize_command_result() {
  response=$1

  command=$(printf '%s\n' "$response" | jq -r '.command // empty')
  if [ -z "$command" ]; then
    printf 'psh: generated command is missing a command\n' >&2
    exit 1
  fi

  printf '%s\n' "$response" | jq -c --arg command "$command" '
    .risk as $risk
    | {
        type: "command",
        command: $command,
        explanation: (.explanation // ""),
        risk: (if $risk == "safe" or $risk == "needs_approval" or $risk == "destructive" then $risk else "needs_approval" end),
        requires_approval: true
      }
  '
}

prompt_value() {
  label=$1
  default=${2:-}

  terminal_spacer
  if [ -n "$default" ]; then
    terminal_printf '%s [%s]: ' "$label" "$default"
  else
    terminal_printf '%s: ' "$label"
  fi

  answer=$(terminal_read_line)
  answer=${answer:-$default}
  printf '%s\n' "$answer"
}

prompt_secret() {
  label=$1

  terminal_spacer
  terminal_printf '%s: ' "$label"
  tty_state=$(stty -g </dev/tty 2>/dev/null || printf '')
  if [ -n "$tty_state" ]; then
    stty -echo </dev/tty 2>/dev/null || true
  fi

  secret=$(terminal_read_line)

  if [ -n "$tty_state" ]; then
    stty "$tty_state" </dev/tty 2>/dev/null || true
  fi
  terminal_printf '\n'
  printf '%s\n' "$secret"
}

prompt_choice() {
  header=$1
  selected=$2
  shift 2

  printf '%s\n' "$@" | prompt_choice_lines "$header" "$selected"
}

prompt_choice_lines() {
  header=$1
  selected_option=${2:-}
  options_file=$(mktemp)
  cat >"$options_file"

  selected=1
  option_count=0
  while IFS= read -r option; do
    option_count=$((option_count + 1))
    if [ -n "$selected_option" ] && [ "$option" = "$selected_option" ]; then
      selected=$option_count
    fi
  done <"$options_file"

  if [ "$option_count" -eq 0 ]; then
    rm -f "$options_file"
    printf '\n'
    return
  fi

  menu_lines=$((option_count + 4))
  rendered=0

  while :; do
    if [ "$rendered" -eq 1 ]; then
      terminal_printf '\033[%sA\033[J' "$menu_lines"
    fi

    terminal_printf '%s\n\n' "$header"
    choice_index=1
    while IFS= read -r option; do
      if [ "$choice_index" -eq "$selected" ]; then
        terminal_printf '\033[1;36m>\033[0m %s\n' "$option"
      else
        terminal_printf '  %s\n' "$option"
      fi
      choice_index=$((choice_index + 1))
    done <"$options_file"
    terminal_printf '\n\033[2mup/down move - enter select - esc cancel\033[0m\n'
    rendered=1

    key=$(terminal_read_key)
    case $key in
      up)
        if [ "$selected" -gt 1 ]; then
          selected=$((selected - 1))
        else
          selected=$option_count
        fi
        ;;
      down)
        if [ "$selected" -lt "$option_count" ]; then
          selected=$((selected + 1))
        else
          selected=1
        fi
        ;;
      enter)
        choice_index=1
        while IFS= read -r option; do
          if [ "$choice_index" -eq "$selected" ]; then
            rm -f "$options_file"
            printf '%s\n' "$option"
            return
          fi
          choice_index=$((choice_index + 1))
        done <"$options_file"
        ;;
      esc)
        rm -f "$options_file"
        printf '\n'
        return
        ;;
      char:*)
        choice=${key#char:}
        case $choice in
          *[!0-9]*|'')
            ;;
          *)
            if [ "$choice" -ge 1 ] && [ "$choice" -le "$option_count" ]; then
              selected=$choice
            fi
            ;;
        esac
        ;;
    esac
  done

}

prompt_model() {
  provider=$1
  default=$2

  case $provider in
    openai)
      model_choice=$(prompt_choice 'Model' "$default" \
        gpt-4.1-mini \
        gpt-4.1 \
        gpt-4o-mini \
        gpt-4o \
        o4-mini \
        Custom)

      if [ "$model_choice" = Custom ]; then
        prompt_value 'Model' "$default"
      else
        printf '%s\n' "$model_choice"
      fi
      ;;
    fireworks)
      model_choice=$(prompt_choice 'Model' "$default" \
        accounts/fireworks/models/deepseek-v3p1 \
        accounts/fireworks/models/deepseek-r1 \
        accounts/fireworks/models/llama-v3p1-405b-instruct \
        accounts/fireworks/models/llama-v3p1-70b-instruct \
        accounts/fireworks/models/qwen2p5-coder-32b-instruct \
        Custom)

      if [ "$model_choice" = Custom ]; then
        prompt_value 'Model' "$default"
      else
        printf '%s\n' "$model_choice"
      fi
      ;;
    codex)
      model_choice=$(prompt_choice 'Model' "$default" \
        gpt-5.5 \
        gpt-5.4 \
        gpt-5.4-mini \
        gpt-5.3-codex \
        gpt-5.3-codex-spark \
        gpt-5.2 \
        Custom)

      if [ "$model_choice" = Custom ]; then
        prompt_value 'Model' "$default"
      else
        printf '%s\n' "$model_choice"
      fi
      ;;
    grok)
      model_choice=$(prompt_choice 'Model' "$default" \
        grok-4.6 \
        grok-4.5 \
        Custom)

      if [ "$model_choice" = Custom ]; then
        prompt_value 'Model' "$default"
      else
        printf '%s\n' "$model_choice"
      fi
      ;;
    claude)
      model_choice=$(prompt_choice 'Model' "$default" \
        sonnet \
        opus \
        haiku \
        Custom)

      if [ "$model_choice" = Custom ]; then
        prompt_value 'Model' "$default"
      else
        printf '%s\n' "$model_choice"
      fi
      ;;
    gemini)
      model_choice=$(prompt_choice 'Model' "$default" \
        gemini-2.5-flash \
        gemini-2.5-pro \
        Custom)

      if [ "$model_choice" = Custom ]; then
        prompt_value 'Model' "$default"
      else
        printf '%s\n' "$model_choice"
      fi
      ;;
    *)
      prompt_value 'Model' "$default"
      ;;
  esac

}

setup() {
  require_jq

  if ! have_tty; then
    printf 'psh: setup requires an interactive terminal\n' >&2
    exit 2
  fi

  existing_provider=$(config_value provider)
  existing_model=$(config_value model)
  existing_api_key=$(config_value api_key)

  provider_default=$(provider_label "$existing_provider" 2>/dev/null || printf 'OpenAI\n')
  provider_choice=$(prompt_provider "$provider_default")
  provider=$(provider_from_choice "$provider_choice" 2>/dev/null || true)

  if [ -z "$provider" ]; then
    printf 'psh: unsupported provider: %s\n' "$provider_choice" >&2
    exit 2
  fi

  if [ "$(provider_kind "$provider")" = cli ] && ! cli_provider_available "$provider"; then
    printf 'psh: unsupported provider: %s\n' "$provider_choice" >&2
    exit 2
  fi

  default_model=$(provider_default_model "$provider")

  if [ "$provider" = "$existing_provider" ] && [ -n "$existing_model" ]; then
    default_model=$existing_model
  fi

  model=$(prompt_model "$provider" "$default_model")
  if ! provider_requires_api_key "$provider"; then
    api_key=
  elif [ -n "$existing_api_key" ]; then
    api_key=$(prompt_secret 'API key [leave blank to keep existing]')
    api_key=${api_key:-$existing_api_key}
  else
    api_key=$(prompt_secret 'API key')
  fi

  if [ -z "$model" ]; then
    printf 'psh: model is required\n' >&2
    exit 2
  fi

  if provider_requires_api_key "$provider" && [ -z "$api_key" ]; then
    printf 'psh: API key is required\n' >&2
    exit 2
  fi

  file=$(config_file)
  dir=${file%/*}

  mkdir -p "$dir"
  jq -n \
    --arg provider "$provider" \
    --arg model "$model" \
    --arg api_key "$api_key" \
    '{provider: $provider, model: $model, api_key: $api_key}' >"$file"
  chmod 600 "$file"

  log_info "saved config to $file"
}

setup_model() {
  require_jq

  if ! have_tty; then
    printf 'psh: setup model requires an interactive terminal\n' >&2
    exit 2
  fi

  existing_provider=$(config_value provider)
  existing_model=$(config_value model)
  existing_api_key=$(config_value api_key)

  if [ -z "$existing_provider" ] || { provider_requires_api_key "$existing_provider" && [ -z "$existing_api_key" ]; }; then
    printf 'psh: run `psh setup` before changing only the model\n' >&2
    exit 2
  fi

  default_model=$(setup_model_default "$existing_provider" "$existing_model" 2>/dev/null || true)
  if [ -z "$default_model" ]; then
    printf 'psh: unsupported provider in config: %s\n' "$existing_provider" >&2
    exit 2
  fi

  model=$(prompt_model "$existing_provider" "$default_model")

  if [ -z "$model" ]; then
    printf 'psh: model is required\n' >&2
    exit 2
  fi

  file=$(config_file)
  dir=${file%/*}

  mkdir -p "$dir"
  jq -n \
    --arg provider "$existing_provider" \
    --arg model "$model" \
    --arg api_key "$existing_api_key" \
    '{provider: $provider, model: $model, api_key: $api_key}' >"$file"
  chmod 600 "$file"

  log_info "saved model to $file"
}

generate_command() {
  prompt=$1

  require_jq
  resolve_generation_provider

  debug_log 1 "configuration provider=$provider model=$model url=$url"

  system='Convert natural language into one safe POSIX shell command. Return only compact JSON. For commands: {"type":"command","command":"...","explanation":"...","risk":"safe|needs_approval|destructive","requires_approval":true}. For ambiguity: {"type":"question","question":"...","options":["...","..."]}. Prefer POSIX shell. Never execute commands. Mark destructive commands risk="destructive".'
  attempts=0

  while :; do
    attempts=$((attempts + 1))

    if [ "$attempts" -gt 3 ]; then
      printf 'psh: too many clarification rounds\n' >&2
      exit 1
    fi

    request_prompt=$(prompt_context "$prompt")
    response=$(generate_provider_response "$system" "$request_prompt")
    type=$(printf '%s\n' "$response" | jq -r '.type // empty')
    debug_log 1 "structured response type=$type"
    debug_json_panel 2 'Structured response' "$response"

    case $type in
      command)
        normalize_command_result "$response"
        return
        ;;
      question)
        question=$(printf '%s\n' "$response" | jq -r '.question // empty')

        if [ -z "$question" ]; then
          printf 'psh: generated clarification is missing a question\n' >&2
          exit 1
        fi

        if ! have_tty; then
          log_error "clarification required: $question"
          printf '%s\n' "$response" | jq -r '.options[]? | "psh: option: " + . ' >&2
          exit 2
        fi

        options=$(printf '%s\n' "$response" | jq -r '.options[]?')

        if [ -z "$options" ]; then
          answer=$(prompt_value "$question")
        else
          choice=$(printf '%s\nCustom\n' "$options" | prompt_choice_lines "$question")
          if [ "$choice" = Custom ]; then
            answer=$(prompt_value 'Answer')
          else
            answer=$choice
          fi
        fi

        if [ -z "$answer" ]; then
          printf 'psh: clarification answer is required\n' >&2
          exit 2
        fi

        prompt=$(printf '%s\n\nClarification: %s\nAnswer: %s' "$prompt" "$question" "$answer")
        ;;
      *)
        printf 'psh: generated invalid structured response\n' >&2
        exit 1
        ;;
    esac
  done
}

generate_response() {
  url=$1
  api_key=$2
  model=$3
  system=$4
  prompt=$5

  request=$(jq -n \
    --arg model "$model" \
    --arg system "$system" \
    --arg prompt "$prompt" \
    '{model: $model, messages: [{role: "system", content: $system}, {role: "user", content: $prompt}], temperature: 0, top_p: 1, max_tokens: 192}')
  debug_log 1 "request model=$model"
  debug_messages "$request"
  debug_json_panel 3 'Request JSON' "$request"

  response_file=$(mktemp)
  trap 'rm -f "$response_file"' EXIT HUP INT TERM

  run_with_spinner "$(spinner_title)" \
    curl -fsS "$url" \
      -H "Authorization: Bearer $api_key" \
      -H 'Content-Type: application/json' \
      -d "$request" \
      -o "$response_file"

  content=$(jq -r '.choices[0].message.content // empty' "$response_file")
  debug_log 1 'api response received'
  debug_json_file_panel 3 'API response JSON' "$response_file"
  debug_model_content "$content"
  rm -f "$response_file"
  trap - EXIT HUP INT TERM

  extract_structured_json "$content"
}

generate_codex_response() {
  system=$1
  prompt=$2

  codex_prompt=$(jq -nr \
    --arg system "$system" \
    --arg prompt "$prompt" \
    '$system + "\n\nUser request:\n" + $prompt')

  debug_log 1 'request provider=codex'

  response_file=$(mktemp)
  trap 'rm -f "$response_file"' EXIT HUP INT TERM

  run_with_spinner "$(spinner_title)" \
    sh -c 'codex exec --json -m "$1" "$2" >"$3" </dev/null' sh "$model" "$codex_prompt" "$response_file"

  debug_log 1 'codex response received'
  debug_panel 3 'Codex JSONL' "$(while IFS= read -r line; do printf '%s\n' "$line"; done <"$response_file")"

  content=$(jq -Rrs -r '
    split("\n")
    | [map(select(length > 0) | fromjson?)[]
      | select(.type == "item.completed" and .item.type == "agent_message")
      | .item.text]
    | last // empty
  ' "$response_file")

  if [ -z "$content" ]; then
    content=$(jq -Rrs -r 'sub("\\s+$"; "")' "$response_file")
  fi

  debug_model_content "$content"
  rm -f "$response_file"
  trap - EXIT HUP INT TERM

  extract_structured_json "$content"
}

cli_combined_prompt() {
  jq -nr \
    --arg system "$1" \
    --arg prompt "$2" \
    '$system + "\n\nUser request:\n" + $prompt'
}

cli_field_or_file() {
  file=$1
  field=$2
  content=$(jq -r --arg field "$field" '.[$field] // empty' "$file" 2>/dev/null || true)
  if [ -z "$content" ]; then
    content=$(jq -Rrs -r 'sub("\\s+$"; "")' "$file")
  fi
  printf '%s\n' "$content"
}

generate_grok_response() {
  system=$1
  prompt=$2
  grok_prompt=$(cli_combined_prompt "$system" "$prompt")

  debug_log 1 'request provider=grok'

  response_file=$(mktemp)
  trap 'rm -f "$response_file"' EXIT HUP INT TERM

  run_with_spinner "$(spinner_title)" \
    sh -c 'grok -p "$1" -m "$2" --output-format json --max-turns 1 --tools "read_file,grep,list_dir" >"$3" </dev/null' \
    sh "$grok_prompt" "$model" "$response_file"

  debug_log 1 'grok response received'
  debug_json_file_panel 3 'Grok JSON' "$response_file"

  content=$(cli_field_or_file "$response_file" text)
  debug_model_content "$content"
  rm -f "$response_file"
  trap - EXIT HUP INT TERM

  extract_structured_json "$content"
}

generate_claude_response() {
  system=$1
  prompt=$2
  claude_prompt=$(cli_combined_prompt "$system" "$prompt")

  debug_log 1 'request provider=claude'

  response_file=$(mktemp)
  trap 'rm -f "$response_file"' EXIT HUP INT TERM

  run_with_spinner "$(spinner_title)" \
    sh -c 'claude -p "$1" --model "$2" --output-format json --disallowedTools Bash Edit Write >"$3" </dev/null' \
    sh "$claude_prompt" "$model" "$response_file"

  debug_log 1 'claude response received'
  debug_json_file_panel 3 'Claude JSON' "$response_file"

  content=$(cli_field_or_file "$response_file" result)
  debug_model_content "$content"
  rm -f "$response_file"
  trap - EXIT HUP INT TERM

  extract_structured_json "$content"
}

generate_gemini_response() {
  system=$1
  prompt=$2
  gemini_prompt=$(cli_combined_prompt "$system" "$prompt")

  debug_log 1 'request provider=gemini'

  response_file=$(mktemp)
  trap 'rm -f "$response_file"' EXIT HUP INT TERM

  run_with_spinner "$(spinner_title)" \
    sh -c 'gemini -p "$1" -m "$2" --output-format json >"$3" </dev/null' \
    sh "$gemini_prompt" "$model" "$response_file"

  debug_log 1 'gemini response received'
  debug_json_file_panel 3 'Gemini JSON' "$response_file"

  content=$(cli_field_or_file "$response_file" response)
  debug_model_content "$content"
  rm -f "$response_file"
  trap - EXIT HUP INT TERM

  extract_structured_json "$content"
}

extract_structured_json() {
  content=$1
  without_think=$(model_content_without_think "$content")

  parsed=$(printf '%s\n' "$without_think" | jq -c . 2>/dev/null || true)
  if [ -n "$parsed" ]; then
    debug_log 1 'structured parse=direct'
    printf '%s\n' "$parsed"
    return
  fi

  parsed=$(printf '%s\n' "$without_think" | jq -Rrs -c '
    capture("(?s)(?<json>\\{.*\\})")?.json
    | fromjson
  ' 2>/dev/null || true)

  if [ -n "$parsed" ]; then
    debug_log 1 'structured parse=extracted'
    printf '%s\n' "$parsed"
    return
  fi

  debug_log 1 'structured parse=invalid'

  printf 'psh: model returned invalid structured response\n' >&2
  exit 1
}

confirm_run() {
  terminal_spacer
  terminal_printf '\033[2mRun\033[0m \033[1;32my\033[0m \033[2m· Cancel\033[0m \033[1mN\033[0m / \033[1menter\033[0m / \033[1mesc\033[0m '
  key=$(terminal_read_key)
  terminal_printf '\n\n'

  case $key in
    char:y|char:Y)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

finish_print_only() {
  exit 0
}

decline_generated_command() {
  exit 1
}

execute_generated_command() {
  command_text=$1

  sh -c "$command_text"
  exit $?
}

approve_and_run() {
  command_result=$1
  generated_command=$(printf '%s\n' "$command_result" | jq -r '.command // empty')
  risk=$(printf '%s\n' "$command_result" | jq -r '.risk // "needs_approval"')
  explanation=$(printf '%s\n' "$command_result" | jq -r '.explanation // empty')

  display_command "$generated_command"

  if ! have_tty; then
    finish_print_only
  fi

  terminal_command_metadata "$risk" "$explanation"

  if ! confirm_run; then
    decline_generated_command
  fi

  execute_generated_command "$generated_command"
}

set_run_prompt() {
  if [ "$#" -gt 0 ]; then
    prompt=$*
  elif [ ! -t 0 ]; then
    prompt=$(cat)
  else
    usage >&2
    exit 2
  fi
}

require_run_prompt() {
  if [ -z "$prompt" ]; then
    printf 'psh: empty prompt\n' >&2
    exit 2
  fi
}

require_generated_command() {
  generated_command=$(printf '%s\n' "$1" | jq -r '.command // empty')

  if [ -z "$generated_command" ]; then
    printf 'psh: empty generated command\n' >&2
    exit 1
  fi
}

run_command() {
  set_run_prompt "$@"
  require_run_prompt

  command_result=$(generate_command "$prompt")
  require_generated_command "$command_result"

  approve_and_run "$command_result"
}

setup_command() {
  if [ "$#" -eq 1 ] && [ "$1" = model ]; then
    setup_model
    exit 0
  fi

  if [ "$#" -gt 0 ]; then
    usage >&2
    exit 2
  fi

  setup
  exit 0
}

dispatch_command() {
  if [ "$#" -eq 0 ]; then
    usage >&2
    exit 2
  fi

  requested_command=$1
  case $requested_command in
    run|setup|install|update|uninstall|help|-h|--help)
      shift
      ;;
    *)
      requested_command=run
      ;;
  esac

  case $requested_command in
    run)
      run_command "$@"
      ;;
    setup)
      setup_command "$@"
      ;;
    install)
      install_command "$@"
      ;;
    update)
      update_command "$@"
      ;;
    uninstall)
      uninstall_command "$@"
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
  esac
}

main() {
  while [ "$#" -gt 0 ]; do
    case $1 in
      -v)
        if [ "$verbosity" -lt 1 ]; then
          verbosity=1
        fi
        shift
        ;;
      -vv)
        if [ "$verbosity" -lt 2 ]; then
          verbosity=2
        fi
        shift
        ;;
      -vvv)
        verbosity=3
        shift
        ;;
      --)
        shift
        break
        ;;
      *)
        break
        ;;
    esac
  done

  dispatch_command "$@"
}

main "$@"
