#!/usr/bin/env bats
# niri_focus_or_spawn must key off app_id alone: a title match would focus
# whatever window happens to mention the app instead of launching it.

setup() {
  repo_root=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  stub_dir="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$stub_dir"

  cat > "$stub_dir/niri" <<'EOF'
#!/bin/bash
[[ "$*" == "msg --json windows" ]] && { echo "$FAKE_WINDOWS"; exit 0; }
echo "NIRI: $*"
EOF
  chmod +x "$stub_dir/niri"
  PATH="$stub_dir:$PATH"

  NIRI_APP_LAUNCHER="echo LAUNCH"
  source "$repo_root/local/bin/lib/niri-helpers.sh"
}

@test "focuses a window whose app_id matches" {
  export FAKE_WINDOWS='[{"id":7,"app_id":"Spotify","title":"Some Song"}]'
  run niri_focus_or_spawn spotify spotify-launcher
  [ "$output" = "NIRI: msg action focus-window --id 7" ]
}

@test "launches when only a title mentions the app" {
  export FAKE_WINDOWS='[{"id":7,"app_id":"kitty","title":"debugging spotify bind"}]'
  run niri_focus_or_spawn spotify spotify-launcher
  [ "$output" = "LAUNCH -- spotify-launcher" ]
}
