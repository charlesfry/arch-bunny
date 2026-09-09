#!/bin/bash

step "Checking optional extras"

extras_repo_list="$BUNNY_INSTALL/packages-extra"
extras_aur_list="$BUNNY_INSTALL/packages-extra-yay"

declare -a extras_repo=() extras_aur=()
if [[ -f $extras_repo_list ]]; then
  mapfile -t extras_repo < <(grep -Ev '^(#|[[:space:]]*$)' "$extras_repo_list")
fi
if [[ -f $extras_aur_list ]]; then
  mapfile -t extras_aur < <(grep -Ev '^(#|[[:space:]]*$)' "$extras_aur_list")
fi

declare -a missing_repo=() missing_aur=()
for package in "${extras_repo[@]}"; do
  package_installed "$package" || missing_repo+=("$package")
done
for package in "${extras_aur[@]}"; do
  package_installed "$package" || missing_aur+=("$package")
done

if ((${#missing_repo[@]} + ${#missing_aur[@]} == 0)); then
  section_note "All optional extras are already installed"
  return 0
fi

extras_answer=${BUNNY_INSTALL_EXTRAS:-}
if [[ -z $extras_answer ]]; then
  if ((BUNNY_INTERACTIVE_OUTPUT)); then
    # The section's status line is mid-render, so clear it before writing the
    # prompt and put it back afterwards. warn() does exactly this dance.
    _clear_status_display
    printf '\nOptional extras are not installed:\n'
    printf '  %s\n' "${missing_repo[@]}" "${missing_aur[@]}"
    printf '\n'
    # Pre-initialized: if /dev/tty cannot be opened the redirect fails, read
    # never runs, and set -u would abort on the unset variable below.
    extras_reply=
    read -rp "Install them now? [y/N] " extras_reply </dev/tty || true
    if [[ $extras_reply =~ ^[Yy]$ ]]; then
      extras_answer=1
    else
      extras_answer=0
    fi
    _render_active_status
  else
    # Never block an unattended run on a question nobody is there to answer.
    extras_answer=0
  fi
fi

if [[ $extras_answer != 1 ]]; then
  log "Optional extras declined: ${missing_repo[*]} ${missing_aur[*]}"
  section_note "Optional extras skipped; rerun install.sh --extras to install them"
  return 0
fi

if ((${#missing_repo[@]} > 0)); then
  run_logged "Installing optional packages: ${missing_repo[*]}" \
    sudo pacman -S --noconfirm --needed "${missing_repo[@]}"
fi

if ((${#missing_aur[@]} > 0)); then
  if ! command_exists yay; then
    error "yay is not installed — 10-packages.sh must install it before this phase"
    return 1
  fi
  # Unprivileged on purpose: makepkg refuses to run as root, and yay calls
  # `sudo pacman -U` itself for the install step. See 14-aur.sh.
  run_logged "Building optional AUR packages: ${missing_aur[*]}" \
    yay -S --noconfirm --needed "${missing_aur[@]}"
fi

# yay can exit 0 with a package silently skipped as an unresolvable dependency,
# so the exit status alone does not prove anything landed. The extras were asked
# for by now, which makes a partial result a failed install.
verify_failed=0
for package in "${missing_repo[@]}" "${missing_aur[@]}"; do
  if ! package_installed "$package"; then
    error "Failed to verify optional package: $package"
    verify_failed=1
  fi
done
((verify_failed == 0)) || return 1
success "Optional extras are installed and verified"
