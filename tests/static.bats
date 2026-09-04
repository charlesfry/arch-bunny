#!/usr/bin/env bats

setup() {
  repo_root=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  scripts=(
    "$repo_root/bootstrap.sh"
    "$repo_root/install.sh"
    "$repo_root/install/verify.sh"
    "$repo_root/install/00-preflight.sh"
    "$repo_root/install/10-packages.sh"
    "$repo_root/install/11-nvidia.sh"
    "$repo_root/install/12-greetd.sh"
    "$repo_root/install/13-bootloader.sh"
    "$repo_root/install/14-aur.sh"
    "$repo_root/install/20-dotfiles.sh"
    "$repo_root/install/30-system-services.sh"
    "$repo_root/install/40-user-setup.sh"
    "$repo_root/install/50-firewall.sh"
    "$repo_root/install/60-docker.sh"
    "$repo_root/install/lib/helpers.sh"
  )
}

@test "installer shell scripts parse" {
  run bash -n "${scripts[@]}"
  [ "$status" -eq 0 ]
}

@test "installer shell scripts pass ShellCheck" {
  command -v shellcheck >/dev/null 2>&1 || skip "shellcheck is not installed"

  run shellcheck -x "${scripts[@]}"
  [ "$status" -eq 0 ]
}
