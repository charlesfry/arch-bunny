#!/usr/bin/env bats

setup() {
  repo_root=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  command -v stow >/dev/null || skip "stow is not installed"
  fake_home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$fake_home/.config/systemd/user/timers.target.wants" "$fake_home/.local"
}

@test "migrate clears hand-made and dangling links but keeps systemd enable links" {
  ln -s "$repo_root/home/.bash_prompt" "$fake_home/.bash_prompt"
  ln -s "$repo_root/home/.gone-away" "$fake_home/.gone-away"
  wants="$fake_home/.config/systemd/user/timers.target.wants/bunny-update-location.timer"
  ln -s "$repo_root/config/systemd/user/bunny-update-location.timer" "$wants"

  HOME="$fake_home" run "$repo_root/local/bin/bunny-migrate"
  [ "$status" -eq 0 ]

  [ "$(readlink "$fake_home/.bash_prompt")" != "$repo_root/home/.bash_prompt" ]
  [ -f "$fake_home/.bash_prompt" ]
  [ ! -e "$fake_home/.gone-away" ] && [ ! -L "$fake_home/.gone-away" ]
  [ -L "$wants" ]
}
