#!/bin/bash

# greetd configuration for autologin with fallback to bare TTY
step "Configuring greetd for direct autologin"

log "Creating greetd configuration directory"
run_logged "Create /etc/greetd" sudo mkdir -p /etc/greetd

# Configure greetd with initial session (autologin) and fallback to bare shell
step "Writing greetd configuration"
sudo tee /etc/greetd/config.toml > /dev/null <<EOF
[terminal]
vt = "next"

[general]
source_profile = true

[initial_session]
command = "uwsm start -- niri.desktop"
user = "$BUNNY_DEFAULT_USER"

[default_session]
command = "/bin/sh"
user = "$BUNNY_DEFAULT_USER"
EOF

# Prevent niri.service from auto-starting via default.target (uwsm manages it)
if systemctl --user is-enabled niri.service >/dev/null 2>&1; then
  run_logged "Disable niri.service user unit" \
    systemctl --user disable niri.service
else
  log "niri.service user unit is already disabled"
fi

success "greetd configuration complete"
log "Auto-login user: $BUNNY_DEFAULT_USER"
