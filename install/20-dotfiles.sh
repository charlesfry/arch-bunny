#!/bin/bash

if [[ $HOME != "$BUNNY_USER_HOME" ]]; then
  error "Stow target does not match the home directory validated by preflight"
  return 1
fi

if [[ "$(pwd)" != "$BUNNY_PATH" ]]; then
  error "Working directory must be $BUNNY_PATH"
  return 1
fi
log "Working directory: $(pwd)"

remove_regular_stow_conflict() {
  local path=$1

  if [[ -f $path && ! -L $path ]]; then
    log "Removing regular file that conflicts with Stow: $path"
    rm -f -- "$path"
  fi
}

remove_regular_stow_conflict "$HOME/.bashrc"

step "Stowing home files"
run_logged "Stowing home files" stow -t "$HOME" home

remove_regular_stow_conflict "$HOME/.config/niri/config.kdl"

mkdir -p "$HOME/.config"
for managed_config in \
  "$HOME/.config/mimeapps.list" \
  "$HOME/.config/gtk-3.0/settings.ini" \
  "$HOME/.config/gtk-4.0/settings.ini"; do
  remove_regular_stow_conflict "$managed_config"
done
run_logged "Stowing application configuration" \
  stow --no-folding -t "$HOME/.config" config

mkdir -p "$HOME/.local"
run_logged "Stowing local executables" \
  stow --no-folding -t "$HOME/.local" local

# Machine-local shell settings, sourced at the end of ~/.bashrc
if [[ -f "$HOME/.personal.bashrc" && ! -e "$HOME/.bashrc.local" ]]; then
  mv "$HOME/.personal.bashrc" "$HOME/.bashrc.local"
  success "Renamed ~/.personal.bashrc to ~/.bashrc.local"
elif [[ ! -e "$HOME/.bashrc.local" ]]; then
  echo "# Machine-local bash settings, never tracked by git." >"$HOME/.bashrc.local"
  success "Created ~/.bashrc.local for machine-local shell settings"
fi

# `git config --global` writes to ~/.gitconfig when it exists, and only falls
# back to ~/.config/git/config when it does not
if [[ ! -e "$HOME/.gitconfig" ]]; then
  cp install/gitconfig.dist "$HOME/.gitconfig"
  success "Created ~/.gitconfig for machine-local settings"
fi

verify_user_ownership "$HOME/.config" "$HOME/.local" "$HOME/.bashrc" "$HOME/.profile"
success "Dotfiles symlinked"
