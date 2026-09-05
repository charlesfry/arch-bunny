#!/bin/bash

step "Configuring networking and system services"

# Bluetooth
if ! systemctl is-enabled --quiet bluetooth.service; then
  run_logged "Enable bluetooth service" \
    sudo systemctl enable bluetooth.service
fi

# Wifi
if systemctl is-enabled --quiet NetworkManager; then
  run_logged "Disable NetworkManager service" \
    sudo systemctl disable NetworkManager
fi

if ! systemctl is-enabled --quiet systemd-networkd.service; then
  run_logged "Enable systemd-networkd service" \
    sudo systemctl enable systemd-networkd.service
fi

if ! systemctl is-enabled --quiet iwd && ! systemctl is-enabled --quiet NetworkManager; then
  run_logged "Enable iwd service" \
    sudo systemctl enable iwd.service
fi

# Use iwd's built-in DHCP client for WiFi
sudo mkdir -p /etc/iwd
sudo cp "$BUNNY_INSTALL_DEFAULTS_PATH/iwd/main.conf" /etc/iwd/main.conf

# Battery low/critical notifications, event-driven off the power_supply
# uevent udev already receives (no resident watcher)
sudo mkdir -p /etc/udev/rules.d
sed "s|@BIN@|$HOME/.local/bin|" "$BUNNY_INSTALL_DEFAULTS_PATH/udev/99-battery-notify.rules" |
  sudo tee /etc/udev/rules.d/99-battery-notify.rules >/dev/null
run_logged "Reloading udev rules" \
  sudo udevadm control --reload-rules

# Keep systemd-networkd for ethernet only — mask WiFi/WWAN .network files
# so networkd doesn't compete with iwd for DHCP on wireless interfaces
sudo cp "$BUNNY_INSTALL_DEFAULTS_PATH/networkd/20-ethernet.network" /etc/systemd/network/20-ethernet.network
for net in 20-wlan.network 20-wwan.network; do
  if [[ -f "/etc/systemd/network/$net" ]] && [[ ! -L "/etc/systemd/network/$net" ]]; then
    sudo ln -sf /dev/null "/etc/systemd/network/$net"
  fi
done

# Disable wait-online — blocks boot when ethernet has no cable
if systemctl is-enabled --quiet systemd-networkd-wait-online.service; then
  run_logged "Disable systemd-networkd-wait-online" \
    sudo systemctl disable systemd-networkd-wait-online.service
fi

# Ensure systemd-resolved is enabled for DNS
if ! systemctl is-enabled --quiet systemd-resolved.service; then
  run_logged "Enable systemd-resolved" \
    sudo systemctl enable --now systemd-resolved.service
fi

# Ensure resolv.conf points to systemd-resolved stub
if [[ ! -L /etc/resolv.conf ]] || [[ "$(readlink /etc/resolv.conf)" != *"stub-resolv"* ]]; then
  sudo ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
fi

# Disable NVIDIA suspend/hibernate services
# NOTE-david possibly revisit this after laptop testing
for svc in nvidia-suspend nvidia-hibernate nvidia-resume nvidia-suspend-then-hibernate; do
  if systemctl is-enabled --quiet "$svc.service" 2>/dev/null; then
    run_logged "Disable $svc" \
      sudo systemctl disable "$svc.service"
  fi
done

# Snapper-sync
if ! systemctl is-enabled --quiet limine-snapper-sync; then
  run_logged "Enable limine-snapper-sync service" \
    sudo systemctl enable limine-snapper-sync.service
fi

# Disable snapper-timeline — we're not using the timer (disabled), so this is pointless
if systemctl is-enabled --quiet snapper-timeline.timer 2>/dev/null; then
  run_logged "Disable snapper-timeline timer" \
    sudo systemctl disable snapper-timeline.timer
fi

# Greetd
if ! systemctl is-enabled --quiet greetd.service; then
  run_logged "Enable greetd service" \
    sudo systemctl enable greetd.service
fi

# Power profile daemon
if ! systemctl is-enabled --quiet power-profiles-daemon; then
  run_logged "Enable power-profiles-daemon" \
    sudo systemctl enable power-profiles-daemon
fi

# Faster shutdown
sudo mkdir -p "/etc/systemd/system.conf.d"
sudo cp "$BUNNY_INSTALL_DEFAULTS_PATH/systemd/faster-shutdown.conf" /etc/systemd/system.conf.d/10-faster-shutdown.conf

# Prevent touchpad input from waking the system.
if [[ -e /sys/bus/i2c/devices/i2c-PIXA3854:00 ]]; then
  sudo mkdir -p /etc/udev/rules.d
  sudo cp "$BUNNY_INSTALL_DEFAULTS_PATH/udev/99-touchpad-no-wakeup.rules" /etc/udev/rules.d/99-touchpad-no-wakeup.rules
  sudo udevadm control --reload
  sudo udevadm trigger --subsystem-match=i2c --sysname-match='i2c-PIXA3854:00'
fi

run_logged "Reloading systemd manager" \
  sudo systemctl daemon-reload
success "System services configured"
