#!/usr/bin/env bats
# bunny-osd reads the level back after changing it; the point of these is that
# wpctl's "0.27 [MUTED]" and brightnessctl's CSV become the right popup, and
# that each popup replaces the last instead of stacking.

setup() {
  repo_root=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  stub_dir="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$stub_dir"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR"

  cat > "$stub_dir/wpctl" <<'STUB'
#!/bin/bash
[[ "$1" == get-volume ]] && echo "Volume: $WPCTL_VOLUME"
exit 0
STUB
  cat > "$stub_dir/brightnessctl" <<'STUB'
#!/bin/bash
echo "amdgpu_bl1,backlight,26214,40%,65535"
STUB
  cat > "$stub_dir/notify-send" <<'STUB'
#!/bin/bash
echo "NOTIFY: $*" >&2
echo 42
STUB
  chmod +x "$stub_dir"/*
  PATH="$stub_dir:$PATH"
}

@test "volume level and mute state come from wpctl's readback" {
  WPCTL_VOLUME="0.27 [MUTED]" run "$repo_root/local/bin/bunny-osd" volume mute
  [ "$status" -eq 0 ]
  [[ "$output" == *"int:value:27 󰝟  27%"* ]]
}

@test "full volume picks the loudest icon" {
  WPCTL_VOLUME="1.00" run "$repo_root/local/bin/bunny-osd" volume 10%+
  [ "$status" -eq 0 ]
  [[ "$output" == *"int:value:100 󰕾  100%"* ]]
}

@test "brightness comes from brightnessctl's machine-readable output" {
  run "$repo_root/local/bin/bunny-osd" brightness +10%
  [ "$status" -eq 0 ]
  [[ "$output" == *"int:value:40 󰃟  40%"* ]]
}

@test "each popup replaces the previous one" {
  WPCTL_VOLUME="0.50" run "$repo_root/local/bin/bunny-osd" volume 10%+
  [[ "$output" == *"-r 0 "* ]]
  WPCTL_VOLUME="0.60" run "$repo_root/local/bin/bunny-osd" volume 10%+
  [[ "$output" == *"-r 42 "* ]]
}

@test "an unknown kind is rejected without a popup" {
  run "$repo_root/local/bin/bunny-osd" speakers 10%+
  [ "$status" -eq 1 ]
  [[ "$output" != *NOTIFY:* ]]
}
