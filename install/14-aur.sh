#!/bin/bash
# Phase 14: build and install everything listed in install/packages-yay from the
# AUR with yay. Runs after 13-bootloader.sh — that phase's last line is
# remove_pacman_generation_override, so by the time this phase starts the normal
# mkinitcpio/limine pacman hooks are live again and an AUR package that *did*
# touch boot artifacts would regenerate them against a config already validated
# and promoted to last-known-working. Nothing in packages-yay does today
# (brave-bin is the only entry), which is exactly why this is a separate phase
# instead of more lines in 10-packages.sh.

log "Installing AUR packages with yay..." # announce the phase, matches the other phases' style.

if [[ ! -f $BUNNY_INSTALL/packages-yay ]]; then
  error "AUR package list not found: $BUNNY_INSTALL/packages-yay"
  return 1 # phases are sourced, not executed, so `return` (not `exit`) reports failure.
fi

# yay is a normal entry in install/packages (the omarchy repo ships a prebuilt
# binary, so pacman can install it without an AUR helper — the usual
# chicken-and-egg problem doesn't apply here). If it is missing, 10-packages.sh
# either did not run or its verification loop lied; fail loudly rather than
# skipping the AUR packages and letting verify.sh discover it later.
if ! command_exists yay; then
  error "yay is not installed — 10-packages.sh must install it before this phase"
  return 1
fi

# Same list-parsing contract as 10-packages.sh: one package per line, blank
# lines and # comments ignored. Kept as a duplicated one-liner rather than a
# shared helper — it is one grep, and a helpers.sh function taking a path would
# be more code than it saves.
declare -a aur_packages=()
mapfile -t aur_packages < <(grep -Ev '^(#|[[:space:]]*$)' "$BUNNY_INSTALL/packages-yay")
if ((${#aur_packages[@]} == 0)); then
  error "AUR package list is empty: $BUNNY_INSTALL/packages-yay"
  return 1
fi

# No validate_package_resolution equivalent here. That helper runs `pacman -Si`,
# which only knows the configured binary repositories and would reject every AUR
# name outright; `yay -Si` would work but means a second full AUR metadata fetch
# to learn something the build itself reports one line later.
#
# yay runs unprivileged on purpose — makepkg refuses to run as root, and yay
# calls `sudo pacman -U` itself for the install step at the end. install.sh
# already rejects EUID 0 at the top, so this phase inherits the invoking user,
# and yay's build tree stays in that user's ~/.cache/yay instead of appearing in
# root's cache with root-owned files. Do not wrap this in sudo.
#
# ponytail: no sudo-timestamp keepalive. A long first build (brave-bin is a large
# download) can outlive the sudo grace period and make yay prompt for a password
# partway through an otherwise unattended install. Add `sudo -v` in a background
# refresh loop if that turns out to be annoying in practice.
run_logged "Building AUR packages: ${aur_packages[*]}" \
  yay -S --noconfirm --needed "${aur_packages[@]}"

# yay exits non-zero on a failed build, and install.sh's ERR trap would already
# have caught it — but a partially satisfied group (one package built, another
# silently skipped as an unresolvable dependency) can still exit 0, so confirm
# each name is actually in the local pacman database. package_installed is
# `pacman -Q`, which sees AUR-built packages the same as repository ones.
for package in "${aur_packages[@]}"; do
  if ! package_installed "$package"; then
    error "Failed to verify AUR package: $package"
    return 1
  fi
done
success "AUR packages are installed and verified"
