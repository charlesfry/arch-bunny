#!/usr/bin/env bats
# bunny-remind hands the minutes to systemd verbatim; the point of these is that
# a decimal survives that trip and that junk never reaches systemd-run at all.

setup() {
  repo_root=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  stub_dir="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$stub_dir"

  cat > "$stub_dir/systemd-run" <<'STUB'
#!/bin/bash
for arg in "$@"; do [[ "$arg" == --on-active=* ]] && echo "RUN: ${arg#*=}"; done
exit 0
STUB
  chmod +x "$stub_dir/systemd-run"
  PATH="$stub_dir:$PATH"
}

@test "a decimal becomes a fractional systemd timespan" {
  run "$repo_root/local/bin/bunny-remind" 2.5 "bread"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RUN: 2.5min"* ]]
  [[ "$output" == *"Reminder in 2min 30s: bread"* ]]
}

@test "the message defaults when omitted" {
  run "$repo_root/local/bin/bunny-remind" 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"Time is up"* ]]
}

@test "non-numeric, zero, and negative minutes are rejected" {
  for bad in "" abc 0 0.0 -3 2,5 1min; do
    run "$repo_root/local/bin/bunny-remind" "$bad"
    [ "$status" -eq 1 ]
    [[ "$output" != *RUN:* ]]
  done
}
