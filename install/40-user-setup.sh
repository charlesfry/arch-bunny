#!/bin/bash

# Enable graphical session services
enable_user_services() {
  for svc in "$@"; do
    run_logged "enabling $svc" \
      systemctl --user enable "$svc"
  done
}

# Enable session services
enable_user_services \
  waybar \
  mako \
  swaybg \
  swayidle \
  swayosd

step "Configuring GTK appearance"
gsettings set org.gnome.desktop.interface color-scheme prefer-dark
gsettings set org.gnome.desktop.interface gtk-theme Adwaita-dark

step "Creating default home directories"
DEFAULT_DIRS=(
  notes
  projects
  work
)
for dir in "${DEFAULT_DIRS[@]}"; do
  mkdir -p "$HOME/$dir"
done

step "Installing application menu overrides"
APPLICATION_OVERRIDES_DIR="$HOME/.local/share/applications"
mkdir -p "$APPLICATION_OVERRIDES_DIR"
for desktop_override in "$BUNNY_INSTALL_DEFAULTS_PATH/applications/"*.desktop; do
  install -m 0644 -- "$desktop_override" \
    "$APPLICATION_OVERRIDES_DIR/${desktop_override##*/}"
done

# Install the repository default wallpaper without stowing it. Keep an
# existing local override.
DEFAULT_BACKGROUND="$BUNNY_INSTALL_DEFAULTS_PATH/background.jpg"
if [[ ! -e $HOME/background.jpg && ! -L $HOME/background.jpg ]]; then
  cp -- "$DEFAULT_BACKGROUND" "$HOME/background.jpg"
  log "Installed default wallpaper"
fi

verify_user_ownership \
  "$APPLICATION_OVERRIDES_DIR" \
  "$HOME/notes" \
  "$HOME/projects" \
  "$HOME/work"

success "Post-install user setup complete"
