#!/bin/bash
# Phase 60: Docker, with its bytes on their own top-level btrfs subvolumes so
# image layers, containers and volumes never land inside a snapper snapshot of @.

log "Configuring Docker storage..."

DOCKER_SYSCTL_SOURCE="$BUNNY_INSTALL_DEFAULTS_PATH/sysctl/99-docker.conf"
DOCKER_SYSCTL_TARGET=/etc/sysctl.d/99-docker.conf
DOCKER_PACKAGES=(docker docker-buildx docker-compose ufw-docker)

readonly DOCKER_SUBVOLS=(
  '@containerd:/var/lib/containerd:0700'
  '@dockervol:/var/lib/docker:0710'
)

if [[ ! -f $DOCKER_SYSCTL_SOURCE ]]; then
  error "Docker sysctl configuration not found: $DOCKER_SYSCTL_SOURCE"
  return 1 # phases are sourced, not executed, so `return` (not `exit`) reports failure.
fi

root_uuid=$(findmnt -no UUID /)
if [[ -z $root_uuid ]]; then
  error "Cannot read the UUID of / — is this the btrfs machine preflight checked?"
  return 1
fi

btrfs_top=
cleanup_btrfs_top() {
  if [[ -n $btrfs_top ]]; then
    if mountpoint -q "$btrfs_top"; then sudo umount "$btrfs_top"; fi
    sudo rmdir "$btrfs_top"
    btrfs_top=
  fi
}

mount_btrfs_top() {
  if [[ -n $btrfs_top ]]; then return 0; fi
  btrfs_top=$(sudo mktemp -d /run/bunny-btrfs-top.XXXXXX)
  sudo mount -o subvolid=5 "UUID=$root_uuid" "$btrfs_top"
}

subvol_mounted() {
  [[ $(findmnt -no OPTIONS "$2" 2>/dev/null || true) == *"subvol=/$1"* ]]
}

for entry in "${DOCKER_SUBVOLS[@]}"; do
  IFS=: read -r subvol dir _ <<< "$entry"
  if subvol_mounted "$subvol" "$dir"; then continue; fi
  if [[ -d $dir ]] && sudo find "$dir" -mindepth 1 -print -quit | grep -q .; then
    error "$dir already holds data and is not mounted from $subvol"
    error "Mounting over it would hide those bytes, not move them. Migrate first."
    return 1
  fi
done

for entry in "${DOCKER_SUBVOLS[@]}"; do
  IFS=: read -r subvol dir mode <<< "$entry"

  if subvol_mounted "$subvol" "$dir"; then
    info "$dir is on $subvol"
  else
    mount_btrfs_top
    if [[ -d "$btrfs_top/$subvol" ]]; then
      info "Subvolume $subvol exists"
    else
      run_logged "Creating subvolume $subvol" \
        sudo btrfs subvolume create "$btrfs_top/$subvol"
    fi

    sudo mkdir -p -- "$dir" # just the mountpoint; the mount hides its mode.

    if ! grep -q "subvol=/$subvol\b" /etc/fstab; then
      printf '\n# arch-bunny: %s out of @, so image layers stay out of root snapshots\nUUID=%s\t%s\tbtrfs\trw,noatime,subvol=/%s\t0 0\n' \
        "$dir" "$root_uuid" "$dir" "$subvol" | sudo tee -a /etc/fstab >/dev/null
      success "fstab: $dir -> $subvol"
    fi

    sudo systemctl daemon-reload
    run_logged "Mounting $dir" sudo mount "$dir"
  fi

  if [[ $(stat -c %a "$dir") != "${mode#0}" ]]; then
    run_logged "Setting mode $mode on $dir" sudo chmod "$mode" "$dir"
  fi
done
cleanup_btrfs_top

run_logged "Installing Docker packages: ${DOCKER_PACKAGES[*]}" \
  sudo pacman -S --needed --noconfirm "${DOCKER_PACKAGES[@]}"

run_logged "Installing the Docker sysctl configuration" \
  sudo install -Dm644 "$DOCKER_SYSCTL_SOURCE" "$DOCKER_SYSCTL_TARGET"
run_logged "Applying the Docker sysctl configuration" \
  sudo sysctl --load "$DOCKER_SYSCTL_TARGET"

if id -nG "$BUNNY_DEFAULT_USER" | grep -qw docker; then
  info "$BUNNY_DEFAULT_USER is in the docker group"
else
  run_logged "Adding $BUNNY_DEFAULT_USER to the docker group" \
    sudo usermod -aG docker "$BUNNY_DEFAULT_USER"
  warn "docker group membership is root-equivalent and takes effect at the next login"
fi

if ! sudo ufw status | grep -Fq 'allow-docker-dns'; then
  run_logged "Allowing container DNS through the firewall" \
    sudo ufw allow in proto udp from 172.16.0.0/12 to 172.17.0.1 port 53 \
    comment 'allow-docker-dns'
fi
run_logged "Installing the ufw-docker rules" sudo ufw-docker install
run_logged "Reloading the firewall" sudo ufw reload

if systemctl is-enabled --quiet docker.socket 2>/dev/null; then
  info "docker.socket is already enabled"
else
  run_logged "Enabling docker.socket" sudo systemctl enable --now docker.socket
fi

for entry in "${DOCKER_SUBVOLS[@]}"; do
  IFS=: read -r subvol dir _ <<< "$entry"
  if ! subvol_mounted "$subvol" "$dir"; then
    error "$dir is not mounted from $subvol after configuration"
    return 1
  fi
done
success "Docker storage on its own subvolumes, outside root snapshots"
