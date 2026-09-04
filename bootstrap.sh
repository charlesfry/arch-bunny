#!/bin/bash
set -euo pipefail

# Curl-able bootstrap for charlesfry/arch-bunny
# Usage:
#   sudo pacman -S --needed curl && bash <(curl -fsSL https://raw.githubusercontent.com/charlesfry/arch-bunny/master/bootstrap.sh)
#   sudo pacman -S --needed curl && bash <(curl -fsSL https://raw.githubusercontent.com/charlesfry/arch-bunny/master/bootstrap.sh) -b back_to_arch

REPO_URL="https://github.com/charlesfry/arch-bunny.git"
CLONE_DIR="$HOME/arch-bunny"
BRANCH=""
BOOTSTRAP_LOG="$HOME/.local/state/arch-bunny/install.log"

if [[ -t 1 && ${TERM:-dumb} != dumb ]]; then
  INTERACTIVE_OUTPUT=1
else
  INTERACTIVE_OUTPUT=0
fi
if ((INTERACTIVE_OUTPUT)) && [[ -z ${NO_COLOR+x} ]]; then
  BLUE='\033[0;94m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  RED='\033[0;31m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  BLUE=
  GREEN=
  YELLOW=
  RED=
  BOLD=
  NC=
fi

bootstrap_error() {
  printf '%b• %s%b\n' "$RED" "$1" "$NC" >&2
}

bootstrap_start() {
  if ((INTERACTIVE_OUTPUT)); then
    printf '%b○ %s%b' "$BLUE" "$1" "$NC"
  else
    printf 'START %s\n' "$1"
  fi
}

bootstrap_done() {
  if ((INTERACTIVE_OUTPUT)); then
    printf '\r\033[2K%b• %s%b\n' "$GREEN" "$1" "$NC"
  else
    printf 'DONE  %s\n' "$1"
  fi
}

run_quiet() {
  local description=$1
  shift
  local capture_file status command_string error_output line
  capture_file=$(mktemp)
  printf -v command_string '%q ' "$@"
  bootstrap_start "$description"

  if "$@" >"$capture_file" 2>&1; then
    status=0
  else
    status=$?
  fi

  {
    printf '[%s] [BOOTSTRAP] Command: %s\n' "$(date '+%F %T')" "${command_string% }"
    sed $'s/\033\[[0-9;?]*[[:alpha:]]//g' "$capture_file"
    printf '[%s] [BOOTSTRAP] Exit status: %d\n' "$(date '+%F %T')" "$status"
  } >> "$BOOTSTRAP_LOG"

  if ((status == 0)); then
    bootstrap_done "$description"
  else
    ((INTERACTIVE_OUTPUT)) && printf '\r\033[2K'
    bootstrap_error "$description failed with status $status"
    error_output=$(tail -n 20 "$capture_file" \
      | tr '\r' '\n' \
      | sed $'s/\033\[[0-9;?]*[[:alpha:]]//g' \
      | grep -Ei 'error|failed|failure|fatal|exception|denied|invalid|not found' \
      | tail -n 4 || true)
    if [[ -z $error_output ]]; then
      error_output=$(tail -n 1 "$capture_file")
    fi
    while IFS= read -r line; do
      [[ -z $line ]] || bootstrap_error "$line"
    done <<< "$error_output"
    bootstrap_error "Log: $BOOTSTRAP_LOG"
  fi
  rm -f "$capture_file"
  return "$status"
}

while (($# > 0)); do
  case "$1" in
    -b|--branch)
      if [[ -z ${2:-} ]]; then
        bootstrap_error "-b/--branch requires a branch name"
        printf 'Usage: bootstrap.sh [-b|--branch <branch>]\n' >&2
        exit 1
      fi
      BRANCH=$2
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage: bootstrap.sh [-b|--branch <branch>]

Options:
  -b, --branch <name>   Branch to clone (default: repo default)
  -h, --help            Show this help message
EOF
      exit 0
      ;;
    *)
      bootstrap_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

mkdir -p "$(dirname "$BOOTSTRAP_LOG")"
touch "$BOOTSTRAP_LOG"

printf '%b%s%b\n' "$BOLD" "dotfiles bootstrap" "$NC"
printf 'Repository: %s\n' "$REPO_URL"
printf 'Target: %s\n' "$CLONE_DIR"
[[ -z $BRANCH ]] || printf 'Branch: %s\n' "$BRANCH"
printf 'Log: %s\n\n' "$BOOTSTRAP_LOG"

# The installer requires sudo access. Authenticate before rendering any
# in-place status lines so a password prompt cannot overwrite them.
if ! sudo -n true 2>/dev/null; then
  printf 'sudo access is required to continue.\n'
  if ! sudo -v; then
    bootstrap_error "Unable to obtain sudo access"
    exit 1
  fi
fi

if ! command -v git >/dev/null 2>&1; then
  run_quiet "Installing Git" sudo pacman -S --noconfirm git
else
  bootstrap_done "Git is available"
fi

if [[ -d $CLONE_DIR ]]; then
  bootstrap_error "$CLONE_DIR already exists; remove or rename it first"
  exit 1
fi

clone_args=(--recurse-submodules)
if [[ -n $BRANCH ]]; then
  clone_args+=(-b "$BRANCH")
fi
run_quiet "Cloning repository" git clone "${clone_args[@]}" "$REPO_URL" "$CLONE_DIR"

printf '\n%b' "$YELLOW"
cat <<'EOF'
! This will configure packages, the bootloader, firewall, display manager,
  and other system settings. It is intended for a fresh Arch installation.
EOF
printf '%b\n' "$NC"

answer=""
if [[ -r /dev/tty ]]; then
  read -rp "Start the installation now? [y/N] " answer </dev/tty || true
else
  read -rp "Start the installation now? [y/N] " answer || true
fi
if [[ ! $answer =~ ^[Yy]$ ]]; then
  printf 'Aborted. You can run it later with: bash %s/install.sh\n' "$CLONE_DIR"
  exit 0
fi

if ! cd "$CLONE_DIR"; then
  bootstrap_error "Failed to cd into $CLONE_DIR"
  exit 1
fi

exec bash install.sh
