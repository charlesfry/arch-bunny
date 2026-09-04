#!/usr/bin/env bats
# shellcheck disable=SC2016 # tests intentionally match literal shell expressions

create_installer_fixture() {
  local fixture=$1
  mkdir -p "$fixture/install/lib" "$fixture/home"
  cp "$installer_script" "$fixture/install.sh"
  cp "$repo_root/install/lib/helpers.sh" "$fixture/install/lib/helpers.sh"
  for phase in \
    00-preflight.sh 10-packages.sh 11-nvidia.sh 12-greetd.sh \
    13-bootloader.sh 20-dotfiles.sh 30-system-services.sh 40-user-setup.sh \
    50-firewall.sh; do
    printf '#!/usr/bin/env bash\n' > "$fixture/install/$phase"
  done
}

setup() {
  repo_root=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  installer_script=$repo_root/install.sh
  verifier_script=$repo_root/install/verify.sh
  bootloader_script=$repo_root/install/13-bootloader.sh
  limine_defaults=$repo_root/install/default/limine/default.conf
  greetd_script=$repo_root/install/12-greetd.sh
  systemd_script=$repo_root/install/30-system-services.sh
  packages_file=$repo_root/install/packages
  pacman_script=$repo_root/install/10-packages.sh
  pacman_fragment=$repo_root/install/default/pacman/bunny-repositories.conf
  app_launcher=$repo_root/local/bin/bunny-menu-apps
  application_overrides=$repo_root/install/default/applications
  user_setup_script=$repo_root/install/40-user-setup.sh
  swayosd_style=$repo_root/config/swayosd/style.css
}

@test "installer rejects root before creating installation state" {
  run grep -F 'if ((EUID == 0)); then' "$installer_script"
  [ "$status" -eq 0 ]

  root_guard_line=$(grep -n -F 'if ((EUID == 0)); then' "$installer_script" | cut -d: -f1)
  log_setup_line=$(grep -n -F 'mkdir -p "$(dirname "$BUNNY_INSTALL_LOG_FILE")"' "$installer_script" | cut -d: -f1)
  [ "$root_guard_line" -lt "$log_setup_line" ]
}

@test "preflight establishes one normal-user context" {
  preflight=$repo_root/install/00-preflight.sh

  grep -Fq 'BUNNY_DEFAULT_UID=$(id -u)' "$preflight"
  grep -Fq 'BUNNY_DEFAULT_USER=$(id -un)' "$preflight"
  grep -Fq 'expected_runtime_dir="/run/user/$BUNNY_DEFAULT_UID"' "$preflight"
  grep -Fq 'systemctl --user show-environment' "$preflight"
  grep -Fq 'export BUNNY_USER_HOME="$passwd_home"' "$preflight"
  grep -Fq 'readonly BUNNY_DEFAULT_USER BUNNY_DEFAULT_UID BUNNY_USER_HOME' \
    "$installer_script"
  [ ! -e "$repo_root/install/11-user.sh" ]

  run grep -R -E 'sudo (-u [^ ]+ )?systemctl --user' "$repo_root/install"
  [ "$status" -eq 1 ]
}

@test "Stow uses explicit validated home targets" {
  dotfiles_script=$repo_root/install/20-dotfiles.sh

  grep -Fq 'stow -t "$HOME" home' "$dotfiles_script"
  grep -Fq 'stow --no-folding -t "$HOME/.config" config' "$dotfiles_script"
  grep -Fq 'stow --no-folding -t "$HOME/.local" local' "$dotfiles_script"
  grep -Fq 'if [[ -f $path && ! -L $path ]]; then' "$dotfiles_script"
  grep -Fq 'verify_user_ownership' "$dotfiles_script"
}

@test "installer records phase context and command failures" {
  # shellcheck disable=SC2016 # matching a literal shell expression
  run grep -F 'export BUNNY_CURRENT_PHASE="$1"' "$installer_script"
  [ "$status" -eq 0 ]

  run grep -F 'Installation failed: run=' "$installer_script"
  [ "$status" -eq 0 ]

  run grep -F 'BUNNY_INSTALL_TRACE_FILE' "$installer_script"
  [ "$status" -eq 0 ]
}

@test "diagnostic logging preserves arguments and streamed input without terminal noise" {
  log_file=$BATS_TEST_TMPDIR/helpers.log

  # shellcheck disable=SC2016 # positional arguments expand in the child shell
  run env BUNNY_INSTALL_LOG_FILE="$log_file" bash -c \
    'source "$1"; log "argument message" </dev/null; printf "%s\\n" "streamed message" | log' \
    _ "$repo_root/install/lib/helpers.sh"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -Fq '[INFO   ] argument message' "$log_file"
  grep -Fq '[INFO   ] streamed message' "$log_file"
}

@test "non-TTY status output is line-oriented and unstyled" {
  log_file=$BATS_TEST_TMPDIR/status.log

  # shellcheck disable=SC2016 # positional arguments expand in the child shell
  run env BUNNY_INSTALL_LOG_FILE="$log_file" bash -c '
    source "$1"
    section_start "Packages"
    step "Synchronizing databases"
    section_complete
  ' _ "$repo_root/install/lib/helpers.sh"

  [ "$status" -eq 0 ]
  [ "$output" = $'START Packages\nSTEP  Synchronizing databases\nDONE  Packages' ]
  [[ $output != *$'\033['* ]]
}

@test "TTY status output uses the configured circle markers and colors" {
  log_file=$BATS_TEST_TMPDIR/tty-status.log
  status_script=$BATS_TEST_TMPDIR/tty-status.sh
  cat > "$status_script" <<EOF
#!/usr/bin/env bash
BUNNY_INSTALL_LOG_FILE=$log_file
source "$repo_root/install/lib/helpers.sh"
section_start "Packages"
step "Synchronizing databases"
section_note "No optional hardware detected; skipped"
section_complete
section_start "Bootloader"
BUNNY_LAST_ERROR="Generation failed"
section_failed 1 "limine-update"
EOF
  chmod +x "$status_script"

  run env TERM=xterm script -qefc "$status_script" /dev/null

  [ "$status" -eq 0 ]
  [[ $output == *$'\033[0;94m○ Packages'* ]]
  [[ $output == *$'\033[0;90m  ○ Synchronizing databases'* ]]
  [[ $output == *$'\033[0;32m• Packages'* ]]
  [[ $output == *$'\033[0;90m  └─ No optional hardware detected; skipped'* ]]
  [[ $output == *$'\033[0;31m• Bootloader'* ]]
}

@test "long-running commands update the TTY ticker with elapsed time" {
  log_file=$BATS_TEST_TMPDIR/elapsed-status.log
  status_script=$BATS_TEST_TMPDIR/elapsed-status.sh
  cat > "$status_script" <<EOF
#!/usr/bin/env bash
BUNNY_INSTALL_LOG_FILE=$log_file
source "$repo_root/install/lib/helpers.sh"
section_start "Packages"
run_logged "Downloading packages" sleep 2
section_complete
EOF
  chmod +x "$status_script"

  run env TERM=xterm script -qefc "$status_script" /dev/null

  [ "$status" -eq 0 ]
  [[ $output == *"○ Downloading packages (1s)"* ]]
  [[ $output == *$'\033[0;32m• Packages'* ]]
}

@test "NO_COLOR keeps TTY markers but removes escape sequences" {
  log_file=$BATS_TEST_TMPDIR/no-color.log
  status_script=$BATS_TEST_TMPDIR/no-color.sh
  cat > "$status_script" <<EOF
#!/usr/bin/env bash
BUNNY_INSTALL_LOG_FILE=$log_file
source "$repo_root/install/lib/helpers.sh"
section_start "Packages"
step "Synchronizing databases"
section_complete
EOF
  chmod +x "$status_script"

  run env TERM=xterm NO_COLOR=1 script -qefc "$status_script" /dev/null

  [ "$status" -eq 0 ]
  [[ $output == *"○ Packages"* ]]
  [[ $output == *"  ○ Synchronizing databases"* ]]
  [[ $output == *"• Packages"* ]]
  [[ $output != *$'\033[0;94m'* ]]
  [[ $output != *$'\033[0;90m'* ]]
  [[ $output != *$'\033[0;32m'* ]]
}

@test "failed command output is logged while only its error is presented" {
  log_file=$BATS_TEST_TMPDIR/command.log
  failing_command=$BATS_TEST_TMPDIR/failing-command
  cat > "$failing_command" <<'EOF'
#!/usr/bin/env bash
printf 'routine package output\n'
printf 'database failure\n' >&2
exit 42
EOF
  chmod +x "$failing_command"

  # shellcheck disable=SC2016 # positional arguments expand in the child shell
  run env BUNNY_INSTALL_LOG_FILE="$log_file" bash -c '
    source "$1"
    section_start "Packages"
    run_logged "Updating packages" "$2" || {
      command_status=$?
      section_failed "$command_status" "$BUNNY_LAST_FAILED_COMMAND"
      exit "$command_status"
    }
  ' _ "$repo_root/install/lib/helpers.sh" "$failing_command"

  [ "$status" -eq 42 ]
  [[ $output != *"routine package output"* ]]
  [[ $output == *"database failure"* ]]
  grep -Fq 'routine package output' "$log_file"
  grep -Fq 'database failure' "$log_file"
  run grep -P $'\033\\[' "$log_file"
  [ "$status" -eq 1 ]
}

@test "installer failure log identifies the phase and failed command" {
  fixture=$BATS_TEST_TMPDIR/installer-fixture
  create_installer_fixture "$fixture"
  printf '#!/usr/bin/env bash\nfalse\n' > "$fixture/install/10-packages.sh"

  # shellcheck disable=SC2016 # positional arguments expand in the child shell
  run env HOME="$fixture/home" bash -c 'cd "$1" && bash install.sh' _ "$fixture"

  [ "$status" -ne 0 ]
  log_file=$fixture/home/.local/state/arch-bunny/install.log
  grep -Fq 'phase=10-packages.sh status=1' "$log_file"
  grep -Fq 'command=false' "$log_file"
  trace_file=$(find "$fixture/home/.local/state/arch-bunny" -name 'install.log.*.trace' -print -quit)
  [ -n "$trace_file" ]
  [ -s "$trace_file" ]
}

@test "verification counts exact kernel arguments" {
  run bash -c 'source "$1"; count_argument quiet "quiet splash quiet quietness"' _ "$verifier_script"
  [ "$status" -eq 0 ]
  [ "$output" = 2 ]
}

@test "verification help does not inspect the system" {
  run "$verifier_script" --help
  [ "$status" -eq 0 ]
  [[ $output == *"read-only checks"* ]]
}

@test "bootloader probes root-only ESP files through sudo" {
  # shellcheck disable=SC2016 # matching a literal shell expression
  run grep -F 'sudo test -f "$candidate"' "$bootloader_script"
  [ "$status" -eq 0 ]

  # shellcheck disable=SC2016 # matching a literal shell expression
  run grep -F 'CMDLINE=$(sudo grep' "$bootloader_script"
  [ "$status" -eq 0 ]

  # shellcheck disable=SC2016 # matching a literal shell expression
  run grep -E '\[\[ -f ("?/boot|"?\$limine_config)' "$bootloader_script"
  [ "$status" -eq 1 ]
}

@test "managed kernel arguments support Plymouth on serial-console VMs" {
  run grep -F 'quiet splash nowatchdog plymouth.ignore-serial-consoles' "$limine_defaults"
  [ "$status" -eq 0 ]

  run grep -F 'for managed_arg in quiet splash nowatchdog plymouth.ignore-serial-consoles' "$bootloader_script"
  [ "$status" -eq 0 ]
}

@test "Limine generation preserves a valid config and restores it on failure" {
  backup_line=$(grep -n 'Last known-working Limine configuration retained' "$bootloader_script" | cut -d: -f1)
  generation_line=$(grep -n 'Running authoritative final Limine generation' "$bootloader_script" | cut -d: -f1)
  validation_line=$(grep -n 'Final Limine configuration and UKI validated' "$bootloader_script" | cut -d: -f1)
  cleanup_line=$(grep -n 'Cleaning stale UKIs' "$bootloader_script" | cut -d: -f1)
  commit_line=$(grep -n 'Generated Limine configuration committed' "$bootloader_script" | cut -d: -f1)

  [ "$backup_line" -lt "$generation_line" ]
  [ "$generation_line" -lt "$validation_line" ]
  [ "$validation_line" -lt "$cleanup_line" ]
  [ "$cleanup_line" -lt "$commit_line" ]

  grep -Fq 'limine.conf.bunny-last-known-good' "$bootloader_script"
  grep -Fq 'restore_last_known_limine_configuration' "$bootloader_script"

  run grep -F 'limine/limine.conf" /boot/limine.conf.bunny-new' "$bootloader_script"
  [ "$status" -eq 1 ]
}

@test "tracked desktop defaults work in a clean home" {
  clean_home=$BATS_TEST_TMPDIR/clean-home
  mkdir -p "$clean_home/.config"

  run stow --no-folding -t "$clean_home/.config" config
  [ "$status" -eq 0 ]

  [ -L "$clean_home/.config/mimeapps.list" ]
  [ -L "$clean_home/.config/gtk-3.0/settings.ini" ]
  [ -L "$clean_home/.config/gtk-4.0/settings.ini" ]

  run env XDG_CONFIG_HOME="$clean_home/.config" \
    xdg-mime query default x-scheme-handler/terminal
  [ "$status" -eq 0 ]
  [ "$output" = Alacritty.desktop ]

  run env XDG_CONFIG_HOME="$clean_home/.config" \
    xdg-mime query default inode/directory
  [ "$status" -eq 0 ]
  [ "$output" = org.gnome.Nautilus.desktop ]

  grep -Fxq 'gtk-theme-name=Adwaita-dark' "$clean_home/.config/gtk-3.0/settings.ini"
  grep -Fxq 'gtk-application-prefer-dark-theme=true' "$clean_home/.config/gtk-4.0/settings.ini"
  run grep -R '^gtk-icon-theme-name=' \
    "$clean_home/.config/gtk-3.0/settings.ini" \
    "$clean_home/.config/gtk-4.0/settings.ini"
  [ "$status" -eq 1 ]
  grep -Fq '"$HOME/.config/mimeapps.list"' "$repo_root/install/20-dotfiles.sh"
  run grep -Fq '91-mimes.sh' "$repo_root/install.sh"
  [ "$status" -eq 1 ]
  [ ! -e "$repo_root/install/91-mimes.sh" ]
}

@test "application launcher uses Bemenu with a desktop-entry backend" {
  grep -Fxq j4-dmenu-desktop "$packages_file"
  grep -Fq 'exec j4-dmenu-desktop' "$app_launcher"
  grep -Fq -- '--dmenu="bunny-launch-menu"' "$app_launcher"
  grep -Fq -- '--wrapper="uwsm-app --"' "$app_launcher"
  grep -Fq -- '--term="xdg-terminal-exec --title={name} -- {cmdline@}"' "$app_launcher"

  hidden_overrides=(
    avahi-discover.desktop
    bssh.desktop
    btop.desktop
    bvnc.desktop
    limine-snapper-restore.desktop
    lstopo.desktop
    qv4l2.desktop
    qvidcap.desktop
    uuctl.desktop
    vim.desktop
    xgps.desktop
    xgpsspeed.desktop
  )
  for desktop_id in "${hidden_overrides[@]}"; do
    grep -Fxq 'Hidden=true' "$application_overrides/$desktop_id"
  done

  grep -Fxq 'X-TerminalArgExec=-e' "$application_overrides/Alacritty.desktop"
  grep -Fxq 'X-TerminalArgAppId=--class' "$application_overrides/Alacritty.desktop"
  [ ! -e "$repo_root/local/share/applications/Alacritty.desktop" ]
  [ "$(find "$application_overrides" -maxdepth 1 -type f -name '*.desktop' | wc -l)" -eq "$(( ${#hidden_overrides[@]} + 1 ))" ]
  if command -v desktop-file-validate >/dev/null 2>&1; then
    run desktop-file-validate "$application_overrides"/*.desktop
    [ "$status" -eq 0 ]
  fi

  grep -Fq 'APPLICATION_OVERRIDES_DIR="$HOME/.local/share/applications"' "$user_setup_script"
  grep -Fq '"$BUNNY_INSTALL_DEFAULTS_PATH/applications/"*.desktop' "$user_setup_script"
  grep -Fq 'install -m 0644 -- "$desktop_override"' "$user_setup_script"
  grep -Fq '"$APPLICATION_OVERRIDES_DIR/${desktop_override##*/}"' "$user_setup_script"
}

@test "Plymouth theme copy is idempotent" {
  # shellcheck disable=SC2016 # matching a literal shell expression
  run grep -F 'sudo cp -a "$BUNNY_INSTALL_DEFAULTS_PATH/plymouth/." "$plymouth_theme_dir/"' "$bootloader_script"
  [ "$status" -eq 0 ]

  # shellcheck disable=SC2016 # matching a literal shell expression
  run grep -F 'sudo rm -rf "$plymouth_theme_dir/plymouth"' "$bootloader_script"
  [ "$status" -eq 0 ]
}

@test "greetd user service command preserves the current user bus" {
  run grep -F 'systemctl --user disable niri.service' "$greetd_script"
  [ "$status" -eq 0 ]

  run grep -E 'sudo (-u [^ ]+ )?systemctl --user' "$greetd_script"
  [ "$status" -eq 1 ]
}

@test "networkd is enabled when NetworkManager is disabled" {
  run grep -F 'sudo systemctl enable systemd-networkd.service' "$systemd_script"
  [ "$status" -eq 0 ]
}

@test "pacman configuration is managed without replacing the complete file" {
  grep -Fq 'PACMAN_ORIGINAL_BACKUP=${PACMAN_ORIGINAL_BACKUP:-$PACMAN_CONF.bunny-original}' "$pacman_script"
  grep -Fq 'PACMAN_REPOSITORY_FRAGMENT=${PACMAN_REPOSITORY_FRAGMENT:-/etc/pacman.d/bunny-repositories.conf}' "$pacman_script"
  grep -Fq 'pacman-conf --config="$staged_conf" --repo-list' "$pacman_script"
  grep -Fq 'validate_package_resolution "${required_packages[@]}"' "$pacman_script"

  run grep -E 'sudo (mv|cp).*pacman\.conf.*pacman\.conf\.bak' "$pacman_script"
  [ "$status" -eq 1 ]

  grep -Fxq '[omarchy]' "$pacman_fragment"
  grep -Fxq 'SigLevel = Optional TrustAll' "$pacman_fragment"
  grep -Fq 'Server = https://pkgs.omarchy.org/stable/$arch' "$pacman_fragment"
}

@test "pacman migration preserves unrelated configuration and activates multilib" {
  fixture=$BATS_TEST_TMPDIR/pacman-migration
  mock_bin=$fixture/bin
  mkdir -p "$mock_bin" "$fixture/install" "$fixture/etc/pacman.d"
  cat > "$fixture/etc/pacman.conf" <<'EOF'
[options]
Architecture = auto
Color
ParallelDownloads = 9

[core]
Server = file:///mirror/$repo/os/$arch

[extra]
Server = file:///mirror/$repo/os/$arch

#[multilib]
#Include = /etc/pacman.d/mirrorlist

[omarchy]
SigLevel = Optional TrustAll
Server = https://old.invalid/$arch
EOF
  printf '%s\n' available-package > "$fixture/install/packages"
  cat > "$mock_bin/sudo" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF
  cat > "$mock_bin/pacman" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PACMAN_CALLS"
exit 0
EOF
  cat > "$mock_bin/pacman-conf" <<'EOF'
#!/usr/bin/env bash
for argument in "$@"; do
  [[ $argument == --config=* || $argument == -c ]] && exec /usr/bin/pacman-conf "$@"
done
exec /usr/bin/pacman-conf --config="$PACMAN_CONF" "$@"
EOF
  cat > "$mock_bin/modprobe" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$mock_bin/sudo" "$mock_bin/pacman" "$mock_bin/pacman-conf" "$mock_bin/modprobe"
  cp "$fixture/etc/pacman.conf" "$fixture/original.conf"

  pacman_env=(
    "PATH=$mock_bin:$PATH"
    "PACMAN_CALLS=$fixture/pacman.calls"
    "PACMAN_CONF=$fixture/etc/pacman.conf"
    "PACMAN_ORIGINAL_BACKUP=$fixture/etc/pacman.conf.bunny-original"
    "PACMAN_ORIGINAL_CHECKSUM=$fixture/etc/pacman.conf.bunny-original.sha256"
    "PACMAN_REPOSITORY_FRAGMENT=$fixture/etc/pacman.d/bunny-repositories.conf"
    "BUNNY_INSTALL=$fixture/install"
    "BUNNY_INSTALL_DEFAULTS_PATH=$repo_root/install/default"
    "BUNNY_INSTALL_LOG_FILE=$fixture/install.log"
    "BUNNY_PACMAN_HOOK_DIR=$fixture/run/pacman-hooks"
  )

  run env "${pacman_env[@]}" bash -c \
    'set -e; source "$1"; source "$2"' _ \
    "$repo_root/install/lib/helpers.sh" "$pacman_script"

  [ "$status" -eq 0 ]
  cmp -s "$fixture/original.conf" "$fixture/etc/pacman.conf.bunny-original"
  grep -Fxq 'ParallelDownloads = 9' "$fixture/etc/pacman.conf"
  grep -Fxq '[multilib]' "$fixture/etc/pacman.conf"
  grep -Fxq "Include = $fixture/etc/pacman.d/bunny-repositories.conf" "$fixture/etc/pacman.conf"
  [ "$(grep -Fxc '[omarchy]' "$fixture/etc/pacman.conf")" -eq 0 ]
  grep -Fxq '[omarchy]' "$fixture/etc/pacman.d/bunny-repositories.conf"
  grep -Fxq -- '-Sy --noconfirm' "$fixture/pacman.calls"
  grep -Fxq -- '-Syu --noconfirm' "$fixture/pacman.calls"

  cp "$fixture/etc/pacman.conf" "$fixture/first-managed.conf"
  run env "${pacman_env[@]}" bash -c \
    'set -e; source "$1"; source "$2"' _ \
    "$repo_root/install/lib/helpers.sh" "$pacman_script"

  [ "$status" -eq 0 ]
  cmp -s "$fixture/first-managed.conf" "$fixture/etc/pacman.conf"
  [ "$(grep -Fxc '# Dotfiles-managed third-party repositories' "$fixture/etc/pacman.conf")" -eq 1 ]
}

@test "package transactions defer only the install generation hook" {
  fixture=$BATS_TEST_TMPDIR/hook-override
  mock_bin=$fixture/bin
  mkdir -p "$mock_bin"
  cat > "$mock_bin/sudo" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF
  cat > "$mock_bin/pacman" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PACMAN_CALLS"
EOF
  chmod +x "$mock_bin/sudo" "$mock_bin/pacman"

  run env \
    PATH="$mock_bin:$PATH" \
    PACMAN_CALLS="$fixture/pacman.calls" \
    BUNNY_INSTALL_LOG_FILE="$fixture/install.log" \
    BUNNY_PACMAN_HOOK_DIR="$fixture/run/pacman-hooks" \
    bash -c '
      set -e
      source "$1"
      prepare_pacman_generation_override
      install_packages_without_generation package-one package-two
      test -L "$BUNNY_PACMAN_HOOK_DIR/90-mkinitcpio-install.hook"
      test "$(readlink "$BUNNY_PACMAN_HOOK_DIR/90-mkinitcpio-install.hook")" = /dev/null
      test ! -e "$BUNNY_PACMAN_HOOK_DIR/60-mkinitcpio-remove.hook"
      remove_pacman_generation_override
    ' _ "$repo_root/install/lib/helpers.sh"

  [ "$status" -eq 0 ]
  grep -Fxq -- "--hookdir $fixture/run/pacman-hooks -S --noconfirm --needed package-one package-two" "$fixture/pacman.calls"
  [ ! -e "$fixture/run/pacman-hooks" ]
}

@test "system upgrade keeps normal hooks enabled" {
  preflight=$repo_root/install/00-preflight.sh

  grep -Fq 'sudo pacman -Syu --noconfirm' "$pacman_script"
  run grep -R -E 'mkinitcpio-(install|remove)\.hook\.disabled|sudo mv .*(60|90)-mkinitcpio' \
    "$repo_root/install.sh" "$repo_root/install"
  [ "$status" -eq 1 ]
}

@test "firewall modules are loaded before a kernel upgrade" {
  module_line=$(grep -nF 'sudo modprobe -a "${firewall_modules[@]}"' "$pacman_script" | cut -d: -f1)
  upgrade_line=$(grep -nF 'sudo pacman -Syu --noconfirm' "$pacman_script" | cut -d: -f1)

  [ "$module_line" -lt "$upgrade_line" ]
  for module in \
    nf_tables nft_compat nft_fib_ipv4 nft_fib_ipv6 nft_limit nft_log \
    ipt_REJECT ip6t_REJECT ip6t_rt xt_hl; do
    grep -Fxq "  $module" "$pacman_script"
  done
}

@test "privileged commands use process-state polling for ticker updates" {
  grep -Fq 'ps -o stat= -p "$1"' "$repo_root/install/lib/helpers.sh"
  run grep -Fq 'kill -0 "$command_pid"' "$repo_root/install/lib/helpers.sh"
  [ "$status" -eq 1 ]
}

@test "NVIDIA generation is deferred to final Limine generation" {
  nvidia_script=$repo_root/install/11-nvidia.sh

  grep -Fq 'install_packages_without_generation "${INSTALL_PACKAGES[@]}"' "$nvidia_script"
  run grep -F 'mkinitcpio -P' "$nvidia_script"
  [ "$status" -eq 1 ]
  grep -Fq 'Running authoritative final Limine generation' "$bootloader_script"
  grep -Fq "grep -Fq 'Unified kernel image generation successful'" "$bootloader_script"
  grep -Fq 'Final Limine configuration and UKI validated' "$bootloader_script"
  run grep -F 'uki_state_' "$bootloader_script"
  [ "$status" -eq 1 ]
}

@test "modern and legacy NVIDIA plans use the generation override" {
  fixture=$BATS_TEST_TMPDIR/nvidia-plans
  mock_bin=$fixture/bin
  mkdir -p "$mock_bin"
  cat > "$mock_bin/lspci" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$MOCK_GPU"
EOF
  cat > "$mock_bin/pacman" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == -Qqs ]]; then
  [[ ${2:-} == "^linux$" ]]
  exit
fi
printf '%s\n' "$*" >> "$PACMAN_CALLS"
EOF
  cat > "$mock_bin/sudo" <<'EOF'
#!/usr/bin/env bash
case ${1:-} in
  mkdir) exit 0 ;;
  tee) cat >/dev/null; exit 0 ;;
esac
exec "$@"
EOF
  chmod +x "$mock_bin/lspci" "$mock_bin/pacman" "$mock_bin/sudo"

  for plan in modern legacy; do
    plan_dir=$fixture/$plan
    mkdir -p "$plan_dir/home" "$plan_dir/hooks"
    ln -s /dev/null "$plan_dir/hooks/90-mkinitcpio-install.hook"
    if [[ $plan == modern ]]; then
      gpu='VGA compatible controller: NVIDIA Corporation GeForce RTX 4070'
      expected='linux-headers nvidia-open-dkms nvidia-utils lib32-nvidia-utils libva-nvidia-driver'
    else
      gpu='VGA compatible controller: NVIDIA Corporation GeForce GTX 1080'
      expected='linux-headers nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils'
    fi

    run env \
      PATH="$mock_bin:$PATH" \
      HOME="$plan_dir/home" \
      MOCK_GPU="$gpu" \
      PACMAN_CALLS="$plan_dir/pacman.calls" \
      BUNNY_INSTALL_LOG_FILE="$plan_dir/install.log" \
      BUNNY_PACMAN_HOOK_DIR="$plan_dir/hooks" \
      bash -c 'set -e; source "$1"; source "$2"' _ \
      "$repo_root/install/lib/helpers.sh" "$repo_root/install/11-nvidia.sh"

    [ "$status" -eq 0 ]
    grep -Fxq -- "--hookdir $plan_dir/hooks -S --noconfirm --needed $expected" "$plan_dir/pacman.calls"
  done
}

@test "required package resolution has elapsed-time status and reports every unresolved package" {
  grep -Fq 'run_logged "Validating required package availability"' "$pacman_script"

  mock_bin=$BATS_TEST_TMPDIR/package-resolution-bin
  mkdir -p "$mock_bin"
  cat > "$mock_bin/pacman" <<'EOF'
#!/usr/bin/env bash
[[ ${3:-} != missing-one && ${3:-} != missing-two ]]
EOF
  chmod +x "$mock_bin/pacman"

  run env PATH="$mock_bin:$PATH" bash -c '
    BUNNY_INSTALL_LOG_FILE=$1
    source "$2"
    validate_package_resolution available missing-one missing-two
  ' _ "$BATS_TEST_TMPDIR/resolution.log" "$repo_root/install/lib/helpers.sh"

  [ "$status" -eq 1 ]
  [[ $output == *"Required packages do not resolve: missing-one missing-two"* ]]
}

@test "PipeWire runtime packages are installed" {
  for package in pipewire pipewire-alsa pipewire-audio pipewire-pulse rtkit wireplumber; do
    run grep -qx "$package" "$packages_file"
    [ "$status" -eq 0 ]
  done
}

@test "successful installation offers an optional reboot" {
  grep -Fq 'Reboot now? [y/N]' "$repo_root/install.sh"
  grep -Fq 'run_logged "Requesting system reboot" sudo systemctl reboot' "$repo_root/install.sh"
}

@test "SwayOSD CSS declarations contain separators" {
  run grep -nE '^ *[a-zA-Z-]+ +[^:;]+;' "$swayosd_style"
  [ "$status" -eq 1 ]
}
