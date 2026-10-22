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

# useradd copies a stock .bashrc from /etc/skel, which would block stow
rm -f "$HOME/.bashrc"
run_logged "Stowing dotfiles" local/bin/bunny-stow

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
