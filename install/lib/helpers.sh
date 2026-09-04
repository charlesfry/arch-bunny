#!/bin/bash

# Installer diagnostics and terminal status rendering.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;94m'
DIM='\033[0;90m'
# shellcheck disable=SC2034 # Used by install.sh after this library is sourced.
BOLD='\033[1m'
NC='\033[0m'
ERASE_LINE='\033[2K'
CURSOR_UP='\033[1A'

BUNNY_ACTIVE_SECTION=${BUNNY_ACTIVE_SECTION:-}
BUNNY_CURRENT_STEP=${BUNNY_CURRENT_STEP:-}
BUNNY_SECTION_NOTE=${BUNNY_SECTION_NOTE:-}
BUNNY_STATUS_RENDERED=0
BUNNY_TICKER_RENDERED=0
BUNNY_LAST_ERROR=${BUNNY_LAST_ERROR:-}
BUNNY_LAST_FAILED_COMMAND=${BUNNY_LAST_FAILED_COMMAND:-}
BUNNY_LAST_COMMAND_ERROR=${BUNNY_LAST_COMMAND_ERROR:-}

if [[ -t 1 && ${TERM:-dumb} != dumb ]]; then
  BUNNY_INTERACTIVE_OUTPUT=1
else
  BUNNY_INTERACTIVE_OUTPUT=0
fi
if [[ -n ${NO_COLOR+x} ]]; then
  BUNNY_COLOR_OUTPUT=0
else
  BUNNY_COLOR_OUTPUT=$BUNNY_INTERACTIVE_OUTPUT
fi

_read_message() {
  if (($#)); then
    printf '%s' "$*"
  else
    cat
  fi
}

_write_log() {
  local level=$1
  shift
  local message timestamp line
  message="$(_read_message "$@")"
  timestamp=$(date '+%F %T')

  while IFS= read -r line || [[ -n $line ]]; do
    printf '[%s] [%-7s] %s\n' "$timestamp" "$level" "$line"
  done <<< "$message" >> "${BUNNY_INSTALL_LOG_FILE:-/dev/null}"
}

_print_styled() {
  local color=$1
  shift
  if ((BUNNY_COLOR_OUTPUT)); then
    printf '%b%s%b' "$color" "$*" "$NC"
  else
    printf '%s' "$*"
  fi
}

_clear_status_display() {
  ((BUNNY_INTERACTIVE_OUTPUT && BUNNY_STATUS_RENDERED)) || return 0

  if ((BUNNY_TICKER_RENDERED)); then
    printf '\r%b' "$ERASE_LINE"
  fi
  printf '%b\r%b' "$CURSOR_UP" "$ERASE_LINE"
  BUNNY_STATUS_RENDERED=0
  BUNNY_TICKER_RENDERED=0
}

_render_active_status() {
  ((BUNNY_INTERACTIVE_OUTPUT)) || return 0
  [[ -n $BUNNY_ACTIVE_SECTION ]] || return 0

  _print_styled "$BLUE" "○ $BUNNY_ACTIVE_SECTION"
  printf '\n'
  BUNNY_STATUS_RENDERED=1

  if [[ -n $BUNNY_CURRENT_STEP ]]; then
    _print_styled "$DIM" "  ○ $BUNNY_CURRENT_STEP"
    BUNNY_TICKER_RENDERED=1
  fi
}

_update_ticker_elapsed() {
  local description=$1
  local elapsed=$2
  ((BUNNY_INTERACTIVE_OUTPUT && BUNNY_TICKER_RENDERED)) || return 0

  printf '\r%b' "$ERASE_LINE"
  _print_styled "$DIM" "  ○ $description (${elapsed}s)"
}

_command_is_running() {
  local state
  state=$(ps -o stat= -p "$1" 2>/dev/null) || return 1
  [[ $state != Z* ]]
}

log() {
  _write_log INFO "$@"
}

step() {
  local message
  message="$(_read_message "$@")"
  BUNNY_CURRENT_STEP=$message
  _write_log STEP "$message"

  if ((BUNNY_INTERACTIVE_OUTPUT)); then
    _clear_status_display
    _render_active_status
  else
    printf 'STEP  %s\n' "$message"
  fi
}

section_start() {
  local title=$1
  if [[ -n $BUNNY_ACTIVE_SECTION ]]; then
    section_complete "$BUNNY_ACTIVE_SECTION"
  fi

  BUNNY_ACTIVE_SECTION=$title
  BUNNY_CURRENT_STEP=
  BUNNY_SECTION_NOTE=
  _write_log SECTION "Starting: $title"

  if ((BUNNY_INTERACTIVE_OUTPUT)); then
    _render_active_status
  else
    printf 'START %s\n' "$title"
  fi
}

section_complete() {
  local title=${1:-$BUNNY_ACTIVE_SECTION}
  [[ -n $title ]] || return 0
  _write_log SECTION "Completed: $title"

  if ((BUNNY_INTERACTIVE_OUTPUT)); then
    _clear_status_display
    _print_styled "$GREEN" "• $title"
    printf '\n'
    if [[ -n $BUNNY_SECTION_NOTE ]]; then
      _print_styled "$DIM" "  └─ $BUNNY_SECTION_NOTE"
      printf '\n'
    fi
  else
    printf 'DONE  %s\n' "$title"
    [[ -z $BUNNY_SECTION_NOTE ]] || printf 'NOTE  └─ %s\n' "$BUNNY_SECTION_NOTE"
  fi

  BUNNY_ACTIVE_SECTION=
  BUNNY_CURRENT_STEP=
  BUNNY_SECTION_NOTE=
}

section_note() {
  BUNNY_SECTION_NOTE="$(_read_message "$@")"
  _write_log NOTE "$BUNNY_SECTION_NOTE"
}

warn() {
  local message
  message="$(_read_message "$@")"
  _write_log WARN "$message"

  if ((BUNNY_INTERACTIVE_OUTPUT)); then
    _clear_status_display
    _print_styled "$YELLOW" "! $message"
    printf '\n'
    _render_active_status
  else
    printf 'WARN  %s\n' "$message" >&2
  fi
}

error() {
  local message
  message="$(_read_message "$@")"
  BUNNY_LAST_ERROR=$message
  _write_log ERROR "$message"

  # install.sh defers errors so its ERR trap can render one complete failure block.
  if [[ ${BUNNY_DEFER_ERRORS:-0} != 1 ]]; then
    if ((BUNNY_INTERACTIVE_OUTPUT)); then
      _clear_status_display
      _print_styled "$RED" "• $message"
      printf '\n'
    else
      printf 'ERROR %s\n' "$message" >&2
    fi
  fi
}

section_failed() {
  local status=$1
  local command=${2:-}
  local reason=${BUNNY_LAST_ERROR:-Command exited with status $status}
  local title=${BUNNY_ACTIVE_SECTION:-${BUNNY_CURRENT_PHASE:-Installation}}

  _write_log ERROR "Failed: $title (status=$status command=$command)"

  if ((BUNNY_INTERACTIVE_OUTPUT)); then
    _clear_status_display
    _print_styled "$RED" "• $title"
    printf '\n'
    _print_styled "$RED" "  $reason"
    printf '\n'
    if [[ -n $command ]]; then
      _print_styled "$RED" "  Command: $command"
      printf '\n'
    fi
    if [[ -n $BUNNY_LAST_COMMAND_ERROR && $BUNNY_LAST_COMMAND_ERROR != "$reason" ]]; then
      while IFS= read -r line; do
        _print_styled "$RED" "  $line"
        printf '\n'
      done <<< "$BUNNY_LAST_COMMAND_ERROR"
    fi
    _print_styled "$RED" "  Log: ${BUNNY_INSTALL_LOG_FILE:-<unavailable>}"
    printf '\n'
  else
    printf 'FAIL  %s\n' "$title" >&2
    printf 'ERROR %s\n' "$reason" >&2
    [[ -z $command ]] || printf 'ERROR Command: %s\n' "$command" >&2
    [[ -z $BUNNY_LAST_COMMAND_ERROR || $BUNNY_LAST_COMMAND_ERROR == "$reason" ]] || \
      printf 'ERROR %s\n' "$BUNNY_LAST_COMMAND_ERROR" >&2
    printf 'ERROR Log: %s\n' "${BUNNY_INSTALL_LOG_FILE:-<unavailable>}" >&2
  fi

  BUNNY_ACTIVE_SECTION=
  BUNNY_CURRENT_STEP=
  BUNNY_SECTION_NOTE=
}

# Run a non-interactive command with all routine output captured in the log.
run_logged() {
  local description=$1
  shift
  local exit_code command_string capture_file started_at elapsed line timestamp error_output
  local command_pid last_elapsed

  printf -v command_string '%q ' "$@"
  command_string=${command_string% }
  step "$description"
  _write_log COMMAND "$command_string"
  started_at=$SECONDS
  capture_file=$(mktemp)

  if ((BUNNY_INTERACTIVE_OUTPUT)); then
    "$@" >"$capture_file" 2>&1 &
    command_pid=$!
    last_elapsed=-1
    # A sudo process changes ownership to root, making `kill -0` fail for the
    # calling user even while the command is still running. Poll process state
    # instead so privileged package operations keep the ticker moving.
    while _command_is_running "$command_pid"; do
      sleep 1
      elapsed=$((SECONDS - started_at))
      if ((elapsed != last_elapsed)) && _command_is_running "$command_pid"; then
        _update_ticker_elapsed "$description" "$elapsed"
        last_elapsed=$elapsed
      fi
    done
    if wait "$command_pid"; then
      exit_code=0
    else
      exit_code=$?
    fi
  elif "$@" >"$capture_file" 2>&1; then
    exit_code=0
  else
    exit_code=$?
  fi

  timestamp=$(date '+%F %T')
  while IFS= read -r line || [[ -n $line ]]; do
    # Commands are not attached to a terminal, but strip any forced ANSI output
    # before it reaches the persistent log.
    line=$(printf '%s' "$line" | sed $'s/\033\[[0-9;?]*[[:alpha:]]//g; s/\r$//')
    printf '[%s] [OUTPUT ] %s\n' "$timestamp" "$line"
  done < "$capture_file" >> "${BUNNY_INSTALL_LOG_FILE:-/dev/null}"
  elapsed=$((SECONDS - started_at))
  _write_log COMMAND "$description exited with status $exit_code after ${elapsed}s"

  if ((exit_code != 0)); then
    BUNNY_LAST_FAILED_COMMAND=$command_string
    error_output=$(tail -n 80 "$capture_file" \
      | tr '\r' '\n' \
      | sed $'s/\033\[[0-9;?]*[[:alpha:]]//g' \
      | awk 'NF && !seen[$0]++')
    BUNNY_LAST_COMMAND_ERROR=$(printf '%s\n' "$error_output" \
      | grep -Ei '(^|[[:space:]])(error|fatal):|not supported|missing kernel module|protocol not supported|permission denied' \
      | head -n 4 || true)
    if [[ -z $BUNNY_LAST_COMMAND_ERROR ]]; then
      BUNNY_LAST_COMMAND_ERROR=$(printf '%s\n' "$error_output" \
        | grep -Ei 'error|failed|failure|fatal|exception|denied|invalid|not found' \
        | tail -n 4 || true)
    fi
    if [[ -z $BUNNY_LAST_COMMAND_ERROR ]]; then
      BUNNY_LAST_COMMAND_ERROR=$(tail -n 1 <<< "$error_output")
    fi
  else
    BUNNY_LAST_FAILED_COMMAND=
    BUNNY_LAST_COMMAND_ERROR=
  fi
  rm -f "$capture_file"
  return "$exit_code"
}

# Compatibility names used while phase scripts are kept independently sourceable.
info() { step "$@"; }
important() { log "$@"; }
success() { log "$@"; }
section() { section_start "$@"; }

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

verify_user_ownership() {
  local path unexpected_owner

  for path in "$@"; do
    [[ -e $path ]] || continue
    unexpected_owner=$(find "$path" -xdev ! -uid "$BUNNY_DEFAULT_UID" -print -quit)
    if [[ -n $unexpected_owner ]]; then
      error "Unexpected ownership under $path: $unexpected_owner"
      return 1
    fi
  done
}

package_installed() {
  pacman -Q "$1" >/dev/null 2>&1
}

prepare_pacman_generation_override() {
  local override_hook

  : "${BUNNY_PACMAN_HOOK_DIR:?BUNNY_PACMAN_HOOK_DIR is not set}"
  override_hook="$BUNNY_PACMAN_HOOK_DIR/90-mkinitcpio-install.hook"

  run_logged "Creating private pacman hook override" \
    sudo rm -rf -- "$BUNNY_PACMAN_HOOK_DIR"
  sudo install -d -m 700 "$BUNNY_PACMAN_HOOK_DIR"
  sudo ln -s /dev/null "$override_hook"

  if [[ $(sudo readlink "$override_hook") != /dev/null ]]; then
    error "Pacman generation hook override is invalid: $override_hook"
    return 1
  fi
  log "Package-triggered boot generation will be deferred after the system upgrade"
}

remove_pacman_generation_override() {
  : "${BUNNY_PACMAN_HOOK_DIR:?BUNNY_PACMAN_HOOK_DIR is not set}"
  run_logged "Removing private pacman hook override" \
    sudo rm -rf -- "$BUNNY_PACMAN_HOOK_DIR"
}

install_packages_without_generation() {
  local override_hook

  if (($# == 0)); then
    error "No packages supplied for installation"
    return 1
  fi

  : "${BUNNY_PACMAN_HOOK_DIR:?BUNNY_PACMAN_HOOK_DIR is not set}"
  override_hook="$BUNNY_PACMAN_HOOK_DIR/90-mkinitcpio-install.hook"
  if [[ $(sudo readlink "$override_hook" 2>/dev/null) != /dev/null ]]; then
    error "Pacman generation hook override is not active: $override_hook"
    return 1
  fi

  log "Packages requested with boot generation deferred: $*"
  run_logged "Installing packages with boot generation deferred" \
    sudo pacman --hookdir "$BUNNY_PACMAN_HOOK_DIR" \
      -S --noconfirm --needed "$@"
}

validate_package_resolution() {
  local package
  local -a unresolved=()

  for package in "$@"; do
    if ! pacman -Si -- "$package" >/dev/null 2>&1; then
      unresolved+=("$package")
    fi
  done

  if ((${#unresolved[@]} > 0)); then
    error "Required packages do not resolve: ${unresolved[*]}"
    printf 'ERROR: Required packages do not resolve: %s\n' "${unresolved[*]}" >&2
    return 1
  fi
  log "All required packages resolve from configured repositories"
}

install_missing_packages() {
  local packages=("$@")
  local missing=()
  local pkg verify_failed

  step "Checking ${#packages[@]} required packages"

  for pkg in "${packages[@]}"; do
    if ! package_installed "$pkg"; then
      missing+=("$pkg")
    fi
  done

  if ((${#missing[@]} > 0)); then
    step "Installing ${#missing[@]} missing packages"
    install_packages_without_generation "${missing[@]}"

    step "Verifying installed packages"
    verify_failed=0
    for pkg in "${packages[@]}"; do
      if ! package_installed "$pkg"; then
        error "Failed to verify package: $pkg"
        verify_failed=1
      fi
    done
    ((verify_failed == 0)) || return 1
  else
    log "All required packages were already installed"
  fi
  log "Required packages are installed and verified"
}
