#!/bin/bash

# Limine bootloader

step "Checking Limine bootloader dependencies"

# Check if limine-mkinitcpio-hook is installed
if ! command_exists limine-mkinitcpio; then
  error "limine-mkinitcpio-hook not found. Install with: sudo pacman -S limine-mkinitcpio-hook"
  return 1
fi

# Check if limine-snapper-sync is installed
if ! command_exists limine-snapper-sync; then
  error "limine-snapper-sync not found. Install with: sudo pacman -S limine-snapper-sync"
  return 1
fi

# Step 1: Extract existing kernel command line from bootloader config
step "Reading the existing kernel command line"

sudo tee /etc/mkinitcpio.conf.d/bunny_hooks.conf <<EOF >/dev/null
HOOKS=(base udev plymouth keyboard autodetect microcode modconf kms keymap block encrypt filesystems btrfs-overlayfs)
EOF

# Detect boot mode
if [[ ! -d /sys/firmware/efi ]]; then
  error "Not EFI system"
  return 1
fi

# Find config location. The ESP may only be readable by root.
step "Finding the Limine configuration"
limine_config=""
for candidate in \
  /boot/EFI/arch-limine/limine.conf \
  /boot/EFI/BOOT/limine.conf \
  /boot/EFI/limine/limine.conf \
  /boot/limine/limine.conf \
  /boot/limine.conf; do
  if sudo test -f "$candidate"; then
    limine_config="$candidate"
    break
  fi
done
if [[ -z "$limine_config" ]]; then
  error "Limine config not found"
  return 1
fi
success "Limine config: $limine_config"

# Extract cmdline BEFORE we overwrite the config file
CMDLINE=$(sudo grep "^[[:space:]]*cmdline:" "$limine_config" 2>/dev/null \
  | head -1 \
  | sed 's/^[[:space:]]*cmdline:[[:space:]]*//' || true)

# If no cmdline found in current config, use a sensible default
if [[ -z "$CMDLINE" ]]; then
  warn "No cmdline found in existing config"
  warn "Manually verify limine config: $limine_config"
  return 1
fi
log "Limine cmdline: $CMDLINE"

# The managed arguments are appended by the template below. Remove existing
# occurrences first so repeated installer runs do not grow the command line.
framework_audio_blacklist=module_blacklist=snd_acp70,snd_acp_pci
for managed_arg in quiet splash nowatchdog plymouth.ignore-serial-consoles "$framework_audio_blacklist"; do
  escaped_arg=$(printf '%s\n' "$managed_arg" | sed 's/[][\\/.^$*+?{}()|]/\\&/g')
  CMDLINE=$(printf '%s\n' "$CMDLINE" | sed -E \
    "s/(^|[[:space:]])${escaped_arg}([[:space:]]|$)/\\1\\2/g; s/[[:space:]]+/ /g; s/^ //; s/ $//")
done

# Framework Laptop 13 AMD Ryzen AI 300 firmware exposes an unwired ACP mic that
# confuses ALSA's Capture Source mux into reverting to a dead capture path.
# https://github.com/FrameworkComputer/SoftwareFirmwareIssueTracker/issues/166
system_vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)
product_name=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
if [[ $system_vendor == Framework &&
      $product_name == "Laptop 13 (AMD Ryzen AI 300 Series)" ]]; then
  CMDLINE+=" $framework_audio_blacklist"
  log "Blacklisting the phantom Framework ACP microphone from the kernel command line"
fi

CMDLINE_ESCAPED=$(printf '%s\n' "$CMDLINE" | sed 's/[&\\]/\\&/g')
staged_limine_defaults=$(mktemp)
cp "$BUNNY_INSTALL_DEFAULTS_PATH/limine/default.conf" "$staged_limine_defaults"
sed -i "s|@@CMDLINE@@|$CMDLINE_ESCAPED|g" "$staged_limine_defaults"
sudo install -m 644 "$staged_limine_defaults" /etc/default/limine.bunny-new
sudo mv /etc/default/limine.bunny-new /etc/default/limine
rm -f "$staged_limine_defaults"

# Preserve the known-working configuration before asking Limine to update it.
# Keep the active file valid throughout the transaction instead of replacing it
# with an entry-less template before generation.
last_known_limine_config=/boot/limine.conf.bunny-last-known-good
sudo cp "$limine_config" "${last_known_limine_config}.bunny-new"
sudo mv "${last_known_limine_config}.bunny-new" "$last_known_limine_config"

restore_last_known_limine_configuration() {
  sudo cp "$last_known_limine_config" /boot/limine.conf.bunny-new
  sudo mv /boot/limine.conf.bunny-new /boot/limine.conf
}

# Normalize older Limine config locations without changing their content. The
# copy is promoted before the old search-path file is removed, so interruption
# cannot leave the ESP without a valid configuration.
if [[ $limine_config != /boot/limine.conf ]]; then
  sudo cp "$limine_config" /boot/limine.conf.bunny-new
  sudo mv /boot/limine.conf.bunny-new /boot/limine.conf
  sudo rm -f -- "$limine_config"
  limine_config=/boot/limine.conf
fi
success "Last known-working Limine configuration retained at $last_known_limine_config"

# Match Snapper configs
if ! sudo snapper list-configs 2>/dev/null | grep -q "root"; then
  run_logged "Creating the root Snapper configuration" \
    sudo snapper -c root create-config /
fi

if ! sudo snapper list-configs 2>/dev/null | grep -q "home"; then
  run_logged "Creating the home Snapper configuration" \
    sudo snapper -c home create-config /home
fi

# Snapper creates /.snapshots as a subvolume nested inside @. A `snapper
# rollback` swaps @, which strands every snapshot taken before it. Relocate the
# store to a top-level @snapshots, mounted from fstab like the Docker
# subvolumes in 60-docker.sh. The mount state below is the end state, so
# re-runs are no-ops.
snapshots_subvol=$(findmnt -no OPTIONS /.snapshots 2>/dev/null | tr ',' '\n' | grep '^subvol=' || true)
if [[ -n $snapshots_subvol ]]; then
  info "/.snapshots is already its own subvolume (${snapshots_subvol#subvol=})"
elif [[ -d /.snapshots ]]; then
  root_uuid=$(findmnt -no UUID /)
  snapshots_top=$(sudo mktemp -d /run/bunny-btrfs-top.XXXXXX)
  sudo mount -o subvolid=5 "UUID=$root_uuid" "$snapshots_top"
  if [[ ! -d "$snapshots_top/@snapshots" ]]; then
    run_logged "Creating subvolume @snapshots" \
      sudo btrfs subvolume create "$snapshots_top/@snapshots"
  fi
  sudo umount "$snapshots_top"
  sudo rmdir "$snapshots_top"
  run_logged "Removing the nested snapshots subvolume" \
    sudo btrfs subvolume delete /.snapshots
  sudo mkdir -p /.snapshots
  if ! grep -q 'subvol=/@snapshots\b' /etc/fstab; then
    printf '\n# arch-bunny: snapshots outside @, so a rollback that swaps @ keeps them\nUUID=%s\t/.snapshots\tbtrfs\trw,noatime,subvol=/@snapshots\t0 0\n' \
      "$root_uuid" | sudo tee -a /etc/fstab >/dev/null
  fi
  sudo systemctl daemon-reload
  run_logged "Mounting /.snapshots" sudo mount /.snapshots
  sudo chmod 750 /.snapshots
  success "Snapshots live on @snapshots, outside the root subvolume"
fi

# Enable quota to allow space-aware algorithms to work
step "Checking Btrfs quota"
if sudo btrfs quota status / | grep -qE '^\s*Enabled:\s+yes'; then
  success "Btrfs quota already enabled"
else
  run_logged "Enabling Btrfs quota" sudo btrfs quota enable /
  success "Enabled btrfs quota"
fi

# Tweak default Snapper configs
sudo sed -i 's/^TIMELINE_CREATE="yes"/TIMELINE_CREATE="no"/' /etc/snapper/configs/{root,home}
sudo sed -i 's/^NUMBER_LIMIT="50"/NUMBER_LIMIT="5"/' /etc/snapper/configs/{root,home}
sudo sed -i 's/^NUMBER_LIMIT_IMPORTANT="10"/NUMBER_LIMIT_IMPORTANT="5"/' /etc/snapper/configs/{root,home}
sudo sed -i 's/^SPACE_LIMIT="0.5"/SPACE_LIMIT="0.3"/' /etc/snapper/configs/{root,home}
sudo sed -i 's/^FREE_LIMIT="0.2"/FREE_LIMIT="0.3"/' /etc/snapper/configs/{root,home}

# Blacklist hardware watchdog modules (desktop, not needed)
step "Blacklisting hardware watchdog modules"
sudo mkdir -p /etc/modprobe.d
sudo cp "$BUNNY_INSTALL_DEFAULTS_PATH/modprobe/nowatchdog.conf" /etc/modprobe.d/nowatchdog.conf

step "Configuring the Plymouth theme"
plymouth_theme_dir=/usr/share/plymouth/themes/bunny
if sudo test -d "$plymouth_theme_dir/plymouth"; then
  run_logged "Removing nested Plymouth theme directory" \
    sudo rm -rf "$plymouth_theme_dir/plymouth"
fi
run_logged "Creating Plymouth theme directory" \
  sudo install -d "$plymouth_theme_dir"
run_logged "Copying Plymouth theme contents" \
  sudo cp -a "$BUNNY_INSTALL_DEFAULTS_PATH/plymouth/." "$plymouth_theme_dir/"

if [[ "$(plymouth-set-default-theme)" != "bunny" ]]; then
  run_logged "Setting default theme" \
    sudo plymouth-set-default-theme bunny
fi
success "Plymouth theme configuration is set"

# Disable default mkinitcpio UKI generation
step "Disabling the default mkinitcpio UKI preset"
preset="/etc/mkinitcpio.d/linux.preset"
if [[ -f "$preset" ]] && grep -q '^default_uki=' "$preset"; then
  sudo sed -i 's/^default_uki=/#default_uki=/' "$preset"
  sudo sed -i 's/^fallback_uki=/#fallback_uki=/' "$preset"
  sudo sed -i 's/^default_options=/#default_options=/' "$preset"
  success "Disabled default UKI in mkinitcpio preset"
fi

expected_uki=/boot/EFI/Linux/bunny_linux.efi
limine_output=$(mktemp)
# shellcheck disable=SC2016 # $1 expands inside the child shell.
if run_logged "Running authoritative final Limine generation" \
  bash -o pipefail -c 'sudo limine-update 2>&1 | tee "$1"' _ "$limine_output"; then
  :
else
  rm -f "$limine_output"
  restore_last_known_limine_configuration
  error "Restored the last known-working Limine configuration"
  return 1
fi

if ! grep -Fq 'Unified kernel image generation successful' "$limine_output"; then
  rm -f "$limine_output"
  restore_last_known_limine_configuration
  error "Final Limine generation did not report a successful UKI build; restored the last known-working configuration"
  return 1
fi
rm -f "$limine_output"

step "Validating final Limine and UKI artifacts"
if ! sudo test -s /boot/limine.conf; then
  restore_last_known_limine_configuration
  error "Final Limine configuration is missing or empty; restored the last known-working configuration"
  return 1
fi
if ! sudo grep -Fq 'bunny_linux.efi' /boot/limine.conf; then
  restore_last_known_limine_configuration
  error "Final Limine configuration does not reference the expected UKI; restored the last known-working configuration"
  return 1
fi
if ! sudo test -s "$expected_uki"; then
  restore_last_known_limine_configuration
  error "Expected UKI is missing or empty: $expected_uki; restored the last known-working configuration"
  return 1
fi
initramfs_listing=$(sudo lsinitcpio -l "$expected_uki")
for required_command in cryptsetup plymouth btrfs; do
  if ! grep -Eq "(^|/)${required_command}$" <<< "$initramfs_listing"; then
    restore_last_known_limine_configuration
    error "Final UKI does not contain: $required_command; restored the last known-working configuration"
    return 1
  fi
done

if [[ -f /etc/mkinitcpio.conf.d/nvidia.conf ]]; then
  for required_module in nvidia nvidia_modeset nvidia_uvm nvidia_drm; do
    if ! grep -Eq "(^|/)${required_module}(\\.ko(\\.[a-z0-9]+)?)?$" <<< "$initramfs_listing"; then
      restore_last_known_limine_configuration
      error "Final UKI does not contain NVIDIA module: $required_module; restored the last known-working configuration"
      return 1
    fi
  done
fi
# Build the committed config from the managed presentation settings and the
# entries generated by limine-update. Entries that reference default-preset
# UKIs are omitted before those artifacts are removed.
staged_limine_config=$(mktemp)
cp "$BUNNY_INSTALL_DEFAULTS_PATH/limine/limine.conf" "$staged_limine_config"
if ! sudo awk '
  function flush_entry() {
    if (entry != "" && entry !~ /\/EFI\/Linux\/arch-linux(-fallback)?\.efi/) {
      printf "%s", entry
    }
    entry = ""
  }
  /^\// {
    flush_entry()
    entry = $0 ORS
    next
  }
  entry != "" { entry = entry $0 ORS }
  END { flush_entry() }
' /boot/limine.conf | tee -a "$staged_limine_config" >/dev/null; then
  rm -f "$staged_limine_config"
  restore_last_known_limine_configuration
  error "Failed to stage generated Limine entries; restored the last known-working configuration"
  return 1
fi
if ! grep -Fq 'bunny_linux.efi' "$staged_limine_config" ||
   grep -Eq '/EFI/Linux/arch-linux(-fallback)?\.efi' "$staged_limine_config"; then
  rm -f "$staged_limine_config"
  restore_last_known_limine_configuration
  error "Staged Limine configuration is invalid; restored the last known-working configuration"
  return 1
fi
sudo install -m 644 "$staged_limine_config" /boot/limine.conf.bunnyfiles-new
sudo mv /boot/limine.conf.bunnyfiles-new /boot/limine.conf
rm -f "$staged_limine_config"
success "Final Limine configuration and UKI validated"

# The validated generation is now the last known-working configuration. Only
# after this promotion is it safe to remove UKIs referenced by the prior config.
sudo cp /boot/limine.conf "${last_known_limine_config}.bunny-new"
sudo mv "${last_known_limine_config}.bunny-new" "$last_known_limine_config"
if ! sudo test -s "$last_known_limine_config"; then
  error "Last known-working Limine configuration is missing or empty"
  return 1
fi

step "Cleaning stale UKIs"
for stale in /boot/EFI/Linux/arch-linux.efi /boot/EFI/Linux/arch-linux-fallback.efi; do
  if sudo test -f "$stale"; then
    run_logged "Removing stale UKI: $stale" \
      sudo rm "$stale"
  fi
done
success "Generated Limine configuration committed"

remove_pacman_generation_override

