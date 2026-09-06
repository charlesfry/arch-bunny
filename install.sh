#!/bin/bash

set -eEuo pipefail

_startup_error() {
  if [[ -t 2 && ${TERM:-dumb} != dumb && -z ${NO_COLOR+x} ]]; then
    printf '\033[0;31m● %s\033[0m\n' "$1" >&2
  else
    printf 'ERROR %s\n' "$1" >&2
  fi
}

if ((EUID == 0)); then
  _startup_error "Run install.sh as a normal user, not as root or through sudo."
  exit 1
fi

if [[ -z "${BUNNY_PATH:-}" ]]; then
  BUNNY_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  export BUNNY_PATH
fi

if [[ "$(pwd)" != "$BUNNY_PATH" ]]; then
  _startup_error "install.sh must be run from the arch-bunny root ($BUNNY_PATH)"
  exit 1
fi

if [[ -z "${BUNNY_INSTALL:-}" ]]; then
  export BUNNY_INSTALL="$BUNNY_PATH/install"
fi

export BUNNY_INSTALL_DEFAULTS_PATH="$BUNNY_INSTALL/default"
export BUNNY_INSTALL_LOG_FILE="${BUNNY_INSTALL_LOG_FILE:-$HOME/.local/state/arch-bunny/install.log}"
export BUNNY_INSTALL_RUN_ID="${BUNNY_INSTALL_RUN_ID:-$(date '+%Y%m%dT%H%M%S')-$$}"
export BUNNY_INSTALL_TRACE_FILE="${BUNNY_INSTALL_TRACE_FILE:-$BUNNY_INSTALL_LOG_FILE.$BUNNY_INSTALL_RUN_ID.trace}"
export BUNNY_CURRENT_PHASE="startup"

# Ensure log files exist and keep the command trace private to the current user.
mkdir -p "$(dirname "$BUNNY_INSTALL_LOG_FILE")" 2>/dev/null || true
touch "$BUNNY_INSTALL_LOG_FILE" "$BUNNY_INSTALL_TRACE_FILE"
chmod 600 "$BUNNY_INSTALL_TRACE_FILE"
exec 19>>"$BUNNY_INSTALL_TRACE_FILE"
export BASH_XTRACEFD=19
export PS4='+ ${BASH_SOURCE##*/}:${LINENO}: '
set -x

# Source helper functions FIRST (before any function calls)
if [[ ! -f "$BUNNY_INSTALL/lib/helpers.sh" ]]; then
  _startup_error "Helper functions not found at $BUNNY_INSTALL/lib/helpers.sh"
  _startup_error "Log: $BUNNY_INSTALL_LOG_FILE"
  exit 1
fi
# shellcheck source=install/lib/helpers.sh
source "$BUNNY_INSTALL/lib/helpers.sh"

BUNNY_DEFER_ERRORS=1
BUNNY_ERROR_REPORTED=0
_install_error() {
  local status=$1
  local line=$2
  local command=$3

  if ((BUNNY_ERROR_REPORTED == 0)); then
    BUNNY_ERROR_REPORTED=1
    if [[ -n ${BUNNY_LAST_FAILED_COMMAND:-} ]]; then
      command=$BUNNY_LAST_FAILED_COMMAND
    elif [[ -n ${BUNNY_LAST_ERROR:-} ]]; then
      command=
    fi
    log "Installation failed: run=$BUNNY_INSTALL_RUN_ID phase=$BUNNY_CURRENT_PHASE status=$status line=$line command=$command"
    section_failed "$status" "$command"
  fi
  return "$status"
}
trap '_install_error "$?" "$LINENO" "$BASH_COMMAND"' ERR
trap 'BUNNY_LAST_ERROR="Installation interrupted"; _install_error 130 "$LINENO" "SIGINT"; exit 130' INT
trap 'BUNNY_LAST_ERROR="Installation terminated"; _install_error 143 "$LINENO" "SIGTERM"; exit 143' TERM

# Source a numbered install phase script or exit
run_phase() {
  local script="$BUNNY_INSTALL/$1"
  local title="${2:-$1}"
  export BUNNY_CURRENT_PHASE="$1"
  if [[ ! -f "$script" ]]; then
    error "Phase script not found: $script"
    exit 1
  fi
  BUNNY_LAST_ERROR=
  BUNNY_LAST_FAILED_COMMAND=
  BUNNY_LAST_COMMAND_ERROR=
  section_start "$title"
  log "Phase context: run=$BUNNY_INSTALL_RUN_ID phase=$1 user=$(id -un) uid=$(id -u) euid=$EUID pwd=$PWD"
  # shellcheck disable=SC1090 # numbered phase paths are validated immediately above
  source "$script"
  section_complete "$title"
}

if ((BUNNY_COLOR_OUTPUT)); then
  printf '\n%b%s%b\n' "$BOLD" "arch-bunny installer" "$NC"
  printf '%b  ├─ Source: %s\n  └─ Log:    %s%b\n\n' \
    "$DIM" "$BUNNY_PATH" "$BUNNY_INSTALL_LOG_FILE" "$NC"
else
  printf '\ndotfiles installer\n'
  printf '  Source: %s\n' "$BUNNY_PATH"
  printf '  Log:    %s\n\n' "$BUNNY_INSTALL_LOG_FILE"
fi
log <<EOF
Vars log:
  + BUNNY_PATH=$BUNNY_PATH
  + BUNNY_INSTALL=$BUNNY_INSTALL
  + BUNNY_INSTALL_LOG_FILE=$BUNNY_INSTALL_LOG_FILE
  + BUNNY_INSTALL_DEFAULTS_PATH=$BUNNY_INSTALL_DEFAULTS_PATH
  + BUNNY_INSTALL_TRACE_FILE=$BUNNY_INSTALL_TRACE_FILE
  + BUNNY_INSTALL_RUN_ID=$BUNNY_INSTALL_RUN_ID
  + USER=$(id -un)
  + UID=$(id -u)
  + EUID=$EUID
  + PWD=$PWD
  + XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-<unset>}
EOF
log "Installation started at: $(date '+%Y-%m-%d %H:%M:%S')"

log "Starting installation phases"

run_phase "00-preflight.sh" "Preflight checks"
readonly BUNNY_DEFAULT_USER BUNNY_DEFAULT_UID BUNNY_USER_HOME

run_phase "10-packages.sh" "Packages and repositories"

# Log the user identity established during preflight.
log <<EOF
Vars log:
    BUNNY_PATH=$BUNNY_PATH
    BUNNY_INSTALL=$BUNNY_INSTALL
    BUNNY_INSTALL_LOG_FILE=$BUNNY_INSTALL_LOG_FILE
    BUNNY_INSTALL_DEFAULTS_PATH=$BUNNY_INSTALL_DEFAULTS_PATH
  + BUNNY_DEFAULT_USER=${BUNNY_DEFAULT_USER:-}
  + BUNNY_DEFAULT_UID=${BUNNY_DEFAULT_UID:-}
  + BUNNY_USER_HOME=${BUNNY_USER_HOME:-}
EOF

run_phase "11-nvidia.sh" "NVIDIA drivers"
run_phase "12-greetd.sh" "Display manager"
run_phase "13-bootloader.sh" "Bootloader and boot process"
run_phase "14-aur.sh" "AUR files"

# Dotfiles phase - stowing dotfiles
run_phase "20-dotfiles.sh" "Dotfiles"

# Systemd phase - starting systemd services
run_phase "30-system-services.sh" "System services"

run_phase "40-user-setup.sh" "User services and directories"
log "Checking ownership of installer-managed user state"
verify_user_ownership \
  "$HOME/.config" \
  "$HOME/.cache" \
  "$HOME/.local" \
  "$HOME/notes" \
  "$HOME/projects" \
  "$HOME/work"
run_phase "45-nvim-notebook.sh" "Neovim notebook stack"
run_phase "50-firewall.sh" "Firewall"
run_phase "60-docker.sh" "Docker"
run_phase "70-factory-snapshot.sh" "Factory snapshot"

export BUNNY_CURRENT_PHASE="complete"
log "Installation finished: run=$BUNNY_INSTALL_RUN_ID status=0"
printf '\n'
if ((BUNNY_COLOR_OUTPUT)); then
  printf '%b%s%b\n' "$GREEN$BOLD" "Installed successfully." "$NC"
  printf '%b  └─ Log: %s%b\n\n' \
    "$DIM" "$BUNNY_INSTALL_LOG_FILE" "$NC"
else
  printf '%s\n' "Installed successfully."
  printf 'Log: %s\n' "$BUNNY_INSTALL_LOG_FILE"
fi

reboot_answer=
if ((BUNNY_INTERACTIVE_OUTPUT)); then
  read -rp "Reboot now? [y/N] " reboot_answer </dev/tty || true
else
  printf 'Reboot to start the configured desktop session.\n'
fi

if [[ $reboot_answer =~ ^[Yy]$ ]]; then
  export BUNNY_CURRENT_PHASE="reboot"
  section_start "Reboot"
  run_logged "Requesting system reboot" sudo systemctl reboot
  section_complete "Reboot"
elif ((BUNNY_INTERACTIVE_OUTPUT)); then
  printf 'Reboot skipped. Run sudo systemctl reboot when ready.\n'
fi
