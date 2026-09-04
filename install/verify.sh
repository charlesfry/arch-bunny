#!/usr/bin/env bash

set -uo pipefail

pass_count=0
fail_count=0
skip_count=0

usage() {
  cat <<'EOF'
Usage: install/verify.sh

Run read-only checks against an installed dotfiles system. Run this as the
normal installation user. Some boot and firewall checks request sudo access.
EOF
}

pass() {
  printf 'PASS %s\n' "$1"
  ((pass_count += 1))
}

fail() {
  printf 'FAIL %s\n' "$1"
  if [[ -n ${2:-} ]]; then
    printf '     %s\n' "$2"
  fi
  ((fail_count += 1))
}

skip() {
  printf 'SKIP %s\n' "$1"
  ((skip_count += 1))
}

check_command() {
  local description=$1
  shift

  if "$@" >/dev/null 2>&1; then
    pass "$description"
  else
    fail "$description" "command: $(printf '%q ' "$@")"
  fi
}

count_argument() {
  local argument=$1
  local command_line=$2

  awk -v expected="$argument" '
    {
      count = 0
      for (field = 1; field <= NF; field++) {
        if ($field == expected) {
          count++
        }
      }
      print count
    }
  ' <<< "$command_line"
}

check_argument_once() {
  local argument=$1
  local command_line=$2
  local count
  count=$(count_argument "$argument" "$command_line")

  if [[ $count == 1 ]]; then
    pass "kernel argument occurs once: $argument"
  else
    fail "kernel argument occurs once: $argument" "observed count: $count"
  fi
}

check_enabled_system_service() {
  local service=$1
  check_command "system service is enabled: $service" systemctl is-enabled --quiet "$service"
}

check_enabled_user_service() {
  local service=$1
  check_command "user service is enabled: $service" systemctl --user is-enabled --quiet "$service"
}

check_package_hook_integrity() {
  local package=$1
  local path_pattern=$2
  local output altered

  output=$(pacman -Qkk "$package" 2>&1 || true)
  altered=$(grep -E "$path_pattern" <<< "$output" || true)
  if [[ -z $altered ]]; then
    pass "$package owns no altered generation hooks"
  else
    fail "$package owns no altered generation hooks" "$altered"
  fi
}

limine_hook_has_expected_owner() {
  [[ $(pacman -Qqo /etc/pacman.d/hooks/90-mkinitcpio-install.hook) == limine-mkinitcpio-hook ]]
}

limine_config_has_no_stale_uki_entries() {
  ! sudo grep -Eq '/EFI/Linux/arch-linux(-fallback)?\.efi' /boot/limine.conf
}

alternate_limine_configs_removed() {
  local candidate

  for candidate in \
    /boot/EFI/arch-limine/limine.conf \
    /boot/EFI/BOOT/limine.conf \
    /boot/EFI/limine/limine.conf \
    /boot/limine/limine.conf; do
    sudo test ! -e "$candidate" || return 1
  done
}

root_is_encrypted_btrfs() {
  [[ $(findmnt -n -o FSTYPE /) == btrfs && $(findmnt -n -o SOURCE /) == /dev/mapper/* ]]
}

# Not "does a subvolume by that name exist" but "is it the one mounted here" —
# read through the mount options, which needs no root.
subvolume_mounted() {
  [[ $(findmnt -no OPTIONS "$2" 2>/dev/null || true) == *"subvol=/$1"* ]]
}

plymouth_bunny_theme_is_selected() {
  [[ $(plymouth-set-default-theme) == bunny ]]
}

resolved_owns_resolv_conf() {
  [[ -L /etc/resolv.conf && $(readlink /etc/resolv.conf) == *stub-resolv* ]]
}

mime_default_is() {
  local mime_type=$1
  local desktop_id=$2
  [[ $(xdg-mime query default "$mime_type") == "$desktop_id" ]]
}

gtk_settings_are_declarative() {
  local settings_file=$1

  grep -Fxq 'gtk-theme-name=Adwaita-dark' "$settings_file" &&
    ! grep -q '^gtk-icon-theme-name=' "$settings_file" &&
    grep -Fxq 'gtk-application-prefer-dark-theme=true' "$settings_file"
}

desktop_defaults_are_stowed() {
  [[ -L $HOME/.config/mimeapps.list &&
    -L $HOME/.config/gtk-3.0/settings.ini &&
    -L $HOME/.config/gtk-4.0/settings.ini ]]
}

default_user_directories_exist() {
  [[ -d $HOME/notes && -d $HOME/projects && -d $HOME/work ]]
}

pacman_original_backup_is_valid() {
  local backup=/etc/pacman.conf.bunny-original
  local checksum=$backup.sha256
  local expected actual

  [[ -f $backup && -f $checksum ]] || return 1
  expected=$(sudo cat "$checksum" | tr -d '[:space:]')
  actual=$(sudo sha256sum "$backup" | awk '{print $1}')
  [[ -n $expected && $expected == "$actual" ]]
}

main() {
  if (($#)); then
    case $1 in
      -h|--help)
        usage
        return 0
        ;;
      *)
        printf 'Unknown argument: %s\n' "$1" >&2
        usage >&2
        return 2
        ;;
    esac
  fi

  if ((EUID == 0)); then
    printf 'Verification must run as the normal installation user, not root.\n' >&2
    return 2
  fi

  local script_dir repo_root package_file aur_package_file repository repositories command_line
  local package missing_packages failed_units root_owned initramfs_listing ufw_status session_errors
  local omarchy_siglevel policy
  local uki=/boot/EFI/Linux/bunny_linux.efi

  script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  repo_root=$(cd -- "$script_dir/.." && pwd)
  package_file=$script_dir/packages
  aur_package_file=$script_dir/packages-yay

  printf 'Dotfiles installation verification\n'
  printf 'Date: %s\n' "$(date --iso-8601=seconds)"
  printf 'Host: %s\n' "$(uname -n)"
  printf 'User: %s uid=%s home=%s\n' "$(id -un)" "$(id -u)" "$HOME"
  printf 'Repository: %s\n' "$repo_root"
  if command -v git >/dev/null 2>&1 && git -C "$repo_root" rev-parse HEAD >/dev/null 2>&1; then
    printf 'Revision: %s\n' "$(git -C "$repo_root" rev-parse HEAD)"
  fi
  printf '\n'

  for command in pacman pacman-conf systemctl findmnt lsinitcpio plymouth-set-default-theme; do
    if command -v "$command" >/dev/null 2>&1; then
      pass "required verification command is available: $command"
    else
      fail "required verification command is available: $command"
    fi
  done

  if sudo -v; then
    pass "sudo access is available"
  else
    fail "sudo access is available"
    printf '\nSUMMARY pass=%d fail=%d skip=%d\n' "$pass_count" "$fail_count" "$skip_count"
    return 1
  fi

  if [[ -f $package_file && -f $aur_package_file ]]; then
    missing_packages=()
    while IFS= read -r package; do
      [[ -n $package && $package != \#* ]] || continue
      if ! pacman -Q "$package" >/dev/null 2>&1; then
        missing_packages+=("$package")
      fi
    done < <(cat "$package_file" "$aur_package_file")

    if ((${#missing_packages[@]} == 0)); then
      pass "all required packages are installed"
    else
      fail "all required packages are installed" "missing: ${missing_packages[*]}"
    fi
  else
    fail "required package lists exist" "$package_file $aur_package_file"
  fi

  repositories=$(pacman-conf --repo-list 2>/dev/null || true)
  for repository in core extra multilib omarchy; do
    local repository_count
    repository_count=$(grep -cx "$repository" <<< "$repositories" || true)
    if [[ $repository_count == 1 ]]; then
      pass "repository is configured once: $repository"
    else
      fail "repository is configured once: $repository" "observed count: $repository_count"
    fi
  done

  check_command \
    "managed repository fragment is installed" \
    cmp -s "$script_dir/default/pacman/bunny-repositories.conf" \
    /etc/pacman.d/bunny-repositories.conf
  if [[ $(grep -Fxc 'Include = /etc/pacman.d/bunny-repositories.conf' /etc/pacman.conf) == 1 ]]; then
    pass "managed repository fragment is included once"
  else
    fail "managed repository fragment is included once"
  fi
  check_command "original pacman configuration backup is valid" pacman_original_backup_is_valid

  if [[ $(pacman-conf --repo omarchy Server 2>/dev/null) == "https://pkgs.omarchy.org/stable/$(uname -m)" ]]; then
    pass "Omarchy repository uses the expected server"
  else
    fail "Omarchy repository uses the expected server"
  fi
  omarchy_siglevel=$(pacman-conf --repo omarchy SigLevel 2>/dev/null || true)
  for policy in PackageOptional PackageTrustAll DatabaseOptional DatabaseTrustAll; do
    if grep -qx "$policy" <<< "$omarchy_siglevel"; then
      pass "Omarchy signature policy includes: $policy"
    else
      fail "Omarchy signature policy includes: $policy"
    fi
  done

  check_package_hook_integrity \
    mkinitcpio \
    '/usr/share/libalpm/hooks/(60-mkinitcpio-remove|90-mkinitcpio-install)\.hook'
  check_package_hook_integrity \
    limine-mkinitcpio-hook \
    '/etc/pacman\.d/hooks/90-mkinitcpio-install\.hook'
  check_command \
    "Limine pacman hook has the expected owner" \
    limine_hook_has_expected_owner
  check_command \
    "private pacman hook override was removed" \
    sudo test ! -e "/run/bunny-install/$(id -u)/pacman-hooks"

  check_command "root uses encrypted Btrfs" root_is_encrypted_btrfs
  check_command "/var/lib/docker is on @dockervol" \
    subvolume_mounted @dockervol /var/lib/docker
  check_command "/var/lib/containerd is on @containerd" \
    subvolume_mounted @containerd /var/lib/containerd
  check_command "system booted in EFI mode" test -d /sys/firmware/efi
  check_command "expected UKI exists and is nonempty" sudo test -s "$uki"
  check_command "Limine configuration exists and is nonempty" sudo test -s /boot/limine.conf
  check_command "Limine configuration references the expected UKI" \
    sudo grep -Fq 'bunny_linux.efi' /boot/limine.conf
  check_command "Limine configuration contains no stale default-preset UKI entries" \
    limine_config_has_no_stale_uki_entries
  check_command "last known-working Limine configuration is retained" \
    sudo test -s /boot/limine.conf.bunny-last-known-good
  check_command "alternate Limine configurations were removed" \
    alternate_limine_configs_removed
  if sudo test -s "$uki"; then
    printf 'UKI SHA256: %s\n' "$(sudo sha256sum "$uki" | awk '{print $1}')"
  fi
  if sudo test -s /boot/limine.conf; then
    printf 'Limine config SHA256: %s\n' "$(sudo sha256sum /boot/limine.conf | awk '{print $1}')"
  fi
  if sudo test -s /boot/limine.conf.bunny-last-known-good; then
    printf 'Last known-working Limine config SHA256: %s\n' \
      "$(sudo sha256sum /boot/limine.conf.bunny-last-known-good | awk '{print $1}')"
  fi
  printf 'mkinitcpio hook SHA256: %s\n' \
    "$(sha256sum /etc/mkinitcpio.conf.d/bunny_hooks.conf 2>/dev/null | awk '{print $1}')"

  command_line=$(< /proc/cmdline)
  printf 'Kernel command line: %s\n' "$command_line"
  for argument in quiet splash nowatchdog plymouth.ignore-serial-consoles; do
    check_argument_once "$argument" "$command_line"
  done

  check_command "mkinitcpio hook configuration includes Plymouth and encryption" \
    grep -Eq '^HOOKS=.*plymouth.*encrypt' /etc/mkinitcpio.conf.d/bunny_hooks.conf
  check_command "Plymouth bunny theme is selected" plymouth_bunny_theme_is_selected
  check_command "Plymouth theme descriptor exists" \
    sudo test -s /usr/share/plymouth/themes/bunny/bunny.plymouth
  check_command "Plymouth theme has no nested duplicate" \
    sudo test ! -d /usr/share/plymouth/themes/bunny/plymouth

  initramfs_listing=$(sudo lsinitcpio -l "$uki" 2>/dev/null || true)
  for command in cryptsetup plymouth btrfs; do
    if grep -Eq "(^|/)${command}$" <<< "$initramfs_listing"; then
      pass "UKI initramfs contains: $command"
    else
      fail "UKI initramfs contains: $command"
    fi
  done

  for service in \
    bluetooth.service \
    systemd-networkd.service \
    iwd.service \
    systemd-resolved.service \
    limine-snapper-sync.service \
    greetd.service \
    power-profiles-daemon.service \
    ufw.service; do
    check_enabled_system_service "$service"
  done

  check_command "terminal MIME handler uses the installed desktop ID" \
    mime_default_is x-scheme-handler/terminal kitty.desktop
  check_command "directory MIME handler uses the installed desktop ID" \
    mime_default_is inode/directory org.gnome.Nautilus.desktop
  check_command "browser MIME handler is declarative" \
    mime_default_is x-scheme-handler/https firefox.desktop
  check_command "text MIME handler is declarative" \
    mime_default_is text/plain nvim.desktop
  check_command "GTK 3 appearance is declarative" \
    gtk_settings_are_declarative "$HOME/.config/gtk-3.0/settings.ini"
  check_command "GTK 4 appearance is declarative" \
    gtk_settings_are_declarative "$HOME/.config/gtk-4.0/settings.ini"
  check_command "desktop defaults are stowed from tracked configuration" \
    desktop_defaults_are_stowed

  for service in waybar.service mako.service swaybg.service swayidle.service swayosd.service; do
    check_enabled_user_service "$service"
  done
  check_command "default user directories use the expected names" \
    default_user_directories_exist

  check_command "user manager is reachable" systemctl --user show-environment

  failed_units=$(systemctl --failed --no-legend --plain 2>/dev/null || true)
  if [[ -z $failed_units ]]; then
    pass "no failed system units"
  else
    fail "no failed system units" "$failed_units"
  fi

  failed_units=$(systemctl --user --failed --no-legend --plain 2>/dev/null || true)
  if [[ -z $failed_units ]]; then
    pass "no failed user units"
  else
    fail "no failed user units" "$failed_units"
  fi

  session_errors=$(journalctl --user -b --no-pager 2>/dev/null \
    | grep -E 'failed to initialize renderer|no allocator available' \
    || true)
  if [[ -z $session_errors ]]; then
    pass "graphical session has no known renderer errors"
  else
    fail "graphical session has no known renderer errors" "$session_errors"
  fi

  check_command "systemd-resolved owns resolv.conf" resolved_owns_resolv_conf
  check_command "DNS resolution works" getent ahosts archlinux.org
  ufw_status=$(sudo ufw status 2>/dev/null || true)
  if grep -Fqx 'Status: active' <<< "$ufw_status"; then
    pass "UFW is active"
  else
    fail "UFW is active"
  fi

  if [[ -f /etc/bunny-test-vm ]]; then
    if sudo ufw status | grep -Fq allow-bunny-test-host-ssh; then
      pass "test VM SSH firewall exception exists"
    else
      fail "test VM SSH firewall exception exists"
    fi
  else
    skip "test VM SSH firewall exception (not a marked test VM)"
  fi

  local -a ownership_roots=()
  for repository in "$HOME/.config" "$HOME/.cache" "$HOME/.local"; do
    [[ -e $repository ]] && ownership_roots+=("$repository")
  done
  root_owned=""
  if ((${#ownership_roots[@]})); then
    root_owned=$(find "${ownership_roots[@]}" -xdev -uid 0 -print -quit 2>/dev/null || true)
  fi
  if [[ -z $root_owned ]]; then
    pass "managed user directories contain no root-owned files"
  else
    fail "managed user directories contain no root-owned files" "$root_owned"
  fi

  printf '\nSUMMARY pass=%d fail=%d skip=%d\n' "$pass_count" "$fail_count" "$skip_count"
  ((fail_count == 0))
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
